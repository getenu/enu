import gdext
import gdext/classes/gdcodehighlighter
import core
import models/colors

type NimHighlighter* = ref object
  highlighter*: gdref CodeHighlighter

proc create_nim_highlighter*(): NimHighlighter =
  ## Create and configure a CodeHighlighter for Nim syntax
  result = NimHighlighter()
  result.highlighter = instantiate(CodeHighlighter)
  
  # Define ir_black color scheme for Nim syntax
  let
    keyword_control_color = ir_black[Keyword].to_godot_color  # Light blue - control flow
    keyword_decl_color = ir_black[Storage].to_godot_color     # Yellow-green - declarations  
    keyword_bool_color = ir_black[Operator].to_godot_color   # White - boolean ops
    string_color = ir_black[Text].to_godot_color             # Green - strings
    comment_color = ir_black[Comment].to_godot_color         # Gray - comments
    number_color = ir_black[Number].to_godot_color           # Purple - numbers
    function_color = ir_black[Entity].to_godot_color         # Orange - functions
    symbol_color = ir_black[Variable].to_godot_color         # Light purple - symbols
  
  # Control flow keywords
  let control_keywords = [
    "block", "break", "case", "continue", "do", "elif", "else", "end", 
    "except", "finally", "for", "if", "raise", "return", "try", "when", 
    "while", "yield"
  ]
  for keyword in control_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_control_color)
  
  # Declaration and type keywords  
  let decl_keywords = [
    "addr", "as", "asm", "atomic", "bind", "cast", "const", "converter", 
    "concept", "defer", "discard", "distinct", "div", "enum", "export", 
    "from", "import", "include", "let", "mod", "mixin", "object", "of", 
    "ptr", "ref", "shl", "shr", "static", "type", "using", "var", "tuple", 
    "iterator", "macro", "func", "method", "proc", "template"
  ]
  for keyword in decl_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_decl_color)
  
  # Boolean and logical operators
  let bool_keywords = [
    "and", "in", "is", "isnot", "not", "notin", "or", "xor"
  ]
  for keyword in bool_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_bool_color)
  
  # String regions
  result.highlighter.addColorRegion(gdstring"\"", "\"", string_color, false)  # Double quotes
  result.highlighter.addColorRegion(gdstring"'", "'", string_color, true)     # Single quotes (line only)
  result.highlighter.addColorRegion(gdstring"\"\"\"", "\"\"\"", string_color, false) # Triple quotes
  result.highlighter.addColorRegion(gdstring"r\"", "\"", string_color, false) # Raw strings
  
  # Comment regions
  result.highlighter.addColorRegion(gdstring"#", "", comment_color, true)     # Line comments
  result.highlighter.addColorRegion(gdstring"#[", "]#", comment_color, false) # Block comments
  result.highlighter.addColorRegion(gdstring"##", "", comment_color, true)    # Doc comments
  
  # Built-in element colors
  result.highlighter.setNumberColor(number_color)
  result.highlighter.setFunctionColor(function_color)  
  result.highlighter.setSymbolColor(symbol_color)
  
  print("[UI] Created Nim syntax highlighter with ", 
        len(control_keywords) + len(decl_keywords) + len(bool_keywords), " keywords")

# TODO: Re-enable once we fix set_syntax_highlighter method access
# proc apply_to_code_edit*(nim_hl: NimHighlighter, code_edit: CodeEdit) =
#   ## Apply the Nim highlighter to a CodeEdit widget
#   if nim_hl.highlighter != nil:
#     code_edit.set_syntax_highlighter(nim_hl.highlighter)
#     print("[UI] Applied Nim syntax highlighting to CodeEdit")
#   else:
#     print("[UI] Warning: Cannot apply syntax highlighting - highlighter is nil")

