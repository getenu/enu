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
        ("osx", ".dylib", "")
    else:
      ("x11", ".so", "")
  arch_file = ".build_arch"

let machine_arch = gorge("uname -m").strip

proc parse_arch_arg(): string =
  for arg in command_line_params():
    if arg in ["amd64", "x86_64", "x64", "64", "arm64", "aarch64"]:
      return arg
  ""

proc get_persisted_arch(): string =
  if file_exists(arch_file):
    read_file(arch_file).strip
  else:
    ""

proc save_arch(arch: string) =
  write_file(arch_file, arch)

proc determine_cpu(): string =
  # Only apply arch logic on Linux
  if host_os != "linux":
    return if host_cpu == "arm64": "arm64" else: "64"

  let arg_arch = parse_arch_arg()
  if arg_arch != "":
    # Normalize arch names
    if arg_arch in ["amd64", "x86_64", "x64", "64"]:
      return "64"
    elif arg_arch in ["arm64", "aarch64"]:
      return "arm64"
    else:
      return arg_arch

  let persisted = get_persisted_arch()
  if persisted != "":
    return persisted

  # Default to native arch
  if machine_arch == "aarch64": "arm64" else: "64"

let
  cpu = determine_cpu()
  cross_compile =
    host_os == "linux" and machine_arch == "aarch64" and cpu == "64"
  cross_compile_opts =
    if cross_compile:
      "CC=x86_64-linux-gnu-gcc CXX=x86_64-linux-gnu-g++ module_webm_enabled=no "
    else:
      ""

# Set PKG_CONFIG_PATH for cross-compilation
if cross_compile:
  put_env("PKG_CONFIG_PATH", "/usr/lib/x86_64-linux-gnu/pkgconfig")

let
  generated_dir = "generated/godotapi"
  api_json = "api.json"
  generator = "tools/build_helpers"
  godot_build_url =
    "https://docs.godotengine.org/en/stable/development/compiling/index.html"
  gcc_dlls = ["libgcc_s_seh-1.dll", "libwinpthread-1.dll"]
  nim_dlls = ["pcre64.dll"]
  godot_opts = "target=debug"

let git_version = static_exec("git describe --tags HEAD").strip

proc godot_bin(target = target): string =
  result = this_dir() & &"/vendor/godot/bin/godot.{target}.tools.{cpu}{exe_ext}"
  if target == "server":
    result = result.replace("godot.server", "godot_server.x11")

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

proc build_godot(target = target, cpu = cpu, opts = godot_opts, force = false) =
  p "Building Godot..."
  if force or not file_exists("vendor/godot/.git"):
    exec "git submodule update --init"
  let
    scons = find_exe "scons"
    cores = gorge(gen() & " core_count")
  if scons == "":
    quit &"*** scons not found on path, and is required to build Godot. See {godot_build_url} ***"
  with_dir "vendor/godot":
    exec &"{scons} custom_modules=../modules platform={target} arch={cpu} {cross_compile_opts}{opts} -j{cores}"

task ios_prereqs, "Build godot for ios":
  with_dir "vendor/pcre":
    exec "./configure  --host=arm-apple-darwin10 --target=arm-apple-darwin10"
    exec "make"

  build_godot(target = "iphone", cpu = "arm64")

task ios, "Build ios":
  exec &"{gen()} write_export_presets --enu_version {git_version}"
  exec &"{godot_bin()} --path app --export-pack \"ios\" " & "ios"

const arch_args = ["amd64", "x86_64", "x64", "64", "arm64", "aarch64"]

task build, "Build enu":
  when host_os == "linux":
    echo &"Target architecture: {cpu}" &
      (if cross_compile: " (cross-compiling)" else: "")
  let
    output = "app/enu" & lib_ext
    params = command_line_params()[1 ..^ 1].filterIt(it notin arch_args)
    extra =
      if params.len > 0:
        " " & params.join(" ")
      else:
        ""
    cross_opts =
      if cross_compile:
        " --cpu:amd64 --gcc.exe:x86_64-linux-gnu-gcc --gcc.linkerexe:x86_64-linux-gnu-gcc"
      elif cpu == "arm64" and target == "x11":
        " --cpu:arm64"
      else:
        ""
  exec &"nim c -o:{output}{cross_opts}{extra} src/enu.nim"

task build_godot, "Build godot. Use --force to re-init submodules":
  build_godot(force = "--force" in command_line_params())

