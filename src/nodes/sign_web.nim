## Signs rendered by the Blitz HTML renderer (rust/pages) instead of the
## Godot viewport + MarkdownLabel. Left out by `-d:no_pages`.

import pkg/godot
import gdnativeapi
import godotapi/[image, image_texture, texture, file, godottypes]
import pkg/chronicles
import ../pages/[renderer, sign_page]

export renderer, sign_page

const PAGE_FONTS = [
  "text", "text-italic", "text-bold", "text-bold-italic", "mono", "mono-italic",
  "mono-bold", "mono-bold-italic", "icons",
]

proc load_page_fonts*() =
  ## Hands Enu's fonts (Jost, IBM Plex Mono, Font Awesome) to the page
  ## renderer. Read through Godot so they're found inside a release's pack
  ## too. Call before any page is made.
  for name in PAGE_FONTS:
    let path = "res://themes/" & name & ".otf"
    var file = gdnew[godottypes.File]()
    if file.open(path, READ) != OK:
      error "page font missing", path
      continue
    let len = file.call("get_len").as_int
    let bytes = file.call("get_buffer", len.to_variant).as_pool_byte_array
    file.close
    var data = new_seq[uint8](bytes.len)
    for i in 0 ..< bytes.len:
      data[i] = bytes[i]
    ew_register_font(data[0].addr, data.len.csize_t)

proc upload*(
    pixels: ptr UncheckedArray[uint8], width, height: int, tex: ImageTexture
) =
  let len = width * height * 4
  var bytes = new_pool_byte_array()
  bytes.set_len(len)
  # One copy through a write lock. (`mitems` would also visit every byte.)
  let api = get_gdnative_api()
  let access = api.pool_byte_array_write(bytes.godot_pool_byte_array[])
  copy_mem(api.pool_byte_array_write_access_ptr(access), pixels, len)
  api.pool_byte_array_write_access_destroy(access)
  var img = gdnew[Image]()
  img.create_from_data(width, height, false, FORMAT_RGBA8, bytes)
  if tex.get_width == width and tex.get_height == height:
    tex.set_data(img)
  else:
    tex.create_from_image(img, FLAG_FILTER or FLAG_MIPMAPS)

proc to_texture*(view: ViewPtr, width, height: int, tex: ImageTexture) =
  upload(ew_render(view), width, height, tex)
