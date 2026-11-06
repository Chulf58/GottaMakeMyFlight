extends SceneTree
## Headless sweep of the hand-offs onto the boarding route (board c1800254): for
## each seed, a 24-passenger flight on the reference terminal runs to its doors,
## and each passenger's first TO_EXIT tick is measured against every walker
## already in a boarding file or waiting for one. Prints, per seed, the least
## ground distance found (and the pair), whether it came from a security exit or
## a seat stand-up, and made/missed. The fix holds the least at or above
## BODY_M; the positive control is the same run on a tree without the fix, which
## shows the pairs the board item names.
##
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##   --path game -s res://spike/hand_off_spacing_sweep.gd [-- --seeds=1,2,3,4]

const BODY_M := 0.45
const NEVER_M := 99.0

var _seeds: Array[int] = [1, 2, 3, 4]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			_seeds.clear()
			for part in arg.get_slice("=", 1).split(","):
				_seeds.append(int(part))
	var worst := NEVER_M
	for seed_value in _seeds:
		worst = minf(worst, _sweep(seed_value))
	print(
		(
			"SWEEP least first-tick distance over seeds %s: %.3f m (body %.2f m) -> %s"
			% [_seeds, worst, BODY_M, "OK" if worst >= BODY_M else "TOO CLOSE"]
		)
	)
	quit(0 if worst >= BODY_M else 1)


func _sweep(seed_value: int) -> float:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), seed_value)
	world.run_to(PassengerTestWorld.arrival_opens_tick())
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	var counts := {"made": 0, "missed": 0}
	world.sim.outcome.connect(
		func(_id: int, did: bool) -> void:
			if did:
				counts["made"] += 1
			else:
				counts["missed"] += 1
	)
	var seen := {}
	var least := NEVER_M
	var note := "none"
	var doors := FlightSim.schedule_starts(0)[FlightSim.State.PUSHBACK] + 100
	while world.clock.tick <= doors:
		world.step()
		for id in world.sim.passenger_ids():
			var p := world.passenger(id)
			if p.stage != Passenger.Stage.TO_EXIT or seen.has(id):
				continue
			seen[id] = true
			var found := TestHandOffSpacing.nearest_filed(world, p)
			if found[0] < least:
				least = found[0]
				note = "t%d walker %d at %s near walker %d" % [world.clock.tick, id, p.at, found[1]]
	print(
		(
			"SWEEP seed %d: made %d missed %d, least %.3f m (%s), %d hand-offs"
			% [seed_value, counts["made"], counts["missed"], least, note, seen.size()]
		)
	)
	world.free_all()
	return least
