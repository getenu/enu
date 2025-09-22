# MIGRATION STATUS: 100% Complete - Simple input handling component fully functional
#
# ✅ FULLY FUNCTIONAL:
#   - Input event interception and consumption
#   - Button type extension with custom behavior
#   - Event propagation prevention (accept_event())
#
# 🔧 KEY CHANGES FROM GODOT 3:
#   - 9 lines -> 9 lines: Functionality preserved exactly
#   - gdobj FloatingButton -> type FloatingButton* {.gdsync.} = ptr object of Button
#   - Method signature updated for gdext (InputEvent parameter)
#   - accept_event() call works identically in Godot 4
#
# ❌ NO LIMITATIONS: This component is fully functional
#
# 📝 NO TODOS: Component is complete and requires no additional work

import gdext
import gdext/classes/[gdbutton, gdinputevent]
import core, gdcore

type FloatingButton* {.gdsync.} = ptr object of Button

method gui_input*(self: FloatingButton, event: gdref InputEvent) {.gdsync.} =
  # Accept all input events to prevent them from propagating
  self.accept_event()
