# vspipe -c y4m ex01.vpy - | ffmpeg -i pipe: encoded.mkv
# vspipe -c y4m script.vpy - | x264 --demuxer y4m - --output encoded.mkv
from vapoursynth import core
video = core.ffms2.Source(source='./resources/test1.mkv')
video = core.std.Transpose(video)
video.set_output()