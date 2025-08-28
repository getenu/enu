import gdext

# import pkg/core/godotcoretypes as godot except Color
import pkg/chroma

export chroma

converter to_chroma_color*(self: gdext.Color): chroma.Color =
  cast[chroma.Color](self)

converter to_godot_color*(self: chroma.Color): gdext.Color =
  cast[gdext.Color](self)

proc col*(hex: string): chroma.Color =
  hex.parse_hex

type
  Colors* = enum
    Eraser
    Blue
    Red
    Green
    Black
    White
    Brown

  Theme* = enum
    Normal
    Comment
    Entity
    Keyword
    Operator
    Class
    Storage
    Constant
    Text
    Number
    Variable
    Invalid

const ir_black* = [
  Normal: col"F6F3E8",
  Comment: col"7C7C7C",
  Entity: col"FFD2A7",
  Keyword: col"96CBFE",
  Operator: col"EDEDED",
  Class: col"FFFFB6",
  Storage: col"CFCB90",
  Constant: col"99CC99",
  Text: col"A8FF60",
  Number: col"FF73FD",
  Variable: col"C6C5FE",
  Invalid: col"FD5FF1"
]

const action_colors* = [
  Eraser: chroma.Color(),
  Blue: col"0067ff",
  Red: col"fc0e0b",
  Green: col"14f707",
  Black: col"000000",
  White: col"d9eed8",
  Brown: col"3f302b"
]

proc action_index*(self: chroma.Color): Colors =
  for key, value in action_colors:
    if value == self:
      return key

when is_main_module:
  print action_colors[white]
