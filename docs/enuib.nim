import std/[sugar, strutils, os, enumerate, pathnorm, macros]
import pkg/[pretty, nimibook, nimib, nimib/themes]
import pkg/nimibook/[types, commands, entries, toc_render]

export pathutils, pretty
# adapted from https://raw.githubusercontent.com/pietroppeter/nimibook/ef700f646db8ec0bbe8a3319cbb3561aaac89a34/src/nimibook/themes.nim

const document* = hl_html static_read("./book/template.html.mustache")

proc use_enu*(doc: var NbDoc) =
  doc.context["path_to_root"] = doc.src_dir_rel.string & "/"
    # I probably should make sure to have / at the end

  # templates are in memory
  doc.partials["document"] = document
  # if they need to be overriden a specific template folder should be created in nbSrcDir
  doc.template_dirs = @[doc.src_dir.string / "templates"]

  # book.json is publicly accessible (sort of a public static api)
  let book_path = doc.home_dir.string / "book.json"
  # load book object
  var book = load(bookPath)

  # book configuration
  doc.context["language"] = book.language
  doc.context["default_theme"] = book.default_theme
  doc.context["description"] = book.description
  doc.context["favicon_escaped"] = book.favicon_escaped
  doc.context["preferred_dark_theme"] = book.preferred_dark_theme
  doc.context["theme_option"] = {"dark": "Dark", "light": "Light"}.to_table
  doc.context["book_title"] = book.title
  doc.context["git_repository_url"] = book.git_repository_url
  doc.context["git_repository_icon"] = book.git_repository_icon
  doc.context["plausible_analytics_url"] = book.plausible_analytics_url
  doc.context["highlightJs"] = highlightJsTags

  var this_entry: Entry
  # process toc
  for i, entry in enumerate(book.toc.entries.mitems):
    if normalize_path(entry.url) ==
        normalize_path(doc.filename.replace('\\', '/')):
      # replace needed for windows
      this_entry = entry
      entry.is_active = true
      let
        prev_url = book.prev_entry_url i
        next_url = book.next_entry_url i
      if prev_url.len > 0:
        doc.context["previous"] = prev_url
      if next_url.len > 0:
        doc.context["next"] = next_url
      break
  doc.partials["toc"] = render book.toc

  # html.head.title (what appears in the tab)
  doc.context["title"] = this_entry.title & " - " & book.title

template load_md*(file) =
  const text = static_read file
  nb_init(theme = use_enu)
  nb_text(text)

template caller_path(): string =
  instantiation_info(0, true).filename

proc root_dir(): string =
  caller_path().splitfile.dir

template md*(file: string) =
  let base_path = root_dir() / "book"
  let caller_path = instantiation_info(-1, true).filename.split_file.dir
  let diff = caller_path.replace(base_path, "").dup(remove_prefix("/"))

  nb_init(theme = use_enu, this_file_rel = diff / file)
  let text = read_file(caller_path / file)
  nb_text(text)
  nb_save
