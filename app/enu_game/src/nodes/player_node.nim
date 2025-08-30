import std/[math]
import gdext
import
  gdext/classes/[
    gdcharacterbody3d, gdnode3d, gdcamera3d, gdraycast3d, gdcollisionshape3d, gdinput,
    gdinputevent, gdinputeventmousemotion, gdpackedscene, gdresourceloader,
  ]
import core, gdutils, models

const
  angle_x_min = -PI / 2.25
  angle_x_max = PI / 2.25
  jump_impulse = 10.0

var
  gamepad_sensitivity: Vector2
  mouse_sensitivity: Vector2

type PlayerNode* {.gdsync.} =
  ptr object of CharacterBody3D
    model*: Player
    flying*: bool
    input_relative*: Vector2

    # Child nodes
    camera_rig*: Node3D
    camera*: Camera3D
    aim_ray*: RayCast3D
    world_ray*: RayCast3D
    down_ray*: RayCast3D
    collision_shape*: CollisionShape3D

    # Player state
    alt_speed*: bool
    skip_next_mouse_move*: bool
    jump_down*: bool
    position_start*: Vector3

method ready*(self: PlayerNode) {.gdsync.} =
  # Initialize child nodes
  self.camera_rig = self.get_node("CameraRig").as(Node3D)
  self.collision_shape = self.get_node("CollisionShape").as(CollisionShape3D)
  self.camera = self.camera_rig.get_node("Camera").as(Camera3D)
  self.aim_ray = self.camera_rig.get_node("Camera/AimRay").as(RayCast3D)
  self.down_ray = self.find_child("DownRay").as(RayCast3D)

  # Store initial position
  self.position_start = self.camera_rig.position

  # Set up sensitivity values
  let x = state.config.mouse_sensitivity / 1000.0
  mouse_sensitivity = vector2(x, -x)
  gamepad_sensitivity =
    vector2(state.config.gamepad_sensitivity, state.config.gamepad_sensitivity)
  if state.config.invert_gamepad_y_axis:
    gamepad_sensitivity.y = -gamepad_sensitivity.y

  # TODO: Set up collision layers for flying - needs GC-safe alternative
  # state.local_flags.watch self.model:
  #   if change.item == Flying:
  #     let collision_enabled = Flying in state.local_flags
  #     for i in [0, 1, 2]:
  #       self.set_collision_mask_value(int32(i + 1), collision_enabled)

# Forward declarations of helper procs
proc get_input_direction(self: PlayerNode): Vector3
proc get_look_direction(self: PlayerNode): Vector2
proc update_rotation(self: PlayerNode, offset: Vector2)

method physics_process*(self: PlayerNode, delta: float) {.gdsync.} =
  # Get input direction
  let input_direction = self.get_input_direction()

  # Calculate movement direction in world space
  let basis = self.camera_rig.global_transform.basis
  let right = basis.x * input_direction.x
  let up = UP * input_direction.y
  let forward = (basis.z * -input_direction.z) # Negative z for forward

  var move_direction = forward + right
  if move_direction.length() > 1.0:
    move_direction = move_direction.normalized()

  move_direction.y = 0
  move_direction += up

  # Calculate velocity
  let speed =
    if self.flying:
      if self.alt_speed xor AltFlySpeed in state.local_flags:
        float(state.config.alt_fly_speed)
      else:
        float(state.config.fly_speed)
    else:
      if self.alt_speed xor AltWalkSpeed in state.local_flags:
        float(state.config.alt_walk_speed)
      else:
        float(state.config.walk_speed)

  var velocity = move_direction * speed

  # Apply gravity if not flying
  if not self.flying:
    velocity.y = self.velocity.y + state.gravity * delta

  # Move the character
  self.velocity = velocity
  discard self.move_and_slide()

  # Update model transform and input
  if not self.model.is_nil:
    # self.model.input_direction = input_direction
    self.model.transform = self.global_transform

method process*(self: PlayerNode, delta: float) {.gdsync.} =
  # Update camera position
  var transform = self.camera_rig.global_transform
  transform.origin = self.global_transform.origin + self.position_start

  # Handle mouse look
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

  # Update model rotation
  if not self.model.is_nil:
    self.model.rotation = rad_to_deg(r.y)

method input*(self: PlayerNode, event: InputEvent) {.gdsync.} =
  # Handle mouse movement for look
  if event.is_class("InputEventMouseMotion") and MouseCaptured in state.local_flags:
    if not self.skip_next_mouse_move:
      let mouse_event = event.as(InputEventMouseMotion)
      self.input_relative += mouse_event.relative
    else:
      self.skip_next_mouse_move = false

  # Handle jump input
  if Input.is_action_just_pressed("ui_accept"): # Using built-in action for now
    if not self.flying and self.is_on_floor():
      var vel = self.velocity
      vel.y = jump_impulse
      self.velocity = vel
    # TODO: Implement flying toggle logic

proc flying*(self: PlayerNode): bool =
  Flying in state.local_flags

proc `flying=`*(self: PlayerNode, value: bool) =
  state.set_flag(Flying, value)

proc get_input_direction(self: PlayerNode): Vector3 =
  if EditorVisible notin state.local_flags or CommandMode in state.local_flags:
    # Use built-in input actions for now, can be customized later
    # Explicitly convert Float (float64) to float32 for proper Vector3 construction
    result = vector3(
      Input.get_axis("ui_left", "ui_right").float32,
      Input.get_axis("ui_down", "ui_up").float32,
      Input.get_axis("ui_down", "ui_up").float32, # TODO: Add proper forward/back actions
    )

proc get_look_direction(self: PlayerNode): Vector2 =
  if EditorVisible notin state.local_flags or CommandMode in state.local_flags:
    # TODO: Implement gamepad look input
    result = vector2()

proc update_rotation(self: PlayerNode, offset: Vector2) =
  var r = self.camera_rig.rotation
  r.y -= offset.x
  r.x += offset.y
  r.x = clamp(r.x, angle_x_min, angle_x_max)
  r.z = 0
  self.camera_rig.rotation = r

proc update_raycast*(self: PlayerNode) =
  # TODO: Implement raycast system for interaction
  discard

proc init*(_: type PlayerNode): PlayerNode =
  let scene =
    cast[gdref PackedScene](ResourceLoader.load("res://components/Player.tscn"))
  result = PlayerNode(scene[].instantiate)
