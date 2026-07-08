# Command Loops

Command loops are how you control the behavior of things. They look like this:

```nim
- boogie:
  position = position.fuzzed(0.5)

- shake:
  left 1
  right 1

- rest:
  sleep 5

loop:
  nil -> shake
  
  if player.near:
    shake -> boogie
    
  elif player.far(50):
    (rest, boogie) -> shake
    
  elif player.far(200):
    (boogie, shake) -> rest
```
