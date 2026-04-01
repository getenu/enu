# Reload and Verify Changes

Enu hot-reloads JSON files. Use this skill to apply changes and verify them
visually with screenshots.

## Usage

```
/reload-verify
```

## Hot-Reload Pattern

After writing JSON or script files:

1. **Touch the files** to ensure Enu sees a newer mtime:
   ```bash
   touch "<level_dir>/data/<name>/<name>.json"
   touch "<level_dir>/scripts/<name>.nim"
   ```

2. **Wait 4–5 seconds** (Enu polls every ~2 seconds)

3. **Take a screenshot** to verify

If the change isn't visible, try a force-reload:

```bash
# Force full reload by switching levels and back
```
Then use eval:
```nim
load_level("level-name")
```

## Positioning the MCP Bot

Move the MCP bot to get a better view of what you're building:

```
set_position x=0 y=15 z=-10 rotation=180
```
- `y=15` lifts the bot to see from above
- `rotation=180` faces south (toward -Z where most content is)

## Check What's in the Level

```nim
# Via eval (output in get_console):
for b in Build.all: echo b.id, " at ", b.position
for bot in Bot.all: echo bot.id, " at ", bot.position
echo "Level: ", level_name()
```

## Verify a Specific Build Exists

```nim
var found = false
for b in Build.all:
  if b.id == "build_my_wall":
    echo "Found at: ", b.position
    found = true
if not found:
  echo "NOT FOUND - check level.json load_order"
```

## Troubleshooting

**Build not appearing:**
- Check `level.json` has the build name in `load_order` (required for scripted builds)
- Static builds (JSON-only, no script) load automatically — don't need level.json
- Verify the JSON file is valid: `python3 -c "import json; json.load(open('path/to/file.json'))"`

**Script errors:**
- Check `get_console` for error messages after triggering a reload
- Common issue: syntax errors in `.nim` files show up in the console

**Position wrong:**
- The `origin` in JSON is world position; voxel coords in `edits` are LOCAL to origin
- Use `set_position` to fly the bot near the expected location and screenshot

**Hot-reload not triggering:**
- Always `touch` files after writing — don't rely on write time alone
- If still not working: `eval("load_level(\"" & level_name() & "\")")`

## Level JSON Format

If `level.json` is missing or empty, scripted builds won't load:

```json
{
  "enu_version": "enu-0.3-pre-godot-upgrade-14-gc3cb91e6",
  "format_version": "v0.9.2",
  "load_order": ["build_one", "build_two", "bot_guard"]
}
```

Order matters when scripts reference each other (define dependencies first).

## Screenshot Positions for Common Views

| View | x | y | z | rotation |
|------|---|---|---|----------|
| Overview (north-facing) | 0 | 25 | 20 | 180 |
| Ground level (player POV) | 0 | 2 | 5 | 180 |
| Side view (east) | -40 | 10 | -30 | 90 |
| Top-down | 0 | 50 | -30 | 0 |
