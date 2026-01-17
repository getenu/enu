import nimibook

var book = init_book_with_toc:
  entry "README", "api/ed_readme"
  entry "API Reference", "api/ed_api"

nimibook_cli(book)
