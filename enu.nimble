import std/[strformat, strutils, strscans, os, json, sequtils]

const
  (target, lib_ext, exe_ext) =
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
  cpu = if host_cpu == "arm64": "arm64" else: "x86_64"
  generated_dir = "generated/godotapi"
  api_json = "api.json"
  generator = "tools/build_helpers"
  godot_build_url =
    "https://docs.godotengine.org/en/stable/development/compiling/index.html"
  gcc_dlls = ["libgcc_s_seh-1.dll", "libwinpthread-1.dll"]
  nim_dlls = ["pcre64.dll"]
  godot_opts = "target=editor"
  # CI builds without dev_build for smaller, optimized binaries
  is_ci = get_env("CI") != "" or get_env("GITHUB_ACTIONS") != ""
  build_state_dir = ".build_state"

version = "0.2.95"
author = "Scott Wadden"
description = "Logo-like DSL for Godot"
license = "MIT"
install_files = @["enu.nim"]
bin_dir = "app/extension/lib"
src_dir = "app/extension"
bin = @["enu" & lib_ext]
package_name = "enu"

requires "https://github.com/getenu/model_citizen 0.19.6",
  "https://github.com/dsrw/nanoid.nim 0.2.1",
  "https://github.com/godot-nim/gdext-nim 0.15.0",
  "https://github.com/godot-nim/gdext-nim?subdir=coronation 0.1.0",
  "https://github.com/treeform/pretty", "cligen", "chroma", "markdown",
  "chronicles", "dotenv", "nimibook", "metrics#51f1227", "zippy", "nph"

let git_version = static_exec("git describe --tags HEAD").strip

# Include build utilities
include "build.nim"

# Tasks

task ios_prereqs, "Build godot for ios":
  with_dir "vendor/pcre":
    exec "./configure  --host=arm-apple-darwin10 --target=arm-apple-darwin10"
    exec "make"
  build_godot(target = "iphone", cpu = "arm64")

task ios, "Build ios":
  exec &"{gen()} write_export_presets --enu_version {git_version}"
  exec &"{godot_bin()} --path app --export-pack \"ios\" " & "ios"

task build_godot, "Build godot":
  build_godot()

task build_headless, "build headless godot":
  build_godot(target = "linuxbsd use_static_cpp=no")

task test, "run godot tests":
  exec "nim c tests/godot/tnode_factories"
  cd "tests/godot/app"
  exec this_dir() /
    &"vendor/godot/bin/godot_server.osx.opt.tools.{cpu} --quiet --script tests/tests.gdns"

task prereqs, "Build godot, download fonts, generate bindings and stdlib":
  verify_envrc_paths()
  build_godot()
  download_fonts()
  copy_fonts()
  gen_binding_and_copy_stdlib()
  gen_godot_bindings()

task import_assets,
  "Import Godot assets. Only required if you're not using the Godot editor":
  p "Importing assets..."
  exec godot_bin() & " app/project.godot --editor --quit"

task clean, "Remove files produced by build":
  rm_dir generated_dir
  rm_dir ".nimcache"

task edit_then_quit, "Edit project in Godot":
  exec godot_bin() & " --verbose --quit-after 500 app/project.godot &"

task edit, "Edit project in Godot":
  exec godot_bin() & " app/project.godot &"

task start, "Run Enu":
  cd "app"
  var cmd = godot_bin() & " --verbose --quit-after 500 scenes/game.tscn"
  let args = command_line_params().filter_it(it.starts_with("--")).join(" ")
  start(args)

task build_and_start, "Build and start":
  exec "nimble build"
  start_task()

task gen, "Generate build_helpers":
  discard gen()

task build_extension, "Build the gdextension":
  p "Building gdextension..."
  let output_lib =
    case host_os
    of "windows": "lib/libEnugame.windows.debug.dll"
    of "macosx": "lib/libEnugame.macos.debug.dylib"
    else: "lib/libEnugame.linux.debug.so"
  with_dir "app/extension":
    exec &"nim c --app:lib --out:{output_lib} enu.nim"

task generate_bindings, "Generate Godot extension API bindings":
  p "Generating Godot extension API bindings..."
  let extension_api_json = "extension_api.json"
  let generated_dir = "generated"
  rm_dir generated_dir
  mk_dir generated_dir

  with_dir(generated_dir):
    exec &"{godot_bin()} --headless --dump-extension-api"

  exec &"nimbledeps/bin/coronation --apisource:{generated_dir}/{extension_api_json} --ifcesource:vendor/godot/core/extension/gdextension_interface.h --outdir:{generated_dir}"

task start_headless, "Run Enu":
  build_extension_task()
  cd "app"
  exec godot_bin() & " --headless --quit-after 1 --verbose scenes/game.tscn"

task dist_prereqs, "Build godot debug and release versions, and download fonts":
  verify_envrc_paths()
  p "Building distribution prereqs..."

  # Build editor (with dev_build locally, without in CI)
  if target == "linuxbsd":
    build_godot(target = "linuxbsd")
  else:
    build_godot()

  download_fonts()

  # Build release templates (never use dev_build for clean, optimized binaries)
  let release_opts = "target=template_release"
  build_godot(cpu = "x86_64", opts = release_opts)
  when host_os == "macosx":
    build_godot(cpu = "arm64", opts = release_opts)

