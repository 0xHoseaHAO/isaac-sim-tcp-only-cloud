#!/bin/bash
# Stop Isaac Sim streaming kit + WebRTC client (keep TurboVNC / noVNC desktop).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env_file

ISAAC_ROOT="${ISAAC_ROOT:-}"
LOG_DIR="${LOG_DIR:-${ISAAC_TCP_ROOT}/logs}"
mkdir -p "${LOG_DIR}"
export ISAAC_ROOT

echo "[stop] Isaac Sim kit + WebRTC client..."
killall -9 isaacsim-webrtc-streaming-client 2>/dev/null || true

python3 - <<PY
import os, signal
killed = []
isaac_root = os.environ.get("ISAAC_ROOT", "")
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "ignore")
    except Exception:
        continue
    match = False
    if isaac_root and f"{isaac_root}/kit/kit" in cmd:
        match = True
    if "isaacsim.exp.full.streaming.kit" in cmd or "isaac-sim.streaming.sh" in cmd:
        match = True
    if match:
        try:
            os.kill(int(pid), signal.SIGKILL)
            killed.append(pid)
        except ProcessLookupError:
            pass
print("killed kit pids:", ",".join(killed) if killed else "(none)")
PY

if [[ -n "${ISAAC_ROOT}" ]]; then
  pkill -9 -f "${ISAAC_ROOT}/isaac-sim.streaming.sh" 2>/dev/null || true
fi

sleep 1
echo "[stop] done. Desktop / TurboVNC / noVNC kept."
nvidia-smi --query-gpu=encoder.stats.sessionCount,utilization.gpu --format=csv 2>/dev/null || true
