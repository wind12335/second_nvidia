#!/usr/bin/env bash
# NVSHMEM 实验线编排（2026-09-02 A800 会话）：formal → matched五格 串行流水
# 由 setsid+nohup 脱离会话运行；产物：/root/port_line_status.txt 供轮询
set -uo pipefail
export LD_LIBRARY_PATH=/root/miniconda3/lib/python3.10/site-packages/nvidia/nvshmem/lib:/root/nvshmem-3.6.5-wheel/lib:${LD_LIBRARY_PATH:-}
cd /root/second_nvidia/phaseb-nvidia-port

echo "$(date -u +%FT%TZ) LINE_START formal launching" > /root/port_line_status.txt
PHASEB_RESULT_BASE=./results/a800_4gpu bash run_phaseb_nv.sh formal > /tmp/port_formal3.log 2>&1
FRC=$?
FOK=$(grep -c " ok \]" /tmp/port_formal3.log); FFAIL=$(grep -c "FAIL" /tmp/port_formal3.log)
echo "$(date -u +%FT%TZ) FORMAL_DONE rc=$FRC ok=$FOK fail=$FFAIL" >> /root/port_line_status.txt

if [[ $FRC -eq 0 ]]; then
  echo "$(date -u +%FT%TZ) MATCHED launching" >> /root/port_line_status.txt
  bash run_matched_shapes_hygon.sh > /tmp/matched_hygon.log 2>&1
  MRC=$?
  MOK=$(grep -c "\[PASS\]" /tmp/matched_hygon.log); MFAIL=$(grep -c "\[FAIL\]" /tmp/matched_hygon.log)
  echo "$(date -u +%FT%TZ) MATCHED_DONE rc=$MRC pass=$MOK fail=$MFAIL" >> /root/port_line_status.txt
else
  echo "$(date -u +%FT%TZ) MATCHED_SKIPPED (formal rc!=0)" >> /root/port_line_status.txt
fi
echo "$(date -u +%FT%TZ) LINE_END" >> /root/port_line_status.txt
