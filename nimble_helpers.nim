## Build system utilities for Enu
## This file contains all build-related procedures and is imported by enu.nimble
##
## NOTE: This file is designed to work specifically in nimscript context (from nimble)

import std/[strformat, strutils, strscans, os, json]

proc enu_root*(): string =
  ## Get the Enu project root directory
  ## Works reliably even when nimble runs from temp cache
  ## Derives from the .nimble file location
  current_source_path().parent_dir()

type
  Settings* = object
    target*: string
    lib_ext*: string
    exe_ext*: string
    cpu*: string
    generated_dir*: string
    api_json*: string
    godot_build_url*: string
    gcc_dlls*: seq[string]
    nim_dlls*: seq[string]
    godot_opts*: string
    build_state_dir*: string
    git_version*: string

proc settings*(): Settings =
  ## Build and return settings object
  let (target, lib_ext, exe_ext) =
    case host_os
    of "windows":
      ("windows", ".dll", ".exe")
    of "macosx":
      if get_env("TARGET") == "ios":
        ("iOS", ".a", "")
      else:
        ("macos", ".dylib", "")
    else:
      ("linuxbsd", ".so", "")

  let cpu = if host_cpu == "arm64": "arm64" else: "x86_64"

  result = Settings(
    target: target,
    lib_ext: lib_ext,
    exe_ext: exe_ext,
    cpu: cpu,
    generated_dir: "generated/godotapi",
    api_json: "api.json",
    godot_build_url: "https://docs.godotengine.org/en/stable/development/compiling/index.html",
    gcc_dlls: @["libgcc_s_seh-1.dll", "libwinpthread-1.dll"],
    nim_dlls: @["pcre64.dll"],
    godot_opts: "target=editor",
    build_state_dir: ".build_state",
    git_version: static_exec("git describe --tags HEAD").strip
  )

proc godot_bin*(
    target = "",
    build_target = "editor",
    cpu = "",
    use_dev = ""  # Empty string means "use default based on GODOT_DEV_BUILD env var"
): string =
  let s = settings()
  let actual_target = if target == "": s.target else: target
  let actual_cpu = if cpu == "": s.cpu else: cpu
  let use_dev_build = get_env("GODOT_DEV_BUILD") != ""
  let actual_use_dev = if use_dev == "": use_dev_build else: use_dev == "true"

  let dev_suffix = if actual_use_dev: ".dev" else: ""
  # Note: Godot 4 doesn't use .opt suffix (that was Godot 3)
  let path = &"vendor/godot/bin/godot.{actual_target}.{build_target}{dev_suffix}.{actual_cpu}{s.exe_ext}"
  result = enu_root() & "/" & path

proc p*(msg: varargs[string, `$`]) =
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

proc get_submodule_sha*(submodule_path: string): string =
  ## Get the current commit SHA of a git submodule
  gorge(&"git -C {submodule_path} rev-parse HEAD").strip

proc get_godot_build_state_key*(target, cpu, opts: string): string =
  ## Generate a unique state key for a Godot build configuration
  let s = settings()
  let godot_sha = get_submodule_sha("vendor/godot")
  let voxel_sha = get_submodule_sha("vendor/modules/voxel")
  let use_dev_build = get_env("GODOT_DEV_BUILD") != ""
  let dev_flag = if use_dev_build: "dev" else: "nodev"
  result = &"{godot_sha}-{voxel_sha}-{target}-{cpu}-{opts}-{dev_flag}"

proc get_godot_state_file*(target, cpu, opts: string): string =
  let s = settings()
  &"{s.build_state_dir}/godot_{target}_{cpu}_{opts.replace('=', '_').replace(' ', '_')}"

proc needs_godot_build*(target, cpu, opts: string): bool =
  let s = settings()
  let state_file = get_godot_state_file(target, cpu, opts)
  let build_target = if opts.contains("template_release"): "template_release" else: "editor"
  let bin_path = godot_bin(target, build_target, cpu)

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

proc save_godot_build_state*(target, cpu, opts: string) =
  let s = settings()
  mk_dir s.build_state_dir
  let state_file = get_godot_state_file(target, cpu, opts)
  let state_key = get_godot_build_state_key(target, cpu, opts)
  write_file(state_file, state_key)

proc needs_fonts_download*(): bool =
  let s = settings()
  let state_file = &"{s.build_state_dir}/fonts_downloaded"

  # Check if fonts directory exists and has content
  if not dir_exists("fonts"):
    return true

  # Check if state file exists
  if not file_exists(state_file):
    return true

  # Could check specific files exist, for now just trust the state file
  return false

proc save_fonts_state*() =
  let s = settings()
  mk_dir s.build_state_dir
  write_file(&"{s.build_state_dir}/fonts_downloaded", "done")

