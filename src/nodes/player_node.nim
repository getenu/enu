import std/[math, sugar, times, monotimes, options]
import gdext
import
  gdext/classes/[
    gdcharacterbody3d, gdnode3d, gdcamera3d, gdraycast3d, gdcollisionshape3d,
    gdinput, gdinputevent, gdinputeventmousemotion, gdinputeventscreentouch,
    gdinputeventscreendrag, gdinputeventjoypadbutton, gdinputeventjoypadmotion,
    gdinputeventpangesture, gdpackedscene, gdresourceloader, gdviewport,
    gdkinematiccollision3d, gdos, gdengine, gdcontrol, gdscenetree,
  ]
import core, gdcore, models
import aim_target

const
  angle_x_min = -PI / 2.25
  angle_x_max = PI / 2.25
  jump_impulse = 10.0
  fly_toggle = 0.3.seconds
  float_time = 0.3.seconds
  alt_speed_toggle = 0.3.seconds
  input_command_timeout = 0.25
  first_delete = 0.5.seconds
  next_deletes = 0.1.seconds

var
  gamepad_sensitivity: Vector2
  mouse_sensitivity: Vector2

let nil_time = MonoTime.none

type PlayerNode* {.gdsync.} =
  ptr object of CharacterBody3D
    model*: Player
    input_relative*: Vector2

    # Child nodes
    camera_rig*: Node3D
    camera*: Camera3D
    aim_ray*: RayCast3D
    world_ray*: RayCast3D
    down_ray*: RayCast3D
    collision_shape*: CollisionShape3D
    aim_target*: AimTarget
    gui_node*: Control

    # Player state
    alt_speed*: bool
    skip_next_mouse_move*: bool
    jump_down*: bool
    position_start*: Vector3

    # Timing state
    jump_time*: Option[MonoTime]
    run_time*: Option[MonoTime]
    crouch_time*: Option[MonoTime]
    command_timer*: float
    pan_delta*: float

    # Touch/mobile state
    touch_position*: Option[Vector2]
    delete_timer*: MonoTime
    deleting*: bool

    # Performance optimization
    boosted*: bool
    skip_release*: bool

    # Model watching ZIDs
    velocity_zid*: ZID
    rotation_zid*: ZID

proc flying*(self: PlayerNode): bool =
  Flying in state.local_flags

proc `flying=`*(self: PlayerNode, value: bool) =
  state.set_flag(Flying, value)

proc handle_collisions(
    self: PlayerNode, collisions: seq[gdref KinematicCollision3D]
) =
  # TODO: Implement collision handling system when model system is ready
  # For now, just ensure we don't crash
  if not self.model.is_nil:
    self.model.colliders.clear()

method ready*(self: PlayerNode) {.gdsync.} =
  self.camera_rig = self.get_node("CameraRig").as(Node3D)
  self.collision_shape = self.get_node("CollisionShape").as(CollisionShape3D)
  self.camera = self.camera_rig.get_node("Camera").as(Camera3D)
  self.aim_ray = self.camera_rig.get_node("Camera/AimRay").as(RayCast3D)
  self.world_ray =
    if not state.nodes.game.is_nil:
      state.nodes.game.get_node("WorldRay").as(RayCast3D)
    else:
      nil
  self.down_ray = self.find_child("DownRay").as(RayCast3D)
  self.aim_target = self.camera_rig.get_node("AimTarget").as(AimTarget)
  self.gui_node = state.nodes.game.find_child("GUI").as(Control)
  assert not self.gui_node.is_nil, "GUI node not found"

  self.position_start = self.camera_rig.position
  self.delete_timer = MonoTime.high
  state.nodes.player = self

  let x = state.config.mouse_sensitivity / 1000.0
  mouse_sensitivity = vector2(x, -x)
  gamepad_sensitivity =
    vector2(state.config.gamepad_sensitivity, state.config.gamepad_sensitivity)
  if state.config.invert_gamepad_y_axis:
    gamepad_sensitivity.y = -gamepad_sensitivity.y

  state.local_flags.changes:
    if MouseCaptured.removed:
      self.skip_next_mouse_move = true
    elif Flying.added or Flying.removed:
      # GD4: Update collision layers for flying mode
      let collision_enabled = Flying notin state.local_flags
      for i in [0, 1, 2]:
        self.set_collision_mask_value(int32(i + 1), collision_enabled)
  state.global_flags.changes:
    if LoadingLevel.added and not self.model.is_nil:
      self.model.colliders.clear()

  self.model.transform_value.changes:
    if added:
      self.global_transform = change.item

  self.camera_rig.rotation = vector3(0, deg_to_rad(self.model.rotation), 0)

  self.rotation_zid = self.model.rotation_value.changes:
    if added or touched:
      self.camera_rig.rotation = vector3(0, deg_to_rad(change.item), 0)

  self.velocity_zid = self.model.velocity_value.changes:
    if added:
      self.velocity = change.item

