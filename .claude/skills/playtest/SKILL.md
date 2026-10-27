---
name: playtest
description: The SOP for playtesting the game like a human tester through the Godot MCP and the dev-only PlaytestHook: take the one windowed slot, launch, drive the UI, read state and the event log, take screenshots, then report bugs and friction notes. Two charters, a smoke run after each game-facing merge and an exploratory run per milestone. Use when asked to playtest, smoke-test a merge, or run a milestone session.
---

# PLAYTEST SOP: DRIVE THE REAL GAME, READ ITS STATE, REPORT WHAT A PLAYER WOULD HIT

Governing decision: `ai-playtester-a-dev-only-debug-hook-event-log-state-queries` (knowledge_get 7e8a606f-b8d3-4f6b-bb1e-086655a7adfc). The hook is `game/debug/playtest_hook.gd` (autoload `PlaytestHook`). Screenshots alone miss most bugs, so every claim comes from three sources: the hook's state and log, the HUD text, and a screenshot you opened.

The agent running this skill owns no game code. A playtest reports; it never edits `game/`, tests or tools. A bug goes to the conductor to be boarded, friction notes go to the user.

## 1. Setup

1. **Take the windowed slot.** AGENTS.md allows exactly one windowed Godot run at a time, project-wide, and a game started through the Godot MCP holds it. If your brief names a lock file, wait while it exists (poll every 60 s, up to 30 min), then write it with the text `playtest`. Hold it for the whole session and delete it right after `stop_project`, also when the session fails.
2. **Check the Godot MCP tools are loaded** (`run_project`, `stop_project`, `get_ui_elements`, `simulate_input`, `run_script`, `take_screenshot`, `get_debug_output`). They may be deferred; load them with ToolSearch first.
3. **Make the evidence folder:** `tools/blender/out/playtest/<yyyymmdd>-<charter>/` (gitignored). Every screenshot you cite is copied there.
4. **Launch:** `run_project` with `projectPath: "C:/Users/chulf/Gotta-make-my-flight/game"` (the Windows path; a /mnt/c path fails). The result lists "Security scan findings" about `preload` and `load`; those are Tier 3 warnings, not blockers. Never set `GODOT_MCP_DISABLE_SECURITY`.
5. **Prove the hook is on** before anything else: run the snapshot script (section 3). `attached: true` means the hook is on. `attached: false` or a missing `PlaytestHook` node means `GMMF_PLAYTEST=1` did not reach the game (see `tools/godot-mcp-wsl.sh`); stop and report a blocker, because without the hook this is only a screenshot session.
6. **Pause at once** with `simulate_input` key `Space`, then confirm `paused: true` in a snapshot. The sim runs from launch: the first flight's doors close about 1:30 after start, and the clock keeps running between your tool calls. Space toggles, so tap it once and check; do not tap it blind. Unpause only to watch the sim: `Shift+3` gives 3x, `Shift+1` gives 1x, or press Space again. `Shift+1`, `Shift+2` or `Shift+3` unpauses as well as setting the speed, so a Space tap after it pauses again; check `paused` in a snapshot whenever you are unsure which state you are in.
7. **No intro dialogue.** The game normally opens paused under an intro dialogue (once per session). `GMMF_PLAYTEST=1` skips it, so a playtest launch starts with the clock running and no dialogue to dismiss. If an intro dialogue does show, the hook is not on (step 5).

Runtime tools take one command at a time. A `take_screenshot` sent while `get_ui_elements` is in flight is rejected ("another command is in flight"). Send runtime calls one after another, never in the same parallel block.

## 2. Driving the game

**Discover the UI first:** `get_ui_elements` (pass `filter: "Button"` or `"Label"` to cut the list). Read the HUD from it too: the flight panel's time, flight state, made/missed counts, the build status line (`StatusLine`) and the debug panel labels all appear as `text`.

`click_element` resolves a node path or node name, never the visible text. `click_element` with `"Starter terminal"` fails with "could not find UI element". Most HUD buttons are generated nodes named `@Button@14` and the numbers change when the UI changes, so always copy the full `path` from a fresh `get_ui_elements` (a path with `@` in it works). Named nodes are `DebugToggle`, `CardFloor`, `CardWall`, `CardGlass`, `CardDoor`, `StatusLine`, `FollowText`.

