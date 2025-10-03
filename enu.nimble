import std/[strformat, strutils, strscans, os, json, os]

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

proc make_godot_bin_path(platform: string, build_target: string, arch: string, use_dev: bool): string =
  let dev_suffix = if use_dev: ".dev" else: ""
  let opt_suffix = if build_target == "template_release": ".opt" else: ""
  result = &"vendor/godot/bin/godot.{platform}.{build_target}{opt_suffix}{dev_suffix}.{arch}{exe_ext}"

proc godot_bin(target = target): string =
  # Try dev build first (local), then non-dev (CI)
  let dev_path = this_dir() & "/" & make_godot_bin_path(target, "editor", cpu, true)
  let non_dev_path = this_dir() & "/" & make_godot_bin_path(target, "editor", cpu, false)

  if file_exists(dev_path):
    result = dev_path
  elif file_exists(non_dev_path):
    result = non_dev_path
  else:
    # Return expected path for better error messages
    result = if is_ci: non_dev_path else: dev_path

var generator_path = ""
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

proc build_godot(target = target, cpu = cpu, opts = godot_opts) =
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

proc find_and_copy_dlls(dep_path, dest: string, dlls: varargs[string]) =
  for dep in dlls:
    cp_file dep_path.join_path(dep), join_path(dest, dep)

proc copy_fonts() =
  p "Coping fonts..."
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

      # Roboto doesn't have a display version. Consider using something else
      # here.
      cp_file "Roboto-Regular.ttf", dest / "display.otf"
      cp_file "Roboto-Italic.ttf", dest / "display-italic.otf"
      cp_file "Roboto-Bold.ttf", dest / "display-bold.otf"
      cp_file "Roboto-BoldItalic.ttf", dest / "display-bold-italic.otf"

  with_dir "fonts/fontawesome-free-6.7.2-desktop/otfs":
    let dest = "../../../app/themes"
    cp_file "Font Awesome 6 Free-Solid-900.otf", dest / "icons.otf"

proc download_fonts() =
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

proc mingw_path(): string =
  var pre, match: string
  let shim_help = gorge_ex("gcc --shimgen-help")
  # chocolatey uses shim exes, so we need to parse shimgen-help to find the real
  # gcc path
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

task prereqs, "Build godot, download fonts, generate bindings and stdlib":
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
  # Support passing additional arguments to start task
  # Usage: nimble start --headless --quit-after 1
  for arg in command_line_params():
    if arg.startsWith("--"):
      cmd = cmd & " " & arg
  exec cmd

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

proc code_sign(id, path: string) =
  exec &"codesign --force -s '{id}' --options runtime {path} -v"

task dist_prereqs, "Build godot debug and release versions, and download fonts":
  p "Buiding distribution prereqs..."

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

proc copy_vmlib(src, dest: string) =
  cp_dir src, dest

task dist_package, "Build distribution binaries":
  p "Packaging distribution..."
  copy_fonts()
  rm_dir "dist"
  mk_dir "dist"

  when host_os == "windows":
    gen_binding_and_copy_stdlib()
    let release_bin = make_godot_bin_path(target, "template_release", cpu, false)
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
    proc nim_build(target, cpu: string) =
      rm_dir ".nim_cache"
      let cmd =
        &"nim c --cpu:{cpu} -l:'-target {target}-apple-macos11' " &
        &"-t:'-target {target}-apple-macos11' -d:release -d:dist " &
        &"-o:dist/Enu.app/Contents/Frameworks/enu.dylib.{target} src/enu.nim"
      exec cmd

    exec "cp -r installer/Enu.app dist/Enu.app"
    exec "mkdir -p dist/Enu.app/Contents/MacOS"
    exec "mkdir -p dist/Enu.app/Contents/Frameworks"
    exec &"{gen()} write_export_presets --enu_version {git_version}"
    exec &"{gen()} write_info_plist --enu_version {git_version}"

    var release_bin = make_godot_bin_path(target, "template_release", "x86_64", false)
    exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.x86_64"
    nim_build "x86_64", "amd64"

    release_bin = make_godot_bin_path(target, "template_release", "arm64", false)
    exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.arm64"
    nim_build "arm64", "arm64"

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
        cp_file universal_lib, "dist/Enu.app/Contents/Frameworks/libMoltenVK.dylib"
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
    let release_bin = make_godot_bin_path(target, "template_release", cpu, false)
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

  # Format src directory (except eval.nim)
  exec "find src -name '*.nim' ! -name 'eval.nim' -exec nph {} +"

  # Format vmlib/enu
  exec "find vmlib/enu -name '*.nim' -exec nph {} +"

  # Format vmlib/worlds
  exec "find vmlib/worlds -name '*.nim' -exec nph {} +"

  p "Formatting complete!"

task screenshot, "Take a screenshot of Enu":
  start_task("--screenshot")

task build_all, "Complete build: setup, prereqs, import_assets, build":
  p "Running complete build..."
  setup_task()
  prereqs_task()
  import_assets_task()
  build_task()
  p "Build complete!"

task dist_all, "Complete distribution build: setup, dist_prereqs, dist_package":
  p "Running complete distribution build..."
  setup_task()
  dist_prereqs_task()
  dist_package_task()
  p "Distribution build complete!"
