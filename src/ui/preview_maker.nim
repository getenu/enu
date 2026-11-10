import
  godotapi/[
    viewport, camera, mesh_instance, material, camera, viewport_texture, image,
    resource_loader, engine, spatial_material
  ]
import godot
import ".."/[core, gdutils]

gdobj PreviewMaker of Viewport:
  var
    camera: Camera
    cube: MeshInstance
    bot: Spatial
    block_material: SpatialMaterial
    callback: proc(img: Image) {.gcsafe.}
    frames_drawn_at_request = int64.high

  method ready*() =
    self.camera = self.find_node("Camera") as Camera
    self.cube = self.find_node("Cube") as MeshInstance
    self.bot = self.find_node("bot") as Spatial
    self.block_material =
      load("res://materials/block_preview.tres") as SpatialMaterial
    assert not self.camera.is_nil
    assert not self.cube.is_nil
    assert not self.bot.is_nil

  method process*(delta: float) =
    # The UPDATE_ONCE render happens on the next actual draw, which can be
    # several frames away at startup (window not presenting yet, fullscreen
    # transition, etc). Counting completed draws instead of process ticks
    # keeps us from grabbing the texture before it has been rendered.
    if not self.callback.is_nil and get_frames_drawn() > self.frames_drawn_at_request:
      let image = self.get_texture().get_data()
      self.callback(image)
      self.callback = nil

  proc generate_block_preview*(
      color: Color, callback: proc(preview: Image) {.gcsafe.}
  ) =
    let material = self.block_material.duplicate as SpatialMaterial
    # The preview light is much brighter than the world's; dimmed like this,
    # an icon looks like the block it places.
    material.albedo_color =
      Color(r: color.r * 0.56, g: color.g * 0.56, b: color.b * 0.56, a: 1.0)
    material.emission = color
    self.cube.visible = true
    self.bot.visible = false
    self.cube.set_surface_material(0, material)
    self.render_target_update_mode = UPDATE_ONCE
    self.camera.fov = 1
    self.camera.look_at vec3(), UP
    self.callback = callback
    self.frames_drawn_at_request = get_frames_drawn()

  proc generate_object_preview*(
      object_name: string, callback: proc(preview: Image) {.gcsafe.}
  ) =
    self.cube.visible = false
    self.bot.visible = true
    self.render_target_update_mode = UPDATE_ONCE
    self.camera.fov = 1.2
    self.camera.look_at vec3(), UP
    self.callback = callback
    self.frames_drawn_at_request = get_frames_drawn()
