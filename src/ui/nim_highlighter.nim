import gdext
import gdext/classes/[gdcodehighlighter, gdsyntaxhighlighter]
import core
import models/colors

proc create_nim_highlighter*(): gdref CodeHighlighter =
  ## Create and configure a CodeHighlighter for Nim syntax
  result = instantiate(CodeHighlighter)

  # Define ir_black color scheme for Nim syntax
  let
    keyword_control_color = ir_black[Keyword].to_godot_color
      # Light blue - control flow
    keyword_decl_color = ir_black[Storage].to_godot_color
      # Yellow-green - declarations
    keyword_bool_color = ir_black[Operator].to_godot_color # White - boolean ops
    string_color = ir_black[Text].to_godot_color # Green - strings
    comment_color = ir_black[Comment].to_godot_color # Gray - comments
    number_color = ir_black[Number].to_godot_color # Purple - numbers
    function_color = ir_black[Entity].to_godot_color # Orange - functions
    symbol_color = ir_black[Variable].to_godot_color # Light purple - symbols

  # Control flow keywords
  let control_keywords = [
    "block", "break", "case", "continue", "do", "elif", "else", "end", "except",
    "finally", "for", "if", "raise", "return", "try", "when", "while", "yield",
  ]
  for keyword in control_keywords:
    result[].addKeywordColor(newGdString(keyword), keyword_control_color)

  # Declaration and type keywords
  let decl_keywords = [
    "addr", "as", "asm", "atomic", "bind", "cast", "const", "converter",
    "concept", "defer", "discard", "distinct", "div", "enum", "export", "from",
    "import", "include", "let", "mod", "mixin", "object", "of", "ptr", "ref",
    "shl", "shr", "static", "type", "using", "var", "tuple", "iterator",
    "macro", "func", "method", "proc", "template",
  ]
  for keyword in decl_keywords:
    result[].addKeywordColor(newGdString(keyword), keyword_decl_color)

  # Boolean and logical operators
  let bool_keywords = ["and", "in", "is", "isnot", "not", "notin", "or", "xor"]
  for keyword in bool_keywords:
    result[].addKeywordColor(newGdString(keyword), keyword_bool_color)

  # String regions
  result[].addColorRegion(
    newGdString("\""), newGdString("\""), string_color, false
  ) # Double quotes
  result[].addColorRegion(
    newGdString("'"), newGdString("'"), string_color, true
  ) # Single quotes (line only)
  result[].addColorRegion(
    newGdString("\"\"\""), newGdString("\"\"\""), string_color, false
  ) # Triple quotes
  result[].addColorRegion(
    newGdString("r\""), newGdString("\""), string_color, false
  ) # Raw strings

  # Comment regions
  result[].addColorRegion(
    newGdString("#"), newGdString(""), comment_color, true
  ) # Line comments
  result[].addColorRegion(
    newGdString("#["), newGdString("]#"), comment_color, false
  ) # Block comments
  result[].addColorRegion(
    newGdString("##"), newGdString(""), comment_color, true
  ) # Doc comments

  # Built-in element colors
  result[].setNumberColor(number_color)
  result[].setFunctionColor(function_color)
  result[].setSymbolColor(symbol_color)