task build_headless, "build headless godot":
  build_godot(target = "server use_static_cpp=no")

task unit_tests, "run unit tests":
  exec "nim c -r tests/unit/script_ctx_test"
  exec "nim c -r tests/unit/serializers_test"

task vm_tests, "run VM script tests":
  exec "nim c -r tests/vm/runner"

task godot_tests, "run godot tests":
  exec "nim c tests/godot/tnode_factories"
  cd "tests/godot/app"
  exec this_dir() /
    &"vendor/godot/bin/godot_server.osx.opt.tools.{cpu} --quiet --script tests/tests.gdns"

task world_tests,
  "run in-world tests (headless for server build, dist for dist build)":
  let
    test_level = this_dir() / "vmlib/worlds/tests/unit-tests"
    params = command_line_params()
    headless = "headless" in params
    use_dist = "dist" in params

  let bin =
    if use_dist:
      case host_os
      of "macosx":
        this_dir() / "dist/Enu.app/Contents/MacOS/Enu"
      of "linux":
        this_dir() / &"dist/enu-{git_version}/bin/enu"
      of "windows":
        this_dir() / &"dist/enu-{git_version}/enu.exe"
      else:
        quit &"--dist not supported on {host_os}"
    elif headless:
      case host_os
      of "linux":
        godot_bin("server")
      else:
        quit "Headless tests are only supported on Linux (Godot 4 will support all platforms)"
    else:
      godot_bin()

  let cmd =
    if use_dist:
      bin & " --level-dir " & test_level & " --enu-test --temp-workdir"
    else:
      "cd app && " & bin & " --level-dir " & test_level &
        " --enu-test scenes/game.tscn --temp-workdir"

  exec cmd

task test, "run all tests":
  var failed: seq[string]

  echo "\n=== Running unit tests ===\n"
  let unit_result = gorge_ex("nim unit_tests")
  echo unit_result.output
  if unit_result.exit_code != 0:
    failed.add "unit_tests"

  echo "\n=== Running VM tests ===\n"
  let vm_result = gorge_ex("nim vm_tests")
  echo vm_result.output
  if vm_result.exit_code != 0:
    failed.add "vm_tests"

  echo "\n=== Running world tests ===\n"
  let world_result = gorge_ex("nim world_tests")
  echo world_result.output
  if world_result.exit_code != 0:
    failed.add "world_tests"

  echo "\n=== Test Summary ===\n"
  if failed.len > 0:
    echo "FAILED: " & failed.join(", ")
    quit 1
  else:
    echo "All tests passed!"

proc find_and_copy_dlls(dep_path, dest: string, dlls: varargs[string]) =
  for dep in dlls:
    cp_file dep_path.join_path(dep), join_path(dest, dep)

proc copy_fonts() =
  p "Copying fonts..."
  let dest = "app/themes"

  # IBM Plex Mono - monospace font (same on all platforms, OFL licensed)
  with_dir "fonts/ibm-plex-mono/ibm-plex-mono/fonts/complete/otf":
    cp_file "IBMPlexMono-Regular.otf", "../../../../../" & dest / "mono.otf"
    cp_file "IBMPlexMono-Italic.otf",
      "../../../../../" & dest / "mono-italic.otf"
    cp_file "IBMPlexMono-Bold.otf", "../../../../../" & dest / "mono-bold.otf"
    cp_file "IBMPlexMono-BoldItalic.otf",
      "../../../../../" & dest / "mono-bold-italic.otf"

  # Jost - proportional font (same on all platforms, OFL licensed)
  with_dir "fonts/jost/Jost-master/fonts/otf":
    cp_file "Jost-400-Book.otf", "../../../../../" & dest / "text.otf"
    cp_file "Jost-400-BookItalic.otf",
      "../../../../../" & dest / "text-italic.otf"
    cp_file "Jost-700-Bold.otf", "../../../../../" & dest / "text-bold.otf"
    cp_file "Jost-700-BoldItalic.otf",
      "../../../../../" & dest / "text-bold-italic.otf"

    cp_file "Jost-400-Book.otf", "../../../../../" & dest / "display.otf"
    cp_file "Jost-400-BookItalic.otf",
      "../../../../../" & dest / "display-italic.otf"
    cp_file "Jost-700-Bold.otf", "../../../../../" & dest / "display-bold.otf"
    cp_file "Jost-700-BoldItalic.otf",
      "../../../../../" & dest / "display-bold-italic.otf"

  with_dir "fonts/fontawesome-free-6.7.2-desktop/otfs":
    cp_file "Font Awesome 6 Free-Solid-900.otf",
      "../../../" & dest / "icons.otf"