proc build_godot*(target = "", cpu = "", opts = "") =
  let s = settings()
  let actual_target = if target == "": s.target else: target
  let actual_cpu = if cpu == "": s.cpu else: cpu
  let actual_opts = if opts == "": s.godot_opts else: opts

  # Check if build is needed
  if not needs_godot_build(actual_target, actual_cpu, actual_opts):
    let state_file = get_godot_state_file(actual_target, actual_cpu, actual_opts)
    p &"Godot already built for {actual_target}/{actual_cpu} ({actual_opts}), skipping..."
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
    quit &"*** scons not found on path, and is required to build Godot. See {s.godot_build_url} ***"

  # Dev builds use dev_build for debug symbols (set GODOT_DEV_BUILD=1 to enable)
  let use_dev_build = get_env("GODOT_DEV_BUILD") != ""
  let dev_flag = if use_dev_build: " dev_build=yes" else: ""

  with_dir "vendor/godot":
    when host_os == "macosx":
      exec &"{scons} custom_modules=../modules platform={actual_target} arch={actual_cpu} macos_deployment_target=10.15 use_volk=yes {actual_opts}{dev_flag}"
    else:
      exec &"{scons} custom_modules=../modules platform={actual_target} arch={actual_cpu} {actual_opts}{dev_flag}"

  # Copy MoltenVK dylib for dynamic Vulkan loading (use_volk)
  when host_os == "macosx":
    # Find the latest installed Vulkan SDK
    let sdk_versions = list_dirs(get_env("HOME") / "VulkanSDK")
    let latest_sdk = sdk_versions[^1]  # Last one (sorted alphabetically = newest version)
    let mvk_dylib = latest_sdk / "macOS/lib/libMoltenVK.dylib"
    cp_file mvk_dylib, "vendor/godot/bin/libMoltenVK.dylib"

  # Save state after successful build
  save_godot_build_state(actual_target, actual_cpu, actual_opts)

proc find_and_copy_dlls*(dep_path, dest: string, dlls: varargs[string]) =
  for dep in dlls:
    cp_file dep_path.join_path(dep), join_path(dest, dep)

proc copy_fonts*() =
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

proc download_fonts*() =
  let s = settings()
  if not needs_fonts_download():
    p "Fonts already downloaded, skipping..."
    when host_os != "windows":
      echo &"\e[00m  To force re-download: rm {s.build_state_dir}/fonts_downloaded\n"
    else:
      echo &"  To force re-download: rm {s.build_state_dir}/fonts_downloaded\n"
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
      when host_os == "windows":
        exec "powershell -Command \"Expand-Archive -Path Roboto.zip -DestinationPath . -Force\""
        exec "powershell -Command \"Expand-Archive -Path RobotoMono.zip -DestinationPath . -Force\""
      else:
        exec "unzip Roboto.zip"
        exec "unzip -o RobotoMono.zip"

    exec "curl -OJL https://github.com/FortAwesome/Font-Awesome/releases/download/6.7.2/fontawesome-free-6.7.2-desktop.zip"
    when host_os == "windows":
      exec "powershell -Command \"Expand-Archive -Path fontawesome-free-6.7.2-desktop.zip -DestinationPath . -Force\""
    else:
      exec "unzip -o fontawesome-free-6.7.2-desktop.zip"

  # Save state after successful download
  save_fonts_state()

proc mingw_path*(): string =
  find_exe("gcc").parent_dir

proc copy_nim_stdlib*() =
  p "Copying Nim stdlib to vmlib..."
  let stdlib = "vendor/nim/lib"
  let destination = "vmlib/stdlib"

  rm_dir destination
  mk_dir destination

  for path in @["core", "pure", "std", "fusion", "system"]:
    cp_dir join_path(stdlib, path), join_path(destination, path)

  for file in @["system.nim", "stdlib.nimble", "system" / "compilation.nim"]:
    cp_file join_path(stdlib, file), join_path(destination, file)

proc gen_godot_bindings*() =
  p "Generating complete Godot bindings from custom Godot build..."
  exec "nim r tools/generate_godot_bindings.nim"

proc verify_paths*() =
  ## Verify that required project paths are in PATH
  ## Calls the appropriate shell script for the platform
  when host_os == "windows":
    exec enu_root() / "tools/verify_paths.bat"
  else:
    exec enu_root() / "tools/verify_paths.sh"

proc start*(args = "") =
  cd "app"
  exec(godot_bin() & " --verbose scenes/game.tscn " & args)

proc code_sign*(id, path: string) =
  exec &"codesign --force -s '{id}' --options runtime {path} -v"

proc copy_vmlib*(src, dest: string) =
  cp_dir src, dest

