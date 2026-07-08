# Random numbers

Generally, if an Enu command takes a number, it will be a `float`. However,
`int` will auto-convert to `float`, and when a numeric `Range` is passed to
something expecting a number, a random value within the range will be selected.
So, even though `forward` expects a `float`, the following are all valid:

```nim
forward 1.0
forward 1

# Convert to a random float between 1.0 and 5.0
forward 1.0..5.0

# Convert to a random int between 1 and 5, then convert the
# int to a float
forward 1..5
```

The `in` operator can be used between two numbers to test for random chance. For
example:

```nim
if 1 in 2:
  echo "I should be hit 50% of the time"
if 1 in 100:
  echo "I should be hit 1% of the time"
```

By default random numbers in Enu are based partially on the time and will be
different each time a script is executed. However, sometimes you want randomness
to create variety, but want the same values to be chosen each time a script is
run. This is especially important when using randomness in a `Build` that you
plan to manually edit later. To ensure the same values are selected each time a
script is run, set the thing's `seed` property to some integer of your choosing,
ie `seed = 12345` or `me.seed = 54321`.

Any child things instanced by a thing with a seed value will get the same seed by
default. However, it will still get a unique random number generator, so
changing the script for a child object won't impact the random numbers selected
by the parent.
