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
  exec "nim c -r tests/unit/dependency_graph_test"

task vm_tests, "run VM script tests":
  exec "nim c -r tests/vm/runner"

task instance_tests, "run heavy-instancing repro for the VM IndexDefect":
  exec "nim c -r tests/vm/instance_runner"

task godot_tests, "run godot tests":
  exec "nim c tests/godot/tnode_factories"
  cd "tests/godot/app"
  exec this_dir() /
    &"vendor/godot/bin/godot_server.osx.opt.tools.{cpu} --quiet --script tests/tests.gdns"

task world_tests,
  "run in-world tests (headless for server build, dist for dist build)":
  # Each level here is run in sequence via `--enu-test`. Test mode exits
  # the process when all scripts settle, with a code derived from script
  # errors and any signal_test_complete calls from scripts. A non-zero
  # exit from any level fails the task.
  #
  # Add new fixtures here:
  #   - unit-tests:   bot-driven assertion suite (movement, blocks,
  #                   serialization).
  #   - bulk-spawn:   regression test for the "scripts re-execute on
  #                   close-pass" bug — see src/libs/eval.nim near
  #                   closePContext. Spawners create a deterministic
  #                   number of clones; without the exit() workaround
  #                   in build/bot_code_template, closePContext+
  #                   interpreterCode re-runs spawner bodies and inflates
  #                   the unit count. The fixture's build_test_check.nim
  #                   asserts the count and signal_test_complete(1) on
  #                   failure.
  let
    test_levels = @[
      this_dir() / "vmlib/worlds/tests/unit-tests",
      this_dir() / "vmlib/worlds/tests/bulk-spawn",
    ]
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

  for test_level in test_levels:
    p &"Running world test: {test_level.split_path.tail}"
    let cmd =
      if use_dist:
        bin & " --level-dir " & test_level & " --enu-test --temp-workdir"
      else:
        "cd app && " & bin & " --level-dir " & test_level &
          " --enu-test scenes/game.tscn --temp-workdir"
    exec cmd

task client_smoke,
  "Two-instance smoke: server + partial-replica client; verify sync via logs":
  p "Building enu..."
  exec "nim build"

  p "Stopping previous harness-launched enu (if any)..."
  discard gorge_ex(
    "for f in /tmp/enu_server.pid /tmp/enu_client.pid; do test -f $f && kill $(cat $f) 2>/dev/null; rm -f $f; done; true"
  )
  discard gorge_ex("pkill -x enu_mcp || true")
  exec "sleep 1"
  let port_check = gorge_ex("lsof -i :9632 -sTCP:LISTEN 2>/dev/null | tail -n +2")
  if port_check.output.strip.len > 0:
    echo "Port 9632 is in use by an enu this harness didn't start — not killing it:"
    echo port_check.output
    quit 1

  let godot = godot_bin()
  p "Starting server..."
  exec &"cd app && ENU_LISTEN_ADDRESS=127.0.0.1 {godot} --verbose " &
    "scenes/game.tscn > /tmp/enu_server.log 2>&1 & echo $! > /tmp/enu_server.pid"
  exec "sleep 6"

  p "Starting client (partial replica)..."
  exec &"cd app && ENU_CONNECT_ADDRESS=127.0.0.1 {godot} --verbose " &
    "scenes/game.tscn --temp-workdir > /tmp/enu_client.log 2>&1 & echo $! > /tmp/enu_client.pid"
  exec "sleep 20" # boot + connect + initial sync + scripts

  p "Checking logs..."
  let client_log = gorge_ex("cat /tmp/enu_client.log").output
  let server_log = gorge_ex("cat /tmp/enu_server.log").output

  var failures: seq[string]
  template expect_check(cond: bool, msg: string) =
    if cond:
      echo "  ok: " & msg
    else:
      failures.add msg
      echo "  FAIL: " & msg

  expect_check "connected to server" in client_log, "client connected"
  expect_check "Unable to connect to server" notin client_log,
    "no connect timeout"
  expect_check "adding child" in client_log,
    "client renders units (add_to_scene)"
  expect_check client_log.count("player-") >= 2,
    "client sees both players (own + server's)"
  expect_check server_log.count("adding child") >= 1 and
    server_log.count("player-") >= 2,
    "server sees the client's player"
  expect_check "unowned Ed field" notin client_log, "client: no unowned fields"
  expect_check "unowned Ed field" notin server_log, "server: no unowned fields"
  expect_check "SIGSEGV" notin client_log and "Traceback" notin client_log,
    "client: no crashes"
  expect_check "SIGSEGV" notin server_log and "Traceback" notin server_log,
    "server: no crashes"

  p "Stopping harness enu instances..."
  discard gorge_ex(
    "for f in /tmp/enu_server.pid /tmp/enu_client.pid; do test -f $f && kill $(cat $f) 2>/dev/null; rm -f $f; done; true"
  )

  if failures.len > 0:
    echo &"\nResult: FAIL ({failures.len} checks failed)"
    quit 1
  echo "\nResult: PASS"

