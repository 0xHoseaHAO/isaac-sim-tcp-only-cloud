# Shared Real-Time 2.0 render flags (optional quality preset).
# Source this file, then expand: "${RENDER_QUALITY_ARGS[@]}"
# shellcheck disable=SC2034
RENDER_QUALITY_ARGS=(
  --/rtx/rendermode=RealTimePathTracing
  --/rtx/post/aa/op=3
  --/rtx/post/dlss/execMode=2
  --/rtx/dldenoiser/responsiveDenoising=true
  --/rtx-transient/dlssg/enabled=true
  --/rtx-transient/internal/dlssg/rtpt/interpolatedFrameCount=1
  --/rtx/rtpt/maxBounces=6
  --/rtx/rtpt/maxSpecularAndTransmissionBounces=6
  --/rtx/rtpt/maxVolumeBounces=63
  --/rtx/post/tonemap/enabled=true
  --/rtx/post/tonemap/op=4
  --/rtx/post/tonemap/filmIso=200
  --/rtx/post/tonemap/whitepoint=6500
  --/rtx/ecoMode/enabled=false
)
