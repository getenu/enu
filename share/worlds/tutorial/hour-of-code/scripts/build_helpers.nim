show = false
proc follow_nearest_player*(thing: Build) =
  ## Makes a thing turn to face the nearest player
  ## Call this in a forever loop with a sleep
  var closest_player: Player
  var closest_distance = 1000.0

  for p in Player.all:
    let dist = thing.position.distance_to(p.position)
    if dist < closest_distance:
      closest_distance = dist
      closest_player = p

  if closest_player != nil:
    move thing
    thing.turn(closest_player)

proc show_exercise*(exercise_id: string) =
  ## Shows the specified exercise sign for the player who clicked
  ## Uses link_clicker to determine which player clicked, then changes their open_sign

  #let clicker = me.link_clicker
  #if clicker == nil:
  #return  # No clicker info available

  # Find the build with the requested exercise_id and open its sign for the clicker
  # for build in Build.all:
  #   if build.name == exercise_id:
  #     # The build should have exactly one sign attached
  #     if build.things.len > 0:
  #       for thing in build.things:
  #         if thing of Sign:
  #           clicker.open_sign = Sign(thing)
  #           return
