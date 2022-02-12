##[
Output
======

Enables piping a video or storing it in a file. The format employed
is `YUV4MPEG2 <https://wiki.multimedia.cx/index.php/YUV4MPEG2>`_.

]##
import strutils,strformat
import locks
import tables
import std/streams
import constants, vsframe, vsmap, audio, ../wrapper/vapoursynth_wrapper

type
  FrameRequest {.bycopy.} = object
    numFrames*: int       # Total number of frames
    nthreads*: int        # Number of threads available
    completedFrames*: int # Number of frames already processed
    requestedFrames*: int # Number of frames already requested 
    frames: Table[int,ptr VSFrame]
    current:int           # Current frame to write
    strm:FileStream

var 
  reqs:FrameRequest
  lock: Lock
  cond : Cond  


proc y4mheader*(node:ptr VSNode):string =
  ## y4m stream header generator
  ##
  ## TODO: I: sólo considera vídeo progresivo (p)
  ##
  ## TODO: A: pixel aspect ratio desconocido (0:0)  
  let vinfo = getVideoInfo( node)

  if not (node.getColorFamily() in [cfYUV, cfGray]):  # vinfo.format.colorFamily
    raise newException(ValueError, ".y4m only supports YUV and Gray formats")
  var format = ""

  let bitsPerSample = vinfo.format.bitsPerSample
  if vinfo.format.colorFamily == cfGray:
    if bitsPerSample > 8: 
      format &= &"mono{bitsPerSample}"
    else:
      format &= "mono"

  elif vinfo.format.colorFamily == cfYUV:
    # https://en.wikipedia.org/wiki/Chroma_subsampling#Types_of_sampling_and_subsampling
    # subSamplingW: 2nd and 3rd plane sampling in horizontal direction
    # subSamplingH: same for vertical direction
    let ssW = vinfo.format.subSamplingW
    let ssH = vinfo.format.subSamplingH
    var tmp = if (ssW, ssH) == (1,1): "420"
              elif (ssW, ssH) == (1,0): "422"
              elif (ssW, ssH) == (0,0): "444"
              elif (ssW, ssH) == (2,2): "410"
              elif (ssW, ssH) == (2,0): "411"
              elif (ssW, ssH) == (0,1): "440"
              else: raise newException(ValueError, "case not covered")
    format &= tmp
    tmp = if bitsPerSample > 8: &"p{bitsPerSample}" else: ""
    format &= tmp

  result = &"YUV4MPEG2 C{format} W{vinfo.width} H{vinfo.height} F{vinfo.fpsNum}:{vinfo.fpsDen} Ip A0:0"


proc frameDoneCallback( reqsData: pointer, 
                        frame: ptr VSFrame, 
                        n: cint, 
                        node: ptr VSNode, 
                        errorMsg: cstring) {.cdecl.} = 
  #[
  Function of the client application called by the core when a requested frame is ready, after a call to getFrameAsync().

  If multiple frames were requested, they can be returned in any order. Client applications must take care of reordering them.
  ]#
  setupForeignThreadGc()

  # Do something with the frame
  if frame != nil:
    reqs.frames[n.int] = frame  # Store the new frame in the buffer
    #echo "Completed: ", n
    # Write to file everything you can
    #if reqs.current == nil:
    var k = reqs.current + 1 
    while reqs.frames.hasKey( k ):
      #echo "Writing: ", k
      #echo repr reqs.frames
      let f = reqs.frames[k]
      #echo f.width(0)
      #echo repr f
      let format = API.getVideoFrameFormat(f) #f.getFrameFormat#.toFormat    
      reqs.strm.writeLine("FRAME")

      for i in 0..<format.numPlanes:
        #let plane = frame.getPlane(i)
        let width  = f.width( i )
        let height = f.height( i )      
        #let width = plane.width
        #let height = plane.height
        #let size = width * height
        let init = cast[uint]( getReadPtr(f, i) )
        let stride = f.getStride(i)
        for row in 0..<height:
          let address = cast[pointer]( init + row.uint * stride)
          reqs.strm.writeData(address, width.int)
      reqs.frames.del(k)
      API.freeFrame( f )
      reqs.current += 1
      k = reqs.current

    reqs.completedFrames += 1

    # Once a frame is completed, we request another frame while there are available
    if reqs.requestedFrames < reqs.numFrames:
      API.getFrameAsync( reqs.requestedFrames.cint, node, frameDoneCallback, nil)
      #echo "Requested: ", reqs.requestedFrames
      reqs.requestedFrames += 1   

    if (reqs.completedFrames == reqs.numFrames):
      cond.signal()
  else:
    raise newException(ValueError, "Failed to get frame")
