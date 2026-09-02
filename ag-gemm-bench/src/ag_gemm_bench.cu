#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <mpi.h>
#include <nccl.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unistd.h>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

#define CUDA_CHECK(command)                                                                    \
  do {                                                                                         \
    const cudaError_t status = (command);                                                      \
    if (status != cudaSuccess) {                                                               \
      throw std::runtime_error(std::string("CUDA failure at ") + __FILE__ + ":" +             \
                               std::to_string(__LINE__) + ": " + cudaGetErrorString(status)); \
    }                                                                                          \
  } while (0)

#define CUBLAS_CHECK(command)                                                              \
  do {                                                                                     \
    const cublasStatus_t status = (command);                                               \
    if (status != CUBLAS_STATUS_SUCCESS) {                                                 \
      throw std::runtime_error(std::string("cuBLAS failure at ") + __FILE__ + ":" +       \
                               std::to_string(__LINE__) + ": status=" +                    \
                               std::to_string(static_cast<int>(status)));                  \
    }                                                                                      \
  } while (0)

#define NCCL_CHECK(command)                                                               \
  do {                                                                                    \
    const ncclResult_t status = (command);                                                \
    if (status != ncclSuccess) {                                                          \
      throw std::runtime_error(std::string("NCCL failure at ") + __FILE__ + ":" +         \
                               std::to_string(__LINE__) + ": " + ncclGetErrorString(status)); \
    }                                                                                     \
  } while (0)

#define MPI_CHECK(command)                                                                  \
  do {                                                                                      \
    const int status = (command);                                                           \
    if (status != MPI_SUCCESS) {                                                            \
      throw std::runtime_error(std::string("MPI failure at ") + __FILE__ + ":" +           \
                               std::to_string(__LINE__) + ": status=" + std::to_string(status)); \
    }                                                                                       \
  } while (0)

enum class Strategy { kFullSerial, kSliceSerial, kSliceOverlap };

struct Config {
  int local_rows = 256;
  int k = 256;
  int n = 256;
  int q = 2;
  int window = 0;  // B2 credit window: 0 = unbounded lookahead (original behavior)
  int warmup = 5;
  int iterations = 10;
  std::string output_dir = "results/manual";
  std::string run_id = "manual";
  std::string transport_hint = "UNSPECIFIED";
  std::string release_curve_path;  // optional per-slice release dump
};

struct Sample {
  double release_first_us = 0.0;
  double release_last_us = 0.0;
  double done_us = 0.0;
  double gemm_first_start_us = 0.0;
  double gemm_last_end_us = 0.0;
  double e2e_us = 0.0;
  double max_abs_error = 0.0;
  double max_rel_error = 0.0;
  int correctness = 0;
  std::vector<double> slice_release_us;  // per-slice t_release(i) - t_issue (us)
};

struct DeviceBuffers {
  float* local_a = nullptr;
  float* gathered = nullptr;
  float* b = nullptr;
  float* c = nullptr;
  float* chunk_c = nullptr;
  float* reference = nullptr;
};

struct EventSet {
  cudaEvent_t issue = nullptr;
  cudaEvent_t comm_done = nullptr;
  cudaEvent_t gemm_first = nullptr;
  cudaEvent_t gemm_last = nullptr;
  cudaEvent_t e2e = nullptr;
  std::vector<cudaEvent_t> release;
  std::vector<cudaEvent_t> slice_done;

  explicit EventSet(int q) : release(q, nullptr), slice_done(q, nullptr) {
    CUDA_CHECK(cudaEventCreate(&issue));
    CUDA_CHECK(cudaEventCreate(&comm_done));
    CUDA_CHECK(cudaEventCreate(&gemm_first));
    CUDA_CHECK(cudaEventCreate(&gemm_last));
    CUDA_CHECK(cudaEventCreate(&e2e));
    for (int i = 0; i < q; ++i) {
      CUDA_CHECK(cudaEventCreate(&release[i]));
      CUDA_CHECK(cudaEventCreate(&slice_done[i]));
    }
  }

  ~EventSet() {
    for (cudaEvent_t event : release) {
      if (event != nullptr) cudaEventDestroy(event);
    }
    for (cudaEvent_t event : slice_done) {
      if (event != nullptr) cudaEventDestroy(event);
    }
    if (issue != nullptr) cudaEventDestroy(issue);
    if (comm_done != nullptr) cudaEventDestroy(comm_done);
    if (gemm_first != nullptr) cudaEventDestroy(gemm_first);
    if (gemm_last != nullptr) cudaEventDestroy(gemm_last);
    if (e2e != nullptr) cudaEventDestroy(e2e);
  }

