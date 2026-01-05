# Linux Cross-Architecture Builds

The build system supports building for different architectures on Linux. Pass `amd64` or `arm64` to `nim prereqs` to set the target architecture. The choice is persisted in `.build_arch` and automatically used by subsequent `nim build` commands.

```bash
# Build for amd64 (x86_64)
nim prereqs amd64
nim build

# Build for arm64 (native on ARM hosts)
nim prereqs arm64
nim build
```

The build system automatically:
- Sets `PKG_CONFIG_PATH` for cross-compilation
- Uses the appropriate cross-compiler (`x86_64-linux-gnu-gcc/g++`)
- Disables incompatible modules (webm) when cross-compiling
- Passes the correct `--cpu` flag to the Nim compiler

## Required Packages

### For amd64 builds on ARM64 host

```bash
# Cross-compiler
sudo apt install gcc-x86-64-linux-gnu g++-x86-64-linux-gnu

# X11 and OpenGL dev packages (amd64)
sudo apt install libx11-dev:amd64 libxcursor-dev:amd64 libxinerama-dev:amd64 \
  libxext-dev:amd64 libxrandr-dev:amd64 libxrender-dev:amd64 libxi-dev:amd64 \
  libgl1-mesa-dev:amd64

# Runtime library for Godot (amd64)
sudo apt install libpcre3:amd64
```

### For arm64 native builds

```bash
sudo apt install libx11-dev:arm64 libxcursor-dev:arm64 libxinerama-dev:arm64 \
  libxext-dev:arm64 libxrandr-dev:arm64 libxrender-dev:arm64 libxi-dev:arm64 \
  libgl1-mesa-dev:arm64
```

## Rosetta Setup for x86_64 Nim on ARM64 Linux (Parallels VM)

If your Nim compiler is x86_64 and you're on ARM64, register Rosetta with binfmt:

```bash
echo ':RosettaLinux:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/media/psf/RosettaLinux/rosetta:OCF' | sudo tee /proc/sys/fs/binfmt_misc/register
```

To make this persistent, enable the `rosetta-binfmt` systemd service.