proc create_dark_theme_highlighter*(): NimHighlighter =
  ## Create a dark theme variant of the Nim highlighter
  result = NimHighlighter()
  result.highlighter = instantiate(CodeHighlighter)
  
  # Dark theme ir_black color scheme (same colors as default)
  let
    keyword_control_color = ir_black[Keyword].to_godot_color  # Light blue - control flow
    keyword_decl_color = ir_black[Storage].to_godot_color     # Yellow-green - declarations  
    keyword_bool_color = ir_black[Operator].to_godot_color   # White - boolean ops
    string_color = ir_black[Text].to_godot_color             # Green - strings
    comment_color = ir_black[Comment].to_godot_color         # Gray - comments
    number_color = ir_black[Number].to_godot_color           # Purple - numbers
    function_color = ir_black[Entity].to_godot_color         # Orange - functions
    symbol_color = ir_black[Variable].to_godot_color         # Light purple - symbols
  
  # Same keywords as default theme
  let control_keywords = [
    "block", "break", "case", "continue", "do", "elif", "else", "end", 
    "except", "finally", "for", "if", "raise", "return", "try", "when", 
    "while", "yield"
  ]
  for keyword in control_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_control_color)
  
  let decl_keywords = [
    "addr", "as", "asm", "atomic", "bind", "cast", "const", "converter", 
    "concept", "defer", "discard", "distinct", "div", "enum", "export", 
    "from", "import", "include", "let", "mod", "mixin", "object", "of", 
    "ptr", "ref", "shl", "shr", "static", "type", "using", "var", "tuple", 
    "iterator", "macro", "func", "method", "proc", "template"
  ]
  for keyword in decl_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_decl_color)
  
  let bool_keywords = [
    "and", "in", "is", "isnot", "not", "notin", "or", "xor"
  ]
  for keyword in bool_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_bool_color)
  
  # String and comment regions (same patterns, different colors)
  result.highlighter.addColorRegion(gdstring"\"", "\"", string_color, false)
  result.highlighter.addColorRegion(gdstring"'", "'", string_color, true)
  result.highlighter.addColorRegion(gdstring"\"\"\"", "\"\"\"", string_color, false)
  result.highlighter.addColorRegion(gdstring"r\"", "\"", string_color, false)
  
  result.highlighter.addColorRegion(gdstring"#", "", comment_color, true)
  result.highlighter.addColorRegion(gdstring"#[", "]#", comment_color, false)
  result.highlighter.addColorRegion(gdstring"##", "", comment_color, true)
  
  result.highlighter.setNumberColor(number_color)
  result.highlighter.setFunctionColor(function_color)
  result.highlighter.setSymbolColor(symbol_color)
  
  print("[UI] Created dark theme Nim syntax highlighter")

proc create_light_theme_highlighter*(): NimHighlighter =
  ## Create a light theme variant of the Nim highlighter
  result = NimHighlighter()
  result.highlighter = instantiate(CodeHighlighter)
  
  # Light theme color scheme (darker versions of ir_black colors for light backgrounds)
  let
    keyword_control_color = col"4080C0".to_godot_color    # Darker blue (based on Keyword)
    keyword_decl_color = col"8A8050".to_godot_color       # Darker yellow-green (based on Storage)
    keyword_bool_color = col"808080".to_godot_color       # Darker gray (based on Operator)
    string_color = col"40A040".to_godot_color             # Darker green (based on Text)
    comment_color = col"404040".to_godot_color            # Darker gray (based on Comment)
    number_color = col"8040A0".to_godot_color             # Darker purple (based on Number)
    function_color = col"C08040".to_godot_color           # Darker orange (based on Entity)
    symbol_color = col"6060A0".to_godot_color             # Darker purple (based on Variable)
  
  # Same keywords as other themes
  let control_keywords = [
    "block", "break", "case", "continue", "do", "elif", "else", "end", 
    "except", "finally", "for", "if", "raise", "return", "try", "when", 
    "while", "yield"
  ]
  for keyword in control_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_control_color)
  
  let decl_keywords = [
    "addr", "as", "asm", "atomic", "bind", "cast", "const", "converter", 
    "concept", "defer", "discard", "distinct", "div", "enum", "export", 
    "from", "import", "include", "let", "mod", "mixin", "object", "of", 
    "ptr", "ref", "shl", "shr", "static", "type", "using", "var", "tuple", 
    "iterator", "macro", "func", "method", "proc", "template"
  ]
  for keyword in decl_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_decl_color)
  
  let bool_keywords = [
    "and", "in", "is", "isnot", "not", "notin", "or", "xor"
  ]
  for keyword in bool_keywords:
    result.highlighter.addKeywordColor(keyword.gdstring, keyword_bool_color)
  
  # String and comment regions
  result.highlighter.addColorRegion(gdstring"\"", "\"", string_color, false)
  result.highlighter.addColorRegion(gdstring"'", "'", string_color, true)
  result.highlighter.addColorRegion(gdstring"\"\"\"", "\"\"\"", string_color, false)
  result.highlighter.addColorRegion(gdstring"r\"", "\"", string_color, false)
  
  result.highlighter.addColorRegion(gdstring"#", "", comment_color, true)
  result.highlighter.addColorRegion(gdstring"#[", "]#", comment_color, false)
  result.highlighter.addColorRegion(gdstring"##", "", comment_color, true)
  
  result.highlighter.setNumberColor(number_color)
  result.highlighter.setFunctionColor(function_color)
  result.highlighter.setSymbolColor(symbol_color)
  
  print("[UI] Created light theme Nim syntax highlighter")