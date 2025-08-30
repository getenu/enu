import gdext
import gdext/classes/[gdmargincontainer, gdcodeedit, gdinputevent, gdinputeventkey]
import core, gdutils, models/[states]

type Editor* {.gdsync.} = ptr object of MarginContainer
  code_edit*: CodeEdit
  
proc configure_highlighting*(self: Editor) =
  # Configure syntax highlighting for Nim
  let code_edit = self.code_edit
  # Enable basic code editing features
  code_edit.syntax_highlighter = nil  # Use default highlighting for now
  code_edit.line_folding = true
  code_edit.line_numbers = true
  code_edit.draw_tabs = true
  code_edit.draw_spaces = false
    
proc get_text*(self: Editor): string =
  return $self.code_edit.text
    
proc set_text*(self: Editor, text: string) =
  self.code_edit.text = text

method ready*(self: Editor) {.gdsync.} =
  print("[UI] Editor ready - using Godot 4 CodeEdit")
  
  # Find the CodeEdit node - this should always succeed if scene is properly set up
  self.code_edit = self.find("CodeEdit", CodeEdit)
  assert not self.code_edit.is_nil(), "CodeEdit node not found in Editor scene"
  
  # Configure the code editor
  self.configure_highlighting()
  
  # Connect signals for editor functionality  
  self.bind_signals(self.code_edit, "text_changed")
  self.bind_signals(self.code_edit, "caret_changed")
  
  print("[UI] Editor configured with CodeEdit")

method on_text_changed*(self: Editor) {.gdsync.} =
  # Handle text changes for auto-save, validation, etc.
  print("[UI] Editor text changed")
  # TODO: Connect to script compilation/validation system
  
method on_caret_changed*(self: Editor) {.gdsync.} =
  # Handle caret position changes for status display
  let line = self.code_edit.get_caret_line()
  let column = self.code_edit.get_caret_column()
  # TODO: Update status display with line:column info
  discard
