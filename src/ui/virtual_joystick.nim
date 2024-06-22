# adapted from https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot/blob/v3/joystick/virtual_joystick.gd
import pkg/[godot, core/transform2d, core/vector2]

import
  godotapi/[
    control, texture_rect, gd_os, input_event_screen_touch,
    input_event_screen_drag, scene_tree, input
  ]
import core, gdutils, models/colors

type
  JoystickMode* = enum
    FIXED
    DYNAMIC

  VisibilityMode* = enum
    ALWAYS
    TOUCHSCREEN_ONLY

gdobj VirtualJoystick of Control:
  var
    pressed_color {.gdexport.} = godot.Color(ir_black[number])
    deadzone_size {.gdexport, hint: Range, hint_str = "0,200,1".} = 10.0
    clampzone_size {.gdexport, hint: Range, hint_str = "0,500,1".} = 75.0
    joystick_mode {.gdexport.} = FIXED
    visibility_mode {.gdexport.} = ALWAYS
    use_input_actions {.gdexport.} = true
    action_left {.gdexport.} = "ui_left"
    action_right {.gdexport.} = "ui_right"
    action_up {.gdexport.} = "ui_up"
    action_down {.gdexport.} = "ui_down"
    pressed* = false
    output: Vector2
    touch_index = -1
    base, tip: Control
    base_radius, base_default_position, tip_default_position: Vector2
    default_color: godot.Color

  method ready*() =
    self.base = find("Base", TextureRect)
    self.tip = find("Tip", TextureRect)
    self.base_radius =
      self.base.rect_size * self.base.get_global_transform_with_canvas().scale() /
      2.0
    self.base_default_position = self.base.rect_position
    self.tip_default_position = self.tip.rect_position
    self.default_color = self.tip.modulate

    if not has_touchscreen_ui_hint() and self.visibility_mode == TOUCHSCREEN_ONLY:
      self.hide()

  method input(event: InputEvent) =
    if event of InputEventScreenTouch:
      let event = event as InputEventScreenTouch
      if event.pressed:
        if self.is_point_inside_joystick_area(event.position) and
            self.touch_index == -1:
          if self.joystick_mode == DYNAMIC or (
            self.joystick_mode == FIXED and
            self.is_point_inside_base(event.position)
          ):
            if self.joystick_mode == DYNAMIC:
              self.move_base(event.position)
            self.touch_index = event.index
            self.tip.modulate = self.pressed_color
            self.update_joystick(event.position)
            self.get_tree().set_input_as_handled()
      elif event.index == self.touch_index:
        self.reset()
        self.get_tree().set_input_as_handled()
    elif event of InputEventScreenDrag:
      let event = event as InputEventScreenDrag
      if event.index == self.touch_index:
        self.update_joystick(event.position)
        self.get_tree().set_input_as_handled()

  proc move_base(new_position: Vector2) =
    self.base.rect_global_position =
      new_position -
      self.base.rect_pivot_offset * self.get_global_transform_with_canvas().scale

  proc move_tip(new_position: Vector2) =
    self.tip.rect_global_position =
      new_position -
      self.tip.rect_pivot_offset *
      self.base.get_global_transform_with_canvas().scale

  proc is_point_inside_joystick_area(point: Vector2): bool =
    point.within(self.rect_global_position, self.rect_size)

  proc is_point_inside_base(point: Vector2): bool =
    var center = self.base.rect_global_position + self.base_radius
    var vector = point - center
    result = vector.length_squared() <= self.base_radius.x * self.base_radius.x

  proc update_joystick(touch_position: Vector2) =
    self.pressed = true
    var center: Vector2 = self.base.rect_global_position + self.base_radius
    var vector: Vector2 = touch_position - center
    vector = vector.limit_length(self.clampzone_size)

    self.move_tip(center + vector)

    if vector.length_squared() > self.deadzone_size * self.deadzone_size:
      self.pressed = true
      self.output =
        (vector - (vector.normalized() * self.deadzone_size)) /
        (self.clampzone_size - self.deadzone_size)
    else:
      self.pressed = false
      self.output = Vector2.default

    if self.use_input_actions:
      self.update_input_actions()

  proc update_input_actions() =
    if self.output.x < 0:
      action_press(self.action_left, -self.output.x)
    elif is_action_pressed(self.action_left):
      action_release(self.action_left)
    if self.output.x > 0:
      action_press(self.action_right, self.output.x)
    elif is_action_pressed(self.action_right):
      action_release(self.action_right)
    if self.output.y < 0:
      action_press(self.action_up, -self.output.y)
    elif is_action_pressed(self.action_up):
      action_release(self.action_up)
    if self.output.y > 0:
      action_press(self.action_down, self.output.y)
    elif is_action_pressed(self.action_down):
      action_release(self.action_down)

  proc reset() =
    self.pressed = false
    self.output = Vector2.default
    self.touch_index = -1
    self.tip.modulate = self.default_color
    self.base.rect_position = self.base_default_position
    self.tip.rect_position = self.tip_default_position
    if self.use_input_actions:
      if is_action_pressed(self.action_left) or
          is_action_just_pressed(self.action_left):
        action_release(self.action_left)
      if is_action_pressed(self.action_right) or
          is_action_just_pressed(self.action_right):
        action_release(self.action_right)
      if is_action_pressed(self.action_down) or
          is_action_just_pressed(self.action_down):
        action_release(self.action_down)
      if is_action_pressed(self.action_up) or
          is_action_just_pressed(self.action_up):
        action_release(self.action_up)
