#include <cuda_runtime.h>
#include <mpi.h>
#include <nvshmem.h>
#include <nvshmemx.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

[[noreturn]] void fail(const std::string& message, int rank = -1) {
  std::cerr << "[nvshmem_admission rank=" << rank << "] " << message << std::endl;
  MPI_Abort(MPI_COMM_WORLD, 1);
  std::abort();
}

#define CUDA_CHECK(call) do { \
  cudaError_t _s = (call); \
  if (_s != cudaSuccess) fail(std::string("CUDA: ") + cudaGetErrorString(_s), rank); \
} while (0)
#define MPI_CHECK(call) do { \
  int _s = (call); \
  if (_s != MPI_SUCCESS) fail("MPI error " + std::to_string(_s), rank); \
} while (0)

struct Options {
  std::string case_id = "manual";
  std::string mode = "put_signal";
  std::string outdir = "results/manual";
  std::size_t payload_bytes = 4096;
  int epochs = 10;
  int slots = 1;
  int credit = 0;
  int quiet = 0;
  int credit_quiet = 1;
  int expected_pes = 4;
};

Options parse_options(int argc, char** argv, int rank) {
  Options o;
  for (int i = 1; i < argc; ++i) {
    std::string k = argv[i];
    auto value = [&](const std::string& name) -> std::string {
      if (++i >= argc) fail(name + " requires a value", rank);
      return argv[i];
    };
    if (k == "--case-id") o.case_id = value(k);
    else if (k == "--mode") o.mode = value(k);
    else if (k == "--outdir") o.outdir = value(k);
    else if (k == "--payload-bytes") o.payload_bytes = std::stoull(value(k));
    else if (k == "--epochs") o.epochs = std::stoi(value(k));
    else if (k == "--slots") o.slots = std::stoi(value(k));
    else if (k == "--credit") o.credit = std::stoi(value(k));
    else if (k == "--quiet") o.quiet = std::stoi(value(k));
    else if (k == "--credit-quiet") o.credit_quiet = std::stoi(value(k));
    else if (k == "--expected-pes") o.expected_pes = std::stoi(value(k));
    else if (k == "--help") {
      if (rank == 0) std::cout <<
        "nvshmem_admission --case-id ID --mode put_signal|fcollect "
        "--payload-bytes BYTES --epochs N --slots N --credit 0|1 "
        "--quiet 0|1 --outdir DIR\n";
      std::exit(0);
    } else fail("unknown option: " + k, rank);
  }
  if (o.payload_bytes == 0 || o.payload_bytes % sizeof(std::uint32_t) != 0 ||
      o.epochs <= 0 || o.slots <= 0 || o.expected_pes <= 0)
    fail("payload must be a positive multiple of 4; epochs/slots/pes must be positive", rank);
  if (o.mode != "put_signal" && o.mode != "fcollect") fail("unsupported mode", rank);
  if (o.mode == "fcollect" && o.credit) fail("credit is only implemented for put_signal", rank);
  return o;
}

__global__ void fill_pattern(std::uint32_t* source, std::size_t words, int producer,
                             std::uint64_t epoch) {
  std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  if (i < words) source[i] = 0xA5000000u ^ (static_cast<std::uint32_t>(producer) << 16) ^
                                  static_cast<std::uint32_t>(epoch) ^ static_cast<std::uint32_t>(i);
}

__global__ void verify_pattern(const std::uint32_t* recv, std::size_t words, int npes,
                               std::uint64_t epoch, int* errors) {
  std::size_t i = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
  std::size_t total = words * static_cast<std::size_t>(npes);
  if (i >= total) return;
  int producer = static_cast<int>(i / words);
  std::size_t word = i % words;
  std::uint32_t expected = 0xA5000000u ^ (static_cast<std::uint32_t>(producer) << 16) ^
                           static_cast<std::uint32_t>(epoch) ^ static_cast<std::uint32_t>(word);
  if (recv[i] != expected) atomicAdd(errors, 1);
}

double event_us(cudaEvent_t start, cudaEvent_t end, int rank) {
  float ms = 0.0f;
  CUDA_CHECK(cudaEventElapsedTime(&ms, start, end));
  return static_cast<double>(ms) * 1000.0;
}

struct Events {
  cudaEvent_t issue{}, comm_done{}, release{}, checked{};
  Events(int rank) {
    CUDA_CHECK(cudaEventCreate(&issue));
    CUDA_CHECK(cudaEventCreate(&comm_done));
    CUDA_CHECK(cudaEventCreate(&release));
    CUDA_CHECK(cudaEventCreate(&checked));
  }
  ~Events() {
    cudaEventDestroy(issue); cudaEventDestroy(comm_done);
    cudaEventDestroy(release); cudaEventDestroy(checked);
  }
};