proc nim_build_mac*(target, cpu: string) =
  rm_dir ".nim_cache"
  # Build to app/extension/lib for gdextension compatibility
  let output_path = &"app/extension/lib/enu.release.{target}.dylib"
  let cmd =
    &"nim c --cpu:{cpu} -l:'-target {target}-apple-macos11' " &
    &"-t:'-target {target}-apple-macos11' -d:release -d:dist " &
    &"--app:lib -o:{output_path} app/extension/enu.nim"
  exec cmd
  # Also copy to dist location for bundling
  cp_file output_path, &"dist/Enu.app/Contents/Frameworks/enu.dylib.{target}"

proc dist_package_windows*() =
  let s = settings()
  let release_bin = godot_bin(build_target = "template_release", use_dev = "false")
  let root = &"dist/enu-{s.git_version}"
  mk_dir root
  exec "strip " & release_bin
  cp_file release_bin, root & "/enu.exe"
  exec &"ResourceHacker -open {root}/enu.exe -save {root}/enu.exe -action addoverwrite -res media/enu_icon.ico -mask ICONGROUP,GODOT_ICON"
  exec &"nim r tools/write_export_presets.nim {s.git_version}"

  let pck_path = &"{enu_root()}/{root}/enu.pck"
  when host_os == "windows":
    exec &"{godot_bin()} --verbose --path app --export-pack \"win\" " & pck_path
  else:
    exec &"{godot_bin()} --headless --verbose --path app --export-pack \"win\" " & pck_path

  # Build release extension for Windows
  let nim_compiler = get_current_compiler_exe()
  exec &"{nim_compiler} c -d:release -d:dist --app:lib -o:app/extension/lib/enu.release.dll app/extension/enu.nim"
  cp_file "app/extension/lib/enu.release.dll", root & "/enu.dll"
  find_and_copy_dlls mingw_path(), root, s.gcc_dlls
  find_and_copy_dlls get_current_compiler_exe().parent_dir, root, s.nim_dlls
  copy_vmlib "vmlib", root & "/vmlib"
  exec &"iscc /DVersion={s.git_version} installer/enu.iss"
  with_dir "dist":
    exec &"zip -r enu-{s.git_version}-windows-x64.zip enu-{s.git_version}"

proc dist_package_macos*() =
  let s = settings()

  exec "cp -r installer/Enu.app dist/Enu.app"
  exec "mkdir -p dist/Enu.app/Contents/MacOS"
  exec "mkdir -p dist/Enu.app/Contents/Frameworks"
  exec &"nim r tools/write_export_presets.nim {s.git_version}"
  exec &"nim r tools/write_info_plist.nim {s.git_version}"

  var release_bin = godot_bin(build_target = "template_release", cpu = "x86_64", use_dev = "false")
  exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.x86_64"
  nim_build_mac "x86_64", "amd64"

  release_bin = godot_bin(build_target = "template_release", cpu = "arm64", use_dev = "false")
  exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.arm64"
  nim_build_mac "arm64", "arm64"

  if not file_exists("dist_config.json"):
    exec "cp dist_config.example.json dist_config.json"

  let config = read_file("dist_config.json").parse_json
  let pck_path = enu_root() & "/dist/Enu.app/Contents/Resources/Enu.pck"

  when host_os == "macosx":
    exec &"{godot_bin()} --path app --export-pack \"mac\" " & pck_path
  else:
    exec &"{godot_bin()} --headless --path app --export-pack \"mac\" " & pck_path

  # Create universal binary for extension lib and copy to dist
  exec "lipo -create app/extension/lib/enu.release.x86_64.dylib app/extension/lib/enu.release.arm64.dylib -output app/extension/lib/enu.release.dylib"
  exec "lipo -create dist/Enu.app/Contents/Frameworks/enu.dylib.x86_64 dist/Enu.app/Contents/Frameworks/enu.dylib.arm64 -output dist/Enu.app/Contents/Frameworks/enu.dylib"
  exec "rm dist/Enu.app/Contents/Frameworks/enu.dylib.*"

  exec "lipo -create dist/Enu.app/Contents/MacOS/Enu.x86_64 dist/Enu.app/Contents/MacOS/Enu.arm64 -output dist/Enu.app/Contents/MacOS/Enu"
  exec "rm dist/Enu.app/Contents/MacOS/Enu.*"

  copy_vmlib "vmlib", "dist/Enu.app/Contents/Resources/vmlib"

  # Copy MoltenVK dylib for dynamic Vulkan loading (use_volk)
  let vulkan_sdk = get_env("VULKAN_SDK", "/usr/local")
  let mvk_framework = vulkan_sdk / "macOS/lib/MoltenVK.xcframework"

  if dir_exists(mvk_framework):
    # Try universal binary first
    let universal_lib = mvk_framework / "macos-arm64_x86_64/libMoltenVK.dylib"
    if file_exists(universal_lib):
      cp_file universal_lib,
        "dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"
    else:
      # Fall back to separate architectures and combine with lipo
      let x86_lib = mvk_framework / "macos-x86_64/libMoltenVK.dylib"
      let arm_lib = mvk_framework / "macos-arm64/libMoltenVK.dylib"

      if file_exists(x86_lib) and file_exists(arm_lib):
        exec &"lipo -create {x86_lib} {arm_lib} -output dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"
      elif file_exists(x86_lib):
        cp_file x86_lib, "dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"
      elif file_exists(arm_lib):
        cp_file arm_lib, "dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"

  if config["sign"].get_bool:
    let id = config["id"].get_str
    if "keychain" in config:
      let keychain = config["keychain"].get_str
      let password = config["keychain-password"].get_str
      exec &"security unlock-keychain -p \"{password}\" {keychain}"
    code_sign(id, "dist/Enu.app/Contents/Frameworks/enu.dylib")
    if file_exists("dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"):
      code_sign(id, "dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib")
    code_sign(id, "dist/Enu.app")

  let package_name = &"enu-{s.git_version}.dmg"
  if config["package"].get_bool:
    exec "ln -s /Applications dist/Applications"
    exec &"hdiutil create {package_name} -ov -volname Enu -fs HFS+ -srcfolder dist"
    exec &"mv {package_name} dist"

  if config["notarize"].get_bool:
    if "notarize-profile" in config:
      let profile = config["notarize-profile"].get_str
      exec &"xcrun notarytool submit \"dist/{package_name}\" --keychain-profile \"{profile}\" --wait"
    else:
      let
        username = config["notarize-username"].get_str
        password = config["notarize-password"].get_str

      exec &"xcrun altool --notarize-app --primary-bundle-id 'com.getenu.enu'  --username '{username}' --password '{password}' --file dist/{package_name}"

