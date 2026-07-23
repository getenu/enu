when not defined(nimsuggest):
  import tasks

# osdialog's Linux backend must be chosen at compile time. Use Zenity (a
# subprocess) rather than GTK so we never link GTK into the app; zenity is a
# runtime dependency, present on most desktops. macOS (Cocoa) and Windows
# (Win32) need no such switch.
when defined(linux):
  switch("define", "osdialogZenity")
