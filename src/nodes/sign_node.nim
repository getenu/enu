import std/[monotimes, times]
import pkg/[godot]
import
  godotapi/[
    spatial, resource_loader, packed_scene, collision_shape, mesh_instance,
    quad_mesh, spatial_material, image_texture, viewport, camera,
  ]
import core
import nodes/sign_web

const MIPMAP_SETTLE_SECONDS = 0.5

gdobj SignNode of Spatial:
  var model* {.cursor.}: Sign
  var zid: EID
  var material: SpatialMaterial
  var shape: CollisionShape
  var quad: QuadMesh
  var web_tex: ImageTexture
  var web_bytes: PoolByteArray
  var web_still: float ## seconds since the picture last changed
  var web_mipmapped: bool
    ## Mipmaps keep distant text smooth, but regenerating them every frame is
    ## expensive. A sign that changes often goes without until it settles.
  var page_version: uint64
    ## Version of the last frame shown from the sign's page (0: none yet).

  proc set_visibility() =
    if VISIBLE in self.model.global_flags:
      self.visible = true
      self.material.params_blend_mode = spatial_material.BLEND_MODE_MIX
    elif GOD in state.player.flags and not (self.model.owner of Player):
      # God mode reveals hidden things scripts can change. A player's sign only
      # shows what they're coding, so it stays hidden.
      self.visible = true
      self.material.params_blend_mode = spatial_material.BLEND_MODE_ADD
    else:
      self.visible = false

  proc light_web() =
    ## Brightness of an unlit page: 1 normally, more when highlighted or
    ## glowing.
    let k =
      if HIGHLIGHT in self.model.local_flags: 1.3
      else: 1.0 + self.model.glow * 0.3
    self.material.albedo_color = init_color(k, k, k)

  proc show_pixels(pixels: pointer, px_width, px_height: int) =
    ## Uploads a rendered page as the albedo and sizes the quad to fit it
    ## across the model's width.
    if self.web_mipmapped and self.web_still < MIPMAP_SETTLE_SECONDS:
      self.web_tex.flags = FLAG_FILTER
      self.web_mipmapped = false
    self.web_still = 0
    upload(
      cast[ptr UncheckedArray[uint8]](pixels),
      px_width,
      px_height,
      self.web_tex,
      self.web_bytes,
    )
    let auto_height = self.model.height == 0.0
    let sign_height = self.model.width * px_height.float / px_width.float
    self.quad.size = vec2(self.model.width, sign_height)
    self.shape.scale = vec3(self.model.width, sign_height, 1)
    let mesh = self.get_node("MeshInstance") as MeshInstance
    var t = mesh.transform
    if auto_height:
      t.origin.y = sign_height / 2
    else:
      t.origin.x = self.model.width / -2 + 0.5
      t.origin.y = self.model.height / -2 + 0.5
    mesh.transform = t

  proc show_page_frame() =
    ## Shows the newest frame of this sign's page, if it changed. The worker
    ## builds the page, from the message or a script, and the render thread
    ## draws it.
    var version: uint64
    let frame = ew_take_frame(self.model.id.cstring, self.page_version, version.addr)
    if frame.is_nil:
      return
    self.page_version = version
    let start = get_mono_time()
    self.show_pixels(
      ew_frame_pixels(frame),
      ew_frame_width(frame).int,
      ew_frame_height(frame).int,
    )
    debug "page frame",
      sign = self.model.id,
      width = ew_frame_width(frame),
      height = ew_frame_height(frame),
      render_ms = ew_frame_render_ms(frame),
      upload_ms = (get_mono_time() - start).in_microseconds.float / 1000
    ew_frame_free(frame)

  proc page_pointer*(kind: uint32, global_point: Vector3): bool =
    ## Passes a pointer event at `global_point` to this sign's page, if it's
    ## a page. True if it was.
    if self.page_version == 0:
      return false
    let mesh = self.get_node("MeshInstance") as MeshInstance
    let local = mesh.to_local(global_point)
    let u = local.x / self.quad.size.x + 0.5
    let v = 0.5 - local.y / self.quad.size.y
    result = ew_post_pointer(self.model.id.cstring, kind, u, v)

  proc setup*() =
    debug "sign setup", sign = self.model.id

    var mesh = self.get_node("MeshInstance") as MeshInstance
    self.shape = mesh.get_node("SignBody/CollisionShape") as CollisionShape
    self.quad = mesh.mesh as QuadMesh
    self.material = mesh.get_active_material(0) as SpatialMaterial
    self.material.params_billboard_mode =
      if self.model.billboard: BILLBOARD_ENABLED else: BILLBOARD_DISABLED

    self.web_tex = gdnew[ImageTexture]()
    self.material.albedo_texture = self.web_tex
    # Pages show their own colors, like a screen, whatever the lighting.
    # Unlit materials ignore emission, so glow and highlight brighten the
    # page instead.
    self.material.flags_unshaded = true
    self.light_web()
    # Ask for the picture again, in case this node is new and the page's
    # last frame was already taken (or dropped while the page was parked).
    discard ew_post_pointer(self.model.id.cstring, POINTER_WAKE, 0, 0)

    self.model.glow_value.watch:
      if added:
        self.light_web()

    self.transform = self.model.transform
    self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.model.global_flags.watch:
      if (
        change.item == VISIBLE and
        SCRIPT_INITIALIZING notin self.model.global_flags
      ) or SCRIPT_INITIALIZING.removed:
        self.set_visibility

    state.player.flags.watch:
      if change.item == GOD:
        self.set_visibility

    self.model.local_flags.watch:
      if HIGHLIGHT.added or HIGHLIGHT.removed:
        self.light_web()

  method process*(delta: float) =
    if ?self.model:
      self.show_page_frame()
      self.web_still += delta
      if not self.web_mipmapped and self.web_still > MIPMAP_SETTLE_SECONDS and
          self.web_tex.get_width > 0:
        self.web_tex.flags = FLAG_FILTER or FLAG_MIPMAPS # generates them
        self.web_mipmapped = true
    # If we only billboard the material, the collision surface doesn't move
    # so highlighting the sign is weird from some angles. Align the mesh to the
    # camera, along with billboarding the material. The mesh doesn't line-up
    # with the billboard 100%, but it's pretty close.
    if ?self.model and self.model.billboard:
      let camera = self.get_viewport.get_camera
      if ?camera:
        let camera_origin = camera.global_transform.origin
        let cross = UP.cross(self.global_transform.origin - camera_origin)

        if cross != vec3():
          self.look_at(camera_origin, UP)

var sign_scene {.threadvar.}: PackedScene
proc init*(_: type SignNode): SignNode =
  if sign_scene.is_nil:
    sign_scene = load("res://components/SignNode.tscn") as PackedScene
  result = sign_scene.instance() as SignNode
