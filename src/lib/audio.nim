import ../wrapper/vapoursynth_wrapper
import strformat

#proc `$`*(af:VSAudioFormat):string =
#  result = &"AudioFormat(sampleType: {af.sampleType}, "
#  result &= &"bitsPerSample: {af.bitPerSample}, "
  #result &= &"numChannels: {af.numChannels}, "
  #result &= &"channelLayout: {af.channelLayout})"

proc `$`*(ai:ptr VSAudioInfo):string =
  return &"""Audio Info:
  format: {ai.format}
  sampleRate: {ai.sampleRate}
  numSamples: {ai.numSamples}
  numFrames: {ai.numFrames}
"""