proc verify_fonts() =
  ## Fonts are now committed to the repo (OFL licensed).
  ## This just verifies they exist.
  p "Verifying fonts..."
  let required = [
    "fonts/ibm-plex-mono/ibm-plex-mono/fonts/complete/otf/IBMPlexMono-Regular.otf",
    "fonts/jost/Jost-master/fonts/otf/Jost-400-Book.otf",
    "fonts/fontawesome-free-6.7.2-desktop/otfs/Font Awesome 6 Free-Solid-900.otf",
  ]
  for path in required:
    if not file_exists(path):
      raise new_exception(IOError, "Missing font: " & path)

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

task extract_dlls, "Extract Nim DLLs to compiler bin directory (Windows only)":
  when host_os == "windows":
    p "Extracting Nim DLLs..."
    let
      nim_bin = get_current_compiler_exe().parent_dir
      dlls_url = "https://nim-lang.org/download/dlls.zip"
      dlls_zip = "dlls.zip"

    with_dir nim_bin:
      exec &"curl -Lo {dlls_zip} {dlls_url}"
      exec &"unzip -o {dlls_zip}"
      rm_file dlls_zip

    echo &"DLLs extracted to: {nim_bin}"
  else:
    echo "extract_dlls is only needed on Windows"

task setup_checksums, "setup checksum module in nim dependency":
  p "Setting up Nim checksums..."
  with_dir "deps/Nim.getenu.github.com":
    exec "nim c koch"
    let koch_cmd = if host_os == "windows": "koch.exe" else: "./koch"
    exec koch_cmd & " checksums"

task prereqs,
  "Build godot, verify fonts, generate binding and stdlib. Use 'amd64' or 'arm64' to set target. Use --force to re-init submodules":
  # Persist arch if specified
  when host_os == "linux":
    if parse_arch_arg() != "":
      save_arch(cpu)
    echo &"Target architecture: {cpu}" &
      (if cross_compile: " (cross-compiling)" else: "")
  exec "atlas rep"
  setup_checksums_task()
  when host_os == "windows":
    extract_dlls_task()
  build_godot(force = "--force" in command_line_params())
  verify_fonts()
  copy_fonts()
  gen_binding_and_copy_stdlib()

task import_assets,
  "Import Godot assets. Only required if you're not using the Godot editor":
  p "Importing assets..."
  exec godot_bin() & " app/project.godot --editor --quit"

task clean, "Remove files produced by build":
  rm_dir generated_dir
  rm_dir ".nimcache"

task edit, "Edit project in Godot":
  exec godot_bin() & " app/project.godot &"

task start, "Run Enu":
  cd "app"
  exec godot_bin() & " --verbose scenes/game.tscn"

task build_and_start, "Build and start":
  exec "nim build"
  start_task()

task gen, "Generate build_helpers":
  discard gen()

proc code_sign(id, path: string) =
  exec &"codesign --force -s '{id}' --options runtime {path} -v"

task dist_prereqs, "Build godot debug and release versions, and verify fonts":
  p "Buiding distribution prereqs..."
  exec "atlas rep"
  setup_checksums_task()
  when host_os == "windows":
    extract_dlls_task()
  if target == "x11":
    build_godot(target = "server")
  else:
    build_godot()
  verify_fonts()

  let release_opts = "target=release tools=no"
  build_godot(cpu = "64", opts = release_opts)
  when host_os == "macosx":
    build_godot(cpu = "arm64", opts = release_opts)

proc copy_vmlib(src, dest: string) =
  cp_dir src, dest

task build_installer, "Build Windows installer (requires dist files to exist)":
  when host_os == "windows":
    p "Building installer..."
    exec &"iscc /DVersion={git_version} installer/enu.iss"
  else:
    echo "build_installer is only available on Windows"

