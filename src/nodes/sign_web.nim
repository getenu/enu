## Showing pages drawn by the Blitz HTML renderer (rust/pages) in Godot.

import pkg/godot
import gdnativeapi
import godotapi/[image, image_texture, texture, file, godottypes, visual_server, gd_os]
import pkg/chronicles
import ../pages/[renderer, sign_page]

export renderer, sign_page

const PAGE_FONTS = [
  "text.otf", "text-italic.otf", "text-bold.otf", "text-bold-italic.otf",
  "mono.otf", "mono-italic.otf", "mono-bold.otf", "mono-bold-italic.otf",
  "icons.otf", "emoji.ttf",
]

proc load_page_fonts*() =
  ## Hands Enu's fonts (Jost, IBM Plex Mono, Font Awesome, Noto Color
  ## Emoji) to the page renderer. Read through Godot so they're found inside
  ## a release's pack too. Call before any page is made.
  for name in PAGE_FONTS:
    let path = "res://themes/" & name
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
    pixels: ptr UncheckedArray[uint8],
    width, height: int,
    tex: ImageTexture,
    bytes: var PoolByteArray,
) =
  ## `bytes` is the sign's own buffer, kept between uploads: Godot fills a
  ## resized pool array a byte at a time, which costs far more than the copy.
  let len = width * height * 4
  if bytes.is_nil:
    bytes = new_pool_byte_array()
  if bytes.len != len:
    bytes.set_len(len)
  # One copy through a write lock. (`mitems` would also visit every byte.)
  let api = get_gdnative_api()
  let access = api.pool_byte_array_write(bytes.godot_pool_byte_array[])
  copy_mem(api.pool_byte_array_write_access_ptr(access), pixels, len)
  api.pool_byte_array_write_access_destroy(access)
  var img = gdnew[Image]()
  img.create_from_data(width, height, false, FORMAT_RGBA8, bytes)
  if tex.get_width == width and tex.get_height == height:
    if get_current_video_driver() == VIDEO_DRIVER_GLES3:
      # `set_data` reallocates the GL texture every time; this writes into it.
      # Our Godot regenerates the mipmaps after a partial update, if the
      # texture has them.
      texture_set_data_partial(tex.get_rid, img, 0, 0, width, height, 0, 0, 0)
    else:
      tex.set_data(img) # GLES2 has no partial updates
  else:
    # Mipmaps come later, once the sign stops changing (see SignNode).
    tex.create_from_image(img, FLAG_FILTER)
