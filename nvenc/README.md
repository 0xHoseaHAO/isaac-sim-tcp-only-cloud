# NVENC fix for multi-GPU containers

Some cloud GPU images (notably AutoDL-style multi-tenant hosts) expose only a
subset of `/dev/nvidia*` nodes while the driver still enumerates every GPU on
the physical machine. Isaac Sim livestream then fails NVENC with errors like
**unsupported device**.

`nvenc_fix.c` is an `LD_PRELOAD` interposer that filters
`NV0000_CTRL_CMD_GPU_GET_ATTACHED_IDS` so NVENC only sees devices that exist
under `/dev`. Approach inspired by
[flexgrip/nvidia-gpu-enumeration](https://github.com/flexgrip/nvidia-gpu-enumeration).

## Build

```bash
cd nvenc
make
# → libnvenc_fix.so
```

## Use

```bash
export NVENC_FIX=/path/to/isaac-sim-tcp-only-cloud/nvenc/libnvenc_fix.so
export NVENC_FIX_DEBUG=/tmp/nvenc_fix.log   # optional
# start_isaac_tcp_stream.sh picks these up automatically
```

Skip the interposer when NVENC already works:

```bash
SKIP_NVENC_FIX=1 ./scripts/start_isaac_tcp_stream.sh
```
