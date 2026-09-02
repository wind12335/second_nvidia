# Phase B analysis (cross-substrate AG-GEMM)

- result root: `./results/a800_4gpu/phaseb_smoke_20260902_223032`
- cases: 13 (PASS 13, other 0)

## Selection boundary (isolated winner vs e2e winner)

| cand | N | q | isolated winner | e2e winner | iso family | e2e family | flag |
|---|---|---|---|---|---|---|---|
| C0_DEFAULT | 2048 | 8 | FC_FCOLLECT_ONLY (465.344us) | D0_FCOLLECT_SERIAL (4115.712us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 2048 | 8 | COMM_ONLY (916.352us) | R1_EVENT_OVERLAP (4426.672us) | RCCL | RCCL | CONSISTENT |

## Control table (positive = listed path faster)

| cand | N | q | r1/rs | r1/r0 | d1/ds | d1/d0 | r1/d1 | d1-done vs dc-done (transport stretch) |
|---|---|---|---|---|---|---|---|---|
| C0_DEFAULT | 2048 | 8 | 9.488 | -8.260 | 9.942 | -8.734 | 0.432 | 287.034 |
| C2_RING_SIMPLE_CH8 | 2048 | 8 |  |  |  |  |  |  |

Cross-substrate reversal cells (per-candidate table): 0 / 2

## Cross-candidate boundary (isolated vs e2e pooled across RCCL configs)

| N | q | isolated ranking (top3, us) | e2e ranking (top3, us) | iso fam | e2e fam | substrate flag | C2 vs C0 iso% / e2e% | config flag |
|---|---|---|---|---|---|---|---|---|
| 2048 | 8 | fc_fcollect_only_c0_default:465 < dc_pushsig_only_c0_default:748 < comm_only_c0_default:754 | d0_fcollect_serial_c0_default:4116 < r0_full_serial_c0_default:4116 < r1_event_overlap_c2_ring_simple_ch8:4427 | DUSHMEM | DUSHMEM | CONSISTENT | -21.493 / 0.655 | CONSISTENT |

Cross-substrate reversal cells: 0 / 1; RCCL-internal C0/C2 reversal cells: 0 / 1

## Case status

