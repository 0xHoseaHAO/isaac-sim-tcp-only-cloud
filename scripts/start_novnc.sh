#!/bin/bash
# TurboVNC (or Xvnc) desktop + noVNC over one TCP/HTTP port.
# Intended for TCP-only cloud proxies (AutoDL / RunPod / Vast / similar).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_env_file

TVNC_BIN="${TVNC_BIN:-/opt/TurboVNC/bin}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-6006}"
RES="${RES:-1920x1080}"
DEPTH="${DEPTH:-24}"
LOG_DIR="${LOG_DIR:-${ISAAC_TCP_ROOT}/logs}"
WM="${WM:-xfce}"

mkdir -p "${LOG_DIR}" /tmp/runtime-root "${HOME}/.vnc"
chmod 700 /tmp/runtime-root
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"

if [[ ! -x "${TVNC_BIN}/vncserver" ]]; then
  echo "ERROR: TurboVNC not found at ${TVNC_BIN}/vncserver" >&2
  echo "Install TurboVNC, or set TVNC_BIN to its bin directory." >&2
  exit 1
fi

cat > "${HOME}/.vnc/turbovncserver.conf" <<EOF
\$geometry = "${RES}";
\$depth = ${DEPTH};
\$securityTypes = "None";
\$wm = "${WM}";
\$quality = "80";
\$subsampling = "2x";
\$alwaysShared = "1";
EOF

cat > "${HOME}/.vnc/xstartup.turbovnc" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
eval $(dbus-launch --sh-syntax)
{
  echo "export DISPLAY=$DISPLAY"
  echo "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  echo "export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
} > "${XDG_RUNTIME_DIR}/xfce.env"
xfconfd >/dev/null 2>&1 &
sleep 0.2
xfwm4 --compositor=on >/dev/null 2>&1 &
sleep 0.4
xfsettingsd >/dev/null 2>&1 &
xfdesktop >/dev/null 2>&1 &
xfce4-panel >/dev/null 2>&1 &
wait
EOF
chmod +x "${HOME}/.vnc/xstartup.turbovnc"

# Rewrite the env dump path into the startup script for this LOG_DIR
sed -i "s|\${XDG_RUNTIME_DIR}/xfce.env|${LOG_DIR}/xfce.env|g" "${HOME}/.vnc/xstartup.turbovnc"

killall -9 x11vnc 2>/dev/null || true

NEED_RESTART=0
WIDTH="${RES%x*}"
HEIGHT="${RES#*x}"
if ! pgrep -x Xvnc >/dev/null; then
  NEED_RESTART=1
elif ! DISPLAY=":${DISPLAY_NUM}" xdpyinfo 2>/dev/null | grep -q "dimensions:[[:space:]]*${WIDTH}x${HEIGHT}"; then
  echo "[novnc] geometry not ${RES} — restarting TurboVNC"
  NEED_RESTART=1
fi

if [[ "${NEED_RESTART}" -eq 1 ]]; then
  echo "[novnc] TurboVNC ${RES} :${DISPLAY_NUM} → ${VNC_PORT}"
  killall -9 Xvfb 2>/dev/null || true
  "${TVNC_BIN}/vncserver" -kill ":${DISPLAY_NUM}" >/dev/null 2>&1 || true
  killall -9 Xvnc 2>/dev/null || true
  sleep 1
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
  "${TVNC_BIN}/vncserver" ":${DISPLAY_NUM}" \
    -geometry "${RES}" \
    -depth "${DEPTH}" \
    -rfbport "${VNC_PORT}" \
    -localhost \
    -securitytypes None \
    -deferupdate 1 \
    -interframe \
    -nthreads 4 \
    -xstartup "${HOME}/.vnc/xstartup.turbovnc" \
    >"${LOG_DIR}/turbovnc.log" 2>&1
  sleep 3
else
  echo "[novnc] TurboVNC already running at ${RES}"
fi

export DISPLAY=":${DISPLAY_NUM}"

WS_BIN="$(command -v websockify || true)"
if [[ -z "${WS_BIN}" ]]; then
  for candidate in "${HOME}/miniconda3/bin/websockify" /root/miniconda3/bin/websockify; do
    [[ -x "${candidate}" ]] && WS_BIN="${candidate}" && break
  done
fi
if [[ -z "${WS_BIN}" ]]; then
  echo "ERROR: websockify not found (pip install websockify, or apt install novnc)" >&2
  exit 1
fi

NOVNC_WEB="${NOVNC_WEB:-/usr/share/novnc}"
if [[ ! -d "${NOVNC_WEB}" ]]; then
  echo "ERROR: noVNC web root not found at ${NOVNC_WEB}" >&2
  exit 1
fi

if ! ss -tlnp 2>/dev/null | grep -q ":${WEB_PORT}"; then
  echo "[novnc] websockify ${WEB_PORT} → localhost:${VNC_PORT}"
  "${WS_BIN}" --web="${NOVNC_WEB}" "${WEB_PORT}" "localhost:${VNC_PORT}" \
    >"${LOG_DIR}/websockify-${WEB_PORT}.log" 2>&1 &
  sleep 1
fi

echo "[novnc] ready on TCP :${WEB_PORT}"
echo "  Open: /vnc.html?autoconnect=1&resize=scale&quality=7&compression=1"
"${TVNC_BIN}/vncserver" -list || true
ss -tlnp 2>/dev/null | grep -E ":${WEB_PORT}|:${VNC_PORT}" || true
