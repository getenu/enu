import gdext
import
  gdext/classes/[
    gdnode3d, gdpackedscene, gdresourceloader, gdcollisionshape3d,
    gdmeshinstance3d, gdquadmesh, gdstandardmaterial3d, gdsubviewport,
    gdstyleboxflat, gdtextedit, gdcamera3d, gdcontrol, gdrichtextlabel,
  ]
import core, gdcore, types
import ui/[markdown_label, editor]

const
  viewport_x = 1200
  viewport_y = 1200

type SignNode* {.gdsync.} =
  ptr object of Node3D
    model*: Sign
    zid: ZID
    material: StandardMaterial3D
    viewport: SubViewport
    label: MarkdownLabel
    shape: CollisionShape3D
    quad: gdref QuadMesh
    counter: int
    expanded: bool

proc set_visibility(self: SignNode) =
  if Hide in self.model.local_flags:
    self.set_visible(false)
  elif Visible in self.model.global_flags:
    self.set_visible(true)
    self.material.set_blend_mode(BaseMaterial3D_BlendMode.blendModeMix)
  elif Visible notin self.model.global_flags and God in state.local_flags:
    self.set_visible(true)
    self.material.set_blend_mode(BaseMaterial3D_BlendMode.blendModeAdd)
  else:
    self.set_visible(false)

proc expand(self: SignNode) =
  self.label.set_custom_minimum_size(vector2(1200, 0))
  self.label.set_size(vector2(1200, 0))

  # The markdown label has extra padding at the bottom. There's probably a
  # good reason for this and a way to remove it properly, but this gets
  # the job done for now.
  let padding = self.model.size.float / (0.9 * self.model.width)
  let rect = vector2(self.label.get_size().x, self.label.get_size().y - padding)

  let ratio = rect.y / rect.x
  self.viewport.set_size(vector2i(int32(rect.x), int32(rect.y)))
  self.quad[].set_size(vector2(self.model.width, self.model.width * ratio))
  self.shape.set_scale(vector3(self.model.width, self.model.width * ratio, 1))

proc setup*(self: SignNode) =
  info "[SIGN] Setting up sign", sign = self.model.id

  var mesh = self.get_node("MeshInstance").as(MeshInstance3D)
  self.viewport = self.get_node("Viewport").as(SubViewport)
  assert ?self.viewport
  assert ?self.viewport.get_node("MarkdownLabel")

  self.label = self.viewport.get_node("MarkdownLabel").as(MarkdownLabel)
  self.shape = mesh.get_node("SignBody/CollisionShape").as(CollisionShape3D)
  self.quad = mesh.get_mesh().as(gdref QuadMesh)

  var text_edit = self.viewport.get_node("TextEdit").as(TextEdit)

  self.material = mesh.get_active_material(0)[].as(StandardMaterial3D)

  # Note: TextEdit in signs uses basic text display, not full syntax highlighting
  # The styling is handled by theme overrides in the scene file

  # Hide scrollbars by scaling them to zero
  let children = text_edit.get_children()
  for i in 0 ..< children.size():
    let child = children[i]
    if ?child:
      if child.is_class(gdstring("VScrollBar")) or child.is_class(gdstring("HScrollBar")):
        if child.is_class(gdstring("Control")):
          let control = child.as(Control)
          if ?control:
            control.set_scale(vector2(0, 0))

  proc resize() =
    info "[SIGN] Resizing sign", sign = self.model.id

    var
      ratio = self.model.width / self.model.height
      size = vector2(viewport_x.float, viewport_y.float / ratio)

    self.expanded = false

    if self.model.height == 0.0:
      self.quad[].set_size(vector2(self.model.width, self.quad[].get_size().y))
      self.shape.set_scale(
        vector3(self.model.width, self.quad[].get_size().y, 1)
      )
    else:
      self.quad[].set_size(vector2(self.model.width, self.model.height))
      self.shape.set_scale(vector3(self.model.width, self.model.height, 1))
      self.label.set_size(size)

      var t = mesh.get_transform()
      t.origin.x = self.model.width / -2 + 0.5
      t.origin.y = self.model.height / -2 + 0.5
      mesh.set_transform(t)
      self.viewport.set_size(vector2i(int32(size.x), int32(size.y)))

    # Configure StyleBox margin
    if ?self.label.og_label:
      let stylebox = self.label.og_label.get_theme_stylebox("normal".to_string_name()).as(gdref StyleBoxFlat)
      if ?stylebox:
        stylebox[].set_content_margin(Side.sideLeft, 80.0 / self.model.width)

    self.label.size = int(float(self.model.size) / self.model.width)

    text_edit.set_visible(self.model.text_only)
    self.label.set_visible(not self.model.text_only)

  resize()

  self.material.set_billboard_mode(
    if self.model.billboard:
      BaseMaterial3D_BillboardMode.billboardEnabled
    else:
      BaseMaterial3D_BillboardMode.billboardDisabled
  )

  info "[SIGN] Setting text",
    sign = self.model.id,
    text_only = self.model.text_only,
    message_length = self.model.message.len

  if self.model.text_only:
    text_edit.set_text(self.model.message)
  else:
    self.label.markdown = self.model.message
    self.label.update()

  self.model.message_value.watch:
    if added or touched:
      if self.model.text_only:
        text_edit.set_text(change.item)
      else:
        self.label.markdown = change.item
      resize()
      self.label.update()

  self.model.glow_value.watch:
    if added:
      self.material.set_emission_energy_multiplier(change.item)

  self.set_transform(self.model.transform)
  self.model.transform_value.watch:
    if added:
      self.set_transform(change.item)

  self.model.global_flags.watch:
    if (
      change.item == Visible and ScriptInitializing notin self.model.global_flags
    ) or ScriptInitializing.removed:
      self.set_visibility()

  state.local_flags.watch:
    if God.removed:
      self.set_visibility()

  self.model.local_flags.watch:
    if Highlight.added:
      self.material.set_emission_energy_multiplier(1.0)
    elif Highlight.removed:
      self.material.set_emission_energy_multiplier(self.model.glow)

method physics_process*(self: SignNode, delta: float64) {.gdsync.} =
  if ?self.model and self.model.height == 0.0 and not self.expanded:
    self.expand()
    self.expanded = true

method process*(self: SignNode, delta: float64) {.gdsync.} =
  # If we only billboard the material, the collision surface doesn't move
  # so highlighting the sign is weird from some angles. Align the mesh to the
  # camera, along with billboarding the material. The mesh doesn't line-up
  # with the billboard 100%, but it's pretty close.
  if ?self.model and self.model.billboard:
    let camera = self.get_viewport().get_camera_3d()
    if ?camera:
      let camera_origin = camera.get_global_transform().origin
      let cross = UP.cross(self.get_global_transform().origin - camera_origin)

      if cross != vector3(0, 0, 0):
        self.look_at(camera_origin, UP)

method ready*(self: SignNode) {.gdsync.} =
  info "[SIGN] SignNode ready - initializing Godot 4 sign system"
  # Setup will be called externally after model is assigned

var sign_scene {.threadvar.}: gdref PackedScene
proc init*(_: type SignNode): SignNode =
  if not ?sign_scene:
    sign_scene = cast[gdref PackedScene](ResourceLoader.load(
      "res://components/SignNode.tscn"
    ))
  result = SignNode(sign_scene[].instantiate())
