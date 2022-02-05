import ../wrapper/vapoursynth_wrapper

let
  API* = getVapourSynthAPI(4)
  CORE* = API.createCore(0)