# Forward declarations of helper procs
proc get_input_direction(self: PlayerNode): Vector3
proc get_look_direction(self: PlayerNode): Vector2
proc update_rotation(self: PlayerNode, offset: Vector2)
proc calculate_velocity(
  self: PlayerNode, move_direction: Vector3, delta: float
): Vector3

proc update_raycast*(self: PlayerNode)
proc has_active_input(self: PlayerNode, device: int32): bool

method physics_process*(self: PlayerNode, delta: float64) {.gdsync.} =
  # Handle command mode timeout
  if CommandMode in state.local_flags and self.command_timer > 0:
    self.command_timer -= delta
    if self.command_timer <= 0:
      state.pop_flag CommandMode

  let process_input = ViewportFocused in state.local_flags

  let input_direction =
    if process_input:
      self.get_input_direction
    else:
      vector3()

  const forward_rotation = deg_to_rad(-90.0)
  let basis = self.camera_rig.global_transform.basis
  let right = basis.get_column_x * input_direction.x
  let up = core.UP * input_direction.y
  let forward = Vector3(basis.get_column_x * input_direction.z).rotated(
      core.UP, forward_rotation
    )
  var move_direction = forward + right

  if move_direction.length() > 1.0:
    move_direction = move_direction.normalized()

  move_direction.y = 0
  move_direction += up

  var velocity = self.calculate_velocity(move_direction, delta)
  self.model.input_direction = input_direction

  self.velocity = velocity
  discard self.move_and_slide()

  self.model.transform = self.global_transform

  if process_input:
    let collisions = collect:
      for i in 0 ..< self.get_slide_collision_count():
        self.get_slide_collision(i)
    handle_collisions(self, collisions)

    if self.is_on_floor():
      self.boosted = false

    if move_direction.length() > 0.5:
      self.down_ray.position = move_direction * 0.3 + vector3(0, 1, 0)
      if self.down_ray.is_colliding():
        let length = 1.85
        let diff =
          length - (
            self.down_ray.global_position - self.down_ray.get_collision_point()
          ).y
        if diff > 0 and (self.is_on_floor() or not self.boosted):
          let boost = 16.1 * pow(diff, 1.0 / 3.0) # cbrt equivalent
          if boost > self.velocity.y:
            self.boosted = true
            var vel = self.velocity
            vel.y = boost
            self.velocity = vel

    # Reset position if fallen through world
    if self.global_position.y < -10:
      self.global_position = vector3(0, 100, 0)

method process*(self: PlayerNode, delta: float64) {.gdsync.} =
  self.model.velocity_value.pause(self.velocity_zid):
    self.model.velocity = self.velocity

  var transform = self.camera_rig.global_transform
  transform.origin = self.global_transform.origin + self.position_start
  let look_direction = self.get_look_direction()

  if self.input_relative.length() > 0:
    self.update_rotation(self.input_relative * mouse_sensitivity)
    self.input_relative = vector2()
  elif look_direction.length() > 0:
    self.update_rotation(look_direction * gamepad_sensitivity * delta)

  # Wrap rotation
  var r = self.camera_rig.rotation
  r.y = wrap(r.y, -PI, PI)
  self.camera_rig.rotation = r

  self.model.rotation_value.pause(self.rotation_zid):
    self.model.rotation = rad_to_deg(r.y)

  if LoadingLevel notin state.global_flags:
    self.update_raycast()

