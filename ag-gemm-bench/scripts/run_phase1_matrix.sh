#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
benchmark=$(printenv BENCHMARK 2>/dev/null || printf '%s/build/ag_gemm_bench' "$script_dir")
ranks=$(printenv RANKS 2>/dev/null || printf '4')
warmup=$(printenv WARMUP 2>/dev/null || printf '20')
iterations=$(printenv ITERATIONS 2>/dev/null || printf '50')
repetitions=$(printenv REPETITIONS 2>/dev/null || printf '5')
transport_hint=$(printenv TRANSPORT_HINT 2>/dev/null || printf 'UNSPECIFIED')
output_root=$(printenv OUTPUT_ROOT 2>/dev/null || printf '%s/results/phase1_%s' "$script_dir" "$(date -u +%Y%m%dT%H%M%SZ)")

if [[ ! -x "$benchmark" ]]; then
  printf 'benchmark not found or not executable: %s\n' "$benchmark" >&2
  exit 1
fi

mkdir -p "$output_root"
"$script_dir/scripts/collect_platform_facts.sh" "$output_root"

# Replace these controlled starter shapes with three trace-derived AG-GEMM shapes before formal runs.
shapes=("1024 1024 1024" "2048 1024 2048" "4096 4096 1024")
partitions=(1 2 4 8)

for shape in "${shapes[@]}"; do
  read -r local_rows k n <<< "$shape"
  for q in "${partitions[@]}"; do
    if (( local_rows % q != 0 )); then
      continue
    fi
    for repetition in $(seq 1 "$repetitions"); do
      printf -v run_id 'phase1_r%s_m%s_n%s_k%s_q%s_rep%s' "$ranks" "$local_rows" "$n" "$k" "$q" "$repetition"
      case_dir="$output_root/$run_id"
      mkdir -p "$case_dir"
      set +e
      NCCL_DEBUG=INFO \
      NCCL_DEBUG_SUBSYS=INIT,GRAPH,ENV \
      NCCL_DEBUG_FILE="$case_dir/nccl.%h.%p.log" \
      mpirun --allow-run-as-root --bind-to none -np "$ranks" "$benchmark" \
        --local-rows "$local_rows" --k "$k" --n "$n" --q "$q" \
        --warmup "$warmup" --iterations "$iterations" --run-id "$run_id" \
        --transport-hint "$transport_hint" --output-dir "$case_dir" \
        > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
      exit_code=$?
      set -e
      printf '%s,%s,%s,%s\n' "$run_id" "$exit_code" "$case_dir" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$output_root/run_manifest.csv"
    done
  done
done

