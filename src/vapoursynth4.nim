##[
VapourSynth.nim
===============

Why?
----

This will enable you to perform video manipulation. 




TODO
----
TODO: something like


TODO: documentation and integrate it with Github pages

https://nim-lang.org/docs/manual.html#types-mixing-gc-ed-memory-with-ptr
]##
# /usr/include/vapoursynth/VapourSynth4.h
{.passL:"-lvapoursynth".}
{.passC:"-I/usr/include/vapoursynth/" .}

when defined(linux):
  const
    libname* = "libvapoursynth.so"
elif defined(windows):
  const
    libname* = "vapoursynth.dll"
else:
  const
    libname* = "libvapoursynth.dylib"

import wrapper/vapoursynth_wrapper
export vapoursynth_wrapper


import lib/[info, vsframe, vsmap, output, vsplugins]
export info, vsframe, vsmap, output, vsplugins

import plugins/all_plugins
export all_plugins

#include "vsmacros/filter"  # This is the macro
#include "wrapper/vshelper4"
#include "wrapper/vsscript4_wrapper"


