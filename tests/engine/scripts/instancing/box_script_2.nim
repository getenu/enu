name box2

def box(length = 10, height = 20):
  height.times:
    4.times:
      forward length
      turn right

box()
echo "BYE FROM ", me.name
