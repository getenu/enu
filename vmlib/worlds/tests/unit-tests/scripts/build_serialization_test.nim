import testing

## Serialization Test
## Places a MANUAL block, saves, reloads from disk, and verifies persistence.

speed = 0

let test_pos = vec3(5, 5, 5)

suite "Serialization":
  test "manual block persists after save and reload":
    # Place a MANUAL block
    me.place_block(test_pos, green)

    # Save the level to disk
    save_level_now()

    # Reload the unit from disk (clears in-memory, reloads from persisted state)
    me.reload_unit()

    # Verify the block persisted
    check has_block_at(test_pos)

  test "persisted block has correct color":
    check block_color_at(test_pos) == green

test_summary()
