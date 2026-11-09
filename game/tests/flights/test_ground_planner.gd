class_name TestGroundPlanner
extends GdUnitTestSuite
## GroundPlanner's bookings (decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, section 5): the routes the
## kit builds are Airside's, the footprint covers both drawn forms of every
## class member, the hold lines, the spacing table, and the booking windows of
## one flight pinned to exact numbers, so a change to taxi motion that moves
## them (and with them which offers are legal) shows here.

## A medium stand in the middle of the site, with gate holds both ways.
const MID_CELL := Vector2i(43, 60)
## test_the_booking_windows_are_pinned(): a medium flight at MID_CELL departing
## 10:00 on day 1 (starts 30940 ... 34840), no pause. Bookings by kind, the sum
## of every window's length, and every booking but the slices as "kind x z
## width depth: from-to". The arrival is off the runway 192.153 ticks into
## TAXI_IN; the departure is on it 808.792 ticks into TAXI_OUT. Re-pinned when
## model 04 parked 1.5 m further out (board f8c8987c): the medium footprint
## shrank (reach 21.902 to 20.780 m), so its parked, corner and runway windows
## did too.
const PINNED_COUNTS := {"parked": 1, "pushback": 2, "corner": 6, "slice": 101, "runway": 2}
const PINNED_HELD := 16485.254
const PINNED_LINES: Array[String] = [
	"parked -17.170 -181.520 28.340 29.820: 32300.000-33600.000",
	"pushback -23.600 -216.500 41.200 64.300: 33600.000-33720.000",
	"pushback -17.170 -181.520 28.340 29.820: 33600.000-33720.000",
	"corner -144.780 -358.780 49.561 41.561: 34640.000-34706.804",
	"corner 103.220 -358.780 41.561 49.561: 31300.000-31558.793",
	"corner 95.220 -312.780 49.561 49.561: 31372.213-31682.319",
	"corner -23.780 -304.780 49.561 49.561: 31773.069-31975.751",
	"runway -1000.000 -352.170 2000.000 28.340: 31040.000-31492.153",
	"corner -31.780 -304.780 49.561 49.561: 33959.234-34179.885",
	"corner -144.780 -312.780 49.561 49.561: 34259.034-34528.814",
	"runway -1000.000 -352.170 2000.000 28.340: 34448.792-34840.000",
]

var _kit: GroundPlannerKit


func before() -> void:
	_kit = GroundPlannerKit.new()


func test_kit_routes_are_the_airside_phase_paths() -> void:
	var airside := TestStandLaneClearance.scene_airside()
	add_child(airside)
	var cells: Array[Vector2i] = [MID_CELL, Vector2i(0, 0), Vector2i(85, 149), Vector2i(10, 120)]
	var compared := 0
	for cell in cells:
		var at := _kit.stand(cell)
		assert_bool(airside.set_gate_stands({"A": at})).is_true()
		for plane_class in PlaneClasses.ORDER:
			var routes := _kit.routes(at, plane_class)
			for state: int in routes:
				(
					assert_array(Array(routes[state]))
					. override_failure_message("cell %s %s state %d" % [cell, plane_class, state])
					. is_equal(Array(airside.phase_path(state, "A", plane_class)))
				)
				compared += 1
	print("compared %d phase paths" % compared)
	assert_int(compared).is_equal(cells.size() * 3 * 6)
	airside.free()


## Each class's footprint covers its members drawn door-aligned (PlaneClasses.
## stand_offset) and centred (half the length either way), and its reach is
## the farthest corner. Pinned: small reaches 15.46 m and large 39.13 m, the
## figures board 13e98b04 measured for the door-aligned turn; medium 20.78 m
## since model 04 parks 1.5 m further out (board f8c8987c).
func test_the_footprint_covers_both_drawn_forms_of_every_member() -> void:
	var expected := {
		PlaneClasses.SMALL: [13.42, 5.345, 7.67, 15.455],
		PlaneClasses.MEDIUM: [15.20, 14.62, 14.17, 20.780],
		PlaneClasses.LARGE: [24.35, 32.15, 22.31, 39.129],
	}
	for plane_class in PlaneClasses.ORDER:
		var fp := GroundPlanner.footprint(plane_class)
		print("%s footprint %s" % [plane_class, fp])
		for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
			var shape: Dictionary = PlaneModels.PLANES[model]
			var offset := PlaneClasses.stand_offset(model)
			assert_float(fp["ahead"]).is_greater_equal(offset.z + shape["nose"])
			assert_float(fp["behind"]).is_greater_equal(shape["tail"] - offset.z)
			assert_float(fp["ahead"]).is_greater_equal(shape["length"] / 2.0)
			assert_float(fp["behind"]).is_greater_equal(shape["length"] / 2.0)
			assert_float(fp["half_width"]).is_greater_equal(shape["half_span"] + absf(offset.x))
		var want: Array = expected[plane_class]
		assert_float(fp["ahead"]).is_equal_approx(want[0], 0.005)
		assert_float(fp["behind"]).is_equal_approx(want[1], 0.005)
		assert_float(fp["half_width"]).is_equal_approx(want[2], 0.005)
		assert_float(fp["reach"]).is_equal_approx(want[3], 0.005)