**Keys.** `simulate_input` `type: "key"` taps (press and release) unless you set `pressed`; use `pressed: true` then `pressed: false` to hold, for the camera keys. The game's keys: `Space` pause, `Shift+1/2/3` speed, `1` Floor, `2` Wall, `3` Desk, `4` Scanner, `5` Seats, `6` Remove, `7` Glass, `8` Door, `9` Entrance, `0` Exit, `Esc` no tool, `R` rotate, camera on `W` `A` `S` `D`, `Q`/`E` to rotate, the wheel to zoom, `Home` to reset. Check `game/project.godot` `[input]` if a key does nothing. Plain number keys are build tools; speed needs Shift.

**The mouse needs a workaround.** The build tools read the viewport's mouse position, not the position carried by an injected event. A `mouse_button` or `mouse_motion` from `simulate_input` reports a position but leaves the viewport mouse where the real cursor is, so a click lands somewhere else (a refusal such as `OUT_OF_BOUNDS` for a cell far outside the grid is the sign). Move the viewport mouse with `run_script`, then send the input:

```gdscript
extends RefCounted

const AT := Vector2(900, 627)   # screen pixels, 1920x1080

func execute(scene_tree: SceneTree) -> Variant:
	scene_tree.root.warp_mouse(AT)
	return scene_tree.root.get_mouse_position()
```

- **One placement, one call.** To place with a tool, one `run_script` can warp and queue the whole input: `warp_mouse(AT)`, then `Input.parse_input_event` for the tool key (press and release `InputEventKey` with `physical_keycode` and `keycode` set), then a left `InputEventMouseButton` press and release. This goes through the game's real input handlers and is logged in the input record.
- **Several warp-and-click steps in one `run_script` need a frame between them.** The viewport mouse position updates on the next frame, so without a pause every click lands on the last warp. Put `await scene_tree.process_frame` after each `warp_mouse` (before the event that reads the position); a whole build, floor drags included, then works in one script:

```gdscript
extends RefCounted

func execute(scene_tree: SceneTree) -> Variant:
	for at in [Vector2(700, 500), Vector2(900, 500)]:
		scene_tree.root.warp_mouse(at)
		await scene_tree.process_frame
		# ... press and release the tool key / mouse button here
	return scene_tree.root.get_mouse_position()
```

- **A drag (floor or remove rectangle, wall line) needs a motion event after each warp.** Warp to the start, press (`simulate_input` `mouse_button` `pressed: true`), warp to the end, then `simulate_input` `mouse_motion` (any `relative_x`/`relative_y`), a short `wait`, and `mouse_button` `pressed: false`. Without the motion event only the first cell is applied. The status line shows the rectangle size (`15 x 14`) while the drag is live and `Placed 210` after the release.
- **Wheel zoom has no `simulate_input` form either.** Warp the mouse to an empty spot of the 3D view first (the camera reads the wheel as unhandled input, so a panel under the cursor would take it), then queue the wheel events in the same `run_script`; each press event is one zoom step, so send several for a large zoom:

```gdscript
extends RefCounted

func execute(scene_tree: SceneTree) -> Variant:
	scene_tree.root.warp_mouse(Vector2(960, 540))
	for i in 5:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP   # WHEEL_DOWN zooms out
		wheel.position = Vector2(960, 540)
		wheel.pressed = true
		Input.parse_input_event(wheel)
	return scene_tree.root.get_mouse_position()
```

- Work out screen coordinates from a screenshot of the paused view; the grid cell under a point is in the `build_edit` / `build_refused` event (`cell`). Aim, place, read the event, correct. Cells near the camera are bigger than far ones.
- Setting state by calling game methods from `run_script` is allowed to save time, but it skips the input path. Say so in the report and use real input for whatever the charter is about.

## 3. Reading state

`run_script` takes a script with `extends RefCounted` and `func execute(scene_tree: SceneTree) -> Variant`:

```gdscript
extends RefCounted

func execute(scene_tree: SceneTree) -> Variant:
	return scene_tree.root.get_node('PlaytestHook').snapshot(20)
```

The snapshot is JSON-safe: `attached`, `session`, `log_path`, `input_log_path`, `seed` (a string), `tick` (20 ticks per sim second), `paused`, `speed`, `flight_state`, `flights`, `passengers` (`total`, `by_stage`, `made`, `missed`, `active`, `pending_spawns`), `stuck` (passenger id, reason, stage, cell, since which tick), `grid` (floor cells, walls by kind, objects by type, entrances, exits), `events` (the last N), `event_total`, `event_counts`, `anomalies` (open now), `errors` (script errors caught, with a count), `input_events` and `staff` (`checkin` and `security`, each with `hired` and `on_duty`). For a long session return a trimmed dictionary (`pax`, `stuck`, `anomalies`, `errors`, `event_counts` and the last 3 events) instead of the whole snapshot. Other calls: `events_since(index)`, `stuck_list()`, `anomalies()`, `run_checks()`, `hire_staff(role)`.

