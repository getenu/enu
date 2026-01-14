switch("path", "$projectDir/../../src")
switch("path", "$projectDir/../../generated")
switch("path", "$projectDir/../../vmlib")

--threads:on
--mm:orc
--deepcopy:on
--tls_emulation:off

--define:no_godot
--define:vmExecHooks
--define:nimPreviewHashRef
--define:nimTypeNames

# Chronicles config (match main project)
--define:"chronicles_enabled=on"
--define:"chronicles_log_level=INFO"
--define:"chronicles_sinks=textlines[dynamic]"

--experimental:dynamicBindSym
--warning:"LockLevel:off"
--warning:"UseBase:off"