## H_IN and H_RWY sit on the stubs 30 m from the runway. H_g is on the gate's
## lead-in at gate_hold_z(), the lane band's south edge (the widest model half
## span, 21.78 m, south of the lane) plus the farthest door-aligned nose (model
## 07, 16.55 m, since model 04 parks 1.5 m further out: board f8c8987c):
## Airside.lead_in_hold_z(), which takes the lane band from
## StandEnvelope.lane_band_south() (half spans rounded up to 0.1 m), so z
## -245.65, the line the paving's hold bars are drawn on. A stand has it only
## when its pushback ends south of that, so the
## north-row stands (pushback end -255.9) have none, row 10 (-245.9) none and
## row 11 (-244.9) has it.
func test_hold_lines() -> void:
	assert_float(GroundPlanner.gate_hold_z()).is_equal_approx(-245.65, 0.001)
	assert_float(GroundPlanner.gate_hold_z()).is_equal(Airside.lead_in_hold_z())
	var planner := _kit.planner()
	var mid := _kit.request("A", PlaneClasses.MEDIUM, _kit.stand(MID_CELL))
	var in_mid := planner.holds(mid, FlightSim.State.TAXI_IN)
	var out_mid := planner.holds(mid, FlightSim.State.TAXI_OUT)
	print("mid in %s, mid out %s" % [in_mid, out_mid])
	(
		assert_array(in_mid.map(func(h: Dictionary) -> String: return h["hold"]))
		. is_equal([GroundPlanner.HOLD_IN, GroundPlanner.HOLD_GATE])
	)
	assert_float(in_mid[0]["hold_s"]).is_equal_approx(30.0, 0.001)
	var back := StandPlacement.pushback_end(mid["stand"])
	var to_hold := back.z - GroundPlanner.gate_hold_z()
	var in_route: PackedVector3Array = mid["routes"][FlightSim.State.TAXI_IN]
	assert_float(in_mid[1]["hold_s"]).is_equal_approx(
		MovementPlan.path_length(in_route) - StandPlacement.PUSHBACK_M - to_hold, 0.001
	)
	(
		assert_array(out_mid.map(func(h: Dictionary) -> String: return h["hold"]))
		. is_equal([GroundPlanner.HOLD_GATE, GroundPlanner.HOLD_RUNWAY])
	)
	assert_float(out_mid[0]["hold_s"]).is_equal_approx(to_hold, 0.001)
	var out_route: PackedVector3Array = mid["routes"][FlightSim.State.TAXI_OUT]
	assert_float(out_mid[1]["hold_s"]).is_equal_approx(
		MovementPlan.path_length(out_route) - 30.0, 0.001
	)
	var expect := {0: false, 10: false, 11: true}
	for row: int in expect:
		var at := _kit.request("B", PlaneClasses.MEDIUM, _kit.stand(Vector2i(43, row)))
		for state in GroundPlanner.TAXI_STATES:
			var names := planner.holds(at, state).map(
				func(h: Dictionary) -> String: return h["hold"]
			)
			(
				assert_bool(names.has(GroundPlanner.HOLD_GATE))
				. override_failure_message("row %d state %d holds %s" % [row, state, names])
				. is_equal(expect[row])
			)


## Pause options run none first, then by length from the shortest, then by
## hold line from the earliest, all valid for MovementPlan.
func test_pause_options_run_from_none_to_the_longest_pause() -> void:
	var planner := _kit.planner()
	var req := _kit.request("A", PlaneClasses.MEDIUM, _kit.stand(MID_CELL))
	for state in GroundPlanner.TAXI_STATES:
		var options := planner.phase_options(req, state)
		assert_dict(options[0]).is_empty()
		for i in range(2, options.size()):
			var key_a := [options[i - 1]["ticks"], options[i - 1]["hold_s"]]
			var key_b := [options[i]["ticks"], options[i]["hold_s"]]
			assert_bool(key_a < key_b).is_true()
		assert_int(options.size()).is_equal(1 + 2 * 8)
		assert_int(options[1]["ticks"]).is_equal(MovementPlan.PAUSE_STEP_TICKS)
		assert_int(options[options.size() - 1]["ticks"]).is_equal(MovementPlan.MAX_PAUSE_TICKS)


