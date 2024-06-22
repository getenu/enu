import std/[math, sugar]
from std/times import `+`
import pkg/godot except print
import
  godotapi/[
    kinematic_body, spatial, input, input_event, input_event_mouse_motion,
    input_event_screen_drag, input_event_screen_touch,
    input_event_joypad_motion, ray_cast, scene_tree, input_event_pan_gesture,
    viewport, camera, global_constants, collision_shape, kinematic_collision,
    packed_scene, resource_loader
  ]
import core, gdutils, nodes/helpers
import aim_target, models

const first_delete = 0.5.seconds
const next_deletes = 0.1.seconds

proc handle_collisions(
    self: Player, collisions: seq[KinematicCollision]
) {.inline, gcsafe.} =
  var colliders: HashSet[Model]
  for collision in collisions:
    let collider = collision.collider
    let normal = collision.normal
    let model = collider.model
    if not model.is_nil:
      if not (model in self.colliders or model in colliders) and model.id != "":
        model.on_collision(self, normal)
      colliders.incl model
  for model in self.colliders - colliders:
    model.off_collision(self)
  self.colliders = colliders

let
  angle_x_min = -PI / 2.25
  angle_x_max = PI / 2.25
  jump_impulse = 10.0
  fly_toggle = 0.3.seconds
  float_time = 0.3.seconds
  alt_speed_toggle = 0.3.seconds
  nil_time = MonoTime.none
  input_command_timeout = 0.25

var
  gamepad_sensitivity: Vector2
  mouse_sensitivity: Vector2