#[ 
proc writeY4mFramesAsync(strm:FileStream, node:ptr VSNode):int =
  # Y-Cb-Cr plane order
  # Y is luminance. It is 8 bits (one byte) per pixel. but you must watch the line stride.
  # The U and V planes are one quarter (half the height and half the width) the resolution of the Y plane. So each byte is 4 pixels (2 wide 2 tall).
  # YUV 4:2:0 (I420/J420/YV12) It has the luma "luminance" plane Y first, then the U chroma plane and last the V chroma plane.
  reqs.nthreads = getNumThreads()  # Get the number of threads
  let vinfo = API.getVideoInfo(node) # video info pointer
  reqs.numFrames = vinfo.numFrames
  reqs.completedFrames = 0
  reqs.requestedFrames = 0
  reqs.current = -1
  reqs.strm = strm
  #echo "ok"
  let initialRequest = min(reqs.nthreads, reqs.numFrames)
  reqs.frames = initTable[int,ptr VSFrameRef]()  # Buffer
  initLock(lock)
  for i in 0..<initialRequest: 
    API.getFrameAsync( i.cint, node, frameDoneCallback, nil) #dataInHeap)
    #echo "Requested: ", i
    reqs.requestedFrames += 1
  cond.wait(lock)
  #API.freeMap(vsmap)
  #API.freeNode(node)


  #for i in 0..<nframes:
    #echo "Writting frame: ", i

    
  #  freeFrame( frame )  # Once we have dealt with all the planes
  strm.flush()
  return reqs.numFrames

 ]#






proc writeY4mFrames*(strm:FileStream, node:ptr VSNode):int =
  # Y-Cb-Cr plane order
  # Y is luminance. It is 8 bits (one byte) per pixel. but you must watch the line stride.
  # The U and V planes are one quarter (half the height and half the width) the resolution of the Y plane. So each byte is 4 pixels (2 wide 2 tall).
  # YUV 4:2:0 (I420/J420/YV12) It has the luma "luminance" plane Y first, then the U chroma plane and last the V chroma plane.

  let vinfo = API.getVideoInfo(node) # video info pointer
  let nframes = vinfo.numFrames 
  for i in 0..<nframes:
    #echo "Writting frame: ", i
    strm.writeLine("FRAME")
    let frame = node.getFrame(i)
    let format = frame.getVideoFrameFormat#.toFormat
    for i in 0..<format.numPlanes:
      #let plane = frame.getPlane(i)
      let width  = frame.width( i )
      let height = frame.height( i )      
      #let width = plane.width
      #let height = plane.height
      #let size = width * height
      let init = cast[int]( getReadPtr(frame, i) )
      let stride = getStride(frame, i)
      for row in 0..<height:
        let address = cast[pointer]( init + row.int * stride.int)
        strm.writeData(address, width.int)
    
    freeFrame( frame )  # Once we have dealt with all the planes
  strm.flush()
  return nframes

proc pipeY4M*(vsmap:ptr VSMap ) =
  ## Pipes the video to stdout. The video goes uncompressed in Y4M format
  let node = getFirstNode(vsmap)
  let header = y4mheader( node )
  let strm = newFileStream(stdout)
  strm.write(header & "\n" )
  discard strm.writeY4mFrames( node ) 
  API.freeMap(vsmap)
  API.freeNode(node)  



#[ 
proc Savey4m*(vsmap:ptr VSMap, filename:string):int =
  ## Saves the video in `filename`
  #echo "ok0"
  let node = getFirstNode(vsmap)
  #echo "ok1"  
  #let d = vsmap.toSeq
  #let node = d[0].nodes[0]  
  let strm = newFileStream(filename, fmWrite)
  
  let header = y4mheader(node)
  strm.writeLine( header )
  #let nframes = strm.writeY4mFrames( node )
  let nframes = strm.writeY4mFramesAsync( node ) 
  strm.close()
  API.freeMap(vsmap)
  API.freeNode(node)
  return nframes
 ]#

