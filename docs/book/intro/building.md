# Install

Most people should just download Enu and play. Grab the latest release for
your platform from the
[releases page](https://github.com/getenu/enu/releases), open it, and you're
ready to build.

That's all you need. Everything below is for people who want to work on Enu
itself, not for regular players.

# Building from source

You only need to build Enu if you want to change it or contribute to it. If you
just want to play, download a release above instead.

```console
$ atlas install && atlas rep
$ nim prereqs
$ nim build
$ nim import_assets
$ nim start
```

## Notes

Enu requires a custom Godot version, which lives in `vendor/godot`. It's
fetched and built as part of `nim prereqs`.

See [Compiling Godot](https://docs.godotengine.org/en/3.5/development/compiling/index.html).