  EventSet(const EventSet&) = delete;
  EventSet& operator=(const EventSet&) = delete;
};

const char* strategy_name(Strategy strategy) {
  switch (strategy) {
    case Strategy::kFullSerial:
      return "B0_FULL_SERIAL";
    case Strategy::kSliceSerial:
      return "B1_SLICE_SERIAL";
    case Strategy::kSliceOverlap:
      return "B2_SLICE_EVENT_OVERLAP";
  }
  return "UNKNOWN";
}

std::string utc_timestamp() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t raw_time = std::chrono::system_clock::to_time_t(now);
  std::tm utc_time {};
  gmtime_r(&raw_time, &utc_time);
  std::ostringstream stream;
  stream << std::put_time(&utc_time, "%Y-%m-%dT%H:%M:%SZ");
  return stream.str();
}

std::string hostname() {
  char value[256] = {};
  if (gethostname(value, sizeof(value) - 1) != 0) return "UNKNOWN";
  return value;
}

std::string csv_escape(const std::string& value) {
  if (value.find_first_of(",\"\n") == std::string::npos) return value;
  std::string escaped = "\"";
  for (char character : value) {
    if (character == '\"') escaped += "\"\"";
    else escaped += character;
  }
  escaped += "\"";
  return escaped;
}

double elapsed_us(cudaEvent_t start, cudaEvent_t end) {
  float elapsed_ms = 0.0F;
  CUDA_CHECK(cudaEventElapsedTime(&elapsed_ms, start, end));
  return static_cast<double>(elapsed_ms) * 1000.0;
}

template <typename T>
double mean(const std::vector<T>& values) {
  if (values.empty()) return 0.0;
  return std::accumulate(values.begin(), values.end(), 0.0) / values.size();
}

double percentile(std::vector<double> values, double fraction) {
  if (values.empty()) return 0.0;
  std::sort(values.begin(), values.end());
  const size_t index = static_cast<size_t>(std::ceil(fraction * values.size())) - 1;
  return values[std::min(index, values.size() - 1)];
}

Config parse_args(int argc, char** argv) {
  Config config;
  for (int i = 1; i < argc; ++i) {
    const std::string key = argv[i];
    auto require_value = [&](const std::string& option) -> std::string {
      if (++i >= argc) throw std::runtime_error(option + " requires a value");
      return argv[i];
    };
    if (key == "--local-rows") config.local_rows = std::stoi(require_value(key));
    else if (key == "--k") config.k = std::stoi(require_value(key));
    else if (key == "--n") config.n = std::stoi(require_value(key));
    else if (key == "--q") config.q = std::stoi(require_value(key));
    else if (key == "--window") config.window = std::stoi(require_value(key));
    else if (key == "--warmup") config.warmup = std::stoi(require_value(key));
    else if (key == "--iterations") config.iterations = std::stoi(require_value(key));
    else if (key == "--output-dir") config.output_dir = require_value(key);
    else if (key == "--run-id") config.run_id = require_value(key);
    else if (key == "--transport-hint") config.transport_hint = require_value(key);
    else if (key == "--dump-release-curve") config.release_curve_path = require_value(key);
    else if (key == "--help") {
      std::cout
          << "Usage: ag_gemm_bench [options]\n"
          << "  --local-rows INT     Rows owned by each rank (default: 256)\n"
          << "  --k INT              GEMM K dimension (default: 256)\n"
          << "  --n INT              GEMM N dimension (default: 256)\n"
          << "  --q INT              Equal local-row partitions (default: 2)\n"
          << "  --window INT         B2 credit window; 0 = unbounded lookahead (default: 0)\n"
          << "  --warmup INT         Untimed repetitions per strategy (default: 5)\n"
          << "  --iterations INT     Timed repetitions per strategy (default: 10)\n"
          << "  --output-dir PATH    Directory for raw and aggregate CSV files\n"
          << "  --run-id STRING      External run identifier\n"
          << "  --transport-hint S   Observed transport label, otherwise UNSPECIFIED\n";
      std::exit(0);
    } else {
      throw std::runtime_error("unknown option: " + key);
    }
  }
  if (config.local_rows <= 0 || config.k <= 0 || config.n <= 0 || config.q <= 0 ||
      config.warmup < 0 || config.iterations <= 0 || config.window < 0) {
    throw std::runtime_error("dimensions, q, and iterations must be positive; warmup must be nonnegative");
  }
  if (config.window > 0 && config.window >= config.q) {
    throw std::runtime_error("--window must be smaller than --q to bound lookahead (use 0 for unbounded)");
  }
  if (config.local_rows % config.q != 0) {
    throw std::runtime_error("--local-rows must be divisible by --q so every slice has identical count");
  }
  return config;
}

