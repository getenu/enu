## Per-script VM execution state. Nim 2.4's VM keeps "the code that's running"
## on the shared `PCtx`: one LIFO bump stack for frames, plus scalars like the
## loop and call-depth budgets and the current exception. Scripts park and
## resume in any order, so each script owns a copy and swaps it in while it
## runs. Everything else (code, heap, globals) stays shared.

import std/importutils
when not defined(windows):
  import std/posix
import pkg/compiler/[vmdef, modulegraphs]
import pkg/compiler/vmmem {.all.}

privateAccess(VmMemory)
privateAccess(StackSegment)

const first_segment_size = 64 * 1024

type ExecState* = object
  # The VM this state belongs to. A script's interpreter can be replaced (a
  # level change) while its tasks are still parked on the old one.
  vm*: PCtx
  stack: typeof(VmMemory().stack)
  sp: StackMark
  boxes: seq[Address]
  module: typeof(TCtx().module)
  prc: PProc
  idgen: typeof(TCtx().idgen)
  callsite: typeof(TCtx().callsite)
  mode: TEvalMode
  loop_iterations*: int
  call_depth: int
  current_exception_a, current_exception_b: Address
  exception_instr: int
  comes_from_heuristic: typeof(TCtx().comesFromHeuristic)
  sem_ctx: PPassContext
  # set when it owns the lazily-mapped first segment, so `release` unmaps it
  owns_first_segment: bool

proc init*(_: type ExecState, c: PCtx): ExecState =
  ## A fresh stack. It starts with one small lazily-committed segment rather
  ## than the VM's zeroed 2MB `StackSegmentSize` (2MB of RSS per parked
  ## script); deeper scripts spill into VM-allocated segments.
  # `type ExecState` makes this generic, instantiated where the caller is.
  privateAccess(VmMemory)
  privateAccess(StackSegment)
  result.vm = c
  result.module = c.module
  result.prc = PProc(blocks: @[])
  result.idgen = c.idgen
  result.mode = c.mode
  result.loop_iterations = c.config.maxLoopIterationsVM
  result.call_depth = c.config.maxCallDepthVM
  when defined(windows):
    let p = alloc0(first_segment_size)
  else:
    let p = mmap(
      nil, first_segment_size, PROT_READ or PROT_WRITE,
      MAP_PRIVATE or MAP_ANONYMOUS, -1, 0,
    )
    doAssert p != MAP_FAILED
  addRegion(c.mem, toAddr(p), first_segment_size, rgStack)
  result.stack = @[StackSegment(base: toAddr(p), cap: first_segment_size)]
  result.owns_first_segment = true

proc swap*(s: var ExecState) =
  ## Exchange the VM's live execution state with `s`. Call once to swap a
  ## script in and again to swap it back out.
  let c = s.vm
  swap c.mem.stack, s.stack
  swap c.mem.sp, s.sp
  swap c.mem.boxes, s.boxes
  swap c.module, s.module
  swap c.prc, s.prc
  swap c.idgen, s.idgen
  swap c.callsite, s.callsite
  swap c.mode, s.mode
  swap c.loopIterations, s.loop_iterations
  swap c.callDepth, s.call_depth
  swap c.currentExceptionA, s.current_exception_a
  swap c.currentExceptionB, s.current_exception_b
  swap c.exceptionInstr, s.exception_instr
  swap c.comesFromHeuristic, s.comes_from_heuristic
  swap c.semCtx, s.sem_ctx

proc release*(s: var ExecState) =
  ## Free a swapped-out state's stack and the boxes of frames that never
  ## returned.
  let c = s.vm
  for box in s.boxes:
    discard heapDealloc(c.mem, box)
  s.boxes.set_len 0
  for i, seg in s.stack:
    removeRegion(c.mem, seg.base)
    if i == 0 and s.owns_first_segment:
      when defined(windows):
        dealloc(toPtr(seg.base))
      else:
        discard munmap(toPtr(seg.base), first_segment_size)
    else:
      hostDealloc(seg.base)
  s.stack.set_len 0
