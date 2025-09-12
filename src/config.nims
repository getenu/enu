--path:
  "../../src"
--path:
  "../../generated"
--path:
  "../../vmlib/enu"

--threads:
  on
--mm:
  orc
--tls_emulation:
  off
--deepcopy:
  on

if host_os == "windows":
  --pass_l:
    "-static"
  --define:
    "chronicles_colors=None"
  --define:
    "nim_raw_setjmp"

--warning:
  "LockLevel:off"
--warning:
  "UseBase:off"
--warning:
  "GcUnsafe2:off"

--experimental:
  "dynamic_bind_sym"

--define:
  "vm_exec_hooks"
--define:
  "nim_preview_hash_ref"
--define:
  "nim_type_names"
--define:
  "chronicles_enabled=on"
--define:
  "chronicles_log_level=INFO"
--define:
  "chronicles_sinks=textlines"
# --define:
#   "chronicles_disabled_topics=verbose"

# GD4: remove me
--threadAnalysis:
  off

if defined(release):
  --define:
    "chronicles_colors=None"
  --define:
    "chronicles_log_level=INFO"
  --assertions:
    off
  --define:
    "zen_lax_free"
