## Sandbox probe: a script must not be able to read host files.
##
## `read_file` is registered as a VM callback only inside `when defined(nimcore)`
## in the compiler's vmops.nim, with no sandbox-flag gate. Static reading could
## not tell whether enu's embedded compiler activates that block, so this runs
## the real interpreter in the shipping binary. Empirically the callback is NOT
## registered: the call falls through to the stdlib body and hits `fopen`
## (importc), which the VM refuses -- an UNCATCHABLE abort (try/except does not
## catch it), so this script never reaches its own end when the sandbox holds.
##
## The regression signal is therefore negative: a working sandbox prints no
## `SANDBOX-LEAK` line. `nim test_sandbox` fails iff that line appears (a script
## reached host data). See the task in tasks.nim.

import std/syncio

speed = 0

# If the sandbox ever regresses (readFile bridged to the host), this returns
# real bytes and prints the leak marker the task greps for. If blocked, the VM
# aborts on `fopen` before reaching this point.
let data = read_file("/etc/hostname")
echo "SANDBOX-LEAK read_file -> ", data.len, " bytes: ", data.strip
