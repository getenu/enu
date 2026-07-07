# Install

Download from 
[https://github.com/dsrw/enu/releases](https://github.com/dsrw/enu/releases). 
The Windows version isn't signed, and UAC will warn that it's untrusted. This 
will be fixed in a future release.

# Build and Run

```console
$ atlas install && atlas rep
$ nim prereqs
$ nim build
$ nim import_assets
$ nim start
```

## Notes

Enu requires a custom Godot version, which lives in `vendor/godot`. This will 
be fetched and built as part of `nim prereqs`.

See [Compiling Godot](https://docs.godotengine.org/en/3.5/development/compiling/index.html).
