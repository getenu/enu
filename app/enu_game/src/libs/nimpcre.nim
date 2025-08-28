# from https://github.com/genotrance/nimpcre/blob/master/nimpcre.nim
import os, strutils

import xxnimterop/[build, cimport]

when not defined(usePcreHeader):
  static:
    doAssert false, "Error: -d:usePcreHeader is required"

static:
  cDebug()

const
  baseDir = getProjectCacheDir("nimpcre")

  defs = """
    pcreStatic
    pcreStd
    pcreDL
    pcreSetVer=8.43
  """

setDefines(defs.splitLines())

getHeader(
  "pcre.h",
  "https://github.com/svn2github/pcre",
  "https://ftp.exim.org/pub/pcre/pcre-$1.tar.gz",
  outdir = baseDir
)

{.passC: "-DPCRE_STATIC -I" & pcrePath.parentDir().}
const
  lpath =
    when "16.a" in pcreLPath:
      pcreLPath.replace("16.a", ".a")
    elif "32.a" in pcreLPath:
      pcreLPath.replace("32.a", ".a")
    else:
      pcreLPath
static:
  if lpath != pcreLPath:
    echo "# Actually including library " & lpath
{.passL: lpath.}