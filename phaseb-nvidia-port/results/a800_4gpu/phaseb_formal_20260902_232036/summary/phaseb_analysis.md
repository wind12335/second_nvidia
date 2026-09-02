# Phase B analysis (cross-substrate AG-GEMM)

- result root: `./results/a800_4gpu/phaseb_formal_20260902_232036`
- cases: 655 (PASS 655, other 0)

## Selection boundary (isolated winner vs e2e winner)

| cand | N | q | isolated winner | e2e winner | iso family | e2e family | flag |
|---|---|---|---|---|---|---|---|
| C0_DEFAULT | 512 | 2 | FC_FCOLLECT_ONLY (440.960us) | R1_EVENT_OVERLAP (1379.184us) | DUSHMEM | RCCL | REVERSAL |
| C0_DEFAULT | 512 | 4 | FC_FCOLLECT_ONLY (441.024us) | R1_EVENT_OVERLAP (1377.216us) | DUSHMEM | RCCL | REVERSAL |
| C0_DEFAULT | 512 | 8 | FC_FCOLLECT_ONLY (440.992us) | R0_FULL_SERIAL (1425.088us) | DUSHMEM | RCCL | REVERSAL |
| C0_DEFAULT | 2048 | 2 | FC_FCOLLECT_ONLY (462.896us) | D0_FCOLLECT_SERIAL (4109.296us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 2048 | 4 | FC_FCOLLECT_ONLY (462.176us) | D0_FCOLLECT_SERIAL (4112.240us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 2048 | 8 | FC_FCOLLECT_ONLY (462.416us) | D0_FCOLLECT_SERIAL (4111.424us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 2048 | 16 | DC_PUSHSIG_ONLY (1020.176us) | D1_PUSHSIG_OVERLAP (4899.072us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 4096 | 2 | FC_FCOLLECT_ONLY (496.064us) | D0_FCOLLECT_SERIAL (7855.792us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 4096 | 4 | FC_FCOLLECT_ONLY (496.544us) | R0_FULL_SERIAL (7854.064us) | DUSHMEM | RCCL | REVERSAL |
| C0_DEFAULT | 4096 | 8 | FC_FCOLLECT_ONLY (496.064us) | D0_FCOLLECT_SERIAL (7857.424us) | DUSHMEM | DUSHMEM | CONSISTENT |
| C0_DEFAULT | 4096 | 16 | COMM_ONLY (1210.256us) | R1_EVENT_OVERLAP (8620.080us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 512 | 2 | COMM_ONLY (568.112us) | R1_EVENT_OVERLAP (1378.016us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 512 | 4 | COMM_ONLY (676.608us) | R1_EVENT_OVERLAP (1387.616us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 512 | 8 | COMM_ONLY (888.224us) | R1_EVENT_OVERLAP (1589.152us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 2048 | 2 | COMM_ONLY (594.320us) | R1_EVENT_OVERLAP (4436.320us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 2048 | 4 | COMM_ONLY (708.032us) | R1_EVENT_OVERLAP (4301.552us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 2048 | 8 | COMM_ONLY (920.976us) | R1_EVENT_OVERLAP (4429.104us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 2048 | 16 | COMM_ONLY (1371.200us) | R1_EVENT_OVERLAP (4825.488us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 4096 | 2 | COMM_ONLY (628.720us) | R1_EVENT_OVERLAP (8055.073us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 4096 | 4 | COMM_ONLY (740.592us) | R1_EVENT_OVERLAP (8255.776us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 4096 | 8 | COMM_ONLY (951.536us) | R1_EVENT_OVERLAP (8381.951us) | RCCL | RCCL | CONSISTENT |
| C2_RING_SIMPLE_CH8 | 4096 | 16 | COMM_ONLY (1401.696us) | R1_EVENT_OVERLAP (8673.647us) | RCCL | RCCL | CONSISTENT |

## Control table (positive = listed path faster)

| cand | N | q | r1/rs | r1/r0 | d1/ds | d1/d0 | r1/d1 | d1-done vs dc-done (transport stretch) |
|---|---|---|---|---|---|---|---|---|
| C0_DEFAULT | 512 | 2 | 12.439 | 3.204 | 10.882 | -7.344 | 9.927 | 62.450 |
| C0_DEFAULT | 512 | 4 | 17.010 | 3.367 | 16.563 | -2.728 | 6.037 | 85.867 |
| C0_DEFAULT | 512 | 8 | 22.780 | -12.229 | 22.619 | -15.390 | 2.834 | 49.469 |
| C0_DEFAULT | 2048 | 2 | 3.468 | -6.745 | 4.945 | -8.311 | 1.359 | 261.730 |
| C0_DEFAULT | 2048 | 4 | 9.267 | -3.631 | 8.090 | -7.189 | 3.304 | 102.242 |
| C0_DEFAULT | 2048 | 8 | 9.494 | -8.283 | 9.996 | -8.811 | 0.466 | 280.450 |
| C0_DEFAULT | 2048 | 16 | 14.474 |  | 14.213 |  | -0.191 | 153.319 |
| C0_DEFAULT | 4096 | 2 | 0.854 | -1.860 | 2.502 | -1.538 | -0.322 | 512.779 |
| C0_DEFAULT | 4096 | 4 | 2.473 | -4.913 | 4.574 | -4.153 | -0.698 | 237.498 |
| C0_DEFAULT | 4096 | 8 | 3.094 | -9.007 | 6.036 | -6.294 | -2.553 | 454.514 |
| C0_DEFAULT | 4096 | 16 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 512 | 2 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 512 | 4 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 512 | 8 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 2048 | 2 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 2048 | 4 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 2048 | 8 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 2048 | 16 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 4096 | 2 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 4096 | 4 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 4096 | 8 |  |  |  |  |  |  |
| C2_RING_SIMPLE_CH8 | 4096 | 16 |  |  |  |  |  |  |

Cross-substrate reversal cells (per-candidate table): 4 / 22

## Cross-candidate boundary (isolated vs e2e pooled across RCCL configs)

| N | q | isolated ranking (top3, us) | e2e ranking (top3, us) | iso fam | e2e fam | substrate flag | C2 vs C0 iso% / e2e% | config flag |
|---|---|---|---|---|---|---|---|---|
| 512 | 2 | fc_fcollect_only_c0_default:441 < comm_only_c0_default:475 < comm_only_c2_ring_simple_ch8:568 | r1_event_overlap_c2_ring_simple_ch8:1378 < r1_event_overlap_c0_default:1379 < r0_full_serial_c0_default:1425 | DUSHMEM | RCCL | REVERSAL | -19.709 / 0.085 | CONSISTENT |
| 512 | 4 | fc_fcollect_only_c0_default:441 < comm_only_c0_default:555 < dc_pushsig_only_c0_default:634 | r1_event_overlap_c0_default:1377 < r1_event_overlap_c2_ring_simple_ch8:1388 < r0_full_serial_c0_default:1425 | DUSHMEM | RCCL | REVERSAL | -21.990 / -0.755 | CONSISTENT |
| 512 | 8 | fc_fcollect_only_c0_default:441 < dc_pushsig_only_c0_default:728 < comm_only_c0_default:732 | r0_full_serial_c0_default:1425 < d0_fcollect_serial_c0_default:1426 < r1_event_overlap_c2_ring_simple_ch8:1589 | DUSHMEM | RCCL | REVERSAL | -21.324 / 0.638 | CONSISTENT |
| 2048 | 2 | fc_fcollect_only_c0_default:463 < comm_only_c0_default:500 < comm_only_c2_ring_simple_ch8:594 | d0_fcollect_serial_c0_default:4109 < r0_full_serial_c0_default:4113 < r1_event_overlap_c0_default:4390 | DUSHMEM | DUSHMEM | CONSISTENT | -18.773 / -1.048 | CONSISTENT |
| 2048 | 4 | fc_fcollect_only_c0_default:462 < comm_only_c0_default:581 < dc_pushsig_only_c0_default:666 | d0_fcollect_serial_c0_default:4112 < r0_full_serial_c0_default:4113 < r1_event_overlap_c0_default:4262 | DUSHMEM | DUSHMEM | CONSISTENT | -21.893 / -0.923 | CONSISTENT |
| 2048 | 8 | fc_fcollect_only_c0_default:462 < dc_pushsig_only_c0_default:750 < comm_only_c0_default:755 | d0_fcollect_serial_c0_default:4111 < r0_full_serial_c0_default:4112 < r1_event_overlap_c2_ring_simple_ch8:4429 | DUSHMEM | DUSHMEM | CONSISTENT | -21.925 / 0.533 | CONSISTENT |
| 2048 | 16 | dc_pushsig_only_c0_default:1020 < comm_only_c0_default:1182 < comm_only_c2_ring_simple_ch8:1371 | r1_event_overlap_c2_ring_simple_ch8:4825 < d1_pushsig_overlap_c0_default:4899 < r1_event_overlap_c0_default:4908 | DUSHMEM | RCCL | REVERSAL | -16.015 / 1.690 | RCCL_CONFIG_REVERSAL |
| 4096 | 2 | fc_fcollect_only_c0_default:496 < comm_only_c0_default:534 < comm_only_c2_ring_simple_ch8:629 | d0_fcollect_serial_c0_default:7856 < r0_full_serial_c0_default:7856 < d1_pushsig_overlap_c0_default:7977 | DUSHMEM | DUSHMEM | CONSISTENT | -17.766 / -0.660 | CONSISTENT |
| 4096 | 4 | fc_fcollect_only_c0_default:497 < comm_only_c0_default:614 < dc_pushsig_only_c0_default:706 | r0_full_serial_c0_default:7854 < d0_fcollect_serial_c0_default:7857 < d1_pushsig_overlap_c0_default:8183 | DUSHMEM | RCCL | REVERSAL | -20.690 / -0.193 | CONSISTENT |
| 4096 | 8 | fc_fcollect_only_c0_default:496 < dc_pushsig_only_c0_default:787 < comm_only_c0_default:791 | d0_fcollect_serial_c0_default:7857 < r0_full_serial_c0_default:7858 < d1_pushsig_overlap_c0_default:8352 | DUSHMEM | DUSHMEM | CONSISTENT | -20.233 / 2.140 | RCCL_CONFIG_REVERSAL |
| 4096 | 16 | comm_only_c0_default:1210 < comm_only_c2_ring_simple_ch8:1402 | r1_event_overlap_c0_default:8620 < r1_event_overlap_c2_ring_simple_ch8:8674 | RCCL | RCCL | CONSISTENT | -15.818 / -0.621 | CONSISTENT |

Cross-substrate reversal cells: 5 / 11; RCCL-internal C0/C2 reversal cells: 2 / 11

## Case status

