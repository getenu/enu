## Build system utilities for Enu
## This file contains all build-related procedures and is included by enu.nimble

var generator_path = ""

proc make_godot_bin_path(
    platform: string, build_target: string, arch: string, use_dev: bool
): string =
  let dev_suffix = if use_dev: ".dev" else: ""
  let opt_suffix = if build_target == "template_release": ".opt" else: ""
  result =
    &"vendor/godot/bin/godot.{platform}.{build_target}{opt_suffix}{dev_suffix}.{arch}{exe_ext}"

proc godot_bin(target = target): string =
  # Try dev build first (local), then non-dev (CI)
  let dev_path =
    this_dir() & "/" & make_godot_bin_path(target, "editor", cpu, true)
  let non_dev_path =
    this_dir() & "/" & make_godot_bin_path(target, "editor", cpu, false)

  if file_exists(dev_path):
    result = dev_path
  elif file_exists(non_dev_path):
    result = non_dev_path
  else:
    # Return expected path for better error messages
    result = if is_ci: non_dev_path else: dev_path

proc gen(): string =
  if generator_path == "":
    exec &"nim c -d:ssl {generator}"
    generator_path = find_exe generator
  generator_path

proc p(msg: varargs[string, `$`]) =
  let msg = msg.join
  let underline = "=".repeat(msg.len)
  echo ""
  if host_os == "windows":
    echo msg
    echo underline
  else:
    echo "\e[1;34m" & msg
    echo underline & "\e[00m"
  echo ""

proc get_submodule_sha(submodule_path: string): string =
  ## Get the current commit SHA of a git submodule
  gorge(&"git -C {submodule_path} rev-parse HEAD").strip

proc get_godot_build_state_key(target, cpu, opts: string): string =
  ## Generate a unique state key for a Godot build configuration
  let godot_sha = get_submodule_sha("vendor/godot")
  let voxel_sha = get_submodule_sha("vendor/modules/voxel")
  let dev_flag = if not is_ci: "dev" else: "nodev"
  result = &"{godot_sha}-{voxel_sha}-{target}-{cpu}-{opts}-{dev_flag}"

proc get_godot_state_file(target, cpu, opts: string): string =
  &"{build_state_dir}/godot_{target}_{cpu}_{opts.replace('=', '_').replace(' ', '_')}"

proc needs_godot_build(target, cpu, opts: string): bool =
  let state_file = get_godot_state_file(target, cpu, opts)
  let bin_path = make_godot_bin_path(
    target,
    if opts.contains("template_release"): "template_release" else: "editor",
    cpu,
    not is_ci,
  )

  # Need build if binary doesn't exist
  if not file_exists(bin_path):
    return true

  # Need build if state file doesn't exist
  if not file_exists(state_file):
    return true

  # Need build if state has changed
  let current_state = get_godot_build_state_key(target, cpu, opts)
  let saved_state = read_file(state_file).strip
  return current_state != saved_state

proc save_godot_build_state(target, cpu, opts: string) =
  mk_dir build_state_dir
  let state_file = get_godot_state_file(target, cpu, opts)
  let state_key = get_godot_build_state_key(target, cpu, opts)
  write_file(state_file, state_key)

proc needs_fonts_download(): bool =
  let state_file = &"{build_state_dir}/fonts_downloaded"

  # Check if fonts directory exists and has content
  if not dir_exists("fonts"):
    return true

  # Check if state file exists
  if not file_exists(state_file):
    return true

  # Could check specific files exist, for now just trust the state file
  return false

proc save_fonts_state() =
  mk_dir build_state_dir
  write_file(&"{build_state_dir}/fonts_downloaded", "done")

proc build_godot(target = target, cpu = cpu, opts = godot_opts) =
  # Check if build is needed
  if not needs_godot_build(target, cpu, opts):
    let state_file = get_godot_state_file(target, cpu, opts)
    p &"Godot already built for {target}/{cpu} ({opts}), skipping..."
    when host_os != "windows":
      echo "\e[00m  To force rebuild: rm " & state_file & "\n"
    else:
      echo "  To force rebuild: rm " & state_file & "\n"
    return

  p "Building Godot..."
  exec "git submodule update --init --recursive"
  when host_os == "macosx":
    with_dir "vendor/godot":
      exec "./misc/scripts/install_vulkan_sdk_macos.sh"

  let scons = find_exe "scons"
  if scons == "":
    quit &"*** scons not found on path, and is required to build Godot. See {godot_build_url} ***"

  # Local builds use dev_build for debug symbols, CI uses optimized builds
  let dev_flag = if not is_ci: " dev_build=yes" else: ""

  with_dir "vendor/godot":
    when host_os == "macosx":
      exec &"{scons} custom_modules=../modules platform={target} arch={cpu} macos_deployment_target=10.15 use_volk=yes {opts}{dev_flag}"
    else:
      exec &"{scons} custom_modules=../modules platform={target} arch={cpu} {opts}{dev_flag}"

  # Save state after successful build
  save_godot_build_state(target, cpu, opts)

