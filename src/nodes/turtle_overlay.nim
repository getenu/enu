import pkg/godot except print, Color
import
  godotapi/[
    viewport_container, viewport, camera, mesh_instance, surface_tool,
    array_mesh, mesh, spatial_material, spatial, environment,
  ]
import core, models/[things, builds, colors]

# The turtle indicator: a three-line arrow — shaft plus two barbs — from the
# centre of the draw cell along the draw heading, rigidly attached to the
# draw transform. Each line is a thin box (GLES3 has no line width): a
# bright core inside a wider translucent halo, for a glowy vector-display
# look.

const
  CORE_THICKNESS = 0.108'f32
  HALO_THICKNESS = 0.18'f32
  ARROW_TIP = -2.0'f32
  BARB = 0.707'f32 # 1m barbs at 45°: 1 / sqrt(2) per axis

proc arrow_edges(): seq[tuple[a, b: Vector3]] =
  let tip = vec3(0, 0, ARROW_TIP)
  result.add (vec3(), tip)
  result.add (tip, tip + vec3(BARB, 0, BARB))
  result.add (tip, tip + vec3(-BARB, 0, BARB))

proc add_edge_box(st: SurfaceTool, a, b: Vector3, thickness: float32) =
  # A segment as a long thin box: 4 side quads, ends extended by the
  # thickness so corners meet.
  let d = (b - a).normalized
  let up = if abs(d.y) > 0.9: vec3(1, 0, 0) else: vec3(0, 1, 0)
  let s1 = d.cross(up).normalized * thickness
  let s2 = d.cross(s1).normalized * thickness
  let a = a - d * thickness
  let b = b + d * thickness
  let sides = [s1 + s2, s1 - s2, -s1 - s2, -s1 + s2]
  for i in 0 .. 3:
    let (p, q) = (sides[i], sides[(i + 1) mod 4])
    st.add_vertex(a + p)
    st.add_vertex(a + q)
    st.add_vertex(b + q)
    st.add_vertex(a + p)
    st.add_vertex(b + q)
    st.add_vertex(b + p)

proc add_layer(
    mesh: ArrayMesh, color: chroma.Color, thickness: float32
): ArrayMesh =
  var st = gdnew[SurfaceTool]()
  st.begin(PRIMITIVE_TRIANGLES)
  st.add_color(color)
  for (a, b) in arrow_edges():
    st.add_edge_box(a, b, thickness)
  st.commit(mesh)

proc arrow_marker(): MeshInstance =
  let material = gdnew[SpatialMaterial]()
  material.flags_unshaded = true
  material.flags_transparent = true
  material.vertex_color_use_as_albedo = true
  material.params_cull_mode = CULL_DISABLED

  var halo = col("44ff66")
  halo.a = 0.3
  # Halo first, bright core drawn over it (surfaces render in order).
  var mesh = add_layer(nil, halo, HALO_THICKNESS)
  mesh = add_layer(mesh, col("e0ffe6"), CORE_THICKNESS)

  result = gdnew[MeshInstance]()
  result.mesh = mesh
  result.material_override = material
  result.cast_shadow = 0

proc arrow_transform(draw_transform: Transform): Transform =
  ## Build-local transform for the arrow: anchored at the centre of the draw
  ## cell (origin + half a cell) and turned with the draw basis.
  var t = draw_transform
  if t.basis.x == vec3():
    # The replica starts zeroed until the first sync; a singular basis makes
    # Godot spam "det == 0".
    t = Transform.init
  t.origin = t.origin + vec3(0.5, 0.5, 0.5)
  t

gdobj TurtleOverlay of ViewportContainer:
  # Draws the arrow over the world, under the GUI. It lives in its own
  # transparent viewport whose camera mirrors the world camera each frame,
  # so it shows through world geometry without touching the world's render
  # state — anything always-on-top drawn inside the world viewport
  # (depth-test-disable or near-plane depth squash) makes the terrain's most
  # recently meshed voxel faces vanish from some angles (GLES3). Sits after
  # the world container in game.tscn: draws above it, and its process runs
  # after the player has moved the camera.
  var
    overlay: Viewport
    camera: Camera
    arrow: MeshInstance
    world_viewport: Viewport

  method ready*() =
    self.visible = false
    self.world_viewport =
      self.get_node("../ViewportContainer/Viewport") as Viewport

    self.overlay = gdnew[Viewport]()
    self.overlay.world = gdnew[World]()
    self.overlay.transparent_bg = true
    # GLES3 drops the alpha channel from HDR render targets, which turns
    # transparent_bg into an opaque black square over the world.
    self.overlay.hdr = false
    self.overlay.usage = USAGE_3D_NO_EFFECTS
    # Renders only while the container is shown — no cost with no editor open.
    self.overlay.render_target_update_mode = UPDATE_WHEN_VISIBLE
    self.overlay.gui_disable_input = true
    self.add_child(self.overlay)

    self.camera = gdnew[Camera]()
    # The project's default environment draws an opaque background even with
    # transparent_bg; override it with a bare clear-color one.
    let env = gdnew[Environment]()
    env.background_mode = BG_CLEAR_COLOR
    self.camera.environment = env
    self.overlay.add_child(self.camera)
    self.camera.make_current()

    self.arrow = arrow_marker()
    self.arrow.visible = false
    self.overlay.add_child(self.arrow)

  method process*(delta: float) =
    # `stretch` only sizes child viewports on the container's own resize
    # events, which happened before ready() added ours — a 0x0 render target
    # composites as an opaque black rect.
    if self.overlay.size != self.rect_size:
      self.overlay.size = self.rect_size

    var show = false
    let thing = state.open_thing
    if ?thing and thing of Build and ?thing.node:
      let world_camera = self.world_viewport.get_camera()
      if ?world_camera:
        show = true
        self.camera.fov = world_camera.fov
        self.camera.near = world_camera.near
        self.camera.far = world_camera.far
        self.camera.global_transform = world_camera.global_transform
        self.arrow.global_transform =
          thing.node.global_transform *
          arrow_transform(Build(thing).turtle_transform)
    self.arrow.visible = show
    self.visible = show
