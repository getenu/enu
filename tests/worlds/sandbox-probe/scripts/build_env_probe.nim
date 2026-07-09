## Sandbox probe: a script must not be able to read the host environment.
##
## Companion to build_read_probe.nim, for `getEnv`. Unlike readFile, get_env
## does NOT abort in enu's VM -- it's evaluated and returns the empty string for
## every key (an effective stub), so it neither aborts nor leaks real env data.
## The leak signal here is therefore a NON-EMPTY return matching the canary the
## task injects (`ENU_SANDBOX_CANARY`): empty = safe, canary value = get_env got
## bridged to the real host environment. A separate thing from the read probe so
## its uncatchable abort can't mask this one.

import std/envvars

speed = 0

# NB: build scripts have injected identifiers (`home`, `enu_target`, `move_mode`,
# ...) so the probe var must avoid those names or it dies on a redefinition
# error before `get_env` is ever reached (a false pass).
let secret = get_env("ENU_SANDBOX_CANARY")
if secret.len > 0:
  echo "SANDBOX-LEAK get_env canary -> ", secret
else:
  echo "sandbox-ok: get_env returned empty"
