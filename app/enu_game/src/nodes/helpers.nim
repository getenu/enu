import gdext
import core

# Minimal helpers implementation to get compilation working
proc model*(self: Object): Model =
  # GD4: Model extraction needs complete rework
  result = nil