proc dist_package_linux*() =
  let s = settings()
  let release_bin = godot_bin(build_target = "template_release", use_dev = "false")
  let root = &"dist/enu-{s.git_version}"
  mk_dir root & "/bin"
  mk_dir root & "/lib"
  # Build release extension for Linux
  let nim_compiler = get_current_compiler_exe()
  exec &"{nim_compiler} c -d:release -d:dist --app:lib -o:app/extension/lib/enu.release.so app/extension/enu.nim"
  exec "strip " & release_bin
  cp_file release_bin, root & "/bin/enu"
  cp_file "app/extension/lib/enu.release.so", root & "/lib/enu.so"
  copy_vmlib "vmlib", root & "/lib/vmlib"
  exec "chmod +x " & root & "/bin/enu"
  exec &"nim r tools/write_export_presets.nim {s.git_version}"
  let pck_path = enu_root() & "/" & root & "/enu.pck"
  exec &"{godot_bin(\"linuxbsd\")} --headless --verbose --path app --export-pack \"linuxbsd\" " &
    pck_path
  with_dir "dist":
    exec &"tar -czvf enu-{s.git_version}-linux-x64.tar.gz enu-{s.git_version}"

  let app_dir = "dist/Enu.AppDir"
  exec &"cp -r installer/Enu.AppDir {app_dir}"
  exec &"cp -r {root}/bin {app_dir}/bin"
  exec &"cp -r {root}/lib {app_dir}/lib"
  exec &"cp {root}/enu.pck {app_dir}/bin/enu.pck"

  with_dir("dist"):
    exec "curl -OJL https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    exec "chmod a+x appimagetool-x86_64.AppImage"
    exec &"./appimagetool-x86_64.AppImage Enu.AppDir enu-{s.git_version}-x86_64.AppImage"

proc do_dist_prereqs*() =
  let s = settings()
  verify_paths()
  p "Building distribution prereqs..."

  # Build editor (with dev_build locally, without in CI)
  if s.target == "linuxbsd":
    build_godot(target = "linuxbsd")
  else:
    build_godot()

  download_fonts()

  # Build release templates (never use dev_build for clean, optimized binaries)
  let release_opts = "target=template_release"
  build_godot(cpu = "x86_64", opts = release_opts)
  when host_os == "macosx":
    build_godot(cpu = "arm64", opts = release_opts)

proc do_dist_package*() =
  p "Packaging distribution..."
  copy_fonts()
  rm_dir "dist"
  mk_dir "dist"

  when host_os == "windows":
    dist_package_windows()
  elif host_os == "macosx":
    dist_package_macos()
  elif host_os == "linux":
    dist_package_linux()
  else:
    quit &"dist is currently unsupported on {host_os}"
