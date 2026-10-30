when not defined(nimsuggest):
  import tasks

# osdialog's Linux backend must be chosen at compile time. Use Zenity (a
# subprocess) rather than GTK so we never link GTK into the app; zenity is a
# runtime dependency, present on most desktops. macOS (Cocoa) and Windows
# (Win32) need no such switch.
when defined(linux):
  switch("define", "osdialogZenity")

# Nim 2.2.12's backend-alias check in procParamTypeRel rejects lambdas whose
# params mention a generic (`proc(changes: seq[Change[O]])`), which breaks ed.
# Fixed in our Nim fork (used by the script VM); this covers the host compiler.
when (NimMajor, NimMinor, NimPatch) >= (2, 2, 12):
  switch("legacy", "procParamTypeBackendAliases")