**A new game starts with no staff** (ruling staff-a-new-game-starts-with-an-empty-staff-pool-and-a-hint). Every desk and scanner is closed until someone of its role is hired, so passengers stand stuck with `NO_CHECKIN` or `NO_SECURITY` and the first flight is missed. The staff panel at the left edge has Hire and Fire buttons per role (named `HireCheckin`, `FireCheckin`, `HireSecurity`, `FireSecurity`) and shows "Hire a check-in agent" while a desk stands with no agent hired. Hired staff walk from the entrance to a station on their own, which takes a few sim seconds. When the charter is not about staffing, hire through the hook instead: `scene_tree.root.get_node('PlaytestHook').hire_staff('checkin')` (or `'security'`) returns the new member's id, or 0 with an error. Hire one per desk and scanner, and say in the report that staff came from the hook.

**The event log** is JSON Lines, one event per line: `{"i","tick","wall","type","data"}`. Types: `session` (start carries the seed, scene and both file paths; also `capped` and `end`), `build_edit`, `build_refused` (carries `reason` and `reason_text`, the text the player sees), `passenger_stage`, `passenger_stuck` (the reason changes), `passenger_made`, `passenger_missed`, `flight_state`, `anomaly` (`state` raised or cleared, `kind`, `subject`, `detail`), `error`. The file is flushed about every half second (each anomaly check) and on close, so it can trail the snapshot by that much. The snapshot's `events` is always current.

- The game's `user://` is `C:/Users/chulf/AppData/Roaming/Godot/app_userdata/Gotta Make My Flight/`. From WSL read it at `/mnt/c/Users/chulf/AppData/Roaming/Godot/app_userdata/Gotta Make My Flight/playtest/`. The exact paths of this session are in the snapshot (`log_path`, `input_log_path`) and in the `PLAYTEST log=... input=... seed=...` line of `get_debug_output`. Convert `C:/` to `/mnt/c/`.
- Files: `<session>.jsonl` (events) and `<session>.input.jsonl` (mouse buttons, positions, modifiers, mouse moves at most every 50 ms, only the keys the game reads). The newest 10 sessions are kept.
- There is no python in WSL. Summarise with `node -e`: parse each line with `JSON.parse`, group `anomaly` events by `data.kind` and `data.state`, count `passenger_stuck` by `data.reason`, list `error` events. Cite the file path and the line index (`i`) of every event you quote.

**Anomaly kinds:** `stuck_too_long` (a passenger stuck more than 10 sim seconds), `no_route`, `off_grid`, `view_drift` and `view_missing` (a passenger or object node that does not match the sim), `frame_time` (average frame time over 50 ms). An anomaly is raised once per subject until it clears. An `error` event or a non-empty `errors` list is a script error the game printed; treat every one as a bug candidate, even when nothing looks wrong on screen. One exception: under `--audio-driver Dummy` the `errors` list can hold WASAPI lines such as `GetBufferSize` or `output_device invalidated`. That is audio-device noise, not a game bug; list it under tool notes.

**Seed and replay.** The seed of the world is `seed` in the snapshot and the session start line. The hook records the input but ships no replay tool. `run_project` passes no arguments, so `--playtest-seed=<n>` cannot be used from it; a replay needs a direct Godot launch, which is a separate windowed run. In a bug report give the seed and the exact input record (section 5); that is what a developer replays by hand.

## 4. Screenshots and frame bursts

- `take_screenshot` with `responseMode: "path_only"`. The PNG lands under `game/.mcp/godot-runtime/screenshots/` (a Windows path in the reply; use `/mnt/c/...`), which is not a place to cite. Copy it at once to `tools/blender/out/playtest/<date>-<charter>/<nn>-<what>.png` with Bash `cp`.
- **Open every screenshot with Read before you say anything about it.** Write one line per image naming what you checked (HUD text legible, objects attached to their cells, nothing floating or clipped, the subject big enough to judge). A passenger a few pixels tall is not inspected; zoom the camera or frame it first. Numbers from the hook are structure evidence; "it looks right" comes only from an opened image.
- **A frame burst** is several screenshots a fixed time apart: `simulate_input` `wait` (`ms` for real time, `frames` for sim-stepping) then `take_screenshot`, repeated, numbered `-a`, `-b`, `-c`. Open each. Use it for motion, queues and anything that changes over a few seconds. There is no single-call burst tool.
- The view is a perspective camera far from a small terminal at the start. Judge a build from a zoomed view, not from the first frame.

