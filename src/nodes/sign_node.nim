import pkg/[godot]
import
  godotapi/[
    spatial, resource_loader, packed_scene, collision_shape, mesh_instance,
    quad_mesh, spatial_material, viewport, style_box_flat, text_edit
  ]
import ui/[markdown_label, editor]
import core

const
  viewport_x = 1200
  viewport_y = 1200

gdobj SignNode of Spatial:
  var model*: Sign
  var zid: ZID
  var material: SpatialMaterial
  var viewport: Viewport
  var label: MarkdownLabel
  var shape: CollisionShape
  var quad: QuadMesh
  var counter: int
  var expanded: bool

  proc set_visibility() =
    if Hide in self.model.local_flags:
      self.visible = false
    elif Visible in self.model.global_flags:
      self.visible = true
      self.material.params_blend_mode = spatial_material.BLEND_MODE_MIX
    elif Visible notin self.model.global_flags and God in state.local_flags:
      self.visible = true
      self.material.params_blend_mode = spatial_material.BLEND_MODE_ADD
    else:
      self.visible = false

  proc expand() =
    self.label.rect_min_size = vec2(1200, 0)
    self.label.rect_size = vec2(1200, 0)

    # The markdown label has extra padding at the bottom. There's probably a
    # good reason for this and a way to remove it properly, but this gets
    # the job done for now.
    let padding = self.model.size.float / (0.9 * self.model.width)
    let rect = vec2(self.label.rect_size.x, self.label.rect_size.y - padding)

    let ratio = rect.y / rect.x
    self.viewport.size = rect
    self.quad.size = vec2(self.model.width, self.model.width * ratio)
    self.shape.scale = vec3(self.model.width, self.model.width * ratio, 1)

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
      self.label.size = int(float(self.model.size) / self.model.width)

      text_edit.visible = self.model.text_only
      self.label.visible = not self.model.text_only

    resize()
    self.material.params_billboard_mode =
      if self.model.billboard: BILLBOARD_ENABLED else: BILLBOARD_DISABLED

    if self.model.text_only:
      text_edit.text = self.model.message
    else:
      self.label.markdown = self.model.message
      self.label.update

    self.model.message_value.watch:
      if added or touched:
        if self.model.text_only:
          text_edit.text = change.item
        else:
          self.label.markdown = change.item
        resize()
        self.label.update

    self.model.glow_value.watch:
      if added:
        self.material.emission_energy = change.item

    self.transform = self.model.transform
    self.model.transform_value.watch:
      if added:
        self.transform = change.item

    self.model.global_flags.watch:
      if (
        change.item == Visible and
        ScriptInitializing notin self.model.global_flags
      ) or ScriptInitializing.removed:
        self.set_visibility

    state.local_flags.watch:
      if God.removed:
        self.set_visibility

    self.model.local_flags.watch:
      if Highlight.added:
        self.material.emission_energy = 1.0
      elif Highlight.removed:
        self.material.emission_energy = self.model.glow

  method physics_process*(delta: float) =
    if ?self.model and self.model.height == 0.0 and not self.expanded:
      self.expand()
      self.expanded = true

  method process*(delta: float) =
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
