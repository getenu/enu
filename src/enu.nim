{.warning[UnusedImport]: off.}

import libs/segfaults
import core, game

import
  ui/[
    editor, console, toolbar, action_button, preview_maker, markdown_label,
    right_panel, settings, virtual_joystick, gui, floating_button
  ]
import
  nodes/[
    player_node, aim_target, selection_area, bot_node, ground_node, build_node,
    sign_node
  ]

Zen.bootstrap
