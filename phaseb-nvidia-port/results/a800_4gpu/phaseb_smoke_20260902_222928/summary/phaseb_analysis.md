# Phase B analysis (cross-substrate AG-GEMM)

- result root: `./results/a800_4gpu/phaseb_smoke_20260902_222928`
- cases: 13 (PASS 0, other 13)

## Selection boundary (isolated winner vs e2e winner)

| cand | N | q | isolated winner | e2e winner | iso family | e2e family | flag |
|---|---|---|---|---|---|---|---|

## Control table (positive = listed path faster)

| cand | N | q | r1/rs | r1/r0 | d1/ds | d1/d0 | r1/d1 | d1-done vs dc-done (transport stretch) |
|---|---|---|---|---|---|---|---|---|

Cross-substrate reversal cells (per-candidate table): 0 / 0

## Cross-candidate boundary (isolated vs e2e pooled across RCCL configs)

| N | q | isolated ranking (top3, us) | e2e ranking (top3, us) | iso fam | e2e fam | substrate flag | C2 vs C0 iso% / e2e% | config flag |
|---|---|---|---|---|---|---|---|---|

Cross-substrate reversal cells: 0 / 0; RCCL-internal C0/C2 reversal cells: 0 / 0

## Case status

- case001_comm_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case002_comm_C2_RING_SIMPLE_CH8_N2048_q8_rep1: status=NO_DATA exit=255
- case003_gemm_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case004_r0_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case005_rs_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case006_r1_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case007_r1_C2_RING_SIMPLE_CH8_N2048_q8_rep1: status=NO_DATA exit=255
- case008_fc_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case009_dc_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case010_d0_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case011_ds_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case012_d1_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
- case013_d1w_C0_DEFAULT_N2048_q8_rep1: status=NO_DATA exit=255
