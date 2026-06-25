switch("path", "$projectDir/../../src")
switch("path", "$projectDir/../../generated")
switch("path", "$projectDir/../../share/vmlib")
switch("path", this_dir())
--define:vmExecHooks
--define:useRealtimeGC
--experimental:dynamicBindSym
