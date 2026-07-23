---
description: Capture a unit's voxel frame-animation (a build that calls play()) from a fixed camera and stitch the frames into a seamless looping video. Use when asked to record/capture/screenshot an animation as an mp4/gif/loop.
---

# Capture a Voxel Frame-Animation as a Looping Video

Turn a unit's N-frame voxel animation (e.g. the island's `build_water`,
whose script is just `play(8.0)`) into a seamless looping MP4, shot from
a fixed camera. The trick is to **pin each frame deterministically** and
screenshot it, rather than filming live playback.

## The core idea

A frame-animated build exposes a display-only frame setter. Pin the frame,
screenshot, repeat 0..count-1, then stitch at the animation's fps.

```nim
me.frame_count        # number of frames (e.g. 24)
me.stop()             # halt playback (frames_fps = 0)
me.frame = 12         # DISPLAY frame 12 (display-only; -1 = live)
me.play(8.0)          # resume playback at 8 fps
```

**These frame procs only exist in the *build's* module.** Call them via
`eval(..., thing_id: "build_water")`, where `me` is that build. They are
NOT in the player module. (Note the eval param is `thing_id`, not
`unit_id`.)

24 frames at `play(8.0)` = 8 fps = a 3-second loop.

## Why the naive approach fails (read this first)

Setting `me.frame` echoes the value back instantly, but that alone does
**not** give correct screenshots. Every one of these will wreck the loop
(observed: frames out of order, "bouncing", duplicates):

- **Playback still running.** If the level is still loading, the build's
  `play()` re-runs as loading finishes and *restarts* playback, which
  advances `current_frame` every tick and overrides your `me.frame = N`
  between the set and the screenshot. Wait until the level is fully
  loaded, `stop()`, and **verify the frame holds** (read `me.frame`
  twice a second apart — if it changed, playback is live).
- **Other unit scripts never stop.** `stop()` only halts *this build's*
  frame playback. Every other script keeps running (a sign's update
  loop, gulls flapping, the windmill turning). There is **no way to stop
  another unit's script from `eval`** — script-stop is host-side only.
  The reachable equivalent is to **hide** them (`show = false`).
- **Cold frame-mesh cache.** Stepping to a frame whose mesh hasn't been
  baked shows a *stale* mesh (no visible change). Warm first.
- **Self-model in shot.** `screenshot_from_player` renders the player's
  own avatar (looks like a translucent blob filling the view). Hide it.

When playback is genuinely stopped, there is **no render latency** — an
immediate screenshot equals a settled one (verified YAVG ≈ 0), so no
settle delay is needed.

## Workflow

