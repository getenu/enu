import testing

# Confirms claim_name's rename path: build_misnamed declares
# `name renamed_prototype`, so it should end up in the world as
# build_renamed_prototype (and the on-disk-only id build_misnamed should be
# gone). The re-add under the new id is driven by the file watcher, so poll
# with a timeout rather than assuming it has landed.
proc thing_ids(): seq[string] =
  for t in all_things():
    result.add t.id

var waited = 0.0
while "build_renamed_prototype" notin thing_ids() and waited < 10.0:
  sleep 0.25
  waited += 0.25

suite "Prototype rename on name/id mismatch":
  test "the thing appears under its name-derived id":
    check "build_renamed_prototype" in thing_ids()

  test "the on-disk-only id is gone":
    check "build_misnamed" notin thing_ids()

test_summary()
