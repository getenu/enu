import pkg/[godot]
import
  godotapi/[
    margin_container, input_event, scene_tree, scene_tree_tween, method_tweener,
    tween, control,
  ]
import ui/markdown_label
import core, gdutils, models/[states, colors]

when defined(enu_pages):
  import godotapi/[scroll_container, texture_rect, image_texture, input_event_mouse_button,
    input_event_mouse_motion, global_constants]
  import nodes/sign_web

  const PANEL_KEY = "enu-right-panel" # matches web_pages

proc set_filter(self: Control, filter: int64) =
  self.mouse_filter = filter
  for child in self.get_children:
    let child = child.as_object(Node)
    if child of Control:
      set_filter(Control(child), filter)

proc md(self: Sign, md: string): string =
  if self.text_only:
    "```nim\n" & md & "\n```"
  else:
    md

gdobj RightPanel of MarginContainer:
  var
    label: MarkdownLabel
    zid: EID
    margin = 3.0
    center = 1.0
    page_scroll: ScrollContainer
      ## A sign's `more`, drawn as a page by the worker (-d:enu_pages).
    page_rect: TextureRect
    page_tex: ImageTexture
    page_bytes: PoolByteArray
    page_version: uint64

  proc show_page(show: bool) =
    ## Pages show a sign's `more`; the label still shows status messages.
    when defined(enu_pages):
      self.page_scroll.visible = show
      self.label.visible = not show
      if show:
        self.page_version = 0 # ask for the newest frame, whatever it is

  proc setup_page() =
    when defined(enu_pages):
      self.page_scroll = gdnew[ScrollContainer]()
      self.page_scroll.scroll_horizontal_enabled = false
      self.page_scroll.visible = false
      self.page_scroll.mouse_filter = MOUSE_FILTER_PASS
      self.page_rect = gdnew[TextureRect]()
      self.page_rect.mouse_filter = MOUSE_FILTER_PASS
      self.page_tex = gdnew[ImageTexture]()
      self.page_rect.texture = self.page_tex
      self.page_scroll.add_child(self.page_rect)
      self.add_child(self.page_scroll)
      # Under the overlay, so the close button stays on top.
      self.move_child(self.page_scroll, self.label.get_index + 1)
      self.bind_signal(self.page_rect, ("gui_input", "page_input"))
      state.nodes.game.bind_signal(self.page_rect, "gui_input", self.name)

  method on_page_input(event: InputEvent) =
    when defined(enu_pages):
      let size = self.page_rect.rect_size
      if size.x <= 0 or size.y <= 0:
        return
      var kind = -1
      var pos: Vector2
      if event of InputEventMouseMotion:
        kind = POINTER_MOVE.int
        pos = InputEventMouseMotion(event).position
      elif event of InputEventMouseButton:
        let button = InputEventMouseButton(event)
        if button.button_index == BUTTON_LEFT:
          kind = if button.pressed: POINTER_DOWN.int else: POINTER_UP.int
          pos = button.position
      if kind >= 0:
        discard ew_post_pointer(
          PANEL_KEY, kind.uint32, pos.x / size.x, pos.y / size.y
        )

  method process*(delta: float) =
    when defined(enu_pages):
      if not self.page_scroll.visible:
        return
      # Drawn 1:1: the panel's width in physical px, with the screen scale
      # and font size setting as the page's scale (its CSS is 16px based).
      var width = self.page_scroll.rect_size.x
      let bar = self.page_scroll.get_v_scrollbar
      if bar.visible:
        width -= bar.rect_size.x
      let scale =
        state.config.screen_scale * state.config.font_size.float / 16.0
      ew_request_size(PANEL_KEY, max(1, width.int).uint32, scale)
      var version: uint64
      let frame = ew_take_frame(PANEL_KEY, self.page_version, version.addr)
      if frame.is_nil:
        return
      self.page_version = version
      let w = ew_frame_width(frame).int
      let h = ew_frame_height(frame).int
      upload(
        cast[ptr UncheckedArray[uint8]](ew_frame_pixels(frame)),
        w,
        h,
        self.page_tex,
        self.page_bytes,
      )
      ew_frame_free(frame)
      self.page_rect.rect_min_size = vec2(w.float, h.float)

  method offset_x*(offset: float) {.gdexport.} =
    let width = self.rect_size.x
    self.rect_position =
      vec2(width * offset + self.margin, self.rect_position.y)

  method ready*() =
    self.label = self.find_node("MarkdownLabel") as MarkdownLabel

    state.nodes.game.bind_signal(self.label, "gui_input", self.name)
    self.bind_signal(find("Close", Control), ("pressed", "close"))
    self.setup_page()

    state.status_message_value.changes:
      if added:
        if ?change.item:
          state.push_flags DOCS_VISIBLE, DOCS_FOCUSED
          self.show_page(false)
          self.label.markdown = change.item
          self.label.update
        else:
          state.pop_flags DOCS_FOCUSED, DOCS_VISIBLE
          self.label.markdown = ""
          self.label.update

    state.player.open_sign_value.changes:
      if added and change.item != nil:
        state.push_flags DOCS_VISIBLE, DOCS_FOCUSED
        var sign = change.item
        self.show_page(defined(enu_pages))
        self.label.markdown = md(sign, sign.more)
        self.label.update
        self.zid = sign.more_value.changes:
          if added:
            self.label.markdown = md(sign, change.item)
            self.label.update
      if removed and change.item != nil:
        if change.item.more_value.valid:
          change.item.more_value.untrack(self.zid)
      if removed and not ?state.player.open_sign:
        state.pop_flags DOCS_FOCUSED, DOCS_VISIBLE

    state.local_flags.changes:
      if FULL_WIDTH_PANELS.added:
        self.center = 0.0
        self.anchor_left = 0.0
        self.margin_left = 0.0
        self.margin_right = 1.0
      elif FULL_WIDTH_PANELS.removed:
        self.center = 1.0
        self.anchor_left = 0.5
        self.margin_left = 2.0

      if DOCS_VISIBLE.added:
        var tween = self.get_tree.create_tween()
        self.visible = true
        discard tween
          .tween_method(
            self, "_offset_x", 2.0.to_variant, self.center.to_variant,
            animation_duration,
          )
          .set_trans(TRANS_EXPO)
          .set_ease(EASE_IN_OUT)
      elif DOCS_VISIBLE.removed:
        var tween = self.get_tree.create_tween()
        discard tween
          .tween_method(
            self, "_offset_x", self.center.to_variant, 2.0.to_variant,
            animation_duration,
          )
          .set_trans(TRANS_EXPO)
          .set_ease(EASE_IN_OUT)
        discard
          tween.tween_callback(self, "set_visible", new_array(false.to_variant))
      elif DOCS_FOCUSED.added:
        self.raisee()
        find("Close", Control).visible = true
      elif DOCS_FOCUSED.removed:
        self.label.release_focus
        if FULL_WIDTH_PANELS in state.local_flags and
            VIEWPORT_FOCUSED notin state.local_flags:
          find("Close", Control).visible = false
      elif COMMAND_MODE.added:
        self.ghost()
      elif COMMAND_MODE.removed:
        self.unghost()
        find("Overlay", Control).set_mouse_filter_recursive(MOUSE_FILTER_IGNORE)
        find("Close", Control).mouse_filter = MOUSE_FILTER_STOP

  method on_close() =
    state.player.open_sign = nil

  method unhandled_input*(event: InputEvent) =
    if DOCS_FOCUSED in state.local_flags and event.is_action_pressed("ui_cancel"):
      if not (event of InputEventJoypadButton) or
          COMMAND_MODE notin state.local_flags:
        state.player.open_sign = nil
        self.get_tree().set_input_as_handled()
