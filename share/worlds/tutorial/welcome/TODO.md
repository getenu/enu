# Island level — TODO

Fixes originally flagged with `# CLAUDE` comments. Done items had their comment
removed; remaining items still have theirs as an anchor.

Done:

- [x] **build_rat_foundation** — green z-fought terrain. Raised origin y4→5
  (sits on the grid-4 surface).
- [x] **build_rat_opera** + **build_rat_pad** — the launchpad (a *separate* unit,
  build_rat_pad) z-fought terrain. Raised both y4→5.
- [x] **build_cottage** — white floor z-fought. Raised origin y4→6 (terrain
  under it is grid 5).
- [x] **build_tower_plot** — south row clipped the slope. Raised origin y4→5.
- [x] **build_beacon_windmill** — was jammed against the windmill and inside the
  blade sweep. Moved to (-159, 2, -26).
- [x] **build_beacon_finale** — sat on the gate pedestal in the portal mouth.
  Moved out onto the east approach, (-55, 6, -161). (Leaves the gate's pedestal
  riser empty — remove it when doing summit_gate below.)
- [x] **build_boat** — the "…beacons to wake it." sign faced out to sea. Made all
  three boat signs `billboard = true` so they face the player.
- [x] **build_windmill_blades** — baked to an **empty starting script** (just the
  prompt). No anchor, no format change. Pattern:
  1. Draw the rotor **flat** in the local XZ plane (perpendicular to the default
     yaw axis, local Y) so a plain `turn right` spins it in-plane.
  2. `persist()` + `save_level_now()` to bake (49 voxels), then delete the draw
     code + bake calls.
  3. Set `start_transform.basis` in the data JSON to tip the build 90° upright
     (`[[0,1,0],[-1,0,0],[0,0,1]]`, a -90° roll about Z). Because move-mode
     `turn` is intrinsic (`transform.basis.xform(axis)`), the spin axis tips with
     the geometry — vertical wheel spinning around the horizontal axle.
  Verified: static render is a proper windmill, and the player's answer
  (`move me` + `forever: turn right; sleep`) spins it in-plane. This is the
  repeatable recipe for baking the other exercises — build in the frame where the
  default motion is correct, then place with `start_transform`.
  (Superseded the earlier anchor-in-script bake.)

- [x] **Exercise-script sweep** — split staging out of exercise units where it
  made sense; left units that just teach the first step or two.
  - Left as-is (first-step / minimal object being acted on): `build_tower_site`
    (starter ring → build to 12), `bot_maze_runner` (`forward 2` → route),
    `build_fireworks` (2-block dud → animate), `build_lighthouse_lamp` (dark lamp
    → light it).
  - `build_rat_foundation` — baked the green outline + starter wall into its data
    (56 voxels: 44 green + 12 invisible), moved the `forever:` block-counting
    monitor into the director (`update_rat_walls`, same world-space counts +
    thresholds, sets the foundation's pen colour that bot_rat/rat_opera read).
    Foundation script is now just the exercise text + the `swap_color` YOUR LINE.
    Verified: outline renders from bake, and the director holds the colour signal
    (green while building).

Remaining (need more than a coordinate nudge):

- [x] **build_summit_gate** — added a two-course skirt under the plinths + plaza,
  raised the whole gate one block (origin y5→6) so the plaza rides above the
  grid-5 approach terrain (was z-fighting flush), and removed the now-empty
  beacon pedestal riser. Reads as a clean monument on a foundation.
- [x] **build_lighthouse** — extended the plinth with two wider lower courses
  (r12@y-3, r13@y-4) that step down past the lowest terrain, so the base plants
  as a foundation instead of a ragged clip against the headland.

(All the originally-flagged `# CLAUDE` items are now done.)

## vmlib / scripting

- [x] **`say` inside a user proc targeted nothing.** The `say` template used the
  injected `var enu_target`, which the VM doesn't capture into user-defined
  procs, so `say` from inside a proc silently did nothing. Fixed in
  `vmlib/enu/signs.nim` to use `active_thing()` (like `turn`/`place`/`box`).
  Applied live via `save_and_reload`; **not yet committed**.
- [ ] **Turtle commands inside user procs still target nothing** — `forward`,
  `up`, `left`, `lean`, etc. share the same `enu_target`-not-captured problem.
  They can't just switch to `active_thing()` because `move enemy`/`build enemy`
  deliberately retarget `enu_target`. Proper fix: make `enu_target` host-backed
  (like `active_thing`) and have `move`/`build`/`anchor` push/pop it, so procs
  see the current turtle target. Bigger change; needs care + tests.
- [ ] **No way to identify the player who clicked a sign link.** A link click
  runs `state.open_sign.owner.eval` in the *bot's* context on the server worker;
  `executing_player` resolves to the code owner, not the clicker. Fine for
  single-player (dialog dismiss uses `sign.open = false`), but multiplayer-
  correct dismiss/branching would need the clicking player threaded through the
  meta-click → eval path (cleanest: a dedicated close directive handled in
  `on_meta_clicked` client-side, where `state.player` is the clicker).

## App bugs (need a `nim build` + restart — not hot-reloadable)

- [~] **Toolbar drifts up-screen after a `player.tools` change**
  (`src/ui/toolbar.nim`). Was: `animate_tools` returned the toolbar to a lazily
  cached `rest_y` read once from `rect_position.y`; if that first read happened
  before the window settled at final size (the director sets tools ~1 s after
  load) it cached too high and stranded the toolbar up-screen. **Fixed** —
  `animate_tools` now derives the rest position from the anchored layout each
  time: `rest = (parent as Control).rect_size.y - 5.0 - self.rect_size.y` (the
  toolbar is bottom-anchored with `margin_bottom = -5`), and the `rest_y` /
  `rest_y_set` fields are gone. Compiles clean (`nim build` → SuccessX).
  **Pending: restart Enu to confirm the behaviour in-app.**
