import gdext
import gdext/classes/[
  gdviewport, gdcamera3d, gdmeshinstance3d, gdmaterial, gdnode3d, gdimage,
  gdresourceloader, gdviewporttexture
]
import core, gdutils

type PreviewMaker* {.gdsync.} = ptr object of Viewport
  camera: Camera3D
  cube: MeshInstance3D
  bot: Node3D
  callback: proc(img: gdref Image) {.gcsafe.}
  skip_next: bool

method ready*(self: PreviewMaker) {.gdsync.} =
  print("[UI] PreviewMaker ready - initializing preview generation system")
  
  self.camera = self.find_child("Camera3D", false, false).as(Camera3D)
  self.cube = self.find_child("Cube", false, false).as(MeshInstance3D)
  self.bot = self.find_child("bot", false, false).as(Node3D)
  
  if self.camera.is_nil():
    print("[UI] ✗ Camera3D not found in PreviewMaker scene")
  if self.cube.is_nil():
    print("[UI] ✗ Cube MeshInstance3D not found in PreviewMaker scene")
  if self.bot.is_nil():
    print("[UI] ✗ bot Node3D not found in PreviewMaker scene")
  
  print("[UI] PreviewMaker initialized")

method process*(self: PreviewMaker, delta: float) {.gdsync.} =
  if not self.skip_next and not self.callback.is_nil():
    # GD4: Get viewport texture and extract image data
    let texture = self.get_texture().as(gdref ViewportTexture)
    if ?texture:
      let image = texture[].get_image()
      if ?image:
        self.callback(image)
      else:
        print("[UI] ✗ PreviewMaker: Failed to get image from texture")
    else:
      print("[UI] ✗ PreviewMaker: Failed to get viewport texture")
    self.callback = nil
  self.skip_next = false

proc generate_block_preview*(
    self: PreviewMaker,
    material_name: string, 
    callback: proc(preview: gdref Image) {.gcsafe.}
) =
  print("[UI] Generating block preview for material: ", material_name)
  
  # GD4: Load material resource
  let material_path = "res://materials/" & material_name & ".tres"
  let material = ResourceLoader.load(material_path).as(gdref Material)
  
  if not ?material:
    print("[UI] ✗ Failed to load material: ", material_path)
    return
  
  # Set up scene for block preview
  self.cube.set_visible(true)
  self.bot.set_visible(false)
  self.cube.set_surface_override_material(0, material)
  
  # GD4: TODO - Set render mode to UPDATE_ONCE equivalent when rendering system is clearer
  # In Godot 4, this may be handled differently through the SubViewport or RenderingServer
  
  # Configure camera for block preview
  if not self.camera.is_nil():
    self.camera.set_fov(1.0)
    # GD4: look_at syntax changed
    self.camera.look_at(vector3(0, 0, 0), vector3(0, 1, 0))
  
  self.callback = callback
  self.skip_next = true

proc generate_object_preview*(
    self: PreviewMaker,
    object_name: string,
    callback: proc(preview: gdref Image) {.gcsafe.}
) =
  print("[UI] Generating object preview for: ", object_name)
  
  # Set up scene for object preview
  self.cube.set_visible(false)
  self.bot.set_visible(true)
  
  # GD4: TODO - Set render mode to UPDATE_ONCE equivalent when rendering system is clearer
  # In Godot 4, this may be handled differently through the SubViewport or RenderingServer
  
  # Configure camera for object preview
  if not self.camera.is_nil():
    self.camera.set_fov(1.2)
    # GD4: look_at syntax changed
    self.camera.look_at(vector3(0, 0, 0), vector3(0, 1, 0))
  
  self.callback = callback
  self.skip_next = true