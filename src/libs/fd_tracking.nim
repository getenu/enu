## File descriptor budget and observability.
##
## Enu's worker thread reloads scripts on every save_and_reload, and the
## Nim VM compiler holds file handles open per loaded module. macOS's
## default per-process fd limit (256) is too low for many reload cycles
## — we hit EMFILE in writeFile partway through retry_failed_scripts.
##
## raise_fd_limit bumps RLIMIT_NOFILE to the hard limit (or 8192) at
## startup. open_fd_count walks /dev/fd so we can watch the actual
## usage over time.

import std/[os, posix]
import pkg/metrics
import chronicles

declare_gauge enu_open_fds, "Open file descriptors held by the Enu process."

proc raise_fd_limit*() =
  ## Set RLIMIT_NOFILE soft limit to the hard limit (or 8192, whichever
  ## is smaller). Logs the before/after for diagnosis.
  var lim: RLimit
  if getrlimit(RLIMIT_NOFILE, lim) != 0:
    error "getrlimit failed", errno = errno
    return
  let before = lim.rlim_cur
  let target = min(8192, lim.rlim_max)
  if lim.rlim_cur >= target:
    info "fd limit already at target", soft = before, hard = lim.rlim_max
    return
  lim.rlim_cur = target
  if setrlimit(RLIMIT_NOFILE, lim) != 0:
    error "setrlimit failed", errno = errno, target = target
    return
  info "raised fd limit", before, after = lim.rlim_cur, hard = lim.rlim_max

proc open_fd_count*(): int =
  ## Count entries in /dev/fd (macOS/Linux). Returns -1 if unavailable.
  ## The directory handle we open is counted, so the result is one
  ## higher than the steady-state count.
  if not dir_exists("/dev/fd"):
    return -1
  for _, _ in walk_dir("/dev/fd"):
    inc result

proc sample_open_fds*() =
  ## Update the enu_open_fds gauge from /dev/fd. Cheap; safe to call
  ## frequently.
  let n = open_fd_count()
  if n >= 0:
    enu_open_fds.set(n.float)
