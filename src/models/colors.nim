import pkg/core/godotcoretypes as godot except Color
import pkg/chroma
import std/[json, strutils, hashes]

export chroma

converter to_chroma_color*(self: godot.Color): chroma.Color =
  cast[chroma.Color](self)

converter to_godot_color*(self: chroma.Color): godot.Color =
  cast[godot.Color](self)

proc col*(hex: string): chroma.Color =
  hex.parse_hex

proc color_of*(id: string): chroma.Color =
  ## A stable, vivid color from an id: hash to a hue with fixed saturation
  ## and lightness, so every id lands somewhere bright and distinguishable.
  hsl(float(id.hash and 0xFFFF) / 65536.0 * 360.0, 70, 55).color

type
  Colors* = enum
    ERASER
    BLUE
    RED
    GREEN
    BLACK
    WHITE
    BROWN

  Theme* = enum
    NORMAL
    COMMENT
    ENTITY
    KEYWORD
    OPERATOR
    CLASS
    STORAGE
    CONSTANT
    TEXT
    NUMBER
    VARIABLE
    INVALID

const IR_BLACK* = [
  NORMAL: col"F6F3E8",
  COMMENT: col"7C7C7C",
  ENTITY: col"FFD2A7",
  KEYWORD: col"96CBFE",
  OPERATOR: col"EDEDED",
  CLASS: col"FFFFB6",
  STORAGE: col"CFCB90",
  CONSTANT: col"99CC99",
  TEXT: col"A8FF60",
  NUMBER: col"FF73FD",
  VARIABLE: col"C6C5FE",
  INVALID: col"FD5FF1",
]

const ACTION_COLORS* = [
  ERASER: chroma.Color(),
  BLUE: col"0067ff",
  RED: col"fc0e0b",
  GREEN: col"14f707",
  BLACK: col"000000",
  WHITE: col"d9eed8",
  BROWN: col"3f302b",
]

proc action_index*(self: Color): Colors =
  for key, value in ACTION_COLORS:
    if value == self:
      return key

proc to_json_hook*(self: Color): JsonNode =
  result =
    if self == ACTION_COLORS[ERASER]:
      %""
    else:
      for c in Colors:
        if self == ACTION_COLORS[c]:
          return %($c)
      %self.to_html_hex

proc from_json_hook*(self: var Color, json: JsonNode) =
  let hex = json.get_str
  if hex == "":
    self = ACTION_COLORS[ERASER]
  else:
    for c in Colors:
      if ($c).toLowerAscii == hex.toLowerAscii:
        self = ACTION_COLORS[c]
        return
    self = hex.parse_html_hex
