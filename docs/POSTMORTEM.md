# Postmortem: Isaac Sim livestream on TCP-only clouds

## Symptom

On TCP-only GPU clouds (AutoDL custom services, RunPod HTTP proxy, etc.):

- WebRTC Streaming Client connects or hangs on signaling
- Viewport stays grey / black
- `ss` shows TCP `49100` listening, but little or no useful UDP media reaches the laptop
- Opening only TCP ports is not enough

## Root cause

Isaac Sim livestream media is **SRTP over UDP** (default stream port `47998`).
Provider proxies that forward **HTTP/TCP only** never carry that media path.
Signaling can succeed on TCP while video never arrives.

NVIDIA docs require both:

| Port | Protocol | Role |
|---|---|---|
| `49100` | TCP | Signaling |
| `47998` | UDP | Media |

See [Livestream Clients](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/manual_livestream_clients.html).

As of late 2025, Isaac Sim 5.x/6.x also does **not** expose a documented
TURN/ICE configuration path for forcing TCP relay the way some 4.2 workflows did
([forum thread](https://forums.developer.nvidia.com/t/isaac-sim-5-0-0-unable-to-configure-turn-server-for-webrtc-tcp-only-setup-no-udp-allowed/347641)).

## Approaches tried

### 1. Point publicIp at the cloud HTTPS URL

Fails. That URL is a reverse proxy for HTTP, not a host that accepts WebRTC UDP.
ICE candidates still need a UDP path the client can reach.

### 2. publicIp = container bridge IP, client on laptop

Signaling may work if TCP is mapped; **UDP still blocked** by the proxy → black screen.

### 3. Full Isaac GUI → Xvfb → x11vnc → noVNC

Works for many people ([Sa3d-99/runpod_noVNC_isaac_sim](https://github.com/Sa3d-99/runpod_noVNC_isaac_sim)).
On Isaac Sim **6.1** with plain Xvfb we repeatedly hit missing Vulkan present /
swapchain / segfault paths — the GUI is not a reliable present surface without a
real NVIDIA Xorg stack, which many cloud images do not ship.

### 4. Keep WebRTC local; VNC the client (this repo)

Works:

1. Start `isaac-sim.streaming.sh` with `publicIp` = reachable **local** address
   (container eth0 / `172.x`)
2. Run the official WebRTC client on TurboVNC `DISPLAY=:1`
3. Client ↔ Isaac talk over **localhost / bridge UDP**
4. Browser only sees noVNC over the one TCP HTTP port the cloud already provides

You keep NVENC-encoded official livestream quality; the “last mile” is VNC of
the client window, not VNC of the full Kit UI.

## Extra failure: NVENC “unsupported device”

On multi-GPU physical hosts that hand the container a non-zero `/dev/nvidiaN`
while the driver enumerates all GPUs, NVENC can fail under driver ≥570.
`nvenc/libnvenc_fix.so` (`LD_PRELOAD`) filters attached GPU ids to devices that
actually exist under `/dev`. See [nvenc/README.md](../nvenc/README.md).

## Verification checklist

```bash
ss -tulnp | grep -E '49100|47998|6006'
# UDP 47998 should show local traffic once the client connects:
timeout 3 tcpdump -ni lo -nn 'udp port 47998' -c 20
grep -E 'Stream started|Stream stopped' "$LOG_DIR/webrtc-client.log"
```

If `tcpdump` on `lo` shows healthy UDP while the laptop never needed UDP, the
architecture is doing its job.
