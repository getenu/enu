name Box1
# import typetraits
#echo "SELF: ", me.type.name
def box(length = 10, height = 20):
  height.times:
    4.times:
      forward length
      turn right

box()
echo "BYE FROM BOX ", me.name