#[  No usar el single threaded
proc Null*(vsmap:ptr VSMap):int =
  let node = getFirstNode(vsmap)
  #API.freeMap(vsmap)  
  let vinfo = API.getVideoInfo(node) # video info pointer
  let nframes = vinfo.numFrames 
  for i in 0..<nframes:  
    let frame = node.getFrame(i)
    API.freeFrame( frame )
    #let frame =  API.getFrame(i, node, nil, 0.cint)
    #API.getFrameAsync(i, node, frameDoneCallback, nil)
    

  API.freeMap(vsmap)
  API.freeNode(node)
  return nframes
]#

proc doNothing*( reqsData: pointer, 
                frame: ptr VSFrame, 
                n: cint, 
                node: ptr VSNode, 
                errorMsg: cstring) {.cdecl.} = 
  #[
  Function of the client application called by the core when a requested frame is ready, after a call to getFrameAsync().

  If multiple frames were requested, they can be returned in any order. Client applications must take care of reordering them.

  This function is only ever called from one thread at a time.

  getFrameAsync() may be called from this function to request more frames.    
  ]#
  setupForeignThreadGc()

  # Do something with the frame
  API.freeFrame( frame )
  reqs.completedFrames += 1

  # Once a frame is completed, we request another frame while there are available
  if reqs.requestedFrames < reqs.numFrames:
    API.getFrameAsync( reqs.requestedFrames.cint, node, doNothing, reqsData)
    #echo "Frame: ", reqs.requestedFrames
    reqs.requestedFrames += 1   

  if (reqs.completedFrames == reqs.numFrames):
    cond.signal()
#[ 
proc Null*(vsmap:ptr VSMap):int =
  reqs.nthreads = getNumThreads()  # Get the number of threads
  let node = getFirstNode(vsmap)
  let vinfo = API.getVideoInfo(node) # video info pointer
  reqs.numFrames = vinfo.numFrames
  reqs.completedFrames = 0
  reqs.requestedFrames = 0

  let initialRequest = min(reqs.nthreads, reqs.numFrames)
  initLock(lock)
  for i in 0..<initialRequest:  #
    API.getFrameAsync( i.cint, node, doNothing, nil) #dataInHeap)
    #echo "Frame: ", i
    reqs.requestedFrames += 1

  cond.wait(lock)
  API.freeMap(vsmap)
  API.freeNode(node)
  return reqs.numFrames
  ]#

#-------------
#[
import subprocess
def encode(clip: vs.VideoNode, filename: str) -> None:
    ffmpeg_args = ['ffmpeg', '-i', 'pipe:', filename]
    enc_proc = subprocess.Popen(ffmpeg_args, stdin=subprocess.PIPE)
    clip.output(enc_proc.stdin, y4m=bool(clip.format.color_family == vs.YUV))
    enc_proc.communicate()


>>> clip = core.ffms2.Source("my_loaded_video.avi")
>>> clip = ...
>>> encode(clip, 'out.mp4')
]#
# https://nim-lang.org/docs/osproc.html
#proc encode*(vsmap:ptr VSMap; filename:string ) =
#  ffmpegArgs = @["ffmpeg", "-i", "pipe:", filename]
#  echo "encode"



# https://github.com/vapoursynth/vapoursynth/blob/5ce771df6be37d9c1c58d6f6643c0eeb369c3246/src/cython/vapoursynth.pyx
#[
def set_output(self, int index = 0, VideoNode alpha = None, int alt_output = 0):
    cdef const VSVideoFormat *aformat = NULL
    clip = self
    if alpha is not None:
        if (self.vi.width != alpha.vi.width) or (self.vi.height != alpha.vi.height):
            raise Error('Alpha clip dimensions must match the main video')
        if (self.num_frames != alpha.num_frames):
            raise Error('Alpha clip length must match the main video')
        if (self.vi.format.colorFamily != UNDEFINED) and (alpha.vi.format.colorFamily != UNDEFINED):
            if (alpha.vi.format.colorFamily != GRAY) or (alpha.vi.format.sampleType != self.vi.format.sampleType) or (alpha.vi.format.bitsPerSample != self.vi.format.bitsPerSample):
                raise Error('Alpha clip format must match the main video')
        elif (self.vi.format.colorFamily != UNDEFINED) or (alpha.vi.format.colorFamily != UNDEFINED):
            raise Error('Format must be either known or unknown for both alpha and main clip')
        
        _get_output_dict("set_output")[index] = VideoOutputTuple(self, alpha, alt_output)
    else:
        _get_output_dict("set_output")[index] = VideoOutputTuple(self, None, alt_output)

