patch_file "nph", "phrenderer", "patches/phrenderer"

--threadAnalysis:
  off
--define:
  vm_exec_hooks
--define:
  nim_preview_hash_ref
--define:
  nim_type_names
--define:
  "chronicles_enabled=on"
--define:
  "chronicles_log_level=INFO"
--define:
  "chronicles_line_numbers"
--define:
  "chronicles_sinks=textlines[nocolors,file(/tmp/enu_mcp.log,truncate)]"
--define:
  "ed_partial_subscriber"
--define:
  "no_godot"
--path:
  "../generated"
--path:
  "../src"
