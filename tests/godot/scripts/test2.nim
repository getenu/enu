proc callback*(name: string) =
  discard

proc quit*(code = 0) =
  discard

echo "running test2"
for i in 0 .. 10:
  echo "test2 ", i
  callback("test2")

echo "test2 done"
quit()
