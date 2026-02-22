import compiler/ast
import compiler/modules
import compiler/passes
import compiler/passaux
import compiler/condsyms
import compiler/options
import compiler/llstream
import compiler/idents
import compiler/sem
import compiler/modulegraphs
import compiler/lineinfos
import compiler/pathutils
import compiler/vm

proc testOwner() =
  var cache = newIdentCache()
  var config = newConfigRef()
  var graph = newModuleGraph(cache, config)
  
  let code = """
import std/strutils
var x = "hello".toUpperAscii()
"""
  # We won't easily setup full compiler here... maybe I can just add a debug dump in eval.nim itself!
