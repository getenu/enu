lock = true
color = white
speed = 2

# The miller adores his favorite book. He has, to put it delicately,
# misunderstood it completely — it is in fact about a man who ATTACKS
# windmills, mistaking them for giants, but the miller is quite sure it's a
# tender story of a knight who simply loved them. He never names the book.
#
# Once the player gets the blades turning he grows even fonder and even less
# accurate, cheerfully mishearing the title as "Dawn Coyote": sometimes a scene
# from the story, sometimes coyotes at dawn, sometimes a coyote named Dawn. His
# grasp of the whole thing swings wildly from line to line. Always warm, never
# sharp, and never at the player's expense.

let stuck_grumbles = [
  "My windmill! The blades are stuck fast...",
  "My favorite book is about a brave knight who simply adored windmills.",
  "He rode for miles just to say hello to every windmill he passed.",
  "Best friends, he and the mills. I get a little choked up, honestly.",
  "He charged one out of pure love. To hug it, I've always assumed.",
  "There's a chapter where he calls them giants. As a compliment, I think.",
  "A windmill was his truest companion. Wasn't it? I'm fairly sure it was.",
  "If only someone who knew a little code could coax these blades open.",
  "I've read it a hundred times. Near a hundred. At least the cover, twice.",
]

let turning_musings = [
  "Look at it go! Just like in Dawn Coyote.",
  "That's the one — Dawn Coyote. The knight who loved windmills.",
  "Dawn Coyote... you know, I think the coyote comes out at dawn?",
  "There's a coyote named Dawn in it, I'm almost certain. She's the hero.",
  "The blades turn and my heart turns with them. Ride on, Dawn Coyote!",
  "A coyote, at dawn, beside a windmill. That's the whole book, really.",
  "Dawn was the name. His name. Her name. The coyote's, at any rate.",
  "In the sequel the windmill and the coyote open a little shop together.",
  "I forget the plot, but the windmills were the good guys. Definitely.",
  "Every dawn the coyote salutes the mills. As one does. As one must.",
  "He loved them so, that knight. Or was it a coyote? A coyote-knight.",
  "Thank you, friend. You've made an old book true. Whatever it was called.",
]

# The windmill beacon lights green once the director confirms the blades have
# made a full turn — a reliable "the player got it spinning" signal.
proc mill_turning(): bool =
  let beacon = Build(find_by_id("build_beacon_windmill"))
  ?beacon and beacon.glow > 0.05

var stuck_line = 0
var turning_line = 0

-wander:
  forward 2 .. 4
  turn -60.0 .. 60.0
  sleep 1 .. 2

-come_home:
  turn start_position
  forward 3

-fret:
  turn player
  if mill_turning():
    say turning_musings[turning_line]
    turning_line = (turning_line + 1) mod turning_musings.len
  else:
    say stuck_grumbles[stuck_line]
    stuck_line = (stuck_line + 1) mod stuck_grumbles.len
  sleep 5

loop:
  nil -> wander
  if start_position.far(6):
    wander -> come_home
  if start_position.near(2):
    come_home -> wander
  if player.near(9):
    (wander, come_home) ==> fret
  fret -> wander
