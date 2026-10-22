# Isaac Sim on TCP-only clouds

Run **NVIDIA Isaac Sim** livestream on GPU hosts that only expose **TCP/HTTP**
custom ports (AutoDL, RunPod HTTP proxy, Vast reverse proxy, campus firewalls,
etc.). Official WebRTC media uses **UDP** and cannot cross those proxies — this
repo keeps WebRTC on the GPU machine and ships the view out through **noVNC**.

Tested with **Isaac Sim 6.1** on an AutoDL-style Linux container (RTX-class GPU).

```
Browser  --TCP/HTTP-->  noVNC  -->  TurboVNC desktop
                                         |
                                         v
                          Official WebRTC Streaming Client
                                         |
                                    UDP localhost
                                         |
                                         v
                          Isaac Sim streaming + NVENC
```

## Why not connect the WebRTC client from your laptop?

| | Official remote WebRTC | This repo |
|---|---|---|
| Signaling | TCP `49100` | stays on GPU host |
| Media | **UDP** `47998` (SRTP) | **UDP localhost only** |
| What you expose | TCP + UDP (often impossible) | **one TCP/HTTP port** (noVNC) |
| Encoder | NVENC hardware | NVENC hardware (same) |

Related alternative: [runpod_noVNC_isaac_sim](https://github.com/Sa3d-99/runpod_noVNC_isaac_sim)
draws the full Isaac **GUI** into Xvfb and VNC. That works on many setups; on
Isaac 6.1 + plain Xvfb we often hit missing Vulkan present / swapchain failures.
Keeping official streaming local preserves NVENC quality while still using one
TCP port.

Longer write-up: [docs/POSTMORTEM.md](docs/POSTMORTEM.md).  
Forum draft: [docs/FORUM_POST.md](docs/FORUM_POST.md).

## Prerequisites

On the **GPU host**:

1. Isaac Sim standalone (with `isaac-sim.streaming.sh`)
2. [Isaac Sim WebRTC Streaming Client](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/manual_livestream_clients.html) extracted on disk
3. TurboVNC + XFCE (or another WM), `websockify`, noVNC web files (`/usr/share/novnc`)
4. NVIDIA driver with NVENC; `gcc` to build the optional NVENC interposer
5. Python 3 + `websockets` (`pip install websockets`) for auto-connect

Map **one** cloud custom service / HTTP port to container `WEB_PORT` (default `6006`).

## Quick start

```bash
git clone https://github.com/<YOU>/isaac-sim-tcp-only-cloud.git
cd isaac-sim-tcp-only-cloud

cp config/example.env config/.env
# edit ISAAC_ROOT, CLIENT_DIR, NVENC_FIX, optional VK_ICD_FILENAMES / NGX_LIB_DIR

(cd nvenc && make)

./scripts/start_isaac_tcp_stream.sh
```

Open your provider’s HTTP URL for port `6006`:

```
.../vnc.html?autoconnect=1&resize=remote
```

You should see the WebRTC client already connected. Stop Kit + client (keep desktop):

```bash
./scripts/stop_isaac.sh
```

## Important environment variables

| Variable | Meaning |
|---|---|
| `ISAAC_ROOT` | Isaac Sim install root |
| `CLIENT_DIR` | Directory containing `isaacsim-webrtc-streaming-client` |
| `HOST_IP` | Address the **local** client can reach (container eth0 / bridge). **Not** the public HTTPS proxy URL |
| `WEB_PORT` | noVNC listen port (default `6006`) |
| `SIGNAL_PORT` / `STREAM_PORT` | WebRTC ports (defaults `49100` / `47998`) |
| `NVENC_FIX` | Path to `libnvenc_fix.so` |
| `SKIP_NVENC_FIX=1` | Skip LD_PRELOAD when NVENC already works |
| `ISAAC_EXTRA_ARGS` | Extra Kit CLI flags (e.g. `--exec` / scene path) |
| `CLIENT_LD_LIBRARY_PATH` | Extra libs for Electron client (e.g. `libasound`) |

Full template: [config/example.env](config/example.env).

## Security

Livestream and VNC endpoints here have **no auth** by default (TurboVNC
`securityTypes=None`). Use only behind your cloud provider’s gated URL, SSH
tunnel, or add your own reverse-proxy auth. Do not expose them on the open
Internet.

## License

Apache-2.0. Isaac Sim and the WebRTC Streaming Client remain under NVIDIA’s
licenses — this repo only ships helper scripts and documentation.
