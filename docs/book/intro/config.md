# Config

The Enu data directory lives in `~/Library/Application Support/enu` on Mac,
`%AppData%\enu` on Windows, and `~/.local/share/enu` on Linux. `config.json` has
a few configurable options:

- `font_size`: The font size.

- `toolbar_size`: Size of the icons in the dock.

- `world`: An Enu world is a collection of levels. Set to `tutorial` by default.
  If the world doesn't exist, it will be created.

- `level`: The level to load. Change this to create a new level, or load an
  existing one. By default, this will be `world` plus `-` and a number. Set to
  `tutorial-1` by default.

- `show_stats`: Show FPS and other stats. `false` by default.

- `god_mode`: Makes hidden units slightly visible, and allows editing locked
  units. `false` by default.

- `megapixels`: The render resolution, in mega pixels. Increase for more
  detail. Decrease for better performance. `2.0` by default.

- `full_screen`: Whether to start Enu full screen, or in a window. `true` by
  default.

- `semicolon_as_colon`: Both `;` and `:` will be interpreted as `:`, allowing
  `:` to be typed without shift. Sometimes useful for new typists. `false` by
  default.

- `listen_address`: Set this to something reasonable, like `0.0.0.0`, to be a
  server. Optionally you can add a `:` and a port number. Empty by default. Will
  use port `9632` if none is specified.

- `connect_address`: An IP or host name of an Enu instance with `listen_address`
  set. Optionally include a `:` and a port number. Empty by default. Will use
  port `9632` if none is specified.

- `player_color`: The color of your avatar when in multiplayer. Set to a hex
  color (like `#ffffff`) or one of Enu's built in colors (`blue`, `red`,
  `green`, `black`, `white`, and `brown`). Defaults to a random hex color.

- `walk_speed`: Normal ground movement speed. `500` by default.

- `fly_speed`: Normal flying speed. `1500` by default

- `alt_walk_speed`: Ground movement speed while `Shift`/`L3` is held or toggled.
  `1000` by default.

- `alt_fly_speed`: Flying speed while `Shift`/`L3` is held or toggled. `250` by
  default.

- `mouse_sensitivity`: Aim/look sensitivity while the mouse is captured. `5.0`
  by default.

- `gamepad_sensitivity`: Gamepad aim/look sensitivity. `2.5` by default.

- `invert_gamepad_y_axis`: You know who you are. `false` by default.

## Example

```json
{
  "font_size": 38,
  "toolbar_size": 193.75,
  "world": "tutorial",
  "level": "tutorial-1",
  "show_stats": true,
  "god_mode": false,
  "megapixels": 5.0,
  "full_screen": false,
  "semicolon_as_colon": false,
  "player_color": "#6495ED",
  "walk_speed": 500,
  "fly_speed": 1500,
  "alt_walk_speed": 1000,
  "alt_fly_speed": 250,
  "mouse_sensitivity": 5.0,
  "gamepad_sensitivity": 2.5,
  "invert_gamepad_y_axis": false
}
```
