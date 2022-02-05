import ../wrapper/vapoursynth_wrapper
import constants
#let
#  API = getVapourSynthAPI(4)
#  CORE = API.createCore(0)

proc getVersionString*():string = 
  var coreInfo:ptr VSCoreInfo   
  API.getCoreInfo( CORE, coreInfo )
  return $coreInfo.versionString

proc getCore*():int = 
  var coreInfo:ptr VSCoreInfo   
  API.getCoreInfo( CORE, coreInfo )
  return coreInfo.core.int

proc getApi*():int = 
  var coreInfo:ptr VSCoreInfo 
  API.getCoreInfo( CORE, coreinfo )
  return coreinfo.api.int

proc getNumThreads*():int = 
  var coreInfo:ptr VSCoreInfo   
  API.getCoreInfo( CORE, coreInfo )
  return coreInfo.numThreads.int

proc getMaxFramebufferSize*():int = 
  var coreInfo:ptr VSCoreInfo    
  API.getCoreInfo( CORE, coreInfo )
  return coreInfo.maxFramebufferSize.int


proc getUsedFramebufferSize*():int = 
  var coreInfo:ptr VSCoreInfo     
  API.getCoreInfo( CORE, coreInfo )
  return coreInfo.usedFramebufferSize.int