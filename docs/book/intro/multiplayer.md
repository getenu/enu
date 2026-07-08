# Multiplayer

Enu worlds can be shared. Run one copy as a server and other people can connect
to it, build alongside you, and see each other's changes live. It generally
works well and is one of the most fun ways to use Enu.

<details class="note">
<summary>Only play with people you trust</summary>

Connecting runs the host's world, scripts and all, on your machine. We haven't
finished a proper security review yet, so for now only host with, or connect
to, people you actually know and trust. A public server on the open internet
isn't a good idea just yet.

</details>

## Hosting a world

Hosting isn't in the settings panel yet, so you start a server one of three
ways:

- **Config file.** Set `listen_address` in your [config file](config.html) to
  something like `0.0.0.0` (optionally with a `:port`). This is the easiest if
  you want to host every time you launch.
- **Command line.** Launch Enu with `--listen`, optionally followed by an
  address. With no address it listens on `0.0.0.0`.
- **Environment variable.** Set `ENU_LISTEN_ADDRESS` before launching.

If no port is given, Enu uses `9632`. Other players then connect using your
computer's IP address or hostname.

## Joining a world

To join someone else's server, use any of:

- The **Connect** field in the [Settings](settings.html) panel: type the host's
  address and press Connect.
- `connect_address` in your [config file](config.html).
- The `--connect <address>` command line flag.
- The `ENU_CONNECT_ADDRESS` environment variable.

Set your [player color](settings.html) so your friends can tell who's who.
