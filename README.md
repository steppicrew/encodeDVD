encodeDVD
=========

These scripts require a ripped disc as mkv (ripped by makemkv) and are based on ffmpeg.

They only encode the video stream (all other streams are copied from source) and put the result in sub directory "out/".

For 3D to half-SBS coding you should have installed wine, tsMuxeR, avisynth, ffdshow, DGMVCSource, avs2yuv
(as described here: http://blog.nomoketo.de/3d-blurays-multiview-video-coding-linux/)

You can remux the audio streams with mkvmerge.
