extends SceneTree
## The exhaustive form of test_ground_planner_sampling.gd: every legal stand of
## one plane class in a range of grid rows, sampled every half tick
## (GroundPlannerKit.sample()) with no pause, and with the longest pause at
## one hold of each taxi phase (the gate's hold line on odd columns where it
## has one, else the stub's). Too slow for the suite (about 0.15 s a stand and
## plan, some 12,900 stands), so it runs by hand, a few processes at once:
##
##   Godot --headless --audio-driver Dummy --path game \
##     -s res://tests/flights/tools/ground_planner_sweep.gd -- --class=small --rows=0:75
##
## Prints one line per uncovered stand and a summary, and exits 1 when any
## tick was uncovered or no stand was sampled.


func _initialize() -> void:
	var plane_class := PlaneClasses.MEDIUM
	var rows := Vector2i(0, GroundPlannerKit.SITE.grid_size.y)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			plane_class = arg.trim_prefix("--class=")
		elif arg.begins_with("--rows="):
			var parts := arg.trim_prefix("--rows=").split(":")
			rows = Vector2i(int(parts[0]), int(parts[1]))
	var kit := GroundPlannerKit.new()
	var planner := kit.planner()
	var began := Time.get_ticks_msec()
	var stands := 0
	var plans := 0
	var samples := 0
	var uncovered := 0
	for row in range(rows.x, rows.y):
		for column in GroundPlannerKit.SITE.grid_size.x:
			var cell := Vector2i(column, row)
			var at := kit.stand(cell)
			if not kit.is_legal(at, plane_class):
				continue
			stands += 1
			var req := kit.request("A", plane_class, at)
			for pauses in [{}, GroundPlannerKit.longest_pauses(planner, req, column % 2 == 1)]:
				var result := GroundPlannerKit.sample(req, pauses)
				plans += 1
				samples += result["samples"]
				uncovered += result["uncovered"]
				if result["uncovered"] > 0:
					print(
						"UNCOVERED %s cell %s pauses %s: %s" % [plane_class, cell, pauses, result]
					)
	print(
		(
			"SWEEP %s rows %d-%d: %d legal stands, %d plans, %d half-tick samples, %d uncovered, %d s"
			% [
				plane_class,
				rows.x,
				rows.y - 1,
				stands,
				plans,
				samples,
				uncovered,
				(Time.get_ticks_msec() - began) / 1000
			]
		)
	)
	quit(0 if uncovered == 0 and stands > 0 else 1)
