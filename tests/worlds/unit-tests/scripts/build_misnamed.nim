# Saved on disk as `build_misnamed`, but declares `name renamed_prototype`,
# which resolves to the id `build_renamed_prototype`. On load, claim_name
# renames this thing's script + data files to match and drops the in-memory
# thing; the file watcher re-adds it under the new id. build_rename_check
# verifies that swap. This is the intended, tested use of the rename path —
# every other fixture is saved under its own name so it never triggers it.
name renamed_prototype
