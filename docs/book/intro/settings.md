# Settings

Open the settings panel with the gear button in the corner of the screen (on
macOS it's also in the menu bar). It slides open and holds everything you can
change without editing the [config file](config.html) by hand.

![Settings panel](../assets/settings.png)

## Levels

The **Levels** dropdown lists every level in your current world. Pick one to
jump straight to it. Choosing **New...** lets you name and create a fresh level
to build in — your worlds are kept separate, so you can have one for
experiments and one for your masterpiece.

## Player Color

The color of your character in multiplayer. Pick one of Enu's built-in colors,
or the panel will show a hex color if you've set a custom one in your config.

## Environment

Changes the scenery and lighting around you. `default` is the usual purple
world; `none` strips it back; and there are others to try. Switching is
instant, so flip through them and see which you like.

## Full Screen

Toggles between filling the whole screen and running in a window. (Hidden on
iOS, where it wouldn't make sense.)

## Megapixels

How sharp the world looks. Higher is crisper but asks more of your computer;
lower is blurrier but runs faster. If things ever feel choppy, turn this down a
notch. Use the arrows to step through sensible values.

## Font Size

How big the text is in the code editor and console. Nudge it up or down with
the arrows.

## Toolbar Size

How big the tool icons are along the bottom of the screen.

## Run Server / Connect

The multiplayer controls. **Run Server** turns your Enu into a server other
people can join. When it's on, a field appears for a **server address** so you
can share your world. To join someone else's world instead, type their address
and press **Connect**. Multiplayer is still experimental — see the
[Multiplayer](multiplayer.html) page. Connecting or disconnecting restarts Enu.

<details class="note">
<summary>Note</summary>

Every setting here writes to the same `config.json` described on the
[Config](config.html) page, so anything you change in the panel sticks around
next time you launch Enu. A few options (like movement speeds and mouse
sensitivity) only live in the config file for now.

</details>