### 1. Attach — one Enu per world
`connect()` to a running instance (started with `--listen`) if the user
has one; otherwise `launch_and_connect(world, level)` (world = the world
dir's path, level = a level name). **Never run two Enu processes on the
same world** — it causes crashes, a netty
`reactor.id` assertion on connect, and fighting writes to the level
files. Prefer attaching to the user's instance so they can watch.

### 2. Find the build and its frame count
```
eval('"count=" & $me.frame_count', thing_id: "build_water")
```

### 3. Set up the camera
- **A specific player view:** hide the player model first, then use
  `screenshot_from_player`. The player camera captures where the human
  is looking and can drift/bob — prefer the bot camera for a locked shot.
- **Any vantage (recommended):** park your bot with
  `set_position(x, y, z, rotation)` (rotation = Y yaw in degrees) or frame
  a point with `screenshot_at(x, y, z, distance, height, angle)`. The
  bot's own model is auto-hidden from its POV, and a parked bot is
  pixel-stable (verify: two identical `screenshot` calls diff to YAVG 0).
- **Preview before the full run.** Capture the first frame and
  `open <file>` it (Preview.app) so the user can confirm the spot. Only a
  single Y-rotation is needed if the view is level; ask for pitch only if
  the preview looks off.
- Watch for the **water draw-distance band**: the mesh is culled ~230 m
  out, leaving a black gap to the sky on open-horizon shots. Frame along
  a coast / tilt down to minimize it.

### 4. Hide everything that animates but isn't the target
Run in the player module (default eval, no `thing_id`):
```nim
block:
  for b in all_bots(): b.show = false
  for b in all_builds():
    if b.id.contains("gull") or b.id.contains("windmill") or
       b.id.contains("boat") or b.id.contains("ferry") or
       b.id.contains("sign") or b.id.contains("beacon") or
       b.id.contains("firework") or b.id.contains("lamp"):
      b.show = false
  for s in all_signs(): s.show = false
  for p in all_players(): p.show = false   # kills the self-model
```
Adjust the id filter per level — hide anything with a `loop:`/`move me`
or its own `play()` (frame-animated gulls, etc.). Static builds (terrain,
trees, huts) can stay.

### 5. Warm the frame-mesh cache at the vantage
Play a few loops while the camera renders this view, so every frame's
mesh bakes for the visible chunks:
```
eval("me.play(8.0)", thing_id: "build_water")
# take a few screenshots at the vantage over ~10s (each forces a render),
# using short waits — sleep(4.0) is fine, but keep eval sleeps <= ~8s:
# a longer sleep exceeds the eval timeout and the eval is cut off BEFORE
# any statement after it runs (e.g. a trailing stop() silently won't run).
```

### 6. Stop, verify it holds
```
eval("me.stop()\nme.frame = 0\n$me.frame", thing_id: "build_water")
# read me.frame again a moment later — must be unchanged (still 0).
```

### 7. Capture frame by frame
For N in 0 .. count-1, re-assert `stop()` as insurance, set the frame,
then screenshot:
```
eval("me.stop()\nme.frame = <N>\n<N>", thing_id: "build_water")
screenshot()            # or screenshot_at(... same params ...) / screenshot_from_player()
```
Screenshots are 1920×1080, written to a temp dir with incrementing
numbers. Note the number of the first shot; frame `i` maps to
`first + i`. Do the eval and its screenshot as an ordered pair — an
off-by-one phase is harmless for a loop, but a race (screenshot before
the set) is not, so don't reorder them.

### 8. Stitch and validate
```bash
OUT=~/enu_water_loops/<name>
for i in $(seq 0 23); do printf -v d "$OUT/frame_%03d.png" $i; cp "shot_$((first+i)).png" "$d"; done
ffmpeg -y -framerate 8 -i "$OUT/frame_%03d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart "$OUT/loop.mp4"
```
Confirm it's a real loop, not a bounce: the difference between
consecutive frames should be **uniform and non-zero**, and the **seam**
(last→first) should match a normal step. Zeros = duplicate frames
(bad warm/stale); erratic jumps = playback wasn't stopped.
```bash
diff(){ ffmpeg -i "$1" -i "$2" -filter_complex \
  "blend=all_mode=difference,format=gray,signalstats,metadata=print:key=lavfi.signalstats.YAVG" \
  -f null - 2>&1 | grep -o "YAVG=[0-9.]*" | tail -1; }
# build a 6x4 contact sheet to eyeball order/composition:
ffmpeg -y -framerate 8 -i "$OUT/frame_%03d.png" -frames:v 1 \
  -vf "scale=300:169,tile=6x4:padding=4:color=black" "$OUT/contact.png"
```

### 9. Restore (if you used the user's instance)
Leave it as you found it:
```nim
block:
  for b in all_bots(): b.show = true
  for b in all_builds(): b.show = true
  for s in all_signs(): s.show = true
  for p in all_players(): p.show = true
```
```
eval("me.play(8.0)", thing_id: "build_water")   # resume playback
```
If you ran on a repo copy of the level, revert any incidental file writes
Enu auto-saved (`git checkout -- <level>/level.json <changed unit>.json`).

## Quick checklist
- [ ] One Enu per level dir; level fully loaded
- [ ] Camera parked & previewed (`open` the first frame)
- [ ] Player self-model + all script-driven units hidden
- [ ] Frame meshes warmed at the vantage
- [ ] `stop()` verified holding (frame doesn't advance)
- [ ] 24 frames captured, contact sheet + seam diff check pass
- [ ] Stitched to mp4; instance restored