def output(self, object fileobj not None, bint y4m = False, object progress_update = None, int prefetch = 0, int backlog = -1):
    if (fileobj is sys.stdout or fileobj is sys.stderr):
        # If you are embedded in a vsscript-application, don't allow outputting to stdout/stderr.
        # This is the responsibility of the application, which does know better where to output it.
        if not isinstance(get_policy(), StandaloneEnvironmentPolicy):
            raise ValueError("In this context, use set_output() instead.")
            
        if hasattr(fileobj, "buffer"):
            fileobj = fileobj.buffer

    if progress_update is not None:
        progress_update(0, len(self))

    if y4m:
        if self.format.color_family == GRAY:
            y4mformat = 'mono'
            if self.format.bits_per_sample > 8:
                y4mformat = y4mformat + str(self.format.bits_per_sample)
        elif self.format.color_family == YUV:
            if self.format.subsampling_w == 1 and self.format.subsampling_h == 1:
                y4mformat = '420'
            elif self.format.subsampling_w == 1 and self.format.subsampling_h == 0:
                y4mformat = '422'
            elif self.format.subsampling_w == 0 and self.format.subsampling_h == 0:
                y4mformat = '444'
            elif self.format.subsampling_w == 2 and self.format.subsampling_h == 2:
                y4mformat = '410'
            elif self.format.subsampling_w == 2 and self.format.subsampling_h == 0:
                y4mformat = '411'
            elif self.format.subsampling_w == 0 and self.format.subsampling_h == 1:
                y4mformat = '440'
            if self.format.bits_per_sample > 8:
                y4mformat = y4mformat + 'p' + str(self.format.bits_per_sample)
        else:
            raise ValueError("Can only use GRAY and YUV for V4M-Streams")

        if len(y4mformat) > 0:
            y4mformat = 'C' + y4mformat + ' '

        data = 'YUV4MPEG2 {y4mformat}W{width} H{height} F{fps_num}:{fps_den} Ip A0:0 XLENGTH={length}\n'.format(
            y4mformat=y4mformat,
            width=self.width,
            height=self.height,
            fps_num=self.fps_num,
            fps_den=self.fps_den,
            length=len(self)
        )
        fileobj.write(data.encode("ascii"))

    write = fileobj.write
    writelines = VideoFrame._writelines

    for idx, frame in enumerate(self.frames(prefetch, backlog, close=True)):
        if y4m:
            fileobj.write(b"FRAME\n")

        writelines(frame, write)

        if progress_update is not None:
            progress_update(idx+1, len(self))

    if hasattr(fileobj, "flush"):
        fileobj.flush()

]#


# TODO
# - Export wav / pcm /wav64
# - NUT
# https://github.com/vapoursynth/vapoursynth/blob/69be0cd2aa4be15618894e310e83c99a96836206/src/vspipe/vspipe.cpp#L257


import easywave, math
#[
proc writeTestFile[T: SomeNumber](filename: string, endian: Endianness,
                                  sampleFormat: SampleFormat,
                                  bitsPerSample: Natural) =
  var rw = createRiffFile(filename, FourCC_WAVE, endian)

  let wf = WaveFormat(
    sampleFormat:  sampleFormat,
    bitsPerSample: sizeof(T) * 8,
    sampleRate:    SampleRate,
    numChannels:   NumChannels
  )

  rw.writeFormatChunk(wf)
  rw.beginChunk(FourCC_WAVE_data)

  var amplitude = case bitsPerSample
  of  8: 2^7 / 4
  of 16: 2^15 / 4
  of 24: 2^23 / 4
  of 32:
    if sampleFormat == sfPCM: 2^31 / 4 else: 1.0 / 4
  of 64: 1.0 / 4
  else: 0

  var
    totalFrames = LengthSeconds * SampleRate  # 1 frame = 2 samples (stereo)
    buf: array[1024, T]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SampleRate/FreqHz)

  while totalFrames > 0:
    var s = if sizeof(T) == 1: T(sin(phase) * amplitude + (2^7).float)
    else:                      T(sin(phase) * amplitude)

    buf[pos]   = s
    buf[pos+1] = s

    inc(pos, 2)
    if pos >= buf.len:
      rw.write(buf, 0, buf.len)
      pos = 0
    dec(totalFrames)

    phase += phaseInc

  if pos > 0:
    rw.write(buf, 0, pos)

  rw.endChunk()

  rw.writeCueChunk(regions)
  rw.writeAdtlListChunk(regions)
  rw.close()
]#

