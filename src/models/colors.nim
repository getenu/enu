import pkg/core/godotcoretypes as godot except Color
import pkg/chroma

export chroma

converter to_chroma_color*(self: godot.Color): chroma.Color =
  cast[chroma.Color](self)

converter to_godot_color*(self: chroma.Color): godot.Color =
  cast[godot.Color](self)

proc col*(hex: string): chroma.Color =
  hex.parse_hex

type
  Colors* = enum
    eraser
    blue
    red
    green
    black
    white
    brown

  Theme* = enum
    normal
    comment
    entity
    keyword
    operator
    class
    storage
    constant
    text
    number
    variable
    invalid

const ir_black* = [
  normal: col"F6F3E8",
  comment: col"7C7C7C",
  entity: col"FFD2A7",
  keyword: col"96CBFE",
  operator: col"EDEDED",
  class: col"FFFFB6",
  storage: col"CFCB90",
  constant: col"99CC99",
  text: col"A8FF60",
  number: col"FF73FD",
  variable: col"C6C5FE",
  invalid: col"FD5FF1"
]

const action_colors* = [
  eraser: chroma.Color(),
  blue: col"0067ff",
  red: col"fc0e0b",
  green: col"14f707",
  black: col"000000",
  white: col"d9eed8",
  brown: col"3f302b"
]

const solid_alpha* = Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
const dimmed_alpha* = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.4)

proc action_index*(self: Color): Colors =
  for key, value in action_colors:
    if value == self:
      return key

when is_main_module:
  print action_colors[white]