## 5. Charters

### Smoke charter (after each game-facing merge)

Aim: what the merge changed, and the path every player takes. Budget: about 55 tool calls and one launch. The first smoke run showed 25 is too few: the setup, one build, one flight and the opened screenshots use most of it, so plan 55.

1. Read the merge's diff summary and name 2 to 4 things it touched (a HUD element, a build tool, a flight stage).
2. Launch, prove the hook, pause.
3. Check the HUD at start: every label shows text, nothing overlaps, the build menu matches the tool keys.
4. Build the minimum terminal with real input (floor, entrance, exit, desk, scanner, seats) and read each `build_edit` event. Inside the Toon shell the Entrance and Exit tools only accept the shell's doors, so a placement away from one is refused with `DOOR_NOT_AT_SHELL_DOOR`. **Shortcut:** on an empty grid, open the Debug panel (`DebugToggle`) and click its `Starter terminal` button, which builds a whole terminal with the entrance on landside door B and the exit on gate C. Use it when the charter is not about building, and say in the report that the terminal came from the shortcut. Hire one staff member per desk and scanner (the staff panel's Hire buttons, or `hire_staff` as in section 3), because a new game has none. Then unpause to 3x, run the flight to `DEPARTED`.
5. Exercise each changed thing once with real input and once at an edge (a refused placement, a second click, Esc mid-drag).
6. Pass if: no `error` events, no open anomaly that is not explained by the build (one desk will always back up a queue), every screenshot opened and clean, and the changed things behave as the diff says. Report pass or fail in one line plus any bug.

### Exploratory charter (per milestone, when an objective finishes)

Aim: find what nobody asked about. Budget: about 60 tool calls. Take a mission, not a script: "build a terminal the way a new player would", "break the build tools", "run a flight to the end and see what the game says", "read every piece of HUD text as a stranger".

1. Launch, prove the hook, pause, screenshot the start screen and read it as a first-time player.
2. Play the game through once the way the HUD instructs, with real input, and note every moment you had to guess.
3. Then push: refused placements (outside the grid, on top of objects, against walls), tool keys in the wrong order, Esc and right-click mid-drag, pausing and speed changes while a drag is live, the debug buttons in states they were not meant for (after the flight departed, on a built grid), clicking a passenger to follow it, the camera at its limits.
4. After each stretch of play, read the snapshot's `errors`, `anomalies`, `stuck` and the tail of the log, and compare the HUD numbers with the hook's (made, missed, in terminal). A mismatch is a bug.
5. End by running the flight to its end and reading what the player is shown.

## 6. Reporting

Write the report in your final message. Do not write files into the repo.

### Bug report (one per bug, ranked by severity: crash or data loss, wrong game result, wrong UI text or state, cosmetic)

```
Title: <what is wrong, in a line a developer can search for>
Severity: <crash | wrong result | wrong text/state | cosmetic>
Build: <git commit, charter, date>
World seed: <seed from the snapshot>
Repro steps: <numbered, from game launch, with real keys and the cells or screen positions used>
Input record: <the input.jsonl path and the line range, or the exact simulate_input / run_script calls>
Expected: <what a player or the rules say should happen, with the source: HUD text, decision slug, code comment>
Actual: <what happened>
Screenshots: <paths under tools/blender/out/playtest/..., each one opened>
Snapshot / log excerpt: <the trimmed snapshot fields or the event lines, with file path and `i`>
```

Reproduce it a second time before you report it when the session budget allows; say "seen once" if not. Never report a hook or MCP tool limitation as a game bug; put those under "tool notes".

### Friction note (a player would be confused, slowed or annoyed; nothing is broken)

```
Moment: <what the player was trying to do>
What happened: <what they saw or had to do>
Why it grates: <the cost: a guess, an extra step, a silent failure>
Suggestion: <optional, one line>
```

Write friction notes for the user in plain words. Keep them out of the bug list.

### Close

1. `stop_project`, then delete the lock file. Both also after a failure.
2. The final message gives: the charter and commit, the evidence folder, the hook's log path, bugs, friction notes, tool notes (surprises in the MCP or the hook), and what you did not cover.
3. The conductor boards the bugs and sends the friction notes to the user. The playtest agent holds no board or store grant.
