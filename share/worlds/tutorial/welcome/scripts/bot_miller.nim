lock = true
color = white
speed = 2

# The miller adores his favorite book — which he has, to put it delicately,
# misunderstood completely. It's in fact about a man who ATTACKS windmills,
# mistaking them for giants; the miller is quite sure it's a tender story of a
# knight who simply loved them. Once the player gets the blades turning he grows
# even fonder and even less accurate, cheerfully mishearing the title as "Dawn
# Coyote." His grasp swings wildly from line to line. Warm, never sharp, never at
# the player's expense.
#
# How he talks: a little branching dialog. He leads with a line (his floating
# bubble); open the sign to hear him out and click a reply to keep him going. The
# windmill actually turning (world state) flips him from his "stuck" tree to his
# "turning" tree. Most replies are a single choice — the tree CAN branch (a node
# can offer several), this level just mostly doesn't.

# The windmill beacon lights green once the director confirms the blades have
# made a full turn — a reliable "the player got it spinning" signal.
proc mill_turning(): bool =
  let beacon = Build(find_by_id("build_beacon_windmill"))
  ?beacon and beacon.glow > 0.05

# The dialog tree. Each node is the line he leads with (also his bubble), a
# little extra rambling shown when you open the sign, and the replies you can
# click — each reply names the node it leads to.
proc node_data(key: string): tuple[
    line: string, more: string, answers: seq[(string, string)]] =
  case key
  # --- stuck: before the blades turn ---
  of "stuck":
    ("My windmill! The blades are stuck fast...",
     "It's just like my favorite book — a brave knight who simply adored " &
       "windmills. Rode for miles to say hello to every one he passed.",
     @[("What happens in it?", "book"), ("Can I help?", "help")])
  of "book":
    ("He charged one out of pure love. To hug it, I've always assumed.",
     "There's a chapter where he calls them giants. As a compliment, I think. " &
       "A windmill was his truest companion. Wasn't it? I'm fairly sure it was.",
     @[("So how do I help?", "help")])
  of "help":
    ("If only someone who knew a little code could coax these blades open.",
     "Things that should happen over and over live inside a `forever:` loop — " &
       "a `turn`, then a little `sleep` to set the pace. That sort of thing.",
     @[("I'll give it a go.", "")])
  # --- turning: after the blades turn ---
  of "turning":
    ("Look at it go! Just like in Dawn Coyote.",
     "That's the one — Dawn Coyote. The knight who loved windmills. Or was it a " &
       "coyote? A coyote-knight. It's all in there, more or less.",
     @[("Dawn Coyote?", "coyote")])
  of "coyote":
    ("There's a coyote named Dawn in it, I'm almost certain. She's the hero.",
     "Every dawn she salutes the mills. As one does. As one must. In the sequel " &
       "the windmill and the coyote open a little shop together.",
     @[("Glad I could help.", "thanks")])
  of "thanks":
    ("Thank you, friend. You've made an old book true. Whatever it was called.",
     "I'll read it again tonight. The cover, at least. Twice, if the light holds.",
     @[("See you around.", "")])
  else:
    ("...", "", @[])

var node = "stuck"
var shown = ""        # last panel we pushed, so we don't re-say needlessly
var sign_ref: Sign    # the say-sign, captured so pick() can pop it open

proc render(force = false) =
  let d = node_data(node)
  # Heading first, so the opened panel has a title and the body text sits clear
  # of the close button in the top-right corner.
  var panel = "# The Miller\n\n" & d.line
  if d.more != "":
    panel = panel & "\n\n" & d.more
  for a in d.answers:
    panel = panel & "\n\n- [" & a[0] & "](<nim://pick(\"" & a[1] & "\")>)"
  if force or panel != shown:
    shown = panel
    sign_ref = say(d.line, panel)

# Clicking a reply lands here — the link evaluates in this bot's own module. An
# empty target ends the chat: close the panel (leaving his bubble on the current
# line). Closing via the sign's own `open` works for the player without our
# needing to know which one clicked.
proc pick(target: string) =
  if target == "":
    if ?sign_ref:
      sign_ref.open = false
    return
  node = target
  render(force = true)
  if ?sign_ref:
    sign_ref.open = true    # keep the panel open on the new node

# Flip him from the "stuck" tree to the "turning" tree the moment the blades
# actually spin, wherever he happens to be in the conversation.
var was_turning = false
proc sync_world() =
  if not was_turning and mill_turning():
    was_turning = true
    node = "turning"
    render(force = true)

-wander:
  render()          # keep his bubble up as he potters about
  sync_world()
  forward 2 .. 4
  turn -60.0 .. 60.0
  sleep 1 .. 2

-come_home:
  render()
  turn start_position
  forward 3

-greet:
  render()
  sync_world()
  turn player
  sleep 3

loop:
  nil -> wander
  if start_position.far(6):
    wander -> come_home
  if start_position.near(2):
    come_home -> wander
  if player.near(9):
    (wander, come_home) ==> greet
  if player.far(11):    # hold still and face them while they're close
    greet -> wander
