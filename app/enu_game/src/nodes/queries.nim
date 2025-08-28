import gdext
import core

# Minimal queries implementation to get compilation working
proc run*(query: var SightQuery, source: Unit) =
  # GD4: Sight query system needs complete rework
  discard