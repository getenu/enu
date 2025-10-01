import std/[tables, strutils, re, sequtils]
import gdext
import
  gdext/classes/[
    gdrichtextlabel, gdscrollcontainer, gdtextedit, gdtheme, gdfont,
    gdstyleboxflat, gdnode, gdvboxcontainer, gdcontrol,
  ]
import core, gdcore, types, models/colors
# TODO: Add markdown package when available
# import pkg/markdown

export gdscrollcontainer

type MarkdownLabel* {.gdsync.} =
  ptr object of ScrollContainer
    markdown*: string
    old_markdown: string
    default_font*: gdref Font
    italic_font*: gdref Font
    bold_font*: gdref Font
    bold_italic_font*: gdref Font
    header_font*: gdref Font
    mono_font*: gdref Font
    size*: int
    current_label: RichTextLabel
    container: VBoxContainer
    og_text_edit: TextEdit
    og_label*: RichTextLabel
    needs_margin: bool
    resized: bool
    local_default_font: gdref Font
    local_italic_font: gdref Font
    local_bold_font: gdref Font
    local_bold_italic_font: gdref Font
    local_header_font: gdref Font
    local_mono_font: gdref Font
    zid: ZID

proc add_label(self: MarkdownLabel) =
  self.current_label = self.og_label.duplicate().as(RichTextLabel)
  self.container.add_child(self.current_label)
  self.current_label.set_visible(true)
  if not state.nodes.game.is_nil:
    if not self.current_label.has_signal("meta_clicked"):
      self.current_label.add_user_signal("meta_clicked")
    let callable_obj =
      callable(state.nodes.game, new_string_name("_on_meta_clicked"))
    discard
      self.current_label.connect(new_string_name("meta_clicked"), callable_obj)

proc set_font_sizes(self: MarkdownLabel) =
  let size =
    if self.size > 0:
      self.size
    else:
      int(float(state.config.font_size) * state.config.screen_scale)

  # TODO: Implement font size setting for Godot 4 Font system
  # In Godot 4, fonts work differently - need to use FontFile or SystemFont
  # self.local_default_font[].set_size(size)
  # self.local_italic_font[].set_size(size)
  # etc.

  let child_count = self.container.get_child_count()
  for i in 0 ..< child_count:
    let child = self.container.get_child(i)

    if child.is_class("TextEdit"):
      let child_edit = child.as(TextEdit)
      let line_count = child_edit.get_line_count()
      let line_height = 20 # TODO: Get actual line height from theme
      let height = line_count * line_height + 24
      let text_lines = ($child_edit.get_text()).split('\n')

      var size = child_edit.get_custom_minimum_size()
      size.y = float(height)
      if text_lines.len > 0:
        # TODO: Calculate proper width based on longest line
        var max_len = 0
        for line in text_lines:
          max_len = max(max_len, line.len)
        # Approximate character width calculation
        size.x = float(max_len * 8) # 8px per character estimate
      child_edit.set_custom_minimum_size(size)
      child_edit.set_size(size)
    elif child.is_class("RichTextLabel"):
      # TODO: Handle RichTextLabel styling for Godot 4
      let child_label = child.as(RichTextLabel)
      if i > 0:
        # Add top margin
        child_label.add_theme_constant_override("margin_top", int32(size + 4))
      if i == child_count - 1:
        # TODO: Fix size flags for Godot 4
        # child_label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
        discard

proc add_text_edit(self: MarkdownLabel): TextEdit =
  result = self.og_text_edit.duplicate().as(TextEdit)
  # TODO: Implement syntax highlighting for TextEdit in Godot 4
  if not ?self.current_label:
    # Don't add borders if the only thing in our doc is code
    # TODO: Fix StyleBox theming for Godot 4
    # let stylebox = result.get_theme_stylebox("normal", "TextEdit")
    # if ?stylebox:
    #   let new_style = stylebox[].duplicate().as(gdref StyleBoxFlat)
    #   new_style[].set_border_color(new_style[].get_bg_color())
    #   result.add_theme_stylebox_override("normal", new_style)
    #   result.add_theme_stylebox_override("read_only", new_style)
    discard

