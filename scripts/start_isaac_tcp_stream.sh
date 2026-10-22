#!/bin/bash
# Isaac Sim official WebRTC livestream for TCP-only cloud ports.
#
# UDP media (streamPort, default 47998) stays on the GPU host.
# The official WebRTC Streaming Client runs on the virtual desktop (DISPLAY=:N).
# You view that desktop through noVNC over one TCP/HTTP port.
#
# On multi-GPU hosts that expose /dev/nvidiaN with N!=0, driver >=570 NVENC often
# fails with "unsupported device" unless LD_PRELOAD=libnvenc_fix.so is used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env_file

ISAAC_ROOT="${ISAAC_ROOT:?Set ISAAC_ROOT to your Isaac Sim install (see config/example.env)}"
CLIENT_DIR="${CLIENT_DIR:?Set CLIENT_DIR to the WebRTC Streaming Client directory}"
LOG_DIR="${LOG_DIR:-${ISAAC_TCP_ROOT}/logs}"
NVENC_FIX="${NVENC_FIX:-${ISAAC_TCP_ROOT}/nvenc/libnvenc_fix.so}"
WEB_PORT="${WEB_PORT:-6006}"
SIGNAL_PORT="${SIGNAL_PORT:-49100}"
STREAM_PORT="${STREAM_PORT:-47998}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
HOST_IP="$(detect_host_ip)"
NGX_LIB_DIR="${NGX_LIB_DIR:-}"
CLIENT_LD_LIBRARY_PATH="${CLIENT_LD_LIBRARY_PATH:-}"
SKIP_NVENC_FIX="${SKIP_NVENC_FIX:-0}"
SKIP_RENDER_PRESET="${SKIP_RENDER_PRESET:-0}"

mkdir -p "${LOG_DIR}"
ensure_runtime_dir
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
export OMNI_KIT_ALLOW_ROOT="${OMNI_KIT_ALLOW_ROOT:-1}"
export ACCEPT_EULA="${ACCEPT_EULA:-Y}"
export PRIVACY_CONSENT="${PRIVACY_CONSENT:-N}"

if [[ ! -x "${ISAAC_ROOT}/isaac-sim.streaming.sh" ]]; then
  echo "ERROR: missing ${ISAAC_ROOT}/isaac-sim.streaming.sh" >&2
  exit 1
fi
if [[ ! -x "${CLIENT_DIR}/isaacsim-webrtc-streaming-client" ]]; then
  echo "ERROR: missing WebRTC client binary under ${CLIENT_DIR}" >&2
  exit 1
fi

PRELOAD_ARGS=()
if [[ "${SKIP_NVENC_FIX}" != "1" ]]; then
  if [[ ! -f "${NVENC_FIX}" ]]; then
    echo "ERROR: missing ${NVENC_FIX}" >&2
    echo "Build: (cd ${ISAAC_TCP_ROOT}/nvenc && make)" >&2
    echo "Or set SKIP_NVENC_FIX=1 if NVENC already works on this host." >&2
    exit 1
  fi
  export NVENC_FIX_DEBUG="${NVENC_FIX_DEBUG:-${LOG_DIR}/nvenc_fix.log}"
  : > "${NVENC_FIX_DEBUG}"
  PRELOAD_ARGS=(LD_PRELOAD="${NVENC_FIX}" NVENC_FIX_DEBUG="${NVENC_FIX_DEBUG}")
fi

echo "[0] ensure noVNC on :${WEB_PORT}"
bash "${SCRIPT_DIR}/start_novnc.sh" >/dev/null

echo "[1] stop old Isaac / WebRTC client"
pkill -9 -f 'isaacsim-webrtc-streaming-client' 2>/dev/null || true
pkill -9 -f "${ISAAC_ROOT}/kit/kit" 2>/dev/null || true
sleep 2

echo "[2] start Isaac official streaming (publicIp=${HOST_IP})"
cd "${ISAAC_ROOT}"

RENDER_ARGS=()
if [[ "${SKIP_RENDER_PRESET}" != "1" ]]; then
  # shellcheck source=isaac_rt2_render_args.sh
  source "${SCRIPT_DIR}/isaac_rt2_render_args.sh"
  RENDER_ARGS=("${RENDER_QUALITY_ARGS[@]}")
fi

LD_PATH_VALUE=""
if [[ -n "${NGX_LIB_DIR}" ]]; then
  LD_PATH_VALUE="${NGX_LIB_DIR}"
fi

# Do not inherit conda libs into Kit — that often segfaults.
nohup env -u DISPLAY -u LD_LIBRARY_PATH \
  ${LD_PATH_VALUE:+LD_LIBRARY_PATH="${LD_PATH_VALUE}"} \
  "${PRELOAD_ARGS[@]}" \
  ${VK_ICD_FILENAMES:+VK_ICD_FILENAMES="${VK_ICD_FILENAMES}"} \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  OMNI_KIT_ALLOW_ROOT="${OMNI_KIT_ALLOW_ROOT}" \
  ACCEPT_EULA="${ACCEPT_EULA}" \
  PRIVACY_CONSENT="${PRIVACY_CONSENT}" \
  ./isaac-sim.streaming.sh --allow-root \
  --/exts/omni.kit.livestream.app/primaryStream/signalPort="${SIGNAL_PORT}" \
  --/exts/omni.kit.livestream.app/primaryStream/streamPort="${STREAM_PORT}" \
  --/exts/omni.kit.livestream.app/primaryStream/publicIp="${HOST_IP}" \
  --/log/channels/omni.kit.livestream.streamsdk=info \
  --/log/channels/omni.kit.livestream.webrtc=info \
  "${RENDER_ARGS[@]}" \
  ${ISAAC_EXTRA_ARGS:-} \
  >"${LOG_DIR}/isaac-stream.log" 2>&1 &