task dist_package, "Build distribution binaries":
  p "Packaging distribution..."
  copy_fonts()
  rm_dir "dist"
  mk_dir "dist"

  when host_os == "windows":
    extract_dlls_task()
    gen_binding_and_copy_stdlib()
    let release_bin = &"vendor/godot/bin/godot.{target}.opt.{cpu}{exe_ext}"
    let root = &"dist/enu-{git_version}"
    mk_dir root
    exec "strip " & release_bin
    cp_file release_bin, root & "/enu.exe"
    exec &"ResourceHacker -open {root}/enu.exe -save {root}/enu.exe -action addoverwrite -res media/enu_icon.ico -mask ICONGROUP,GODOT_ICON"
    exec &"{gen()} write_export_presets --enu_version {git_version}"

    let pck_path = &"{this_dir()}/{root}/enu.pck"
    exec &"{godot_bin()} --verbose --path app --export-pack \"win\" " & pck_path

    exec "nim build -d:release -d:dist"
    cp_file "app/enu.dll", root & "/enu.dll"
    find_and_copy_dlls mingw_path(), root, gcc_dlls
    find_and_copy_dlls get_current_compiler_exe().parent_dir, root, nim_dlls
    copy_vmlib "vmlib", root & "/vmlib"
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

    var release_bin = &"vendor/godot/bin/godot.{target}.opt.64{exe_ext}"
    exec &"cp {release_bin} dist/Enu.app/Contents/MacOS/Enu.x86_64"
    nim_build "x86_64", "amd64"

    release_bin = &"vendor/godot/bin/godot.{target}.opt.arm64{exe_ext}"
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

    if config["sign"].get_bool:
      let id = config["id"].get_str
      if "keychain" in config:
        let keychain = config["keychain"].get_str
        let password = config["keychain-password"].get_str
        exec &"security unlock-keychain -p \"{password}\" {keychain}"
      code_sign(id, "dist/Enu.app/Contents/Frameworks/enu.dylib")
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
    gen_binding_and_copy_stdlib("server")
    let release_bin = &"vendor/godot/bin/godot.{target}.opt.{cpu}{exe_ext}"
    let root = &"dist/enu-{git_version}"
    mk_dir root & "/bin"
    mk_dir root & "/lib"
    exec "nim build -d:release -d:dist"
    exec "strip " & release_bin
    cp_file release_bin, root & "/bin/enu"
    cp_file "app/enu.so", root & "/lib/enu.so"
    copy_vmlib "vmlib", root & "/lib/vmlib"
    exec "chmod +x " & root & "/bin/enu"
    exec &"{gen()} write_export_presets --enu_version {git_version}"
    let pck_path = this_dir() & "/" & root & "/enu.pck"
    exec &"{godot_bin(\"server\")} --verbose --path app --export-pack \"x11\" " &
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
    exec "nim r ed.nim build"
  exec "cp -r docs/book/assets dist/docs"
  exec "cp -r docs/assets/* dist/docs/assets/"
  exec "cp media/*.{png,webp} dist/docs/assets"
  exec "rm -rf dist/docs/assets/fonts"
  exec "mkdir -p dist/docs/assets/fonts"
  exec "cp -r fonts/jost dist/docs/assets/fonts/"
  exec "cp -r fonts/ibm dist/docs/assets/fonts/"
  # Copy Ed docs to /ed/ for https://getenu.com/ed
  exec "mkdir -p dist/docs/ed"
  exec "cp dist/docs/api/ed_readme.html dist/docs/ed/index.html"
  exec "cp dist/docs/api/ed_api.html dist/docs/ed/api.html"

task export_docs, "Build docs and copy them to ../enu-site/docs":
  docs_task()
  exec "rm -rf ../enu-site/docs"
  exec "cp -r dist/docs ../enu-site"

task build_bin, "Build all nim files in bin/":
  p "Building bin/ tools..."
  for file in list_files("bin"):
    if file.ends_with(".nim"):
      let name = file.split_file.name
      echo &"  Building {name}..."
      exec &"nim c bin/{name}.nim"

task build_docs, "Build all documentation (enu, godot, godot-voxel)":
  echo "Required tools: python3, mkdocs, sphinx-build"
  echo "  pip install mkdocs sphinx sphinx_rtd_theme"
  echo ""

  p "Building Godot class reference..."
  with_dir "vendor/godot/doc":
    exec "python3 tools/make_rst.py -o _build/rst classes/ ../modules/"
    exec "sphinx-build -b html _build/rst _build/html"

  p "Building godot-voxel docs..."
  with_dir "vendor/modules/voxel/doc":
    exec "mkdocs build"

  p "Building Enu docs..."
  export_docs_task()
