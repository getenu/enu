import pkg/godot
import godotapi/node
import core, bot_node, build_node, ground_node, selection_area, sign_node

proc model*(self: Object): Model =
  result =
    if self of SelectionArea:
      SelectionArea(self).bot.model
    elif self of BuildNode:
      BuildNode(self).model
    elif self of GroundNode:
      GroundNode(self).model
    elif self of StaticBody and StaticBody(self).name == "SignBody":
      SignNode(StaticBody(self).get_parent.get_parent).model
    else:
      nil
