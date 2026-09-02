# AG-GEMM Phase 1 Baseline

This benchmark tests a dependency-aware AllGather-GEMM pipeline without assuming PGAS completion semantics.

It implements three controlled strategies for the same q partitioning, GEMM math, and rank-major output layout:

- B0_FULL_SERIAL: one complete NCCL AllGather, followed by one complete GEMM.
- B1_SLICE_SERIAL: q AllGather slices and q slice GEMMs, but slice i + 1 cannot issue until GEMM i ends. This measures the partitioning cost without overlap.
- B2_SLICE_EVENT_OVERLAP: each NCCL slice records a CUDA event; the compute stream waits for that event before its corresponding GEMM. t_release(i) is the legal NCCL event time, never an unsynchronized read.

The initial implementation uses FP32 and cuBLAS deliberately. It is a correctness-first Phase 1 baseline, not a final GEMM kernel or a claim about tensor-core performance. Add FP16/BF16 and cuBLASLt only after this baseline passes on the target 2/4-rank host.

## Build

    cd /root/comm-study/ag-gemm-bench
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j

## Minimal preflight

The current host must expose at least one CUDA device. A single-rank run validates data layout, event ordering, output comparison, and CSV emission, but does not measure inter-GPU communication.

    mpirun --allow-run-as-root --bind-to none -np 1 ./build/ag_gemm_bench \
      --local-rows 128 --k 128 --n 128 --q 2 --warmup 2 --iterations 3 \
      --run-id single_gpu_preflight --output-dir results/single_gpu_preflight

## Formal Phase 1 matrix

On a host that exposes RANKS local CUDA GPUs, build first and run:

    RANKS=4 WARMUP=20 ITERATIONS=50 REPETITIONS=5 \
      TRANSPORT_HINT='SHM/direct (verify from NCCL logs)' \
      ./scripts/run_phase1_matrix.sh

The script writes platform_facts.txt, NCCL logs, stdout/stderr, a top-level run manifest, and one directory per run. Each run contains:

- raw_rank{rank}.csv: one local timing record per timed repetition and strategy.
- raw_global_samples.csv: rank-maximum timing records, which are the end-to-end comparison values.
- summary.csv: derived mean/p50/p95 values; never the only retained data.
- manifest.csv and rank{rank}.log: exact configuration and rank/device mapping.

B2 may only be compared with B1 at the same q; comparing it only with B0 confounds overlap with fragmented-GEMM cost.

