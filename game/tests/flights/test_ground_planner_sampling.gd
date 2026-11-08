class_name TestGroundPlannerSampling
extends GdUnitTestSuite
## GroundPlanner's analytic windows cross-checked by half-tick footprint
## sampling (decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses, section 5: sampling cross-checks the windows, it is
## not the proof). GroundPlannerKit.sample() poses the plane as PlaneView does
## (FlightPose, which takes the taxi phases from MovementPlan) and requires its
## footprint polygon (GroundPlanner.footprint()) to lie inside the union of its
## own bookings active at that half tick.
##
## Here every class is sampled at a spread of legal stands: the four corners
## of its legal set, eight neighbouring columns (every offset against the
## 8 m slice grid) and the rows either side of the gate hold line's cut-off,
## each with no pause and with the longest pause at a hold of each phase.
## Every legal stand is swept by tools/ground_planner_sweep.gd, which is too
## slow for the suite (about 0.15 s a stand and plan). PUSHBACK is not sampled:
## the drawn plane staying inside its swing square through the turn is board
## 13e98b04's acceptance, and the planner books that square for the phase.

var _kit: GroundPlannerKit


func before() -> void:
	_kit = GroundPlannerKit.new()


## The spread of legal stands for `plane_class` described above.
func _spread(plane_class: String) -> Array[Vector2i]:
	var legal := _kit.legal_cells(plane_class)
	var low := legal[0]
	var high := legal[0]
	for cell in legal:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var middle := Vector2i(floori((low.x + high.x) / 2.0), floori((low.y + high.y) / 2.0))
	var wanted: Array[Vector2i] = [low, high, Vector2i(low.x, high.y), Vector2i(high.x, low.y)]
	for dx in 8:
		wanted.append(Vector2i(middle.x + dx, middle.y))
	# Row 11 is the first whose pushback ends south of the gate hold line.
	for row in [10, 11]:
		wanted.append(Vector2i(middle.x, row))
	var out: Array[Vector2i] = []
	for cell in wanted:
		if legal.has(cell) and not out.has(cell):
			out.append(cell)
	print(
		(
			"%s: %d legal stands, rows %d-%d, columns %d-%d"
			% [plane_class, legal.size(), low.y, high.y, low.x, high.x]
		)
	)
	return out


func _check_class(plane_class: String) -> void:
	var planner := _kit.planner()
	var stands := _spread(plane_class)
	var samples := 0
	var paused := 0
	for cell in stands:
		var req := _kit.request("A", plane_class, _kit.stand(cell))
		for pauses in [{}, GroundPlannerKit.longest_pauses(planner, req, cell.x % 2 == 1)]:
			var result := GroundPlannerKit.sample(req, pauses)
			samples += result["samples"]
			paused += pauses.size()
			(
				assert_int(result["uncovered"])
				. override_failure_message("%s %s %s: %s" % [plane_class, cell, pauses, result])
				. is_equal(0)
			)
	print(
		(
			"%s: %d stands, %d half-tick samples, %d paused phases"
			% [plane_class, stands.size(), samples, paused]
		)
	)
	assert_int(stands.size()).is_greater_equal(10)
	assert_int(paused).is_equal(2 * stands.size())
	assert_int(samples).is_greater(2 * stands.size() * 4000)


func test_small_windows_cover_every_sampled_tick() -> void:
	_check_class(PlaneClasses.SMALL)


func test_medium_windows_cover_every_sampled_tick() -> void:
	_check_class(PlaneClasses.MEDIUM)


func test_large_windows_cover_every_sampled_tick() -> void:
	_check_class(PlaneClasses.LARGE)


## Regression: these stands, found by the sweep, each had one half tick with
## the whole footprint uncovered where a leg's window, the wait's and the next
## leg's met a rounding error apart (32-bit Vector2 spans, and the smoothstep
## inverse giving 0.9999999999999999 at 1). The longest gate-hold pauses.
func test_leg_and_wait_windows_meet_without_a_gap() -> void:
	var planner := _kit.planner()
	var cases := [
		[PlaneClasses.LARGE, Vector2i(3, 120)],
		[PlaneClasses.LARGE, Vector2i(1, 11)],
		[PlaneClasses.SMALL, Vector2i(5, 60)],
		[PlaneClasses.SMALL, Vector2i(1, 95)],
	]
	for one: Array in cases:
		var req := _kit.request("A", one[0], _kit.stand(one[1]))
		var pauses := GroundPlannerKit.longest_pauses(planner, req, true)
		assert_str(pauses[FlightSim.State.TAXI_IN]["hold"]).is_equal(GroundPlanner.HOLD_GATE)
		var result := GroundPlannerKit.sample(req, pauses)
		print("%s %s %s: %s" % [one[0], one[1], pauses, result])
		assert_int(result["uncovered"]).is_equal(0)


## Control: windows shortened by 3 ticks at each end leave uncovered ticks, so
## the sampling can fail.
func test_shortened_windows_are_caught() -> void:
	for plane_class in PlaneClasses.ORDER:
		var req := _kit.request("A", plane_class, _kit.stand(Vector2i(43, 60)))
		var result := GroundPlannerKit.sample(req, {}, 3.0)
		print("%s cut by 3 ticks: %s" % [plane_class, result])
		assert_int(result["uncovered"]).is_greater(0)