proc toWav*(vsmap:ptr VSMap ) =
  ## Pipes the video to stdout. The video goes uncompressed in Y4M format
  ## https://web.archive.org/web/20040317073101/http://ccrma-www.stanford.edu/courses/422/projects/WaveFormat/
  ## $ nimble install easywave
  let node = getFirstNode(vsmap)  # --> Deberíamos poder elegir otros nodos.

  let aInfo:ptr VSAudioInfo = API.getAudioInfo(node)
  echo $aInfo
  #[
  Audio Info:
    format: (sampleType: 1, bitsPerSample: 32, bytesPerSample: 4, numChannels: 2, channelLayout: 3)
    sampleRate: 32000
    numSamples: 872064
    numFrames: 284
  ]#

  # Create the wave file
  var rw = createRiffFile("writetest-PCM16-LE.wav", FourCC_WAVE, littleEndian)
  var sampleFormat = sfPCM 
  let wf = WaveFormat(
    sampleFormat:  sfPCM,
    bitsPerSample: aInfo.format.bitsPerSample,
    sampleRate:    aInfo.sampleRate,
    numChannels:   aInfo.format.numChannels
  )

  rw.writeFormatChunk(wf)
  rw.beginChunk(FourCC_WAVE_data)
  var bitsPerSample = aInfo.format.bitsPerSample
  var amplitude = case bitsPerSample
  of  8: 2^7 / 4
  of 16: 2^15 / 4
  of 24: 2^23 / 4
  of 32:
    if sampleFormat == sfPCM: 2^31 / 4 else: 1.0 / 4
  of 64: 1.0 / 4
  else: 0

  var
    totalFrames =  aInfo.numFrames #LengthSeconds * SampleRate  # 1 frame = 2 samples (stereo)
    buf: array[1024, int32]
    pos = 0

  #var rw = writeTestFile[uint16]("writetest-PCM32-LE.wav", littleEndian, sfPCM, 16)
  #let nframes = vinfo.numFrames 
  for i in 0 ..< totalFrames:
    let 
      frame      = node.getFrame(i)
      fi         = API.getAudioFrameFormat(frame)
      numSamples = API.getFrameLength(frame)
      bytesPerOutputSample = ((fi.bitsPerSample + 7) / 8).int

    echo "bytesPerOutputSample:", bytesPerOutputSample
    #let toOutput = bytesPerOutputSample * numSamples * fi.numChannels
    #echo toOutput
    # Get pointers to channels
    var srcPtrs:seq[ptr uint8]
    var src:seq[ptr UncheckedArray[int8]]
    for channel in 0 ..< fi.numChannels:
      srcPtrs &= API.getReadPtr(frame, channel)
      src &= cast[ptr UncheckedArray[int8]](srcPtrs[channel])
    
    for sample in 0 ..< numSamples:    
      echo "sample: ", sample, "/",numSamples
      for channel in 0 ..< fi.numChannels:
        #echo "  channel: ", channel
        # memcpy(Dst + c * 3, Src[c] + i * 4 + 1, 3);
        #var tmp = @[src[channel][sample*4 + 1], src[channel][sample*4 + 2], src[channel][sample*4 + 3]]
        #var tmp  = cast[uint8](srcPtrs[channel]) + (sample*4 + 1).uint8
        #var tmp2 = cast[ptr UncheckedArray[int32]](tmp)
        #echo repr src[channel][(sample*4 + 1)..(sample*4 + 4)]
