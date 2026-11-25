import testing

# Confirms claim_name's rename path (bot_misnamed is the same for a bot):
# build_misnamed declares
# `name renamed_prototype`, so it should end up in the world as
# build_renamed_prototype (and the on-disk-only id build_misnamed should be
# gone). The re-add under the new id is driven by the file watcher, so poll
# with a timeout rather than assuming it has landed.
proc thing_ids(): seq[string] =
  for t in all_things():
    result.add t.id

var waited = 0.0
while ("build_renamed_prototype" notin thing_ids() or
    "bot_renamed_walker" notin thing_ids()) and waited < 10.0:
  sleep 0.25
  waited += 0.25

suite "Prototype rename on name/id mismatch":
  test "the thing appears under its name-derived id":
    check "build_renamed_prototype" in thing_ids()

  test "the on-disk-only id is gone":
    check "build_misnamed" notin thing_ids()

  test "a renamed bot stays a bot":
    check "bot_renamed_walker" in thing_ids()
    check "bot_misnamed" notin thing_ids()
    check "build_renamed_walker" notin thing_ids()
    for t in all_things():
      if t.id == "bot_renamed_walker":
        check t of Bot

test_summary()