proc find_and_copy_dlls(dep_path, dest: string, dlls: varargs[string]) =
  for dep in dlls:
    cp_file dep_path.join_path(dep), join_path(dest, dep)

proc copy_fonts() =
  p "Copying fonts..."
  when host_os == "macosx":
    with_dir "fonts/mono/SFMonoFonts.pkg/Payload/Library/Fonts":
      let dest = "../../../../../../app/themes"
      cp_file "SF-Mono-Regular.otf", dest / "mono.otf"
      cp_file "SF-Mono-RegularItalic.otf", dest / "mono-italic.otf"
      cp_file "SF-Mono-Bold.otf", dest / "mono-bold.otf"
      cp_file "SF-Mono-BoldItalic.otf", dest / "mono-bold-italic.otf"

    with_dir "fonts/pro/SFProFonts.pkg/Payload/Library/Fonts":
      let dest = "../../../../../../app/themes"
      cp_file "SF-Pro-Text-Regular.otf", dest / "text.otf"
      cp_file "SF-Pro-Text-RegularItalic.otf", dest / "text-italic.otf"
      cp_file "SF-Pro-Text-Bold.otf", dest / "text-bold.otf"
      cp_file "SF-Pro-Text-BoldItalic.otf", dest / "text-bold-italic.otf"

      cp_file "SF-Pro-Display-Regular.otf", dest / "display.otf"
      cp_file "SF-Pro-Display-RegularItalic.otf", dest / "display-italic.otf"
      cp_file "SF-Pro-Display-Bold.otf", dest / "display-bold.otf"
      cp_file "SF-Pro-Display-BoldItalic.otf", dest / "display-bold-italic.otf"
  else:
    with_dir "fonts/Roboto Mono/static":
      let dest = "../../../app/themes"
      cp_file "RobotoMono-Regular.ttf", dest / "mono.otf"
      cp_file "RobotoMono-Italic.ttf", dest / "mono-italic.otf"
      cp_file "RobotoMono-Bold.ttf", dest / "mono-bold.otf"
      cp_file "RobotoMono-BoldItalic.ttf", dest / "mono-bold-italic.otf"

    with_dir "fonts/Roboto":
      let dest = "../../app/themes"
      cp_file "Roboto-Regular.ttf", dest / "text.otf"
      cp_file "Roboto-Italic.ttf", dest / "text-italic.otf"
      cp_file "Roboto-Bold.ttf", dest / "text-bold.otf"
      cp_file "Roboto-BoldItalic.ttf", dest / "text-bold-italic.otf"

      # Roboto doesn't have a display version. Consider using something else here.
      cp_file "Roboto-Regular.ttf", dest / "display.otf"
      cp_file "Roboto-Italic.ttf", dest / "display-italic.otf"
      cp_file "Roboto-Bold.ttf", dest / "display-bold.otf"
      cp_file "Roboto-BoldItalic.ttf", dest / "display-bold-italic.otf"

  with_dir "fonts/fontawesome-free-6.7.2-desktop/otfs":
    let dest = "../../../app/themes"
    cp_file "Font Awesome 6 Free-Solid-900.otf", dest / "icons.otf"

