#!/usr/bin/env bash
# Stage 1 full matrix per protocol 下一阶段实验计划 §6 + README-RUN-ORDER:
#   Stage A: 8 representative shapes x q{1,2,4,8,16} x DEFAULT x window=0 x 5 reps
#   Stage B: B4 candidates (DEFAULT / Ring-Simple ch1/ch4/ch8) on 3 shapes x q{4,8,16} x 3 reps
#   Stage C: window {1,2,4} on 3 shapes x q{4,8,16} x DEFAULT x 3 reps
# Shapes are representative (comm/balanced/compute-heavy), NOT first-paper trace derived:
# the trace export is not present on this host. Recorded honestly in every manifest.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
benchmark="$script_dir/build/ag_gemm_bench"
output_root=${OUTPUT_ROOT:-$script_dir/results/stage1_$(date -u +%Y%m%dT%H%M%SZ)}
RANKS=${RANKS:-4}
WARMUP=${WARMUP:-20}
ITERATIONS=${ITERATIONS:-50}
STAGES=${STAGES:-"A B C"}

[[ -x "$benchmark" ]] || { echo "benchmark missing: $benchmark" >&2; exit 1; }
mkdir -p "$output_root"
"$script_dir/scripts/collect_platform_facts.sh" "$output_root"

# name|local_rows|K|N|category
SHAPES_A=(
  "S1|4096|512|512|comm_heavy"
  "S2|2048|1024|2048|comm_heavy"
  "S5|4096|4096|1024|comm_heavy"
  "S4|512|4096|4096|balanced"
  "S6|1024|4096|4096|balanced"
  "S3|256|8192|8192|balanced_compute"
  "S7|1024|4096|16384|compute_heavy"
  "S8|2048|4096|8192|compute_heavy"
)
SHAPES_B=("S1|4096|512|512|comm_heavy" "S4|512|4096|4096|balanced" "S7|1024|4096|16384|compute_heavy")
SHAPES_C=("S1|4096|512|512|comm_heavy" "S4|512|4096|4096|balanced" "S5|4096|4096|1024|comm_heavy")

# candidate_id|env assignments
CANDIDATES=(
  "DEFAULT|"
  "RS_ch1|NCCL_ALGO=Ring NCCL_PROTO=Simple NCCL_NCHANNELS=1"
  "RS_ch4|NCCL_ALGO=Ring NCCL_PROTO=Simple NCCL_NCHANNELS=4"
  "RS_ch8|NCCL_ALGO=Ring NCCL_PROTO=Simple NCCL_NCHANNELS=8"
)

manifest="$output_root/run_manifest.csv"
echo "run_id,stage,candidate,shape_id,category,local_rows,K,N,q,window,repetition,exit_code,case_dir,timestamp_utc" > "$manifest"

run_case() {
  local stage=$1 cand_id=$2 cand_env=$3 shape_id=$4 lr=$5 k=$6 n=$7 cat=$8 q=$9 w=${10} rep=${11}
  local run_id="stage1_${stage}_${cand_id}_${shape_id}_m${lr}k${k}n${n}_q${q}w${w}_rep${rep}"
  local case_dir="$output_root/$run_id"
  mkdir -p "$case_dir"
  printf '%s\n' "stage=$stage candidate=$cand_id env=[$cand_env] shape=$shape_id local_rows=$lr K=$k N=$n q=$q window=$w rep=$rep" > "$case_dir/case_config.txt"
  set +e
  # NCCL INFO log only on rep 1 to keep formal runs light; evidence purpose only
  local debug_env=()
  if [[ $rep == 1 ]]; then
    debug_env=(NCCL_DEBUG=INFO NCCL_DEBUG_SUBSYS=INIT,ENV,TUNING NCCL_DEBUG_FILE="$case_dir/nccl.%h.%p.log")
  fi
  env $cand_env "${debug_env[@]}" \
    mpirun --allow-run-as-root --bind-to none -np "$RANKS" "$benchmark" \
      --local-rows "$lr" --k "$k" --n "$n" --q "$q" --window "$w" \
      --warmup "$WARMUP" --iterations "$ITERATIONS" \
      --run-id "$run_id" --transport-hint "${cand_id}" \
      --output-dir "$case_dir" \
      > "$case_dir/stdout.log" 2> "$case_dir/stderr.log"
  local rc=$?
  set -e
  echo "$run_id,$stage,$cand_id,$shape_id,$cat,$lr,$k,$n,$q,$w,$rep,$rc,$case_dir,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$manifest"
  if (( rc != 0 )); then
    echo "[WARN] $run_id exit=$rc (recorded as UNSUPPORTED/ERROR, kept in manifest)" >&2
  fi
}

for stage in $STAGES; do
  case $stage in
    A)
      for shape in "${SHAPES_A[@]}"; do
        IFS='|' read -r sid lr k n cat <<< "$shape"
        for q in 1 2 4 8 16; do
          for rep in 1 2 3 4 5; do
            run_case A DEFAULT "" "$sid" "$lr" "$k" "$n" "$cat" "$q" 0 "$rep"
          done
        done
      done
      ;;
    B)
      for shape in "${SHAPES_B[@]}"; do
        IFS='|' read -r sid lr k n cat <<< "$shape"
        for cand in "${CANDIDATES[@]}"; do
          IFS='|' read -r cid cenv <<< "$cand"
          for q in 4 8 16; do
            for rep in 1 2 3; do
              run_case B "$cid" "$cenv" "$sid" "$lr" "$k" "$n" "$cat" "$q" 0 "$rep"
            done
          done
        done
      done
      ;;
    C)
      for shape in "${SHAPES_C[@]}"; do
        IFS='|' read -r sid lr k n cat <<< "$shape"
        for q in 4 8 16; do
          for w in 1 2 4; do
            for rep in 1 2 3; do
              run_case C DEFAULT "" "$sid" "$lr" "$k" "$n" "$cat" "$q" "$w" "$rep"
            done
          done
        done
      done
      ;;
    *) echo "unknown stage $stage" >&2; exit 2;;
  esac
  echo "[INFO] stage $stage done $(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
done
echo "[DONE] results in $output_root"
