#let vsmap = Source("../test/2sec.mkv")#.ClipInfo()
#vsmap.Savey4m("borrame.y4m")

#echo vsmap.propGetData("hola", 1)
#echo vsmap.get(1)
#echo vsmap.toSeq



#ffmpeg -i test1.mkv -ss 00:00:12  -frames 1 -vcodec copy -an 1frame.mkv
 #ffmpeg -y -i file.mpg -r 1/1 $filename%03d.bmp | eog img.png

#xxd -b outputfile.y4m 
#ffmpeg -i ../test/test1.mkv  outputfile.y4m

# ffmpeg -i ../test/test1.mkv -f yuv4mpegpipe - | mplayer -idx -