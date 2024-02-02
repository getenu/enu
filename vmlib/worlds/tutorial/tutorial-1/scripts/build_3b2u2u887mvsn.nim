name Confetti(arms = 31, count = 99)

if not is_instance:
  show = false
  quit()

speed = 0
var arm_speed = 0.7

arms.times:
  drawing = false
  let h = cycle(3, 4, 5, 4)
  up h
  turn 360 / arms

  Streamer.new(speed = arm_speed, count = me.count)

  arm_speed += 1.0 / arms
  down h
  back 2
