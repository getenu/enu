## Signs rendered by the Blitz HTML renderer (rust/pages) instead of the
## Godot viewport + MarkdownLabel. Left out by `-d:no_pages`.

import pkg/godot
import gdnativeapi
import godotapi/[image, image_texture, texture]
import ../pages/[renderer, sign_page]

export renderer, sign_page

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
