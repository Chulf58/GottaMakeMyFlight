extends SceneTree
## The exhaustive form of test_ground_planner_sampling.gd: every legal stand of
## one plane class in a range of grid rows, sampled every half tick
## (GroundPlannerKit.sample()) with no pause, and with the longest pause at
## one hold of each taxi phase (the gate's hold line on odd columns where it
## has one, else the stub's). Too slow for the suite (about 0.15 s a stand and
## plan, some 12,900 stands), so it runs by hand, a few processes at once:
##
##   Godot --headless --audio-driver Dummy --path game \
##     -s res://spike/ground_planner_sweep.gd -- --class=small --rows=0:75
##
## --side=W or --side=E sweeps synthetic west or east stands instead (board
## airside-all-around-s4: their exit faces out to that side and their way out
## runs on its spur), each on its own taxi pair (TaxiTimes.for_stand()), with
## the longest pause at every hold of each phase in turn, the spur head's
## included. --step=N samples every Nth row and column only (default 1), for a
## side sweep that would otherwise take hours. A side sweep also prints the
## range of taxi pairs it met and how many break the pair bounds.
##
## Prints one line per uncovered stand and a summary, and exits 1 when any
## tick was uncovered or no stand was sampled.


func _initialize() -> void:
	var plane_class := PlaneClasses.MEDIUM
	var rows := Vector2i(0, GroundPlannerKit.SITE.grid_size.y)
	var side := StandPlacement.NORTH
	var step := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			plane_class = arg.trim_prefix("--class=")
		elif arg.begins_with("--rows="):
			var parts := arg.trim_prefix("--rows=").split(":")
			rows = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--side="):
			side = arg.trim_prefix("--side=")
		elif arg.begins_with("--step="):
			step = maxi(1, int(arg.trim_prefix("--step=")))
	var kit := GroundPlannerKit.new()
	var planner := kit.planner()
	var began := Time.get_ticks_msec()
	var stands := 0
	var plans := 0
	var samples := 0
	var uncovered := 0
	var pairs := {"in": Vector2i(1 << 30, 0), "out": Vector2i(1 << 30, 0), "bad": 0}
	for row in range(rows.x, rows.y, step):
		for column in range(0, GroundPlannerKit.SITE.grid_size.x, step):
			var cell := Vector2i(column, row)
			var at := kit.stand(cell, side)
			if not kit.is_legal(at, plane_class):
				continue
			stands += 1
			var req := kit.request("A", plane_class, at)
			var options: Array = [{}]
			if side == StandPlacement.NORTH:
				options.append(GroundPlannerKit.longest_pauses(planner, req, column % 2 == 1))
			else:
				options.append_array(GroundPlannerKit.every_hold_pauses(planner, req))
				_count_pair(pairs, TaxiTimes.for_stand(at))
			for pauses: Dictionary in options:
				var result := GroundPlannerKit.sample(req, pauses)
				plans += 1
				samples += result["samples"]
				uncovered += result["uncovered"]
				if result["uncovered"] > 0:
					print(
						(
							"UNCOVERED %s %s cell %s pauses %s: %s"
							% [plane_class, side, cell, pauses, result]
						)
					)
	print(
		(
			(
				"SWEEP %s side %s rows %d-%d step %d: %d legal stands, %d plans, "
				+ "%d half-tick samples, %d uncovered, %d s"
			)
			% [
				plane_class,
				side,
				rows.x,
				rows.y - 1,
				step,
				stands,
				plans,
				samples,
				uncovered,
				(Time.get_ticks_msec() - began) / 1000
			]
		)
	)
	if side != StandPlacement.NORTH:
		print(
			(
				"PAIRS %s side %s: taxi in %d-%d, taxi out %d-%d, %d over the bounds"
				% [
					plane_class,
					side,
					pairs["in"].x,
					pairs["in"].y,
					pairs["out"].x,
					pairs["out"].y,
					pairs["bad"]
				]
			)
		)
	quit(0 if uncovered == 0 and stands > 0 else 1)


static func _count_pair(pairs: Dictionary, pair: Array[int]) -> void:
	pairs["in"] = Vector2i(mini(pairs["in"].x, pair[0]), maxi(pairs["in"].y, pair[0]))
	pairs["out"] = Vector2i(mini(pairs["out"].x, pair[1]), maxi(pairs["out"].y, pair[1]))
	if TaxiTimes.problem(pair) != "":
		pairs["bad"] += 1
