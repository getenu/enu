color = green

let hellos = [
  "Phil? Hey, Phil? Phil! Phil Connors? Phil Connors, I thought that was you!",
  "I got friends of mine who live and die by the actuarial tables and I say, Hey! It's all one big crapshoot anyhoo.",
  "Tell me, have you ever heard of single premium life? Cause I think that really could be the ticket for you.",
  "Hey, hey! Now, don't you tell me you don't remember me because I sure as heckfire remember you.",
  "Do you have life insurance? Because if you do you could always use a little more. Am I right or am I right or am I right? Right? Right?"
]

let goodbyes = [
  "Uh, I gotta get going. Uh, it's good to see you, Phil.",
  "Whoa-ho-ho! Watch out for that first step! It's a doozy!",
  "Where are we going?", "Phil, this is the best day of my life."
]

-wander:
  speed = 3
  forward 2 .. 10
  turn -45 .. 45

-chase:
  speed = 6
  turn player
  forward 5

-caught:
  say ""
  sleep 2
  say random(goodbyes)
  sleep 2

loop:
  nil -> wander
  (go_home, wander_home) -> wander
  caught -> go_home

  if start_position.far(20):
    # `go_home`, but we want to be able to interrupt and
    # switch to `chase` if the player is near. Alias to
    # `wander_home`, which switches the same as `wander`.
    wander -> go_home as wander_home

  if player.near(10) and start_position.near(30):
    # `chase` if the player is near and we're not too far 
    # from home base
    (wander, wander_home) ==> chase:
      # this will be called when the command switches
      say cycle(hellos)

  if player.far(20):
    chase -> go_home

  if player.near(3):
    chase -> caught