task dist_package, "Build distribution binaries":
  p "Packaging distribution..."
  copy_fonts()
  rm_dir "dist"
  mk_dir "dist"

  when host_os == "windows":
    gen_binding_and_copy_stdlib()
    let release_bin =
      make_godot_bin_path(target, "template_release", cpu, false)
    let root = &"dist/enu-{git_version}"
    mk_dir root
    exec "strip " & release_bin
    cp_file release_bin, root & "/enu.exe"
    exec &"ResourceHacker -open {root}/enu.exe -save {root}/enu.exe -action addoverwrite -res media/enu_icon.ico -mask ICONGROUP,GODOT_ICON"
    exec &"{gen()} write_export_presets --enu_version {git_version}"

    let pck_path = &"{this_dir()}/{root}/enu.pck"
    exec &"{godot_bin()} --verbose --path app --export-pack \"win\" " & pck_path

    exec "nimble build -d:release -d:dist"
    cp_file "app/enu.dll", root & "/enu.dll"
    find_and_copy_dlls mingw_path(), root, gcc_dlls
    find_and_copy_dlls get_current_compiler_exe().parent_dir, root, nim_dlls
    copy_vmlib "vmlib", root & "/vmlib"
    exec &"iscc /DVersion={git_version} installer/enu.iss"
    with_dir "dist":
      exec &"zip -r enu-{git_version}-windows-x64.zip enu-{git_version}"
  elif host_os == "macosx":
    gen_binding_and_copy_stdlib()

    exec "cp -r installer/Enu.app dist/Enu.app"
    exec "mkdir -p dist/Enu.app/Contents/MacOS"
    exec "mkdir -p dist/Enu.app/Contents/Frameworks"
    exec &"{gen()} write_export_presets --enu_version {git_version}"
    exec &"{gen()} write_info_plist --enu_version {git_version}"

    var release_bin =
      make_godot_bin_path(target, "template_release", "x86_64", false)
    exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.x86_64"
    nim_build_mac "x86_64", "amd64"

    release_bin =
      make_godot_bin_path(target, "template_release", "arm64", false)
    exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.arm64"
    nim_build_mac "arm64", "arm64"

    if not "dist_config.json".file_exists:
      exec &"cp dist_config.example.json dist_config.json"

    let config = read_file("dist_config.json").parse_json
    let pck_path = this_dir() & "/dist/Enu.app/Contents/Resources/Enu.pck"

    exec &"{godot_bin()} --path app --export-pack \"mac\" " & pck_path

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

    let package_name = &"enu-{git_version}.dmg"
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
  elif host_os == "linux":
    gen_binding_and_copy_stdlib("linuxbsd")
    let release_bin =
      make_godot_bin_path(target, "template_release", cpu, false)
    let root = &"dist/enu-{git_version}"
    mk_dir root & "/bin"
    mk_dir root & "/lib"
    exec "nimble build -d:release -d:dist"
    exec "strip " & release_bin
    cp_file release_bin, root & "/bin/enu"
    cp_file "app/enu.so", root & "/lib/enu.so"
    copy_vmlib "vmlib", root & "/lib/vmlib"
    exec "chmod +x " & root & "/bin/enu"
    exec &"{gen()} write_export_presets --enu_version {git_version}"
    let pck_path = this_dir() & "/" & root & "/enu.pck"
    exec &"{godot_bin(\"linuxbsd\")} --verbose --path app --export-pack \"linuxbsd\" " &
      pck_path
    with_dir "dist":
      exec &"tar -czvf enu-{git_version}-linux-x64.tar.gz enu-{git_version}"

    let app_dir = "dist/Enu.AppDir"
    exec &"cp -r installer/Enu.AppDir {app_dir}"
    exec &"cp -r {root}/bin {app_dir}/bin"
    exec &"cp -r {root}/lib {app_dir}/lib"
    exec &"cp {root}/enu.pck {app_dir}/bin/enu.pck"

    with_dir("dist"):
      exec "curl -OJL https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
      exec "chmod a+x appimagetool-x86_64.AppImage"
      exec &"./appimagetool-x86_64.AppImage Enu.AppDir enu-{git_version}-x86_64.AppImage"
  else:
    quit &"dist is currently unsupported on {host_os}"

task dist, "Build distribution":
  dist_prereqs_task()
  dist_package_task()

task docs, "Build docs":
  exec "rm -rf dist/docs"
  with_dir "docs":
    exec "nim r book.nim init"
    exec "nim r book.nim build"
  exec "cp -r docs/book/assets dist/docs"
  exec "cp media/*.{png,webp} dist/docs/assets"

task export_docs, "Build docs and copy them to ../enu-site/docs":
  docs_task()
  exec "rm -rf ../enu-site/docs"
  exec "cp -r dist/docs ../enu-site"

task format, "Format code with nph (skip src/eval.nim)":
  p "Formatting code with nph..."
  exec "find src -name '*.nim' ! -name 'eval.nim' -exec nph {} +"
  exec "find vmlib/enu -name '*.nim' -exec nph {} +"
  exec "find vmlib/worlds -name '*.nim' -exec nph {} +"
  p "Formatting complete!"

task screenshot, "Take a screenshot of Enu":
  start("--screenshot")

task build_all, "Complete build: setup, prereqs, import_assets, build":
  p "Running complete build..."
  exec nimble_exe & " setup"
  prereqs_task()
  import_assets_task()
  exec nimble_exe & " build"
  p "Build complete!"

task dist_all, "Complete distribution build: setup, dist_prereqs, dist_package":
  p "Running complete distribution build..."
  exec nimble_exe & " setup"
  dist_prereqs_task()
  dist_package_task()
  p "Distribution build complete!"