# :( Most of this needs to be moved into player model
gdobj PlayerNode of KinematicBody:
  var
    alt_speed, skip_release, skip_next_mouse_move, jump_down: bool

    aim_ray, world_ray, down_ray: RayCast
    jump_time, run_time: Option[MonoTime]

    position_start: Vector3
    input_relative* = vec2()
    camera_rig: Spatial
    camera: Camera
    aim_target: AimTarget
    velocity = vec3()
    pan_delta = 0.0
    index = 0
    collision_shape: CollisionShape
    command_timer = 0.0
    model*: Player
    velocity_zid, rotation_zid: ZID
    boosted = false
    # touch_time = MonoTime.low
    touch_position: Option[Vector2]
    delete_timer = MonoTime.high
    deleting = false

  proc flying(): bool =
    Flying in state.local_flags

  proc flying(value: bool) =
    state.set_flag Flying, value

  proc get_look_direction(): Vector2 =
    vec2(
      get_action_strength("look_right") - get_action_strength("look_left"),
      get_action_strength("look_up") - get_action_strength("look_down"),
    )

  proc update_rotation(offset: Vector2) =
    var r = self.camera_rig.rotation
    r.y -= offset.x
    r.x += offset.y
    r.x = clamp(r.x, angle_x_min, angle_x_max)
    r.z = 0
    self.camera_rig.rotation = r

  proc get_input_direction(): Vector3 =
    if CommandMode in state.local_flags or
        (
          {EditorFocused, ConsoleFocused, DocsFocused, SettingsFocused} -
          state.local_flags.value
        ).card == 4:
      result = vec3(
        get_action_strength("move_right") - get_action_strength("move_left"),
        get_action_strength("jump") - get_action_strength("crouch"),
        get_action_strength("move_back") - get_action_strength("move_front"),
      )

  proc calculate_velocity(
      velocity_current: Vector3,
      move_direction: Vector3,
      delta: float,
      flying, alt_speed: bool,
  ): Vector3 =
    let speed =
      if not flying and not (alt_speed xor AltWalkSpeed in state.local_flags):
        vec3(state.config.walk_speed)
      elif not flying and (alt_speed xor AltWalkSpeed in state.local_flags):
        vec3(state.config.alt_walk_speed)
      elif flying and not (alt_speed xor AltFlySpeed in state.local_flags):
        vec3(state.config.fly_speed)
      else:
        vec3(state.config.alt_fly_speed)

    result = move_direction * delta * speed

    if not flying:
      let float_time =
        if alt_speed:
          float_time + float_time
        else:
          float_time
      let floating =
        self.jump_down and ?self.jump_time and
        self.jump_time.get + float_time > get_mono_time()

      let gravity =
        if floating:
          state.gravity / 4
        else:
          state.gravity
      result.y = velocity_current.y + gravity * delta

  method ready*() =
    self.camera_rig = self.get_node("CameraRig") as Spatial
    self.collision_shape = self.get_node("CollisionShape") as CollisionShape
    self.camera = self.camera_rig.get_node("Camera") as Camera
    self.aim_ray = self.camera_rig.get_node("Camera/AimRay") as RayCast
    self.world_ray = state.nodes.game.get_node("WorldRay") as RayCast
    self.down_ray = self.find_node("DownRay") as RayCast
    self.aim_target = self.camera_rig.get_node("AimTarget") as AimTarget

    self.position_start = self.camera_rig.translation
    state.nodes.player = self

    let x = state.config.mouse_sensitivity / 1000.0
    mouse_sensitivity = vec2(x, -x)
    gamepad_sensitivity = vec2(state.config.gamepad_sensitivity)
    if state.config.invert_gamepad_y_axis:
      gamepad_sensitivity.y = -gamepad_sensitivity.y

    state.local_flags.watch:
      if MouseCaptured.removed:
        self.skip_next_mouse_move = true
      elif change.item == Flying:
        for i in [0, 1, 2]:
          let collision_enabled = Flying.removed
          self.set_collision_mask_bit(i, collision_enabled)

    state.global_flags.watch:
      if LoadingLevel.added:
        self.model.colliders.clear

    self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.camera_rig.rotation = vec3(0, deg_to_rad self.model.rotation, 0)
    self.rotation_zid = self.model.rotation_value.watch:
      if added or touched:
        self.camera_rig.rotation = vec3(0, deg_to_rad change.item, 0)

    self.velocity_zid = self.model.velocity_value.watch:
      if added:
        self.velocity = change.item

  method process*(delta: float) =
    self.model.velocity_value.pause self.velocity_zid:
      self.model.velocity = self.velocity
    if EditorVisible notin state.local_flags or CommandMode in state.local_flags:
      var transform = self.camera_rig.global_transform
      transform.origin = self.global_transform.origin + self.position_start

      var look_direction = self.get_look_direction()

      if self.input_relative.length() > 0:
        self.update_rotation(self.input_relative * mouse_sensitivity)
        self.input_relative = vec2()
      elif look_direction.length() > 0:
        self.update_rotation(look_direction * gamepad_sensitivity * delta)

      var r = self.camera_rig.rotation
      r.y = wrap(r.y, -PI, PI)
      self.camera_rig.rotation = r

      self.model.rotation_value.pause(self.rotation_zid):
        self.model.rotation = rad_to_deg r.y

    if LoadingLevel notin state.global_flags:
      self.update_raycast()

  method physics_process*(delta: float) =
    if CommandMode in state.local_flags and self.command_timer > 0:
      self.command_timer -= delta
      if self.command_timer <= 0:
        state.pop_flag CommandMode

    const forward_rotation = deg_to_rad(-90.0)
    let
      process_input =
        EditorVisible notin state.local_flags or CommandMode in state.local_flags
      input_direction =
        if process_input:
          self.get_input_direction()
        else:
          vec3()

      basis = self.camera_rig.global_transform.basis
      right = basis.x * input_direction.x
      up = UP * input_direction.y
      forward = (basis.x * input_direction.z).rotated(UP, forward_rotation)

    var move_direction = forward + right

    if move_direction.length() > 1.0:
      move_direction = move_direction.normalized()

    move_direction.y = 0
    move_direction += up

    var velocity = self.calculate_velocity(
      self.velocity, move_direction, delta, self.flying, self.alt_speed
    )

    self.model.input_direction = input_direction
    self.velocity = self.move_and_slide(velocity, UP)

    self.model.transform = self.transform

    let collisions = collect:
      for i in 0 .. (self.get_slide_count - 1):
        self.get_slide_collision(i)

    handle_collisions(self.model, collisions)

    if process_input:
      if self.is_on_floor:
        self.boosted = false

      if move_direction.length > 0.5:
        self.down_ray.translation = move_direction * 0.3 + vec3(0, 1, 0)
        if self.down_ray.is_colliding():
          let length = 1.85
          let diff =
            length -
            (
              self.down_ray.global_transform.origin -
              self.down_ray.get_collision_point
            ).y
          if diff > 0 and (self.is_on_floor() or not self.boosted):
            let boost = 16.1 * cbrt(diff)
            if boost > self.velocity.y:
              self.boosted = true
              self.velocity.y = boost

      # drop us back in the middle of the world if we fall through
      if self.translation.y < -10:
        self.translation = vec3(0, 100, 0)

  proc has_active_input(device: int): bool =
    for axis in 0 .. JOY_AXIS_MAX:
      if axis != JOY_ANALOG_L2 and axis != JOY_ANALOG_R2 and
          get_joy_axis(device, axis).abs >= 0.2:
        return true
    for button in 0 .. JOY_BUTTON_MAX:
      if is_joy_button_pressed(device, button):
        return true

  proc update_raycast() =
    let ray_length = if state.tool == CodeMode: 200.0 else: 100.0
    if MouseCaptured notin state.local_flags:
      let
        mouse_pos =
          self.get_viewport().get_mouse_position() * float state.scale_factor
        cast_from = self.camera.project_ray_origin(mouse_pos)
        cast_to =
          self.aim_ray.translation +
          self.camera.project_ray_normal(mouse_pos) * ray_length

      self.world_ray.cast_to =
        if ViewportFocused in state.local_flags: cast_to else: cast_from

      self.world_ray.translation = cast_from
      self.aim_target.update(self.world_ray)
    else:
      self.aim_ray.cast_to = vec3(0, 0, -ray_length)
      self.aim_target.update(self.aim_ray)

  method viewport_input*(event: InputEvent) =
    if event of InputEventJoypadMotion:
      let event = event as InputEventJoypadMotion
      if event.axis == JOY_ANALOG_L2 or event.axis == JOY_ANALOG_R2:
        return

    if event of InputEventMouseMotion and MouseCaptured in state.local_flags and
        TouchControls notin state.local_flags:
      if not self.skip_next_mouse_move:
        self.input_relative += event.as(InputEventMouseMotion).relative()
      else:
        self.skip_next_mouse_move = false

    if event of InputEventScreenTouch and TouchControls in state.local_flags:
      let event = event as InputEventScreenTouch
      if event.index == 0:
        if event.pressed:
          self.touch_position = some event.position
          # self.touch_time = get_mono_time()
          self.delete_timer = get_mono_time() + first_delete
        else:
          if ?self.touch_position and self.touch_position.get == event.position:
            self.update_raycast()
            state.push_flag PrimaryDown
            state.pop_flag PrimaryDown
            self.deleting = false
            self.delete_timer = MonoTime.high
            self.touch_position = none(Vector2)

    if event of InputEventScreenDrag and TouchControls in state.local_flags:
      let event = event as InputEventScreenDrag
      if event.index == 0:
        self.touch_position = none(Vector2)
      self.input_relative += event.relative()
      if not self.deleting:
        self.delete_timer = MonoTime.high

    if EditorVisible in state.local_flags and not self.skip_release and
        (event of InputEventJoypadButton or event of InputEventJoypadMotion):
      let active_input = self.has_active_input(event.device.int)
      if CommandMode in state.local_flags and not active_input:
        self.command_timer = input_command_timeout
      elif CommandMode in state.local_flags and active_input:
        self.command_timer = 0.0
      elif active_input:
        self.command_timer = 0.0
        state.push_flag CommandMode

    if event.is_action_pressed("jump"):
      self.jump_down = true
      let
        time = get_mono_time()
        toggle = ?self.jump_time and time < self.jump_time.get + fly_toggle

      if toggle and Playing notin state.local_flags:
        self.jump_time = nil_time
        self.flying(not self.flying)
      elif self.is_on_floor():
        self.velocity += vec3(0, jump_impulse, 0)
        self.jump_time = some time
      else:
        self.jump_time = some time
    elif event.is_action_released("jump"):
      self.jump_down = false

    if event.is_action_pressed("run"):
      let
        time = get_mono_time()
        toggle = ?self.run_time and time < self.run_time.get + alt_speed_toggle

      if toggle:
        self.run_time = nil_time
        if self.flying:
          state.toggle_flag(AltFlySpeed)
        else:
          state.toggle_flag(AltWalkSpeed)
      else:
        self.run_time = some time
      self.alt_speed = true
    elif event.is_action_released("run"):
      self.alt_speed = false

    if event of InputEventPanGesture and state.tool notin {CodeMode, PlaceBot}:
      let pan = event as InputEventPanGesture
      self.pan_delta += pan.delta.y
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

proc get_player*(): PlayerNode =
  PlayerNode(state.nodes.player)

var scene {.threadvar.}: PackedScene
proc init*(_: type PlayerNode): PlayerNode =
  if scene.is_nil:
    scene = load("res://components/Player.tscn") as PackedScene
  result = scene.instance() as PlayerNode
