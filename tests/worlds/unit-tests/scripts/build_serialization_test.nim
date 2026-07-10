import testing

## Serialization Test
## Places a PERSISTED block, saves, reloads from disk, and verifies persistence.

speed = 0

let test_pos = vec3(5, 5, 5)

suite "Serialization":
  test "manual block persists after save and reload":
    # Place a PERSISTED block
    me.place_block(test_pos, green)

    # Save the level to disk
    save_level_now()

    # Reload the thing from disk (clears in-memory, reloads from persisted state)
    me.reload_thing()

    # Verify the block persisted
    check has_block_at(test_pos)

  test "persisted block has correct color":
    check block_color_at(test_pos) == green

test_summary()
