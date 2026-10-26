---
name: test-writing
description: The SOP for writing gdUnit4 tests that keep the suite fast and clean: build the world once per file in before(), restore any global state a test changes, free what a test creates, keep files small, and run the file alone with a case count. Use when writing or changing any file under game/tests and when briefing an implementor to write tests.
---

# TEST-WRITING SOP: KEEP THE SUITE FAST

Ported from Dome Farmer and trimmed to what applies here. Dome Farmer enforced these rules with a shard script and a leak-guard hook; this repo has neither yet, so the rules below are followed by hand and a lane reports its numbers.

Tests are gdUnit4 files under `game/tests/`, named `test_<name>.gd`, mirroring the source folder (for example `game/tests/core/test_sim_clock.gd`).

## Rules for a new or changed test file

1. **Build the expensive thing once per file, in `before()`.** Loading a scene, building a world or loading a large resource goes in `before()` and is kept in a member. `before_test()` runs for every case, so a 3 s build in it costs 3 s times the case count. Reset only the small state a case changes, in `before_test()`.
2. **Do not boot the real scene when a unit will do.** Logic that lives in one class is tested by building that class alone. Keep real-scene checks to a few cases in one file.
3. **Never wait on the wall clock longer than the case needs.** Await a signal or a frame count, not a long `create_timer`. A fixed wait is both slow and flaky.
4. **Restore global state.** If a test pauses the tree, changes `Engine.time_scale`, edits an autoload or writes an input action, it puts the value back before it ends. Freeing a node does not undo a global change, and the next suite fails far from the file that caused it.
5. **Free what the test creates.** Wrap each `Node` the test makes in `auto_free(...)`, or call `free()` or `queue_free()` yourself. A node left under root is a leak.
6. **Keep a file small.** One concern per file, split by subject. A big file is slow to find a failure in and cannot run beside the others.
7. **A test that writes to `user://` removes what it wrote.**

## Running tests

- The gdUnit4 suite needs `--ignoreHeadlessMode`, `-c` (so one failure does not hide the rest) and `--audio-driver Dummy`. Exit 0 is a pass, 100 is failures, 103 means gdUnit4 refused to run.
- Run a single file alone first: `-a res://test/<area>/<name>_test.gd`. Report the test COUNT, and grep the output for "No test cases found", because a path that matches nothing still exits 0.
- Import is mandatory after adding or moving any `.gd`: until it runs, gdUnit4 does not see the file and its `class_name` does not resolve.
- Run the full suite once on the final tree before a merge, not on every commit. It holds the one Godot slot.
- A case that takes more than a few seconds is a defect to explain before you report done. Open the results XML, find the case holding most of the time, and apply rules 1 to 3.
- Never raise a time limit or skip a case to make a run pass.