echo $! > "${LOG_DIR}/isaac-stream.pid"
echo "    pid=$(cat "${LOG_DIR}/isaac-stream.pid") log=${LOG_DIR}/isaac-stream.log"

echo "[3] wait for TCP signal :${SIGNAL_PORT}"
for i in $(seq 1 90); do
  if ss -tlnp 2>/dev/null | grep -q ":${SIGNAL_PORT}"; then
    echo "    signal ready after ${i}s"
    break
  fi
  if ! pgrep -f "${ISAAC_ROOT}/kit/kit" >/dev/null; then
    echo "Isaac died:"; tail -40 "${LOG_DIR}/isaac-stream.log"; exit 1
  fi
  sleep 2
  if (( i == 90 )); then
    echo "timeout:"; tail -40 "${LOG_DIR}/isaac-stream.log"; exit 1
  fi
done

echo "[4] start official WebRTC Streaming Client on DISPLAY=:${DISPLAY_NUM}"
pkill -9 -f 'isaacsim-webrtc-streaming-client' 2>/dev/null || true
sleep 1
cd "${CLIENT_DIR}"
: > "${LOG_DIR}/webrtc-client.log"

CLIENT_LIBS="${CLIENT_DIR}"
if [[ -n "${CLIENT_LD_LIBRARY_PATH}" ]]; then
  CLIENT_LIBS="${CLIENT_DIR}:${CLIENT_LD_LIBRARY_PATH}"
fi

nohup env DISPLAY=":${DISPLAY_NUM}" \
  LD_LIBRARY_PATH="${CLIENT_LIBS}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  VK_ICD_FILENAMES="${CLIENT_DIR}/vk_swiftshader_icd.json" \
  ./isaacsim-webrtc-streaming-client \
  --no-sandbox --disable-gpu-sandbox --ignore-gpu-blocklist \
  --enable-unsafe-swiftshader --enable-webgl \
  --use-gl=angle --use-angle=swiftshader-webgl \
  --disable-dev-shm-usage --ozone-platform=x11 \
  --remote-debugging-port=9222 \
  >"${LOG_DIR}/webrtc-client.log" 2>&1 &
echo $! > "${LOG_DIR}/webrtc-client.pid"
sleep 6

# Auto-connect via Chrome DevTools Protocol (UDP stays on this host)
python3 - <<PY
import json, urllib.request, time, asyncio
HOST = "${HOST_IP}"
SIGNAL = "${SIGNAL_PORT}"
STREAM = "${STREAM_PORT}"
for _ in range(30):
    try:
        tabs = json.load(urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=1))
        break
    except Exception:
        time.sleep(0.5)
else:
    raise SystemExit("CDP not ready — open the WebRTC client on the VNC desktop and Connect manually")
page = next(t for t in tabs if t.get("type") == "page")
try:
    import websockets
except ImportError as exc:
    raise SystemExit("pip install websockets  (needed for auto-connect)") from exc

async def main():
    async with websockets.connect(page["webSocketDebuggerUrl"]) as ws:
        expr = (
            f'localStorage.setItem("server","{HOST}");'
            f'localStorage.setItem("signalPort","{SIGNAL}");'
            f'localStorage.setItem("streamPort","{STREAM}");'
            f'location.search="?server={HOST}&signalPort={SIGNAL}&streamPort={STREAM}&autoConnect";'
        )
        await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expr}}))
        while True:
            d = json.loads(await ws.recv())
            if d.get("id") == 1:
                print("cdp auto-connect ok")
                break

asyncio.get_event_loop().run_until_complete(main())
PY

echo "[5] wait for stream result..."
for i in $(seq 1 40); do
  if grep -q 'Stream started' "${LOG_DIR}/webrtc-client.log" 2>/dev/null \
     && ! grep -q 'Stream stopped' "${LOG_DIR}/webrtc-client.log" 2>/dev/null; then
    echo "    STREAM LIVING at ${i}s"
    break
  fi
  sleep 1
done

echo
echo "======== READY ========"
echo "1) Open your cloud HTTP/TCP service mapped to :${WEB_PORT}"
echo "   .../vnc.html?autoconnect=1&resize=remote"
echo "2) You should see the WebRTC Streaming Client already connected to ${HOST_IP}"
echo "   (UDP ${STREAM_PORT} never leaves this machine; only noVNC TCP goes out)"
echo "Logs: ${LOG_DIR}/isaac-stream.log | ${LOG_DIR}/webrtc-client.log"
ss -tulnp 2>/dev/null | grep -E "${SIGNAL_PORT}|${STREAM_PORT}|${WEB_PORT}" || true