#[         var tmp3 = [src[channel][(sample*4 + 1)], 
                     src[channel][(sample*4 + 2)],
                     src[channel][(sample*4 + 3)] ] ]#
        var tmp3 = [src[channel][(sample*4 + 3)], 
                     src[channel][(sample*4 + 2)],
                     src[channel][(sample*4 + 1)] ]                     
        rw.write(tmp3, 0, 3 )

        #rw.write( data[sample*4+2] )  #Src[c][i * 4 + 2];
        #rw.write( data[sample*4+1] )
        #rw.write( data[sample*4] )
        #buf[pos]   = data[sample*4+2] #Src[c][i * 4 + 2];
        #buf[pos+1] = data[sample*4+1]
        #buf[pos+2] = data[sample*4]   
        #pos += 3
        #    Dst[c * 3 + 1] = Src[c][i * 4 + 1];
        #    Dst[c * 3 + 2] = Src[c][i * 4 + 0];    
    #for channel in 0..fi.numChannels:
      #
      #for i in 0..<numSamples:
      #  buf[pos] = srcPtrs[channel][].int16 - amplitude .int16
      #  pos += 1



        #if pos >= buf.len-4:
        #  rw.write(buf, 0, buf.len)
        #  pos = 0
          #echo "---------------------"


  #if pos > 0:
  #  rw.write(buf, 0, pos)

  rw.endChunk()

  #rw.writeCueChunk(regions)
  #rw.writeAdtlListChunk(regions)
  rw.close()


#[
void PackChannels32to24le(const uint8_t *const *const Src, uint8_t *Dst, size_t Length, size_t Channels) {
    for (size_t i = 0; i < Length; i++) {
        for (size_t c = 0; c < Channels; c++) {
#ifdef WAVE_LITTLE_ENDIAN
            memcpy(Dst + c * 3, Src[c] + i * 4 + 1, 3);
#else
            Dst[c * 3 + 0] = Src[c][i * 4 + 2];
            Dst[c * 3 + 1] = Src[c][i * 4 + 1];
            Dst[c * 3 + 2] = Src[c][i * 4 + 0];
#endif
        }
        Dst += Channels * 3;
    }
}
]#
#[
if (bytesPerOutputSample == 2)
    PackChannels16to16le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);
else if (bytesPerOutputSample == 3)
    PackChannels32to24le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);
else if (bytesPerOutputSample == 4)
    PackChannels32to32le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);
]#

#[
void PackChannels16to16le(const uint8_t *const *const Src, uint8_t *Dst, size_t Length, size_t Channels) {
    const uint16_t *const *const S = reinterpret_cast<const uint16_t *const *>(Src);
    uint16_t *D = reinterpret_cast<uint16_t *>(Dst);
    for (size_t i = 0; i < Length; i++) {
        for (size_t c = 0; c < Channels; c++)
            D[c] = WAVE_SWAP16_LE(S[c][i]);
        D += Channels;
    }
}
]#
    
  #let header = y4mheader( node )
  #let strm = newFileStream(stdout)
  #strm.write(header & "\n" )
  #discard strm.writeY4mFrames( node ) 
  API.freeMap(vsmap)
  API.freeNode(node)  


#[
} else if (data->vsapi->getFrameType(frame) == mtAudio) {
    const VSAudioFormat *fi = data->vsapi->getAudioFrameFormat(frame);

    int numChannels = fi->numChannels;
    int numSamples = data->vsapi->getFrameLength(frame);
    size_t bytesPerOutputSample = (fi->bitsPerSample + 7) / 8;
    size_t toOutput = bytesPerOutputSample * numSamples * numChannels;

    std::vector<const uint8_t *> srcPtrs;
    srcPtrs.reserve(numChannels);
    for (int channel = 0; channel < numChannels; channel++)
        srcPtrs.push_back(data->vsapi->getReadPtr(frame, channel));
    
    if (bytesPerOutputSample == 2)
        PackChannels16to16le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);
    else if (bytesPerOutputSample == 3)
        PackChannels32to24le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);
    else if (bytesPerOutputSample == 4)
        PackChannels32to32le(srcPtrs.data(), data->buffer.data(), numSamples, numChannels);

    if (data->calculateMD5)
        MD5_Update(&data->md5Ctx, data->buffer.data(), static_cast<unsigned long>(toOutput));

    if (fwrite(data->buffer.data(), 1, toOutput, data->outFile) != toOutput) {
        if (data->errorMessage.empty())
            data->errorMessage = "Error: fwrite() call failed when writing frame: " + std::to_string(data->outputFrames) + ", errno: " + std::to_string(errno);
        data->totalFrames = data->requestedFrames;
        data->outputError = true;
    }
}
    

]#