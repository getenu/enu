import std/[asynchttpserver, asyncdispatch, os, strutils, mimetypes]

const
  project_path = currentSourcePath().parent_dir().parent_dir()
  vendor_path = project_path / "vendor"
  voxel_docs_path = vendor_path / "modules/voxel/doc/site"
  godot_docs_path = vendor_path / "godot/doc/_build/html"
  enu_docs_path = project_path.parent_dir() / "enu-site"
  port = 9999

proc handle_request(req: Request) {.async, gcsafe.} =
  var path = req.url.path

  # Determine which docs to serve based on path prefix
  var docs_path: string
  var relative_path: string

  if path.starts_with("/voxel"):
    docs_path = voxel_docs_path
    relative_path = path[6..^1]  # Strip "/voxel"
  elif path.starts_with("/godot"):
    docs_path = godot_docs_path
    relative_path = path[6..^1]  # Strip "/godot"
  elif path.starts_with("/enu"):
    docs_path = enu_docs_path
    relative_path = path[4..^1]  # Strip "/enu"
  elif path == "/" or path == "":
    # Serve index page with links to all
    let index_html = """<!DOCTYPE html>
<html><head><title>Docs</title></head>
<body>
<h1>Local Documentation</h1>
<ul>
  <li><a href="/enu/">Enu docs</a></li>
  <li><a href="/voxel/">godot-voxel module docs</a></li>
  <li><a href="/godot/">Godot 3.5 class reference</a></li>
</ul>
</body></html>"""
    await req.respond(HTTP200, index_html, new_http_headers([("Content-Type", "text/html")]))
    return
  else:
    await req.respond(HTTP404, "Not found. Try <a href=\"/\">/</a> for index.")
    return

  # Handle empty path or directory paths
  if relative_path == "" or relative_path == "/":
    relative_path = "/index.html"
  elif not relative_path.contains('.'):
    relative_path = relative_path / "index.html"

  let file_path = docs_path / relative_path

  if file_exists(file_path):
    let content = read_file(file_path)
    let ext = file_path.split_file().ext
    let mimes = new_mimetypes()
    let mime = mimes.get_mimetype(ext.strip(chars = {'.'}), default = "text/html")
    await req.respond(Http200, content, new_http_headers([("Content-Type", mime)]))
  else:
    await req.respond(Http404, "Not found: " & path)

proc main() =
  echo "Serving docs at http://localhost:", port
  echo "  /enu/   -> Enu docs"
  echo "  /voxel/ -> godot-voxel docs"
  echo "  /godot/ -> Godot 3.5 class reference"
  let server = new_async_http_server()
  wait_for server.serve(port.Port, handle_request)

main()
