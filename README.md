# vapoursynth4.nim

This enables video editing using the Nim programming language by means of using VapourSynth.

For more information visit the [web page](https://mantielero.github.io/VapourSynth.nim/) or go straight to the [documentation](https://mantielero.github.io/VapourSynth.nim/docs/).

> Everything is work in progress

# TODO

## Adding an audio example
To support the following:
```python
import vapoursynth as vs
audio = vs.core.bas.Source("somefile.mp3", track=-1)
video = vs.core.std.BlankClip()
video.set_output(0)
audio.set_output(1)
```

In Linux, install [BestAudioSource](https://github.com/vapoursynth/bestaudiosource):
```bash
$ yay -S aur/vapoursynth-plugin-bestaudiosource-git
```


About [set_output](http://vapoursynth.com/doc/pythonreference.html?highlight=pipe#VideoNode.set_output)
https://github.com/vapoursynth/vapoursynth/blob/7c9512fb39578d7cd8076b55e4b157a885877a10/src/common/wave.cpp


Audio and video?
```
import subprocess
def encode(clip: vs.VideoNode, filename: str) -> None:
    ffmpeg_args = ['ffmpeg', '-i', 'pipe:', filename]
    enc_proc = subprocess.Popen(ffmpeg_args, stdin=subprocess.PIPE)
    clip.output(enc_proc.stdin, y4m=bool(clip.format.color_family == vs.YUV))
    enc_proc.communicate()


>>> clip = core.ffms2.Source("my_loaded_video.avi")
>>> clip = ...
>>> encode(clip, 'out.mp4')
```