__global__ void scatter_rank_major(const float* chunk_c, float* output, int world, int local_rows,
                                   int chunk_rows, int slice_index, int n) {
  const int64_t total = static_cast<int64_t>(world) * chunk_rows * n;
  const int64_t thread_id = static_cast<int64_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  if (thread_id >= total) return;

  const int column = static_cast<int>(thread_id % n);
  const int chunk_row = static_cast<int>(thread_id / n);
  const int source_rank = chunk_row / chunk_rows;
  const int row_in_chunk = chunk_row % chunk_rows;
  const int output_row = source_rank * local_rows + slice_index * chunk_rows + row_in_chunk;
  output[static_cast<int64_t>(output_row) * n + column] = chunk_c[thread_id];
}

class Benchmark {
 public:
  Benchmark(const Config& config, int rank, int world, int device, const cudaDeviceProp& property,
            ncclComm_t communicator)
      : config_(config), rank_(rank), world_(world), device_(device), property_(property), comm_(communicator) {
    chunk_rows_ = config_.local_rows / config_.q;
    global_rows_ = world_ * config_.local_rows;
    local_a_elements_ = static_cast<size_t>(config_.local_rows) * config_.k;
    full_a_elements_ = static_cast<size_t>(global_rows_) * config_.k;
    output_elements_ = static_cast<size_t>(global_rows_) * config_.n;
    chunk_a_elements_ = static_cast<size_t>(world_) * chunk_rows_ * config_.k;
    chunk_c_elements_ = static_cast<size_t>(world_) * chunk_rows_ * config_.n;
    allocate();
    initialize_inputs();
    CUDA_CHECK(cudaStreamCreateWithFlags(&comm_stream_, cudaStreamNonBlocking));
    CUDA_CHECK(cudaStreamCreateWithFlags(&compute_stream_, cudaStreamNonBlocking));
    CUBLAS_CHECK(cublasCreate(&cublas_));
    CUBLAS_CHECK(cublasSetStream(cublas_, compute_stream_));
  }

  ~Benchmark() {
    if (cublas_ != nullptr) cublasDestroy(cublas_);
    if (comm_stream_ != nullptr) cudaStreamDestroy(comm_stream_);
    if (compute_stream_ != nullptr) cudaStreamDestroy(compute_stream_);
    if (buffers_.local_a != nullptr) cudaFree(buffers_.local_a);
    if (buffers_.gathered != nullptr) cudaFree(buffers_.gathered);
    if (buffers_.b != nullptr) cudaFree(buffers_.b);
    if (buffers_.c != nullptr) cudaFree(buffers_.c);
    if (buffers_.chunk_c != nullptr) cudaFree(buffers_.chunk_c);
    if (buffers_.reference != nullptr) cudaFree(buffers_.reference);
  }

  void establish_reference() {
    run_once(Strategy::kFullSerial);
    CUDA_CHECK(cudaStreamSynchronize(compute_stream_));
    CUDA_CHECK(cudaMemcpy(buffers_.reference, buffers_.c, output_elements_ * sizeof(float),
                          cudaMemcpyDeviceToDevice));
    CUDA_CHECK(cudaDeviceSynchronize());
  }

  void warmup_all() {
    for (Strategy strategy : strategies()) {
      for (int iteration = 0; iteration < config_.warmup; ++iteration) {
        run_once(strategy);
      }
      CUDA_CHECK(cudaDeviceSynchronize());
      MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
    }
  }

  Sample run_timed(Strategy strategy) {
    Sample sample = run_once(strategy);
    validate_output(sample);
    return sample;
  }

  const Config& config() const { return config_; }
  int rank() const { return rank_; }
  int world() const { return world_; }
  int device() const { return device_; }
  const cudaDeviceProp& property() const { return property_; }