void write_header(std::ofstream& out) {
  out << "case_id,mode,rank,npes,epoch,slot,payload_bytes,"
         "issue_to_comm_stream_complete_us,issue_to_release_us,issue_to_checked_us,"
         "checksum_mismatches,iteration_status\n";
}

int main(int argc, char** argv) {
  int rank = 0, world = 1;
  MPI_CHECK(MPI_Init(&argc, &argv));
  MPI_CHECK(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
  MPI_CHECK(MPI_Comm_size(MPI_COMM_WORLD, &world));
  Options o = parse_options(argc, argv, rank);
  if (world != o.expected_pes) fail("MPI world size differs from --expected-pes", rank);

  MPI_Comm mpi_comm = MPI_COMM_WORLD;
  nvshmemx_init_attr_t attr = NVSHMEMX_INIT_ATTR_INITIALIZER;
  attr.mpi_comm = &mpi_comm;
  nvshmemx_init_attr(NVSHMEMX_INIT_WITH_MPI_COMM, &attr);
  int pe = nvshmem_my_pe();
  int npes = nvshmem_n_pes();
  int device = nvshmem_team_my_pe(NVSHMEMX_TEAM_NODE);
  CUDA_CHECK(cudaSetDevice(device));
  if (npes != world) fail("NVSHMEM PE count differs from MPI world", rank);

  const std::size_t words = o.payload_bytes / sizeof(std::uint32_t);
  const std::size_t slot_words = words * static_cast<std::size_t>(npes);
  std::uint32_t* source = static_cast<std::uint32_t*>(nvshmem_malloc(o.payload_bytes));
  std::uint32_t* recv = static_cast<std::uint32_t*>(nvshmem_malloc(
      slot_words * static_cast<std::size_t>(o.slots) * sizeof(std::uint32_t)));
  std::uint64_t* signals = static_cast<std::uint64_t*>(nvshmem_malloc(
      static_cast<std::size_t>(npes) * o.slots * sizeof(std::uint64_t)));
  std::uint64_t* credits = static_cast<std::uint64_t*>(nvshmem_malloc(
      static_cast<std::size_t>(npes) * o.slots * sizeof(std::uint64_t)));
  int* errors = nullptr;
  CUDA_CHECK(cudaMalloc(&errors, sizeof(int)));
  CUDA_CHECK(cudaMemset(source, 0, o.payload_bytes));
  CUDA_CHECK(cudaMemset(recv, 0, slot_words * static_cast<std::size_t>(o.slots) * sizeof(std::uint32_t)));
  CUDA_CHECK(cudaMemset(signals, 0, static_cast<std::size_t>(npes) * o.slots * sizeof(std::uint64_t)));
  CUDA_CHECK(cudaMemset(credits, 0, static_cast<std::size_t>(npes) * o.slots * sizeof(std::uint64_t)));
  CUDA_CHECK(cudaDeviceSynchronize());
  nvshmem_barrier_all();

  cudaStream_t comm_stream{}, compute_stream{};
  CUDA_CHECK(cudaStreamCreateWithFlags(&comm_stream, cudaStreamNonBlocking));
  CUDA_CHECK(cudaStreamCreateWithFlags(&compute_stream, cudaStreamNonBlocking));
  Events ev(rank);
  fs::create_directories(fs::path(o.outdir) / "raw");
  std::ofstream raw(fs::path(o.outdir) / ("raw/rank_" + std::to_string(rank) + ".csv"));
  write_header(raw);
  if (rank == 0) {
    std::cout << "NVSHMEM admission case=" << o.case_id << " mode=" << o.mode
              << " payload_bytes=" << o.payload_bytes << " epochs=" << o.epochs
              << " slots=" << o.slots << " credit=" << o.credit
              << " quiet=" << o.quiet << " npes=" << npes << " arch=sm_89\n";
  }

  const int block = 256;
  const int fill_grid = static_cast<int>((words + block - 1) / block);
  const int verify_grid = static_cast<int>((slot_words + block - 1) / block);
  for (int epoch = 1; epoch <= o.epochs; ++epoch) {
    int slot = (epoch - 1) % o.slots;
    if (o.credit && epoch > o.slots) {
      std::uint64_t reusable = static_cast<std::uint64_t>(epoch - o.slots);
      for (int consumer = 0; consumer < npes; ++consumer) if (consumer != pe) {
        nvshmemx_signal_wait_until_on_stream(credits + consumer * o.slots + slot,
            NVSHMEM_CMP_GE, reusable, comm_stream);
      }
    }
    CUDA_CHECK(cudaEventRecord(ev.issue, comm_stream));
    fill_pattern<<<fill_grid, block, 0, comm_stream>>>(source, words, pe, epoch);
    CUDA_CHECK(cudaGetLastError());
    auto* local_dst = recv + static_cast<std::size_t>(slot) * slot_words +
                      static_cast<std::size_t>(pe) * words;
    CUDA_CHECK(cudaMemcpyAsync(local_dst, source, o.payload_bytes, cudaMemcpyDeviceToDevice, comm_stream));
    if (o.mode == "put_signal") {
      for (int peer = 0; peer < npes; ++peer) if (peer != pe) {
        auto* remote_recv = static_cast<std::uint32_t*>(nvshmem_ptr(recv, peer)) +
            static_cast<std::size_t>(slot) * slot_words + static_cast<std::size_t>(pe) * words;
        auto* remote_signal = static_cast<std::uint64_t*>(nvshmem_ptr(signals, peer)) +
            static_cast<std::size_t>(pe) * o.slots + slot;
        nvshmemx_putmem_signal_on_stream(remote_recv, source, o.payload_bytes, remote_signal,
                                         static_cast<std::uint64_t>(epoch), NVSHMEM_SIGNAL_SET,
                                         peer, comm_stream);
      }
      if (o.quiet) nvshmemx_quiet_on_stream(comm_stream);
    } else {
      int status = nvshmemx_fcollectmem_on_stream(
          NVSHMEM_TEAM_WORLD, recv + static_cast<std::size_t>(slot) * slot_words,
          source, o.payload_bytes, comm_stream);
      if (status != 0) fail("nvshmemx_fcollectmem_on_stream returned " + std::to_string(status), rank);
    }
    CUDA_CHECK(cudaEventRecord(ev.comm_done, comm_stream));
    if (o.mode == "put_signal") {
      for (int producer = 0; producer < npes; ++producer) if (producer != pe) {
        nvshmemx_signal_wait_until_on_stream(signals + producer * o.slots + slot,
            NVSHMEM_CMP_GE, static_cast<std::uint64_t>(epoch), comm_stream);
      }
    }
    CUDA_CHECK(cudaEventRecord(ev.release, comm_stream));
    CUDA_CHECK(cudaStreamWaitEvent(compute_stream, ev.release, 0));
    CUDA_CHECK(cudaMemsetAsync(errors, 0, sizeof(int), compute_stream));
    verify_pattern<<<verify_grid, block, 0, compute_stream>>>(
        recv + static_cast<std::size_t>(slot) * slot_words, words, npes, epoch, errors);
    CUDA_CHECK(cudaGetLastError());
    if (o.credit) {
      CUDA_CHECK(cudaStreamSynchronize(compute_stream));
      for (int consumer = 0; consumer < npes; ++consumer) if (consumer != pe) {
        auto* remote_credit = static_cast<std::uint64_t*>(nvshmem_ptr(credits, consumer)) +
            static_cast<std::size_t>(pe) * o.slots + slot;
        nvshmemx_signal_op_on_stream(remote_credit, static_cast<std::uint64_t>(epoch),
                                     NVSHMEM_SIGNAL_SET, consumer, compute_stream);
      }
      if (o.credit_quiet) nvshmemx_quiet_on_stream(compute_stream);
    }
    CUDA_CHECK(cudaEventRecord(ev.checked, compute_stream));
    CUDA_CHECK(cudaEventSynchronize(ev.checked));
    int host_errors = 0;
    CUDA_CHECK(cudaMemcpy(&host_errors, errors, sizeof(int), cudaMemcpyDeviceToHost));
    double comm_us = event_us(ev.issue, ev.comm_done, rank);
    double release_us = event_us(ev.issue, ev.release, rank);
    double checked_us = event_us(ev.issue, ev.checked, rank);
    raw << o.case_id << ',' << o.mode << ',' << pe << ',' << npes << ',' << epoch << ',' << slot
        << ',' << o.payload_bytes << ',' << std::fixed << std::setprecision(3)
        << comm_us << ',' << release_us << ',' << checked_us << ',' << host_errors << ','
        << (host_errors == 0 ? "PASS" : "FAIL_CHECKSUM") << '\n';
    raw.flush();
    nvshmem_barrier_all();
  }
  CUDA_CHECK(cudaDeviceSynchronize());
  raw.close();
  nvshmem_free(source); nvshmem_free(recv); nvshmem_free(signals); nvshmem_free(credits);
  CUDA_CHECK(cudaFree(errors));
  CUDA_CHECK(cudaStreamDestroy(comm_stream)); CUDA_CHECK(cudaStreamDestroy(compute_stream));
  nvshmem_finalize();
  MPI_CHECK(MPI_Finalize());
  return 0;
}

