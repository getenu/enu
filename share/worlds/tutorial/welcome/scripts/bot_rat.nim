lock = true
color = brown
speed = 2

# The rat-catcher. He is certain the walls are full of invisible rats, and that
# the invisible rats need his help reaching their rocket. He is loud, wrong,
# and — under the Tom-Sawyer act — genuinely trying to help. The twist he never
# quite lands on: the invisible rats are real.
#
# How he talks: the same little branching dialog as the miller. He leads with a
# line (his bubble); open the sign and click a reply to keep him going. The first
# stretch (rant -> pitch -> "here's how to build") is click-driven. The rest is
# gated on what the player actually does in the world — building the walls, then
# hiding them — which flips him forward wherever he is in the conversation.
#
# Arc: rant -> pitch -> tutorial -> hide -> done
#   rant:     invisible rats -> invisible walls
#   pitch:    they need to reach the rocket; reveal a demo wall
#   tutorial: talk the player through building white walls (suspiciously)
#   hide:     teach `swap_color white, invisible`
#   done:     the walls vanish, the rocket turns up, everyone (invisibly) cheers

proc foundation(): Build =
  Build(find_by_id("build_rat_foundation"))

# The foundation reports its own state through its (undrawn) pen colour, since a
# bot can't read another build's blocks directly: green building, blue walls up,
# red walls hidden.
proc f_color(): Color =
  let b = foundation()
  if ?b: b.color else: green

proc walls_built(): bool = f_color() == blue or f_color() == red
proc walls_hidden(): bool = f_color() == red

proc reveal_demo() =
  # turn the starter "invisible" wall visible — the promised demonstration
  let b = foundation()
  if ?b:
    b.swap_color(invisible, white)

# The dialog tree. Each node is the line he leads with (also his bubble), a bit
# more rambling shown when you open the sign, and the replies you can click.
proc node_data(key: string): tuple[
    line: string, more: string, answers: seq[(string, string)]] =
  case key
  # --- rant ---
  of "rant1":
    ("RATS! Rats in the walls! Can you hear them? Scritch, scritch, scritch!",
     "There! In the wall! ...No? You didn't see it? That's because it's " &
       "INVISIBLE. You can't see them. You can't hear them. That's how you KNOW " &
       "they're there.",
     @[("Invisible rats?", "rant2")])
  of "rant2":
    ("Invisible rats. In the walls. INVISIBLE walls. It is a whole situation.",
     "I've counted forty. Forty invisible rats. Give or take... forty. Ohh, " &
       "they're clever. Invisible AND punctual. You have to respect it.",
     @[("...what do they need?", "pitch1")])
  # --- pitch ---
  of "pitch1":
    ("Okay. Okay. Deep breath. The rats need to get to their rocket.",
     "The invisible rats. They have a rocket. Obviously. Do keep up. But the " &
       "invisible walls don't REACH the rocket. You see the tragedy.",
     @[("Show me a wall, then.", "pitch2")])
  of "pitch2":
    ("THERE. A wall! You're welcome. That was invisible a moment ago. Trust me.",
     "The rats travel inside the walls, see. To the rocket. It's very sanitary. " &
       "I'd finish it myself, but my hands are full of panic. So. You'll do it.",
     @[("How do I build them?", "build1")])
  # --- tutorial (loops here until the player has the walls up) ---
  of "build1":
    ("Build the walls white, along the green line. Nice and tall. For the rats.",
     "Three high is plenty. Rats aren't giraffes. Well — not the visible ones. " &
       "This is NOT me tricking you into building my house. Why would you even " &
       "say that.",
     @[("Got it.", "build2")])
  of "build2":
    ("You're doing great. This is rat infrastructure and definitely not a porch.",
     "A little more to the left. The rats prefer symmetry. Don't ask me how I " &
       "know. Every wall is a highway. An invisible, rat-sized highway.",
     @[("On it.", "")])
  # --- hide (loops until the walls are made invisible) ---
  of "hide1":
    ("PERFECT. Now the magic words. On the walls, type: swap_color white, invisible",
     "Make them invisible. Solid, but unseen. Exactly how the rats prefer it. " &
       "They'll still be there, don't fret. Everything invisible still is.",
     @[("swap_color?", "hide2")])
  of "hide2":
    ("swap_color white, invisible. Go on. The rats are getting impatient. I assume.",
     "Ask me how I know they're impatient. Actually — don't.",
     @[("Okay, okay.", "")])
  # --- done ---
  of "done1":
    ("IT WORKED! Look at it — nothing! Beautiful, empty, rat-filled nothing!",
     "They're boarding the rocket now. I can't see them. But I can FEEL the " &
       "wholesomeness.",
     @[("Glad to help.", "done2")])
  of "done2":
    ("You helped the invisible rats. I knew you had it in you. I had my doubts.",
     "...you did see the rocket appear just now, didn't you? So. Maybe I wasn't " &
       "entirely wrong. Thank you, friend. From me, and from forty invisible " &
       "rats. Give or take forty.",
     @[("Anytime.", "")])
  else:
    ("...", "", @[])

# Track ordering, so world state can only ever push him forward.
proc rank(key: string): int =
  case key
  of "rant1", "rant2": 0
  of "pitch1", "pitch2": 1
  of "build1", "build2": 2
  of "hide1", "hide2": 3
  else: 4

var node = "rant1"
var shown = ""        # last panel we pushed, so we don't re-say needlessly
var sign_ref: Sign    # the say-sign, captured so pick() can pop it open

proc render(force = false) =
  let d = node_data(node)
  # Heading first, so the opened panel has a title and the body text sits clear
  # of the close button in the top-right corner.
  var panel = "# The Rat-Catcher\n\n" & d.line
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

# The world drives the back half: once he's pitched, keep the demo wall visible;
# when the player actually raises the walls, jump to the hide track; when they
# make them invisible, jump to the finale — wherever he is in the conversation.
proc sync_world() =
  if rank(node) >= 1:
    reveal_demo()
  if walls_hidden() and rank(node) < 4:
    node = "done1"
    render(force = true)
  elif walls_built() and rank(node) < 3:
    node = "hide1"
    render(force = true)

forever:
  render()
  sync_world()
  turn player
  sleep 3