task mcp_repro,
  "Build enu, restart it, and run MCP integration tests (repeat N times, default 5)":
  let
    params = command_line_params()
    # parse optional count argument, e.g. `nim mcp_repro 10`
    count_str = params.filter_it(it.all_chars_in_set({'0'..'9'}))
    iterations = if count_str.len > 0: count_str[0].parse_int else: 5

  p "Building enu..."
  exec "nim build"

  p "Stopping previous harness-launched enu (if any)..."
  # Only kill instances *this harness* started (pidfile) — never a manually
  # launched enu. If the port is still busy, fail loudly instead.
  discard gorge_ex(
    "test -f /tmp/enu_repro.pid && kill $(cat /tmp/enu_repro.pid) 2>/dev/null; rm -f /tmp/enu_repro.pid; true"
  )
  discard gorge_ex("pkill -x enu_mcp || true")
  exec "sleep 1"
  let port_check = gorge_ex("lsof -i :9632 -sTCP:LISTEN 2>/dev/null | tail -n +2")
  if port_check.output.strip.len > 0:
    echo "Port 9632 is in use by an enu this harness didn't start — not killing it:"
    echo port_check.output
    quit 1

  p &"Starting enu in background..."
  let godot = godot_bin()
  exec &"cd app && ENU_LISTEN_ADDRESS=127.0.0.1 {godot} --verbose scenes/game.tscn > /tmp/enu_repro.log 2>&1 & echo $! > /tmp/enu_repro.pid"
  exec "sleep 4"

  p &"Running MCP integration tests ({iterations} iterations)..."
  var pass_count = 0
  var fail_count = 0
  for i in 1 .. iterations:
    echo &"\n--- Iteration {i}/{iterations} ---"
    let result = gorge_ex(
      "ENU_CONNECT_ADDRESS=127.0.0.1 nim c -r bin/enu_mcp_test.nim 2>&1"
    )
    echo result.output
    if result.exit_code == 0:
      inc pass_count
      echo &"PASS ({pass_count} passed, {fail_count} failed so far)"
    else:
      inc fail_count
      echo &"FAIL ({pass_count} passed, {fail_count} failed so far)"
      # Stop early once we've reproduced the failure
      echo "Bug reproduced — stopping."
      break

  p "Stopping harness enu..."
  discard gorge_ex(
    "test -f /tmp/enu_repro.pid && kill $(cat /tmp/enu_repro.pid) 2>/dev/null; rm -f /tmp/enu_repro.pid; true"
  )

  echo &"\nResult: {pass_count}/{iterations} passed"
  if fail_count > 0:
    quit 1

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
  with_dir "fonts/ibm":
    cp_file "IBMPlexMono-Regular.otf", "../../" & dest / "mono.otf"
    cp_file "IBMPlexMono-Italic.otf", "../../" & dest / "mono-italic.otf"
    cp_file "IBMPlexMono-Bold.otf", "../../" & dest / "mono-bold.otf"
    cp_file "IBMPlexMono-BoldItalic.otf",
      "../../" & dest / "mono-bold-italic.otf"

  # Jost - proportional font (same on all platforms, OFL licensed)
  with_dir "fonts/jost":
    cp_file "Jost-400-Book.otf", "../../" & dest / "text.otf"
    cp_file "Jost-400-BookItalic.otf", "../../" & dest / "text-italic.otf"
    cp_file "Jost-700-Bold.otf", "../../" & dest / "text-bold.otf"
    cp_file "Jost-700-BoldItalic.otf", "../../" & dest / "text-bold-italic.otf"

    cp_file "Jost-400-Book.otf", "../../" & dest / "display.otf"
    cp_file "Jost-400-BookItalic.otf", "../../" & dest / "display-italic.otf"
    cp_file "Jost-700-Bold.otf", "../../" & dest / "display-bold.otf"
    cp_file "Jost-700-BoldItalic.otf",
      "../../" & dest / "display-bold-italic.otf"

  with_dir "fonts/fa":
    cp_file "Font Awesome 6 Free-Solid-900.otf", "../../" & dest / "icons.otf"

proc verify_fonts() =
  ## Fonts are now committed to the repo (OFL licensed).
  ## This just verifies they exist.
  p "Verifying fonts..."
  let required = [
    "fonts/ibm/IBMPlexMono-Regular.otf", "fonts/jost/Jost-400-Book.otf",
    "fonts/fa/Font Awesome 6 Free-Solid-900.otf",
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
