lock = true
color = brown
speed = 2

# The rat-catcher. He is certain the walls are full of invisible rats, and that
# the invisible rats need his help reaching their rocket. He is loud, wrong,
# and — under the Tom-Sawyer act — genuinely trying to help. The twist he never
# quite lands on: the invisible rats are real.
#
# Arc (driven by watching the foundation build):
#   rant -> pitch -> tutorial -> hide -> done
# rant: shouting about rats -> invisible rats -> invisible walls
# pitch: they need to reach the rocket; the walls don't reach; reveal a wall
# tutorial: talk the player through building white walls (suspiciously)
# hide: teach `swap_color white, invisible`
# done: the walls vanish, the rocket turns up, everyone (invisibly) cheers

let rant_lines = [
  "RATS! Rats in the walls! Can you hear them? Scritch, scritch, scritch!",
  "There! In the wall! ...No? You didn't see it? That's because it's INVISIBLE.",
  "Invisible rats. In the walls. INVISIBLE walls. It is a whole situation.",
  "You can't see them. You can't hear them. That's how you KNOW they're there.",
  "I've counted forty. Forty invisible rats. Give or take... forty.",
  "The walls are FULL of them. Well — the walls that aren't here yet. Details.",
  "Ohh, they're clever. Invisible AND punctual. You have to respect it.",
]

let pitch_lines = [
  "Okay. Okay. Deep breath. The rats need to get to their rocket.",
  "The invisible rats. They have a rocket. Obviously. Do keep up.",
  "But the invisible walls don't REACH the rocket. You see the tragedy.",
  "Watch — I'll make one of the invisible walls visible for you. Ready?",
  "THERE. A wall! You're welcome. That was invisible a moment ago. Trust me.",
  "The rats travel inside the walls, see. To the rocket. It's very sanitary.",
  "I'd finish it myself, but my hands are full of panic. So. You'll do it.",
]

let build_lines = [
  "Build the walls white, along the green line. Nice and tall. For the rats.",
  "This is NOT me tricking you into building my house. Why would you even say that.",
  "Three high is plenty. Rats aren't giraffes. Well — not the visible ones.",
  "When I was young these hills were covered with invisible rats, as far as the eye could see. Which, admittedly, was not far.",
  "You're doing great. This is rat infrastructure and definitely not, say, a porch.",
  "A little more to the left. The rats prefer symmetry. Don't ask me how I know.",
  "I could do this myself. I simply choose the joy of watching you. Selflessly.",
  "Keep going! Every wall is a highway. An invisible, rat-sized highway.",
  "My cousin built walls exactly like these. For rats, allegedly. He's rich now. Suspicious, isn't it.",
]

let hide_lines = [
  "PERFECT. Now, the magic words. On the walls, type: swap_color white, invisible",
  "Make them invisible. Solid, but unseen. Exactly how the rats prefer it.",
  "swap_color white, invisible. Go on. The rats are getting impatient. I assume.",
  "They'll still be there, don't fret. Everything invisible still is. Ask me how I know. Actually — don't.",
]

let done_lines = [
  "IT WORKED! Look at it — nothing! Beautiful, empty, rat-filled nothing!",
  "They're boarding the rocket now. I can't see them. But I can FEEL the wholesomeness.",
  "You helped the invisible rats. I knew you had it in you. I had my doubts. But I knew.",
  "...you did see the rocket appear just now, didn't you? So. Maybe I wasn't entirely wrong.",
  "Thank you, friend. From me, and from forty invisible rats. Give or take forty.",
]

proc foundation(): Build =
  Build(find_by_id("build_rat_foundation"))

# The foundation reports its own state through its (undrawn) pen colour, since
# a bot can't read another build's blocks directly: green building, blue walls
# up, red walls hidden.
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

var phase = "rant"
var said = 0

forever:
  turn player
  if phase == "rant":
    say rant_lines[said mod rant_lines.len]
    inc said
    if player.near(11):
      phase = "pitch"
      said = 0
  elif phase == "pitch":
    say pitch_lines[said mod pitch_lines.len]
    if said == 3:
      reveal_demo()
    inc said
    if said >= pitch_lines.len:
      phase = "tutorial"
      said = 0
  elif phase == "tutorial":
    reveal_demo()   # keep the demo wall showing as a reference while they build
    say build_lines[said mod build_lines.len]
    inc said
    if walls_built():
      phase = "hide"
      said = 0
  elif phase == "hide":
    say hide_lines[said mod hide_lines.len]
    inc said
    if walls_hidden():
      phase = "done"
      said = 0
  else:
    say done_lines[said mod done_lines.len]
    inc said
  sleep 4
