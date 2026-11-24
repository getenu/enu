when not defined(nimsuggest):
  import tasks

# Distributed builds leave out the debug checks (build_node's display check).
# Benchmarks pass -d:skip_checks themselves.
when defined(dist):
  switch("define", "skip_checks")

# Signs and script pages are rendered by Blitz (rust/pages),
# which `nim build` builds. `-d:no_pages` leaves it out. Not on iOS yet.
when not defined(no_pages) and not defined(ios) and get_env("TARGET") != "ios":
  switch("define", "enu_pages")

# osdialog's Linux backend must be chosen at compile time. Use Zenity (a
# subprocess) rather than GTK so we never link GTK into the app; zenity is a
# runtime dependency, present on most desktops. macOS (Cocoa) and Windows
# (Win32) need no such switch.
when defined(linux):
  switch("define", "osdialogZenity")
