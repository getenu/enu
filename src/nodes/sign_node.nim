import pkg/[godot]
import
  godotapi/[
    spatial, resource_loader, packed_scene, collision_shape, mesh_instance,
    quad_mesh, spatial_material, viewport, style_box_flat, text_edit
  ]
import ui/[markdown_label, editor]
import core
import godotapi/image_texture

when defined(enu_pages):
  import std/[monotimes, times]
  import nodes/sign_web

const
  viewport_x = 1200
  viewport_y = 1200
  # The sign renders its markdown into a fixed `viewport_x`-wide texture mapped
  # across `width` blocks, so a block spans `viewport_x / width` px. `size` (the
  # model field) is the text height in blocks, so its font size in texture px is
  # `size * viewport_x / width`. This constant is the whole bridge between the
  # block-space API and the pixel-space label.
  text_px_per_block = viewport_x.float

gdobj SignNode of Spatial:
  var model* {.cursor.}: Sign
  var zid: EID
  var material: SpatialMaterial
  var viewport: Viewport
  var label: MarkdownLabel
  var shape: CollisionShape
  var quad: QuadMesh
  var counter: int
  var expanded: bool
  var web_tex: ImageTexture
  var web_bytes: PoolByteArray
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

  proc expand() =
    self.label.rect_min_size = vec2(1200, 0)
    self.label.rect_size = vec2(1200, 0)

    # The markdown label has extra padding at the bottom. There's probably a
    # good reason for this and a way to remove it properly, but this gets
    # the job done for now. (`size` is blocks; scale to texture px like the
    # font does, so the trim tracks the text size.)
    let padding =
      self.model.size * text_px_per_block / (0.9 * self.model.width)
    let rect = vec2(self.label.rect_size.x, self.label.rect_size.y - padding)

    let ratio = rect.y / rect.x
    let sign_height = self.model.width * ratio
    self.viewport.size = rect
    self.quad.size = vec2(self.model.width, sign_height)
    self.shape.scale = vec3(self.model.width, sign_height, 1)

    # Auto-sized signs (bots, mainly) anchor their bottom edge and grow upward,
    # so a long message climbs into the air instead of clipping down through the
    # speaker's head. The quad is centred on the mesh origin, so lifting the mesh
    # by half its height pins the bottom edge at the sign's origin.
    let mesh = self.get_node("MeshInstance") as MeshInstance
    var t = mesh.transform
    t.origin.y = sign_height / 2
    mesh.transform = t

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
    when defined(enu_pages):
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
      self.expanded = true

  proc show_page_frame() =
    ## Shows the newest frame of this sign's page, if it changed. The worker
    ## builds the page, from the message or a script, and the render thread
    ## draws it.
    when defined(enu_pages):
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
    when defined(enu_pages):
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
    self.viewport = self.get_node("Viewport") as Viewport
    self.label = self.viewport.get_node("MarkdownLabel") as MarkdownLabel
    self.shape = mesh.get_node("SignBody/CollisionShape") as CollisionShape
    self.quad = mesh.mesh as QuadMesh

    var text_edit = self.viewport.get_node("TextEdit") as TextEdit

    self.material = mesh.get_active_material(0) as SpatialMaterial
    text_edit.configure_highlighting

    for child in text_edit.get_children:
      let child = child.as_object(Node)
      if child of ScrollBar or child of HScrollBar:
        # hide scrollbars
        ScrollBar(child).rect_scale = vec2()

    proc resize() =
      debug "sign resize", sign = self.model.id

      var
        ratio = self.model.width / self.model.height
        size = vec2(viewport_x, viewport_y / ratio)

      self.expanded = false

      if self.model.height == 0.0:
        self.quad.size = vec2(self.model.width, self.quad.size.y)
        self.shape.scale = vec3(self.model.width, self.quad.size.y, 1)
      else:
        self.quad.size = vec2(self.model.width, self.model.height)
        self.shape.scale = vec3(self.model.width, self.model.height, 1)
        self.label.rect_size = size

        var t = mesh.transform
        t.origin.x = self.model.width / -2 + 0.5
        t.origin.y = self.model.height / -2 + 0.5
        mesh.transform = t
        self.viewport.size = size

      var stylebox = self.label.og_label.get_stylebox("normal") as StyleBoxFlat

      stylebox.content_margin_left = 80 / self.model.width
      self.label.size = int(self.model.size * text_px_per_block / self.model.width)

      text_edit.visible = self.model.text_only
      self.label.visible = not self.model.text_only

    resize()
    self.material.params_billboard_mode =
      if self.model.billboard: BILLBOARD_ENABLED else: BILLBOARD_DISABLED

    let use_web = defined(enu_pages) and not self.model.text_only
    if use_web:
      self.web_tex = gdnew[ImageTexture]()
      self.material.albedo_texture = self.web_tex
      # Pages show their own colors, like a screen, whatever the lighting.
      # Unlit materials ignore emission, so glow and highlight brighten the
      # page instead.
      self.material.flags_unshaded = true
      self.light_web()
      self.viewport.render_target_update_mode = UPDATE_DISABLED
      self.label.visible = false
      # Ask for the picture again, in case this node is new and the page's
      # last frame was already taken (or dropped while the page was parked).
      when defined(enu_pages):
        discard ew_post_pointer(self.model.id.cstring, POINTER_WAKE, 0, 0)

    if self.model.text_only:
      text_edit.text = self.model.message
    elif not use_web:
      self.label.markdown = self.model.message
      self.label.update

    self.model.message_value.watch:
      if added or touched:
        if use_web:
          discard # the worker rebuilds the page
        elif self.model.text_only:
          text_edit.text = change.item
          resize()
        else:
          self.label.markdown = change.item
          resize()
          self.label.update

    self.model.glow_value.watch:
      if added:
        if use_web:
          self.light_web()
        else:
          self.material.emission_energy = change.item

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
      if use_web and (HIGHLIGHT.added or HIGHLIGHT.removed):
        self.light_web()
      elif HIGHLIGHT.added:
        self.material.emission_energy = 1.0
      elif HIGHLIGHT.removed:
        self.material.emission_energy = self.model.glow

  method physics_process*(delta: float) =
    if ?self.model and self.model.height == 0.0 and not self.expanded:
      self.expand()
      self.expanded = true

  method process*(delta: float) =
    when defined(enu_pages):
      if ?self.model and ?self.web_tex:
        self.show_page_frame()
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
