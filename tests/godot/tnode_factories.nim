import std/unittest
import pkg/[print, model_citizen]
import godot except print
import godotapi/node
import world/node_factories, models/[states, bots, types, builds]

when is_main_module:
  proc tests() =
    var state = GameState.init(Node)
    state.nodes.game = gdnew[Node]()
    state.nodes.data = gdnew[Node]()
    var factory = NodeFactory.init(state)
    let u = Bot.init(Node)
    state.things += u
    let u2 = Build.init(Node)
    u.things += u2
    let u3 = Bot.init(Node)
    let u4 = Bot.init(Node)
    u2.things += u3
    u2.things += u4
    u2.things -= u4
    u3.flags += Targeted

  tests()
