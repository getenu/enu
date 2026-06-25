# MCP integration tests. These drive a *running* Enu over the client layer
# (no_godot, like bin/enu.nim), so they aren't part of `nim test` yet — see the
# TODO in tasks.nim. Run against a live Enu with `nim mcp_repro`.
switch("path", "$projectDir/../../src")
switch("path", "$projectDir/../../generated")
switch("path", "$projectDir/../../share/vmlib")

--threads:on
--mm:orc
--deepcopy:on
--tls_emulation:off

--define:no_godot
--define:vmExecHooks
--define:nimPreviewHashRef
--define:nimTypeNames
--define:ed_partial_subscriber

# Chronicles config (match main project)
--define:"chronicles_enabled=on"
--define:"chronicles_log_level=INFO"
--define:"chronicles_sinks=textlines[dynamic]"

--experimental:dynamicBindSym
--warning:"LockLevel:off"
--warning:"UseBase:off"