## The spacing table: two neighbouring stands whose exits are d whole metres
## apart can both swing a plane of a class at once from 19 / 42 / 66 m (small /
## medium / large), the ruled spacings StandEnvelope.spacing_cells() keeps.
## Measured with the planner's own clash() on the two pushback bookings.
func test_the_spacing_table() -> void:
	var table := {}
	for plane_class in PlaneClasses.ORDER:
		var smallest := -1
		for d in range(5, 90):
			var a := _kit.request("A", plane_class, StandPlacement.make(1, 0.5, -120.0))
			var b := _kit.request("B", plane_class, StandPlacement.make(2, 0.5 + d, -120.0))
			if not _swings_clash(a, b):
				smallest = d
				break
		table[plane_class] = smallest
		# Control: a metre closer they clash.
		var near_a := _kit.request("A", plane_class, StandPlacement.make(1, 0.5, -120.0))
		var near_b := _kit.request("B", plane_class, StandPlacement.make(2, smallest - 0.5, -120.0))
		assert_bool(_swings_clash(near_a, near_b)).is_true()
	print("spacing table (m between exits): %s" % [table])
	assert_dict(table).is_equal(
		{PlaneClasses.SMALL: 19, PlaneClasses.MEDIUM: 42, PlaneClasses.LARGE: 66}
	)
	for plane_class in PlaneClasses.ORDER:
		assert_int(table[plane_class]).is_equal(StandEnvelope.spacing_cells(plane_class))


## Whether the swing-square pushback bookings of `a` and `b` clash.
func _swings_clash(a: Dictionary, b: Dictionary) -> bool:
	var swing_a: Dictionary = GroundPlanner.fixed_bookings(a)[1]
	var swing_b: Dictionary = GroundPlanner.fixed_bookings(b)[1]
	assert_str(swing_a["kind"]).is_equal(GroundPlanner.PUSHBACK)
	assert_that(swing_a["rect"]).is_equal(StandEnvelope.rects(a["stand"], a["class"])[0])
	return GroundPlanner.clash(swing_a, swing_b)


## Rectangles that only share an edge, or windows that only meet, do not clash.
func test_clash_needs_area_and_overlapping_time() -> void:
	var a := {"rect": Rect2(0, 0, 8, 10), "from": 0.0, "to": 10.0}
	var edge := {"rect": Rect2(8, 0, 8, 10), "from": 0.0, "to": 10.0}
	var after := {"rect": Rect2(0, 0, 8, 10), "from": 10.0, "to": 20.0}
	var both := {"rect": Rect2(7.9, 0, 8, 10), "from": 9.9, "to": 20.0}
	assert_bool(GroundPlanner.clash(a, edge)).is_false()
	assert_bool(GroundPlanner.clash(a, after)).is_false()
	assert_bool(GroundPlanner.clash(a, both)).is_true()


## The booking windows of one medium flight at MID_CELL departing 10:00 on
## day 1, no pause: counts by kind and the windows of its runway blocks,
## corners, parked and pushback bookings, to a thousandth of a tick.
func test_the_booking_windows_are_pinned() -> void:
	var req := _kit.request("A", PlaneClasses.MEDIUM, _kit.stand(MID_CELL))
	var list: Array[Dictionary] = GroundPlanner.fixed_bookings(req)
	for state in GroundPlanner.TAXI_STATES:
		list.append_array(GroundPlanner.phase_bookings(req, state, {}))
	var counts := {}
	var held := 0.0
	var lines: Array[String] = []
	for booking in list:
		counts[booking["kind"]] = counts.get(booking["kind"], 0) + 1
		held += booking["to"] - booking["from"]
		if booking["kind"] != GroundPlanner.SLICE:
			lines.append(
				(
					"%s %.3f %.3f %.3f %.3f: %.3f-%.3f"
					% [
						booking["kind"],
						booking["rect"].position.x,
						booking["rect"].position.y,
						booking["rect"].size.x,
						booking["rect"].size.y,
						booking["from"],
						booking["to"]
					]
				)
			)
	print("starts %s" % [req["starts"]])
	print("counts %s, held %.3f" % [counts, held])
	for line in lines:
		print(line)
	assert_dict(counts).is_equal(PINNED_COUNTS)
	assert_float(held).is_equal_approx(PINNED_HELD, 0.001)
	assert_array(lines).is_equal(PINNED_LINES)