proc download_fonts() =
  if not needs_fonts_download():
    p "Fonts already downloaded, skipping..."
    when host_os != "windows":
      echo &"\e[00m  To force re-download: rm {build_state_dir}/fonts_downloaded\n"
    else:
      echo &"  To force re-download: rm {build_state_dir}/fonts_downloaded\n"
    return

  p "Downloading fonts..."
  rm_dir "fonts"
  mk_dir "fonts"
  with_dir "fonts":
    when host_os == "macosx":
      exec "curl -OJL https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg"
      exec "curl -OJL https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg"
      exec "hdiutil attach SF-Mono.dmg"
      exec "pkgutil --expand-full '/Volumes/SFMonoFonts/SF Mono Fonts.pkg' mono"
      exec "hdiutil detach /Volumes/SFMonoFonts"

      exec "hdiutil attach SF-Pro.dmg"
      exec "pkgutil --expand-full '/Volumes/SFProFonts/SF Pro Fonts.pkg' pro"
      exec "hdiutil detach /Volumes/SFProFonts"
    else:
      exec "curl -Lo Roboto.zip \"https://github.com/mobiledesres/Google-UI-fonts/blob/main/zip/Roboto.zip?raw=true\""
      exec "curl -Lo RobotoMono.zip \"https://github.com/mobiledesres/Google-UI-fonts/blob/main/zip/Roboto%20Mono.zip?raw=true\""
      exec "unzip Roboto.zip"
      exec "unzip -o RobotoMono.zip"

    exec "curl -OJL https://github.com/FortAwesome/Font-Awesome/releases/download/6.7.2/fontawesome-free-6.7.2-desktop.zip"
    exec "unzip -o fontawesome-free-6.7.2-desktop.zip"

  # Save state after successful download
  save_fonts_state()

proc mingw_path(): string =
  var pre, match: string
  let shim_help = gorge_ex("gcc --shimgen-help")
  # chocolatey uses shim exes, so we need to parse shimgen-help to find the real gcc path
  if shim_help.exit_code < 1 and
      shim_help.output.scanf("$+Target: '$+'", pre, match):
    match.parent_dir
  else:
    find_exe("gcc").parent_dir

proc gen_binding_and_copy_stdlib(target = target) =
  if host_os == "windows":
    # Assumes mingw
    find_and_copy_dlls mingw_path(), "app", gcc_dlls
    find_and_copy_dlls get_current_compiler_exe().parent_dir,
      join_path("vendor", "godot", "bin"), nim_dlls
  mk_dir generated_dir
  exec &"{godot_bin(target)} --verbose --gdnative-generate-json-api {join_path generated_dir, api_json}"
  exec &"{gen()} generate_api -d={generated_dir} -j={api_json}"
  exec &"{gen()} copy_stdlib -d=vmlib/stdlib"

proc gen_godot_bindings() =
  p "Generating complete Godot bindings from custom Godot build..."
  exec "nim r tools/generate_godot_bindings.nim"

proc verify_envrc_paths() =
  ## Verify that paths from .envrc are in PATH
  if not file_exists(".envrc"):
    quit "*** .envrc not found. Please ensure .envrc exists and has been loaded with direnv. ***"

  let envrc_content = read_file(".envrc")
  let project_dir = this_dir()
  var missing_paths: seq[string]

  # Parse .envrc for PATH_add lines
  for line in envrc_content.split_lines():
    if line.strip.starts_with("PATH_add "):
      let path_to_add = line.strip[9 ..^ 1].strip
      let full_path = project_dir / path_to_add

      # Check if this path is in the current PATH
      let current_path = get_env("PATH")
      if full_path notin current_path:
        missing_paths.add(full_path)

  if missing_paths.len > 0:
    echo ""
    echo "*** ERROR: Required paths not found in PATH ***"
    echo ""
    echo "The following paths are missing from your PATH:"
    for path in missing_paths:
      echo "  - " & path
    echo ""
    echo "Please add these paths to your PATH, or use direnv to manage them automatically."
    echo "For direnv installation and setup, see: https://direnv.net/docs/installation.html\n\n"
    quit 1

proc start(args = "") =
  cd "app"
  exec(godot_bin() & " --verbose --quit-after 500 scenes/game.tscn " & args)

proc code_sign(id, path: string) =
  exec &"codesign --force -s '{id}' --options runtime {path} -v"

proc copy_vmlib(src, dest: string) =
  cp_dir src, dest

# Helper proc for macOS dist package
proc nim_build_mac(target, cpu: string) =
  rm_dir ".nim_cache"
  let cmd =
    &"nim c --cpu:{cpu} -l:'-target {target}-apple-macos11' " &
    &"-t:'-target {target}-apple-macos11' -d:release -d:dist " &
    &"-o:dist/Enu.app/Contents/Frameworks/enu.dylib.{target} src/enu.nim"
  exec cmd