 private:
  std::vector<Strategy> strategies() const {
    return {Strategy::kFullSerial, Strategy::kSliceSerial, Strategy::kSliceOverlap};
  }

  void allocate() {
    CUDA_CHECK(cudaMalloc(&buffers_.local_a, local_a_elements_ * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&buffers_.gathered, full_a_elements_ * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&buffers_.b, static_cast<size_t>(config_.k) * config_.n * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&buffers_.c, output_elements_ * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&buffers_.chunk_c, output_elements_ * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&buffers_.reference, output_elements_ * sizeof(float)));
  }

  void initialize_inputs() {
    std::vector<float> local_a(local_a_elements_);
    std::vector<float> b(static_cast<size_t>(config_.k) * config_.n);
    for (int row = 0; row < config_.local_rows; ++row) {
      for (int column = 0; column < config_.k; ++column) {
        local_a[static_cast<size_t>(row) * config_.k + column] =
            static_cast<float>((rank_ + 1) * 0.03125 + (row % 17) * 0.0078125 + (column % 13) * 0.00390625);
      }
    }
    for (int row = 0; row < config_.k; ++row) {
      for (int column = 0; column < config_.n; ++column) {
        b[static_cast<size_t>(row) * config_.n + column] =
            static_cast<float>((row % 19) * 0.015625 - (column % 11) * 0.0078125 + 0.125);
      }
    }
    CUDA_CHECK(cudaMemcpy(buffers_.local_a, local_a.data(), local_a_elements_ * sizeof(float),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(buffers_.b, b.data(), b.size() * sizeof(float), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaDeviceSynchronize());
  }

  void gemm(const float* a, float* c, int rows) {
    const float alpha = 1.0F;
    const float beta = 0.0F;
    // Row-major C=A*B is represented to cuBLAS as column-major C^T=B^T*A^T.
    CUBLAS_CHECK(cublasSgemm(cublas_, CUBLAS_OP_N, CUBLAS_OP_N, config_.n, rows, config_.k, &alpha,
                             buffers_.b, config_.n, a, config_.k, &beta, c, config_.n));
  }

  void launch_scatter(const float* source, int slice_index) {
    const int64_t elements = static_cast<int64_t>(world_) * chunk_rows_ * config_.n;
    constexpr int threads = 256;
    const int blocks = static_cast<int>((elements + threads - 1) / threads);
    scatter_rank_major<<<blocks, threads, 0, compute_stream_>>>(source, buffers_.c, world_, config_.local_rows,
                                                                  chunk_rows_, slice_index, config_.n);
    CUDA_CHECK(cudaPeekAtLastError());
  }

  Sample run_once(Strategy strategy) {
    CUDA_CHECK(cudaMemsetAsync(buffers_.c, 0, output_elements_ * sizeof(float), compute_stream_));
    CUDA_CHECK(cudaMemsetAsync(buffers_.chunk_c, 0, output_elements_ * sizeof(float), compute_stream_));
    CUDA_CHECK(cudaStreamSynchronize(compute_stream_));

    EventSet events(config_.q);
    CUDA_CHECK(cudaEventRecord(events.issue, comm_stream_));

    if (strategy == Strategy::kFullSerial) {
      NCCL_CHECK(ncclAllGather(buffers_.local_a, buffers_.gathered, local_a_elements_, ncclFloat, comm_, comm_stream_));
      CUDA_CHECK(cudaEventRecord(events.release[0], comm_stream_));
      CUDA_CHECK(cudaEventRecord(events.comm_done, comm_stream_));
      CUDA_CHECK(cudaStreamWaitEvent(compute_stream_, events.release[0], 0));
      CUDA_CHECK(cudaEventRecord(events.gemm_first, compute_stream_));
      gemm(buffers_.gathered, buffers_.c, global_rows_);
      CUDA_CHECK(cudaEventRecord(events.gemm_last, compute_stream_));
    } else {
      for (int slice = 0; slice < config_.q; ++slice) {
        if (strategy == Strategy::kSliceSerial && slice > 0) {
          CUDA_CHECK(cudaStreamWaitEvent(comm_stream_, events.slice_done[slice - 1], 0));
        }
        if (strategy == Strategy::kSliceOverlap && config_.window > 0 && slice >= config_.window) {
          CUDA_CHECK(cudaStreamWaitEvent(comm_stream_, events.slice_done[slice - config_.window], 0));
        }
        const size_t local_offset = static_cast<size_t>(slice) * chunk_rows_ * config_.k;
        const size_t gathered_offset = static_cast<size_t>(slice) * chunk_a_elements_;
        const size_t chunk_c_offset = static_cast<size_t>(slice) * chunk_c_elements_;
        NCCL_CHECK(ncclAllGather(buffers_.local_a + local_offset, buffers_.gathered + gathered_offset,
                                 static_cast<size_t>(chunk_rows_) * config_.k, ncclFloat, comm_, comm_stream_));
        CUDA_CHECK(cudaEventRecord(events.release[slice], comm_stream_));
        CUDA_CHECK(cudaStreamWaitEvent(compute_stream_, events.release[slice], 0));
        if (slice == 0) CUDA_CHECK(cudaEventRecord(events.gemm_first, compute_stream_));
        gemm(buffers_.gathered + gathered_offset, buffers_.chunk_c + chunk_c_offset, world_ * chunk_rows_);
        launch_scatter(buffers_.chunk_c + chunk_c_offset, slice);
        CUDA_CHECK(cudaEventRecord(events.slice_done[slice], compute_stream_));
      }
      CUDA_CHECK(cudaEventRecord(events.comm_done, comm_stream_));
      CUDA_CHECK(cudaEventRecord(events.gemm_last, compute_stream_));
    }
    CUDA_CHECK(cudaEventRecord(events.e2e, compute_stream_));
    CUDA_CHECK(cudaEventSynchronize(events.e2e));
    CUDA_CHECK(cudaEventSynchronize(events.comm_done));

    Sample sample;
    sample.release_first_us = elapsed_us(events.issue, events.release.front());
    sample.release_last_us = strategy == Strategy::kFullSerial
                                 ? sample.release_first_us
                                 : elapsed_us(events.issue, events.release.back());
    sample.done_us = elapsed_us(events.issue, events.comm_done);
    sample.gemm_first_start_us = elapsed_us(events.issue, events.gemm_first);
    sample.gemm_last_end_us = elapsed_us(events.issue, events.gemm_last);
    sample.e2e_us = elapsed_us(events.issue, events.e2e);
    sample.slice_release_us.reserve(events.release.size());
    for (cudaEvent_t event : events.release) {
      sample.slice_release_us.push_back(elapsed_us(events.issue, event));
    }
    return sample;
  }

  void validate_output(Sample& sample) {
    std::vector<float> output(output_elements_);
    std::vector<float> reference(output_elements_);
    CUDA_CHECK(cudaMemcpy(output.data(), buffers_.c, output_elements_ * sizeof(float), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(reference.data(), buffers_.reference, output_elements_ * sizeof(float),
                          cudaMemcpyDeviceToHost));
    for (size_t index = 0; index < output_elements_; ++index) {
      const double absolute_error = std::abs(static_cast<double>(output[index]) - reference[index]);
      const double relative_error = absolute_error / std::max(1.0, std::abs(static_cast<double>(reference[index])));
      sample.max_abs_error = std::max(sample.max_abs_error, absolute_error);
      sample.max_rel_error = std::max(sample.max_rel_error, relative_error);
    }
    const double local_abs_error = sample.max_abs_error;
    const double local_rel_error = sample.max_rel_error;
    MPI_CHECK(MPI_Allreduce(&local_abs_error, &sample.max_abs_error, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD));
    MPI_CHECK(MPI_Allreduce(&local_rel_error, &sample.max_rel_error, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD));
    sample.correctness = sample.max_abs_error <= 1e-4 && sample.max_rel_error <= 1e-5 ? 1 : 0;
  }

  Config config_;
  int rank_ = 0;
  int world_ = 1;
  int device_ = 0;
  cudaDeviceProp property_ {};
  ncclComm_t comm_ = nullptr;
  int chunk_rows_ = 0;
  int global_rows_ = 0;
  size_t local_a_elements_ = 0;
  size_t full_a_elements_ = 0;
  size_t output_elements_ = 0;
  size_t chunk_a_elements_ = 0;
  size_t chunk_c_elements_ = 0;
  DeviceBuffers buffers_;
  cudaStream_t comm_stream_ = nullptr;
  cudaStream_t compute_stream_ = nullptr;
  cublasHandle_t cublas_ = nullptr;
};

struct CsvWriters {
  std::ofstream rank_raw;
  std::ofstream global_raw;
  std::ofstream summary;
  std::ofstream manifest;
};

void write_raw_header(std::ofstream& stream) {
  stream << "scope,run_id,timestamp_utc,host,gpu_model,device,rank,rank_count,dtype,M,N,K,collective,q,"
          << "slice_bytes,backend,strategy,transport_hint,warmup,iteration_index,status,correctness,max_abs_error,"
          << "max_rel_error,t_release_first_us,t_release_last_us,t_done_us,gemm_first_start_us,gemm_last_end_us,e2e_us,log_path,window\n";
}

void write_summary_header(std::ofstream& stream) {
  stream << "run_id,timestamp_utc,host,gpu_model,rank_count,dtype,M,N,K,collective,q,slice_bytes,backend,"
         << "strategy,transport_hint,warmup,iterations,status,correctness,max_abs_error,max_rel_error,"
         << "release_first_mean_us,release_first_p50_us,release_first_p95_us,release_last_mean_us,"
         << "done_mean_us,done_p50_us,done_p95_us,gemm_first_mean_us,gemm_last_mean_us,e2e_mean_us,"
         << "e2e_p50_us,e2e_p95_us,log_path,window\n";
}

void write_manifest_header(std::ofstream& stream) {
  stream << "run_id,timestamp_utc,status,rank_count,local_rows,M,N,K,q,warmup,iterations,backend,"
         << "gpu_model,transport_hint,raw_rank_csv,raw_global_csv,summary_csv,rank_log_pattern,window\n";
}

std::string device_model(const cudaDeviceProp& property) { return property.name; }

void write_sample(std::ofstream& stream, const std::string& scope, const Config& config, const Benchmark& benchmark,
                  Strategy strategy, int iteration, const Sample& sample, const std::string& log_path) {
  const int global_rows = benchmark.world() * config.local_rows;
  const size_t slice_bytes =
      static_cast<size_t>(benchmark.world()) * (config.local_rows / config.q) * config.k * sizeof(float);
  stream << scope << ',' << csv_escape(config.run_id) << ',' << utc_timestamp() << ',' << csv_escape(hostname()) << ','
         << csv_escape(device_model(benchmark.property())) << ',' << benchmark.device() << ',' << benchmark.rank() << ','
         << benchmark.world() << ",fp32," << global_rows << ',' << config.n << ',' << config.k << ",AllGather-GEMM,"
         << config.q << ',' << slice_bytes << ",NCCL," << strategy_name(strategy) << ','
         << csv_escape(config.transport_hint) << ',' << config.warmup << ',' << iteration << ','
         << (sample.correctness ? "PASS" : "FAIL") << ',' << sample.correctness << ',' << std::setprecision(12)
         << sample.max_abs_error << ',' << sample.max_rel_error << ',' << sample.release_first_us << ','
         << sample.release_last_us << ',' << sample.done_us << ',' << sample.gemm_first_start_us << ','
         << sample.gemm_last_end_us << ',' << sample.e2e_us << ',' << csv_escape(log_path) << ','
         << config.window << '\n';
}

Sample max_across_ranks(const Sample& local) {
  Sample global = local;
  double local_values[] = {local.release_first_us, local.release_last_us, local.done_us, local.gemm_first_start_us,
                           local.gemm_last_end_us, local.e2e_us, local.max_abs_error, local.max_rel_error};
  double global_values[8] = {};
  MPI_CHECK(MPI_Reduce(local_values, global_values, 8, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD));
  int global_correctness = 0;
  MPI_CHECK(MPI_Reduce(&local.correctness, &global_correctness, 1, MPI_INT, MPI_MIN, 0, MPI_COMM_WORLD));
  global.release_first_us = global_values[0];
  global.release_last_us = global_values[1];
  global.done_us = global_values[2];
  global.gemm_first_start_us = global_values[3];
  global.gemm_last_end_us = global_values[4];
  global.e2e_us = global_values[5];
  global.max_abs_error = global_values[6];
  global.max_rel_error = global_values[7];
  global.correctness = global_correctness;
  return global;
}

void write_summary(std::ofstream& stream, const Config& config, const Benchmark& benchmark, Strategy strategy,
                   const std::vector<Sample>& samples, const std::string& log_path) {
  std::vector<double> release_first, release_last, done, gemm_first, gemm_last, e2e;
  release_first.reserve(samples.size());
  release_last.reserve(samples.size());
  done.reserve(samples.size());
  gemm_first.reserve(samples.size());
  gemm_last.reserve(samples.size());
  e2e.reserve(samples.size());
  double max_abs_error = 0.0;
  double max_rel_error = 0.0;
  int correctness = 1;
  for (const Sample& sample : samples) {
    release_first.push_back(sample.release_first_us);
    release_last.push_back(sample.release_last_us);
    done.push_back(sample.done_us);
    gemm_first.push_back(sample.gemm_first_start_us);
    gemm_last.push_back(sample.gemm_last_end_us);
    e2e.push_back(sample.e2e_us);
    max_abs_error = std::max(max_abs_error, sample.max_abs_error);
    max_rel_error = std::max(max_rel_error, sample.max_rel_error);
    correctness = std::min(correctness, sample.correctness);
  }
  const int global_rows = benchmark.world() * config.local_rows;
  const size_t slice_bytes =
      static_cast<size_t>(benchmark.world()) * (config.local_rows / config.q) * config.k * sizeof(float);
  stream << csv_escape(config.run_id) << ',' << utc_timestamp() << ',' << csv_escape(hostname()) << ','
         << csv_escape(device_model(benchmark.property())) << ',' << benchmark.world() << ",fp32," << global_rows << ','
         << config.n << ',' << config.k << ",AllGather-GEMM," << config.q << ',' << slice_bytes << ",NCCL,"
         << strategy_name(strategy) << ',' << csv_escape(config.transport_hint) << ',' << config.warmup << ','
         << samples.size() << ',' << (correctness ? "PASS" : "FAIL") << ',' << correctness << ','
         << std::setprecision(12) << max_abs_error << ',' << max_rel_error << ',' << mean(release_first) << ','
         << percentile(release_first, 0.50) << ',' << percentile(release_first, 0.95) << ',' << mean(release_last) << ','
         << mean(done) << ',' << percentile(done, 0.50) << ',' << percentile(done, 0.95) << ',' << mean(gemm_first)
         << ',' << mean(gemm_last) << ',' << mean(e2e) << ',' << percentile(e2e, 0.50) << ','
         << percentile(e2e, 0.95) << ',' << csv_escape(log_path) << ',' << config.window << '\n';
}

int local_rank_from_mpi() {
  MPI_Comm local_communicator = MPI_COMM_NULL;
  MPI_CHECK(MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, 0, MPI_INFO_NULL, &local_communicator));
  int local_rank = 0;
  MPI_CHECK(MPI_Comm_rank(local_communicator, &local_rank));
  MPI_CHECK(MPI_Comm_free(&local_communicator));
  return local_rank;
}

int main(int argc, char** argv) {
  int mpi_initialized = 0;
  ncclComm_t communicator = nullptr;
  try {
    MPI_CHECK(MPI_Init(&argc, &argv));
    mpi_initialized = 1;
    int rank = 0;
    int world = 1;
    MPI_CHECK(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
    MPI_CHECK(MPI_Comm_size(MPI_COMM_WORLD, &world));
    const Config config = parse_args(argc, argv);

    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    const int local_rank = local_rank_from_mpi();
    if (device_count == 0 || local_rank >= device_count) {
      throw std::runtime_error("local MPI rank exceeds the CUDA devices visible on this host");
    }
    CUDA_CHECK(cudaSetDevice(local_rank));
    cudaDeviceProp property {};
    CUDA_CHECK(cudaGetDeviceProperties(&property, local_rank));

    ncclUniqueId unique_id {};
    if (rank == 0) NCCL_CHECK(ncclGetUniqueId(&unique_id));
    MPI_CHECK(MPI_Bcast(&unique_id, sizeof(unique_id), MPI_BYTE, 0, MPI_COMM_WORLD));
    NCCL_CHECK(ncclCommInitRank(&communicator, world, unique_id, rank));

    if (rank == 0) fs::create_directories(config.output_dir);
    MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
    const fs::path output_dir(config.output_dir);
    const std::string rank_log_path = (output_dir / ("rank" + std::to_string(rank) + ".log")).string();
    std::ofstream rank_log(rank_log_path, std::ios::out | std::ios::trunc);
    rank_log << "run_id=" << config.run_id << '\n'
             << "timestamp_utc=" << utc_timestamp() << '\n'
             << "rank=" << rank << '/' << world << '\n'
             << "local_rank=" << local_rank << '\n'
             << "cuda_device=" << local_rank << '\n'
             << "gpu_model=" << property.name << '\n'
             << "dimensions=M=" << world * config.local_rows << ",N=" << config.n << ",K=" << config.k << '\n'
             << "q=" << config.q << '\n'
             << "window=" << config.window << '\n';

    CsvWriters writers;
    std::ofstream release_curve;
    if (!config.release_curve_path.empty()) {
      const std::string curve_path =
          config.release_curve_path + ".rank" + std::to_string(rank) + ".csv";
      release_curve.open(curve_path, std::ios::out | std::ios::trunc);
      release_curve << "strategy,iteration,rank,q,slice,t_release_us\n";
    }
    const std::string rank_csv_path = (output_dir / ("raw_rank" + std::to_string(rank) + ".csv")).string();
    writers.rank_raw.open(rank_csv_path, std::ios::out | std::ios::trunc);
    write_raw_header(writers.rank_raw);
    if (rank == 0) {
      writers.global_raw.open(output_dir / "raw_global_samples.csv", std::ios::out | std::ios::trunc);
      writers.summary.open(output_dir / "summary.csv", std::ios::out | std::ios::trunc);
      writers.manifest.open(output_dir / "manifest.csv", std::ios::out | std::ios::trunc);
      write_raw_header(writers.global_raw);
      write_summary_header(writers.summary);
      write_manifest_header(writers.manifest);
    }

    Benchmark benchmark(config, rank, world, local_rank, property, communicator);
    benchmark.establish_reference();
    benchmark.warmup_all();

    int global_pass = 1;
    for (Strategy strategy : {Strategy::kFullSerial, Strategy::kSliceSerial, Strategy::kSliceOverlap}) {
      std::vector<Sample> global_samples;
      if (rank == 0) global_samples.reserve(config.iterations);
      for (int iteration = 0; iteration < config.iterations; ++iteration) {
        const Sample local_sample = benchmark.run_timed(strategy);
        if (release_curve.is_open()) {
          for (size_t slice = 0; slice < local_sample.slice_release_us.size(); ++slice) {
            release_curve << strategy_name(strategy) << ',' << iteration << ',' << rank << ','
                          << config.q << ',' << slice << ',' << std::setprecision(12)
                          << local_sample.slice_release_us[slice] << '\n';
          }
          release_curve.flush();
        }
        write_sample(writers.rank_raw, "rank", config, benchmark, strategy, iteration, local_sample, rank_log_path);
        writers.rank_raw.flush();
        const Sample global_sample = max_across_ranks(local_sample);
        if (rank == 0) {
          write_sample(writers.global_raw, "global_max", config, benchmark, strategy, iteration, global_sample,
                       (output_dir / "rank{rank}.log").string());
          writers.global_raw.flush();
          global_samples.push_back(global_sample);
          global_pass = std::min(global_pass, global_sample.correctness);
        }
      }
      if (rank == 0) {
        write_summary(writers.summary, config, benchmark, strategy, global_samples,
                      (output_dir / "rank{rank}.log").string());
        writers.summary.flush();
      }
      MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
    }

    if (rank == 0) {
      writers.manifest << csv_escape(config.run_id) << ',' << utc_timestamp() << ','
                       << (global_pass ? "PASS" : "FAIL") << ',' << world << ',' << config.local_rows << ','
                       << world * config.local_rows << ',' << config.n << ',' << config.k << ',' << config.q << ','
                       << config.warmup << ',' << config.iterations << ",NCCL," << csv_escape(property.name) << ','
                       << csv_escape(config.transport_hint) << ",raw_rank{rank}.csv,raw_global_samples.csv,summary.csv,"
                       << "rank{rank}.log," << config.window << '\n';
      std::cout << "run_id=" << config.run_id << " status=" << (global_pass ? "PASS" : "FAIL")
                << " output_dir=" << config.output_dir << std::endl;
    }
    MPI_CHECK(MPI_Bcast(&global_pass, 1, MPI_INT, 0, MPI_COMM_WORLD));
    NCCL_CHECK(ncclCommDestroy(communicator));
    communicator = nullptr;
    MPI_CHECK(MPI_Finalize());
    return global_pass ? 0 : 2;
  } catch (const std::exception& error) {
    std::cerr << "fatal: " << error.what() << std::endl;
    if (communicator != nullptr) ncclCommDestroy(communicator);
    if (mpi_initialized) MPI_Abort(MPI_COMM_WORLD, 1);
    return 1;
  }
}
