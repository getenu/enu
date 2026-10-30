## Stackful coroutines (minicoro) for running scripts. A script parks by
## switching back to whoever resumed it, from anywhere in its call stack —
## including from inside the Nim VM.

import std/os
when not defined(windows):
  import std/posix

{.passc: "-I" & current_source_path().parent_dir / "minicoro".}
{.compile: "minicoro/minicoro_impl.c".}

type
  McoCoro {.importc: "mco_coro", header: "minicoro.h", incompleteStruct.} = object
  McoResult {.importc: "mco_result", header: "minicoro.h".} = cint
  McoState {.importc: "mco_state", header: "minicoro.h".} = cint
  McoDesc {.importc: "mco_desc", header: "minicoro.h", bycopy.} = object
    `func`: proc(co: ptr McoCoro) {.cdecl.}
    user_data: pointer
    alloc_cb: proc(size: csize_t, allocator_data: pointer): pointer {.cdecl.}
    dealloc_cb: proc(p: pointer, size: csize_t, allocator_data: pointer) {.cdecl.}

  Coroutine* = ref object
    co: ptr McoCoro
    body: proc() {.gcsafe.}
    frame_state: typeof(get_frame_state())
    error: ref Exception

const
  MCO_SUCCESS = 0.McoResult
  MCO_DEAD = 0.McoState

proc mco_desc_init(
  fn: proc(co: ptr McoCoro) {.cdecl.}, stack_size: csize_t
): McoDesc {.importc, header: "minicoro.h".}

proc mco_create(
  out_co: ptr ptr McoCoro, desc: ptr McoDesc
): McoResult {.importc, header: "minicoro.h".}

proc mco_destroy(co: ptr McoCoro): McoResult {.importc, header: "minicoro.h".}
proc mco_resume(co: ptr McoCoro): McoResult {.importc, header: "minicoro.h".}
proc mco_yield(co: ptr McoCoro): McoResult {.importc, header: "minicoro.h".}
proc mco_status(co: ptr McoCoro): McoState {.importc, header: "minicoro.h".}
proc mco_get_user_data(co: ptr McoCoro): pointer {.importc, header: "minicoro.h".}
proc mco_running(): ptr McoCoro {.importc, header: "minicoro.h".}

when not defined(windows):
  # Stacks are lazily committed, with a guard page below so an overflow
  # faults instead of silently corrupting the neighbouring allocation.
  # (On Windows minicoro runs on fibers, which manage their own stacks.)
  let page = sysconf(SC_PAGESIZE).int

  proc mapped_size(size: csize_t): int =
    ((size.int + page - 1) div page) * page + page

  proc guarded_alloc(size: csize_t, data: pointer): pointer {.cdecl.} =
    let total = mapped_size(size)
    let p = mmap(
      nil, total, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0
    )
    if p == MAP_FAILED:
      return nil
    doAssert mprotect(p, page, PROT_NONE) == 0
    cast[pointer](cast[int](p) + page)

  proc guarded_dealloc(p: pointer, size: csize_t, data: pointer) {.cdecl.} =
    discard munmap(cast[pointer](cast[int](p) - page), mapped_size(size))

proc entry(co: ptr McoCoro) {.cdecl.} =
  let self = cast[Coroutine](mco_get_user_data(co))
  try:
    self.body()
  except Exception as e:
    # Exceptions can't unwind past the coroutine; `resume` re-raises it.
    self.error = e

proc init*(
    _: type Coroutine, body: proc() {.gcsafe.}, stack_size = 512 * 1024
): Coroutine =
  result = Coroutine(body: body)
  var desc = mco_desc_init(entry, stack_size.csize_t)
  desc.user_data = cast[pointer](result)
  when not defined(windows):
    desc.alloc_cb = guarded_alloc
    desc.dealloc_cb = guarded_dealloc
  doAssert mco_create(addr result.co, addr desc) == MCO_SUCCESS,
    "could not create coroutine"

proc finished*(self: Coroutine): bool =
  self.co == nil or mco_status(self.co) == MCO_DEAD

proc resume*(self: Coroutine) =
  ## Run until the coroutine suspends or finishes. An exception that escaped
  ## its body is raised here. Nim's frame and current-exception thread-locals
  ## belong to whichever stack is running, so they're swapped too.
  assert not self.finished
  let host_state = get_frame_state()
  set_frame_state(self.frame_state)
  doAssert mco_resume(self.co) == MCO_SUCCESS
  self.frame_state = get_frame_state()
  set_frame_state(host_state)
  if not self.error.is_nil:
    let e = self.error
    self.error = nil
    raise e

proc suspend*() =
  ## Park the running coroutine, returning to whoever resumed it.
  let co = mco_running()
  doAssert co != nil, "suspend called outside a coroutine"
  doAssert mco_yield(co) == MCO_SUCCESS

proc in_coroutine*(): bool =
  mco_running() != nil

proc running*(self: Coroutine): bool =
  ## True while this coroutine is the one executing.
  self.co != nil and mco_running() == self.co

proc destroy*(self: Coroutine) =
  ## Free the stack. A coroutine destroyed while suspended is abandoned
  ## without unwinding, so anything still live on its stack leaks.
  if self.co != nil:
    discard mco_destroy(self.co)
    self.co = nil
