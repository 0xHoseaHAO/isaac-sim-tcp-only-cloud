# NVIDIA Developer Forums — ready to paste

**Category:** Omniverse / Isaac Sim  
**Title:** Isaac Sim livestream on TCP-only clouds (AutoDL / RunPod / etc.): keep WebRTC local, view via noVNC

---

## TL;DR

Isaac Sim’s official WebRTC livestream **cannot** cross cloud proxies that only forward TCP/HTTP: media is SRTP over **UDP** (`47998`). Setting `publicIp` does not fix a missing UDP path, and current 5.x/6.x releases do not expose a documented TURN “TCP-only” knob.

**Workaround that preserves NVENC livestream:** run Isaac streaming **and** the official WebRTC Streaming Client on the GPU host (UDP stays local), then view the client window through **TurboVNC + noVNC** on the single TCP port your provider already gives you.

Scripts + write-up: **https://github.com/0xHoseaHAO/isaac-sim-tcp-only-cloud**  
(Tested: Isaac Sim **6.1**, AutoDL-style Linux container, RTX-class GPU.)

## The problem

On TCP-only GPU clouds:

- Signaling on TCP `49100` may connect
- Media on UDP `47998` never reaches a laptop behind the HTTP proxy
- Result: grey/black viewport

This matches the official docs (both TCP and UDP required) and earlier forum reports about TURN/ICE not being configurable for TCP-only setups in 5.x.

## What we did instead

```
Browser --TCP--> noVNC --> TurboVNC desktop
                                |
                                v
                 Official WebRTC Streaming Client
                                |
                           UDP localhost
                                |
                                v
                 Isaac Sim streaming + NVENC
```

1. `isaac-sim.streaming.sh` with `primaryStream/publicIp` set to the **container bridge / eth0 IP** (reachable by the local client — **not** the public HTTPS proxy URL).
2. Official WebRTC Streaming Client on `DISPLAY=:1` (TurboVNC), auto-connected via CDP.
3. Expose only noVNC (default `:6006`) through the cloud custom HTTP service.

## How this differs from “GUI into noVNC”

There is already an excellent RunPod write-up that puts the **full Isaac GUI** into Xvfb/noVNC. That is a great path when it works.

On Isaac **6.1** we often could not get a stable Vulkan present surface on plain Xvfb. Running **official streaming locally** keeps hardware NVENC and the supported livestream path, while still using **one TCP port** for the browser.

## Extra gotcha: NVENC on multi-GPU containers

If the host has many GPUs but the container only sees `/dev/nvidiaN` with `N != 0`, NVENC may fail with “unsupported device” on newer drivers. The repo includes a small `LD_PRELOAD` interposer (`nvenc_fix.c`) that filters GPU enumeration to devices that actually exist under `/dev`.

## Ask / hope for upstream

A documented ICE/TURN (or TCP-relay) configuration for livestream would help TCP-only clouds a lot. Until then, local-WebRTC + noVNC is a practical pattern for AutoDL / RunPod / similar providers.

Happy to share logs or refine the scripts if this is useful to others.