method unhandled_input*(self: PlayerNode, event: gdref InputEvent) {.gdsync.} =
  let time = get_mono_time()
  let event = event[]

  if event.is_class("InputEventMouseMotion") and
      MouseCaptured in state.local_flags and
      TouchControls notin state.local_flags:
    if not self.skip_next_mouse_move:
      let mouse_event = event.as(InputEventMouseMotion)
      self.input_relative += mouse_event.get_relative()
    else:
      self.skip_next_mouse_move = false

  if event.is_class("InputEventScreenTouch") and
      TouchControls in state.local_flags:
    let event = event.as(InputEventScreenTouch)
    let index = byte(event.get_index())
    if index notin state.ignored_touches:
      if event.get_index() == 0:
        if event.is_pressed():
          self.touch_position = some(event.get_position())
          self.delete_timer = get_mono_time() + first_delete
        else:
          if ?self.touch_position and
              self.touch_position.get() == event.get_position():
            self.update_raycast()
            state.push_flag PrimaryDown
            state.pop_flag PrimaryDown
            self.deleting = false
            self.delete_timer = MonoTime.high
            self.touch_position = none(Vector2)
    elif index in state.ignored_touches and not event.is_pressed():
      state.ignored_touches.excl(index)
      self.get_viewport().set_input_as_handled()
  elif event.is_class("InputEventScreenDrag") and
      TouchControls in state.local_flags:
    let event = event.as(InputEventScreenDrag)
    let index = byte(event.get_index())
    if index notin state.ignored_touches:
      if event.get_index() == 0:
        self.touch_position = none(Vector2)
      self.input_relative += event.get_relative()
      if not self.deleting:
        self.delete_timer = MonoTime.high

  if EditorVisible in state.local_flags and not self.skip_release and (
    event.is_class("InputEventJoypadButton") or
    event.is_class("InputEventJoypadMotion")
  ):
    let active_input = self.has_active_input(event.get_device())
    if CommandMode in state.local_flags and not active_input:
      self.command_timer = input_command_timeout
    elif CommandMode in state.local_flags and active_input:
      self.command_timer = 0.0
    elif active_input:
      self.command_timer = 0.0
      state.push_flag CommandMode

  if event.is_action_pressed("jump"):
    self.jump_down = true
    let toggle = ?self.jump_time and time < self.jump_time.get() + fly_toggle

    if toggle and Playing notin state.local_flags:
      self.jump_time = nil_time
      self.`flying=`(not self.flying())
    elif self.is_on_floor():
      var vel = self.velocity
      vel.y = jump_impulse
      self.velocity = vel
      self.jump_time = some(time)
    else:
      self.jump_time = some(time)
  elif event.is_action_released("jump"):
    self.jump_down = false

  if event.is_action_pressed("crouch") and self.flying():
    self.get_viewport().set_input_as_handled()

    if ?self.crouch_time and time < self.crouch_time.get() + fly_toggle:
      self.crouch_time = nil_time
      self.`flying=`(false)
    else:
      self.crouch_time = some(time)

  if event.is_action_pressed("run"):
    self.get_viewport().set_input_as_handled()
    let toggle =
      ?self.run_time and time < self.run_time.get() + alt_speed_toggle

    if toggle:
      self.run_time = nil_time
      if self.flying():
        state.toggle_flag(AltFlySpeed)
      else:
        state.toggle_flag(AltWalkSpeed)
    else:
      self.run_time = some(time)
    self.alt_speed = true
  elif event.is_action_released("run"):
    self.get_viewport().set_input_as_handled()
    self.alt_speed = false

  if event.is_class("InputEventPanGesture") and
      state.current_tool_value.value notin {CodeMode, PlaceBot}:
    let pan = event.as(InputEventPanGesture)
    self.pan_delta += pan.get_delta().y
    if self.pan_delta > 2:
      self.pan_delta = 0
      state.update_action_index(1)
    elif self.pan_delta < -2:
      self.pan_delta = 0
      state.update_action_index(-1)

  if event.is_action_pressed("fire"):
    if EditorVisible in state.local_flags:
      self.skip_release = true
    state.push_flag PrimaryDown
  elif event.is_action_released("fire"):
    self.skip_release = false
    state.pop_flag PrimaryDown

  if event.is_action_pressed("remove"):
    state.push_flag SecondaryDown
  elif event.is_action_released("remove"):
    state.pop_flag SecondaryDown

proc calculate_velocity(
    self: PlayerNode, move_direction: Vector3, delta: float
): Vector3 =
  let speed =
    if not self.flying() and
        not (self.alt_speed xor AltWalkSpeed in state.local_flags):
      float(state.config.walk_speed)
    elif not self.flying() and
      (self.alt_speed xor AltWalkSpeed in state.local_flags):
      float(state.config.alt_walk_speed)
    elif self.flying() and
      not (self.alt_speed xor AltFlySpeed in state.local_flags):
      float(state.config.fly_speed)
    else:
      float(state.config.alt_fly_speed)

  result = move_direction * delta * speed

  if not self.flying():
    let float_time =
      if self.alt_speed:
        float_time + float_time
      else:
        float_time
    let floating =
      self.jump_down and ?self.jump_time and
      self.jump_time.get() + float_time > get_mono_time()

    let gravity =
      if floating:
        state.gravity / 4
      else:
        state.gravity
    result.y = self.velocity.y + gravity * delta

