## Sandbox probe: a script must not be able to read host files at compile time.
##
## `slurp`/`staticRead` run in the compiler's VM while the script compiles, not
## through a vmops callback, so the `read_file` probe doesn't cover them. A
## blocked slurp is a compile error, so a working sandbox never prints
## `SANDBOX-LEAK`. See `nim test_sandbox` in tasks.nim.

speed = 0

const data = static_read("/etc/hosts")
echo "SANDBOX-LEAK static_read -> ", data.len, " bytes"
