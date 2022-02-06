import ../wrapper/vapoursynth_wrapper

let
  API* = getVapourSynthAPI(4)
  CORE* = API.createCore(0)
#[ 
type
  VNode* = distinct ptr VSNode
  ANode* = distinct ptr VSNode

converter toVNode*(tmp:ptr VSNode):VNode =
  tmp.VNode

converter toANode*(tmp:ptr VSNode):ANode =
  tmp.ANode
 ]#