proc get_input_direction(self: PlayerNode): Vector3 =
  if EditorVisible notin state.local_flags or CommandMode in state.local_flags or
      TouchControls in state.local_flags:
    result = vector3(
      Input.get_action_strength("move_right") -
        Input.get_action_strength("move_left"),
      Input.get_action_strength("jump") - Input.get_action_strength("crouch"),
      Input.get_action_strength("move_back") -
        Input.get_action_strength("move_front"),
    )

proc get_look_direction(self: PlayerNode): Vector2 =
  if EditorVisible notin state.local_flags or CommandMode in state.local_flags or
      TouchControls in state.local_flags:
    result = vector2(
      Input.get_action_strength("look_right") -
        Input.get_action_strength("look_left"),
      Input.get_action_strength("look_up") -
        Input.get_action_strength("look_down"),
    )

proc update_rotation(self: PlayerNode, offset: Vector2) =
  var r = self.camera_rig.rotation
  r.y -= offset.x
  r.x += offset.y
  r.x = clamp(r.x, angle_x_min, angle_x_max)
  r.z = 0
  self.camera_rig.rotation = r

proc has_active_input(self: PlayerNode, device: int32): bool =
  for axis in 0 .. 9:
    if axis != 6 and axis != 7 and
        Input.get_joy_axis(device, JoyAxis(axis)).abs() >= 0.2:
      return true
  for button in 0 .. 22:
    if Input.is_joy_button_pressed(device, JoyButton(button)):
      return true

proc is_mouse_over_ui(self: PlayerNode): bool =
  ## Check if mouse is over any visible UI control that should block raycast
  let mouse_pos = self.get_viewport().get_mouse_position()

  # Use cached GUI node for faster lookup
  let all_controls = self.gui_node.find_children("*", "Control", true, false)

  for i in 0..<all_controls.size():
    let control_node = all_controls.get(i.int32)
    if ?control_node:
      let control = control_node.as(Control)
      if ?control:
        # Check if control is truly visible and interactive
        if control.is_visible_in_tree():
          let global_rect = control.get_global_rect()

          # Check if mouse is over this control
          if global_rect.has_point(mouse_pos):
            let mouse_filter = control.get_mouse_filter()

            # Only STOP filter should block the raycast
            # PASS and IGNORE should not block
            if mouse_filter == Control_MouseFilter.mouseFilterStop:
              return true

  return false

proc update_raycast*(self: PlayerNode) =
  let ray_length =
    if state.current_tool_value.value == CodeMode: 200.0 else: 100.0

  if MouseCaptured notin state.local_flags:
    # Check if mouse is over UI - if so, skip raycast
    if self.is_mouse_over_ui():
      # Disable world ray when mouse is over UI
      if not self.world_ray.is_nil:
        self.world_ray.set_enabled(false)
      # Hide aim target
      if not self.aim_target.is_nil:
        self.aim_target.set_visible(false)
    else:
      # Mouse is free and not over UI - cast ray from camera through mouse position
      let mouse_pos = self.get_viewport().get_mouse_position()
      let cast_from = self.camera.project_ray_origin(mouse_pos)
      let cast_to =
        cast_from + self.camera.project_ray_normal(mouse_pos) * ray_length

      if not self.world_ray.is_nil:
        self.world_ray.target_position = cast_to
        self.world_ray.position = cast_from
        self.world_ray.set_enabled(true)

        # Update aim target with world ray (matches Godot 3)
        if not self.aim_target.is_nil:
          self.aim_target.update(self.world_ray)
  else:
    # Mouse is captured - cast ray from camera center
    self.aim_ray.target_position = vector3(0, 0, -ray_length)

    # Update aim target with aim ray (matches Godot 3)
    if not self.aim_target.is_nil:
      self.aim_target.update(self.aim_ray)

proc get_player*(): PlayerNode =
  PlayerNode(state.nodes.player)

proc init*(_: type PlayerNode): PlayerNode =
  let scene =
    cast[gdref PackedScene](ResourceLoader.load("res://components/Player.tscn"))
  result = PlayerNode(scene[].instantiate())
