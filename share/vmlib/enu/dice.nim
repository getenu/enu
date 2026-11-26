## Rolling dice in scripts. A range where a number goes picks one at random
## (`forward 2 .. 10`, `turn -45.0 .. 45.0`), and `1 in 10` is true one time
## in ten. Only scripts import this. Library code that wants a random number
## says `rand(...)`, so a range or an `in` there means what it does in Nim.

import core

converter int_slice_to_float*(range: Slice[int]): float =
  rand(range).float

converter int_slice_to_fint*(range: Slice[int]): int =
  rand(range)

converter float_slice_to_float*(range: Slice[float]): float =
  rand(range)

proc contains*(max, chance: int): bool =
  ## Roll the dice: `1 in 10` is true 1 time out of 10. Use it for
  ## things that should only happen sometimes:
  ## `if 1 in 100: echo "jackpot!"`.
  rand(1 .. max) <= chance