# Forward declaration
proc update*(self: MarkdownLabel)

method ready*(self: MarkdownLabel) {.gdsync.} =
  print("[UI] MarkdownLabel ready - initializing Godot 4 markdown renderer")

  if not self.has_signal("resized"):
    self.add_user_signal("resized")
  let callable_obj = callable(self, new_string_name("_on_resized"))
  discard self.connect(new_string_name("resized"), callable_obj)
  self.container = self.get_node("VBoxContainer").as(VBoxContainer)
  self.og_text_edit = self.container.get_node("TextEdit").as(TextEdit)
  self.og_label = self.container.get_node("RichTextLabel").as(RichTextLabel)

  self.container.remove_child(self.og_text_edit)
  self.container.remove_child(self.og_label)

  # Clone fonts so they can be resized without impacting other labels
  # TODO: Implement proper font cloning for Godot 4
  # self.local_default_font = self.default_font[].duplicate().as(Font)
  # etc.

  # TODO: Set fonts on controls
  # self.og_text_edit[].add_theme_font_override("font", self.local_mono_font)
  # self.og_label[].add_theme_font_override("normal_font", self.local_default_font)

  # Set up config watching
  self.zid = state.config_value.changes:
    if added:
      self.set_font_sizes()

  self.update()
  print("[UI] MarkdownLabel initialized")

# TODO: Fix signal connection for resized in Godot 4
# method on_resized*(self: MarkdownLabel) {.gdsync.} =
#   if not self.resized:
#     self.set_font_sizes()
#     self.resized = true

proc render_plain_text(self: MarkdownLabel, text: string) =
  # Fallback renderer when markdown package isn't available
  if not ?self.current_label:
    self.add_label()

  let label = self.current_label
  label.clear()

  # Split text into paragraphs and code blocks
  let lines = text.split('\n')
  var i = 0
  while i < lines.len:
    let line = lines[i].strip()

    if line.startsWith("```"):
      # Code block
      var code_lines: seq[string]
      inc i
      while i < lines.len and not lines[i].strip().startsWith("```"):
        code_lines.add(lines[i])
        inc i

      if code_lines.len > 0:
        let editor = self.add_text_edit()
        editor.set_text(code_lines.join("\n"))
        editor.set_visible(true)
        self.container.add_child(editor)
        self.add_label()
      inc i
    elif line.startsWith("#"):
      # Header
      let header_text = line.replace(re"^#+\s*", "")
      # TODO: Implement header styling when fonts are available
      # label.push_font(self.local_header_font, 1)
      # label.push_color(ir_black[Keyword])
      self.current_label.append_text("[b]" & header_text & "[/b]")
      # label.pop_all()
      self.current_label.newline()
      inc i
    elif line.len > 0:
      # Regular text
      self.current_label.append_text(line)
      self.current_label.newline()
      inc i
    else:
      # Empty line
      self.current_label.newline()
      inc i

# TODO: Implement full markdown rendering when markdown package is available
# proc render_markdown(self: MarkdownLabel, token: Token, list_position = 0, inline_blocks = false) =
#   # Full markdown implementation will go here

proc update*(self: MarkdownLabel) =
  self.resized = false
  if self.markdown != self.old_markdown:
    # Clear existing content
    let child_count = self.container.get_child_count()
    for i in 0 ..< child_count:
      let child = self.container.get_child(0) # Always remove first child
      self.container.remove_child(child)
      child.queue_free()

    self.current_label = nil
    self.old_markdown = self.markdown

    # TODO: Use full markdown parser when available
    # For now, use plain text renderer
    self.render_plain_text(self.markdown)
    self.set_font_sizes()

# TODO: Fix notification method for Godot 4
# method notification*(self: MarkdownLabel, what: int32) {.gdsync.} =
#   if what == Node_NotificationPredelete:
#     if self.zid != ZID(0):
#       state.config_value.untrack(self.zid)
