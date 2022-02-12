# vspipe -c y4m ex02.vpy - | ffmpeg -i pipe: encoded.mkv
# vspipe -c wav -o 1 ex02.vpy salida.wav
# vspipe -c y4m ex02.vpy - | x264 --demuxer y4m - --output encoded.mkv
import vapoursynth as vs
audio = vs.core.bas.Source("./resources/file_example_MP3_700KB.mp3", track=-1)
video = vs.core.std.BlankClip()
video.set_output(0)
audio.set_output(1)