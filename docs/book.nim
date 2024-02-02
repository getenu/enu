import nimibook

var book =
  init_book_with_toc:
    section "Introduction", "intro":
      entry "Tutorial", "intro/tutorial"
      entry "Install or Build", "intro/building"
      entry "Controls and Usage", "intro/controls"
      entry "Examples", "intro/examples"
      entry "Multiplayer (Experimental)", "intro/multiplayer"
      entry "Config", "intro/config"

    section "Coding Enu", "coding":
      entry "Concepts", "coding/concepts"
      entry "Built-in Commands", "coding/commands"
      entry "Shorthand Commands", "coding/shorthand"
      entry "Random Numbers", "coding/random_numbers"

    section "Command Loops", "command_loops":
      entry "Writing Commands", "command_loops/commands"
      entry "Arrows", "command_loops/arrows"
      entry "Loops", "command_loops/loops"
      entry "Child Loops", "command_loops/child_loops"
      entry "More About Command Loops", "command_loops/more"

    entry "Goals", "goals"
    entry "Demos", "demos"
    entry "TODO", "todo"

nimibook_cli(book)
