#!/usr/bin/env bash
set -euo pipefail

output_dir=$1
if [[ -z "$output_dir" ]]; then
  printf 'usage: collect_platform_facts.sh OUTPUT_DIR\n' >&2
  exit 2
fi
mkdir -p "$output_dir"

{
  date -u +%Y-%m-%dT%H:%M:%SZ
  hostname
  uname -a
  nvidia-smi -L
  nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,driver_version,compute_cap,memory.total,pstate,temperature.gpu --format=csv,noheader
  nvidia-smi topo -m
  nvcc --version
  mpirun --version
  if command -v rg >/dev/null 2>&1; then
    ldconfig -p | rg 'libnccl|libcublas' || true
    env | rg '^(CUDA|NCCL|OMPI|SLURM|PATH|LD_LIBRARY_PATH)=' || true
  else
    ldconfig -p | grep -E 'libnccl|libcublas' || true
    env | grep -E '^(CUDA|NCCL|OMPI|SLURM|PATH|LD_LIBRARY_PATH)=' || true
  fi
} > "$output_dir/platform_facts.txt" 2>&1
