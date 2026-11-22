class_name TestGroundPlannerSpurs
extends GdUnitTestSuite
## GroundPlanner at west and east stands (board airside-all-around-s4, slice S4
## of design airside-all-around-technical-design-one-route-source-per-con):
## their routes run on the two two-way spurs south from TaxiWest and TaxiEast,
## so every segment is on the axes and the planner books them. Their parked
## footprint faces the stand's own way, their pushback books the spur slices
## its swing square touches, and their hold lines are the spur head on the lane
## (inbound, west spur) and the stand connector's H_g, turned from the north
## lead-in hold. Sampling (GroundPlannerKit.sample()) checks that the analytic
## windows cover every half tick at a spread of synthetic side stands.

## A west and an east stand with the sill at x 0, z -149.5: 124 m from either
## spur, so the connector has its hold line both ways.
const WEST_CELL := Vector2i(128, 60)
const EAST_CELL := Vector2i(127, 60)

var _kit: GroundPlannerKit


func before() -> void:
	_kit = GroundPlannerKit.new()


func _req(
	id: String, plane_class: String, cell: Vector2i, side: String, minute := 600
) -> Dictionary:
	return _kit.request(
		id, plane_class, _kit.stand(cell, side), GroundPlannerKit.DEPARTURE_DAY, minute
	)


static func _names(lines: Array) -> Array:
	return lines.map(func(h: Dictionary) -> String: return h["hold"])


## Both side stands' taxi routes run on the axes and plan with no pause on an
## empty airside. Before the spurs, TaxiRoutes gave them a diagonal from
## TaxiEast and the planner refused it (BAD_ROUTE).
func test_side_routes_run_on_the_axes_and_plan() -> void:
	for side in [StandPlacement.WEST, StandPlacement.EAST]:
		var cell := WEST_CELL if side == StandPlacement.WEST else EAST_CELL
		var stand := _kit.stand(cell, side)
		var planned := FlightGround.routes(stand, PlaneClasses.MEDIUM)
		var kit := _kit.routes(stand, PlaneClasses.MEDIUM)
		for state in GroundPlanner.TAXI_STATES:
			var route: PackedVector3Array = planned[state]
			print("%s state %d: %s" % [side, state, route])
			(
				assert_bool(GroundPlanner.axis_aligned(route))
				. override_failure_message("%s state %d %s" % [side, state, route])
				. is_true()
			)
			assert_array(Array(route)).is_equal(Array(kit[state]))
		# On the stand's own taxi pair (TaxiTimes.for_stand()), as its contract.
		var pair := TaxiTimes.for_stand(stand)
		print("%s taxi pair %s: %s" % [side, pair, TaxiTimes.problem(pair)])
		assert_str(TaxiTimes.problem(pair)).is_equal("")
		var req := GroundPlanner.request(
			"S", PlaneClasses.MEDIUM, stand, GroundPlannerKit.starts_at(1, 600, pair), planned, 0
		)
		var result: Dictionary = _kit.planner().plan_all([req])["S"]
		print(
			(
				"%s plan: ok %s reason '%s', %d bookings"
				% [side, result["ok"], result["reason"], result["bookings"].size()]
			)
		)
		assert_bool(result["ok"]).is_true()
		(
			assert_array(
				result["pauses"].values().filter(
					func(p: Dictionary) -> bool: return not p.is_empty()
				)
			)
			. is_empty()
		)


## The hold lines of a side stand: inbound H_IN on the east stub, the west spur
## head on the lane (west stands only: an east stand's taxi in never runs on
## the lane) and the connector's H_g; outbound H_g, then H_RWY. H_g lies the
## north lead-in hold's distance (gate_hold_z() - TAXI_LANE_Z) from the spur
## along the connector, and the spur head that far east of TaxiWest on the
## lane, so a plane stopped on either keeps every nose clear of the spur band.
func test_side_hold_lines() -> void:
	var planner := _kit.planner()
	var clear := GroundPlanner.gate_hold_z() - StandPlacement.TAXI_LANE_Z
	var west := _req("W", PlaneClasses.MEDIUM, WEST_CELL, StandPlacement.WEST)
	var east := _req("E", PlaneClasses.MEDIUM, EAST_CELL, StandPlacement.EAST)
	var w_in := planner.holds(west, FlightSim.State.TAXI_IN)
	var w_out := planner.holds(west, FlightSim.State.TAXI_OUT)
	var e_in := planner.holds(east, FlightSim.State.TAXI_IN)
	var e_out := planner.holds(east, FlightSim.State.TAXI_OUT)
	print("west in %s out %s; east in %s out %s" % [w_in, w_out, e_in, e_out])
	assert_array(_names(w_in)).is_equal(
		[GroundPlanner.HOLD_IN, GroundPlanner.HOLD_SPUR, GroundPlanner.HOLD_GATE]
	)
	assert_array(_names(w_out)).is_equal([GroundPlanner.HOLD_GATE, GroundPlanner.HOLD_RUNWAY])
	assert_array(_names(e_in)).is_equal([GroundPlanner.HOLD_IN, GroundPlanner.HOLD_GATE])
	assert_array(_names(e_out)).is_equal([GroundPlanner.HOLD_GATE, GroundPlanner.HOLD_RUNWAY])
	var w_join := StandPlacement.lane_join(west["stand"])
	var e_join := StandPlacement.lane_join(east["stand"])
	var w_gate := GroundPlanner.gate_hold(west["stand"])
	var e_gate := GroundPlanner.gate_hold(east["stand"])
	print("west H_g %s, east H_g %s" % [w_gate, e_gate])
	assert_vector(w_gate).is_equal_approx(w_join + Vector3(clear, 0.0, 0.0), Vector3.ONE * 0.001)
	assert_vector(e_gate).is_equal_approx(e_join - Vector3(clear, 0.0, 0.0), Vector3.ONE * 0.001)
	var head := Airside.spur_head_hold(w_join)
	print("west spur head %s" % head)
	assert_vector(head).is_equal_approx(
		Vector3(-StandPlacement.SIDE_LANE_X + clear, 0.0, StandPlacement.TAXI_LANE_Z),
		Vector3.ONE * 0.001
	)
	# Metres along: the spur head is on the lane, 248 m less `clear` past
	# TaxiEast, and H_g on the out route is `clear` short of the join.
	var lane := 2.0 * StandPlacement.SIDE_LANE_X
	assert_float(w_in[1]["hold_s"]).is_equal_approx(54.0 + lane - clear, 0.001)
	var back := StandPlacement.pushback_end(west["stand"])
	assert_float(w_out[0]["hold_s"]).is_equal_approx(absf(back.x - w_join.x) - clear, 0.001)
	# A side stand whose pushback ends inside that distance of the spur has no
	# H_g, as a north-row stand has none: the twin of north row 0.
	var near := _kit.stand(Vector2i(78, 60), StandPlacement.WEST)
	assert_float(StandPlacement.north_twin(near)["wall_z"]).is_equal(-210.0)
	assert_vector(GroundPlanner.gate_hold(near)).is_equal(Vector3.INF)


## A side stand's fixed bookings face its own way: the parked footprint lies
## nose to the stand's wall (east at a west stand, west at an east one), and
## the pushback books the swing square, the parked footprint and every slice
## of the stand's own spur the swing square touches, none on the north lane.
func test_side_parked_and_pushback_bookings_face_the_stand() -> void:
	for side in [StandPlacement.WEST, StandPlacement.EAST]:
		var req := _req("S", PlaneClasses.LARGE, _nearest_to_spur(PlaneClasses.LARGE, side), side)
		var stand: Dictionary = req["stand"]
		var fp := GroundPlanner.footprint(PlaneClasses.LARGE)
		var spot := StandPlacement.stand_point(stand)
		var nose := StandPlacement.turn(stand, Vector3(0.0, 0.0, 1.0))
		var list := GroundPlanner.fixed_bookings(req)
		var is_parked := func(b: Dictionary) -> bool: return b["kind"] == GroundPlanner.PARKED
		var parked: Rect2 = list.filter(is_parked)[0]["rect"]
		print("%s parked %s, nose %s" % [side, parked, nose])
		assert_float(parked.size.x).is_equal_approx(fp["ahead"] + fp["behind"], 0.001)
		assert_float(parked.size.y).is_equal_approx(2.0 * fp["half_width"], 0.001)
		var ahead := spot.x + nose.x * float(fp["ahead"])
		assert_float(parked.end.x if nose.x > 0.0 else parked.position.x).is_equal_approx(
			ahead, 0.001
		)
		var swing: Rect2 = StandEnvelope.rects(stand, PlaneClasses.LARGE)[0]
		var spur_x := StandPlacement.lane_join(stand).x
		var slices := list.filter(
			func(b: Dictionary) -> bool: return b["kind"] == GroundPlanner.SLICE
		)
		print("%s swing %s, %d pushback slices" % [side, swing, slices.size()])
		assert_int(slices.size()).is_greater(0)
		for one: Dictionary in slices:
			var rect: Rect2 = one["rect"]
			assert_float(rect.get_center().x).is_equal_approx(spur_x, 0.001)
			assert_float(rect.size.y).is_equal(GroundPlanner.SLICE_M)
			assert_bool(rect.intersects(swing)).is_true()
		var reach := (
			ceili(swing.end.y / GroundPlanner.SLICE_M)
			- floori(swing.position.y / GroundPlanner.SLICE_M)
		)
		assert_int(slices.size()).is_equal(reach)


## The legal side stand of `plane_class` on row 60 nearest its spur, whose
## swing square reaches the spur band.
func _nearest_to_spur(plane_class: String, side: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var west := side == StandPlacement.WEST
	for x in GroundPlannerKit.SITE.grid_size.x:
		var cell := Vector2i(x, 60)
		if not _kit.is_legal(_kit.stand(cell, side), plane_class):
			continue
		if best.x < 0 or (cell.x < best.x if west else cell.x > best.x):
			best = cell
	return best


## The spread of legal side stands of `plane_class` facing out to `side`: the
## four corners of the legal set and eight neighbouring columns and rows from
## its middle (every offset against the 8 m slice grid, along the connector and
## along the spur).
func _spread(plane_class: String, side: String) -> Array[Vector2i]:
	var legal := _kit.legal_cells(plane_class, side)
	var low := legal[0]
	var high := legal[0]
	for cell in legal:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var middle := Vector2i(floori((low.x + high.x) / 2.0), floori((low.y + high.y) / 2.0))
	var wanted: Array[Vector2i] = [low, high, Vector2i(low.x, high.y), Vector2i(high.x, low.y)]
	for d in 8:
		wanted.append(Vector2i(middle.x + d, middle.y))
		wanted.append(Vector2i(middle.x, middle.y + d))
	var out: Array[Vector2i] = []
	for cell in wanted:
		if legal.has(cell) and not out.has(cell):
			out.append(cell)
	print(
		(
			"%s %s: %d legal stands, rows %d-%d, columns %d-%d"
			% [plane_class, side, legal.size(), low.y, high.y, low.x, high.x]
		)
	)
	return out


func _check(plane_class: String) -> void:
	var planner := _kit.planner()
	var plans := 0
	var samples := 0
	for side in [StandPlacement.WEST, StandPlacement.EAST]:
		var stands := _spread(plane_class, side)
		assert_int(stands.size()).is_greater_equal(10)
		for cell in stands:
			var req := _kit.request("A", plane_class, _kit.stand(cell, side))
			var options: Array[Dictionary] = [{}]
			options.append_array(GroundPlannerKit.every_hold_pauses(planner, req))
			for pauses in options:
				var result := GroundPlannerKit.sample(req, pauses)
				plans += 1
				samples += result["samples"]
				(
					assert_int(result["uncovered"])
					. override_failure_message(
						"%s %s %s %s: %s" % [plane_class, side, cell, pauses, result]
					)
					. is_equal(0)
				)
	print("%s side stands: %d plans, %d half-tick samples" % [plane_class, plans, samples])
	assert_int(samples).is_greater(plans * 4000)


func test_small_side_windows_cover_every_sampled_tick() -> void:
	_check(PlaneClasses.SMALL)


func test_medium_side_windows_cover_every_sampled_tick() -> void:
	_check(PlaneClasses.MEDIUM)


func test_large_side_windows_cover_every_sampled_tick() -> void:
	_check(PlaneClasses.LARGE)


## Whether any two of `held`'s bookings of different owners clash, checked pair
## by pair in time order (not with the planner's own index): [clashes, pairs
## compared].
static func _clashes(held: Array[Dictionary]) -> Array[int]:
	held.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["from"] < b["from"])
	var clashes := 0
	var compared := 0
	for i in held.size():
		var j := i + 1
		while j < held.size() and held[j]["from"] < held[i]["to"]:
			if held[j]["owner"] != held[i]["owner"]:
				compared += 1
				if GroundPlanner.clash(held[i], held[j]):
					clashes += 1
			j += 1
	return [clashes, compared]


## The spurs are two-way: a plane taxiing in to a stand far down a spur meets
## one taxiing out from a stand near its head. For each side, B (row 110)
## departs a searched number of minutes after A (row 20) until B's plan needs a
## pause; it takes one at a hold line, and the two flights' bookings never
## clash.
func test_inbound_and_outbound_on_one_spur_resolve_with_a_pause() -> void:
	var planner := _kit.planner()
	for side in [StandPlacement.WEST, StandPlacement.EAST]:
		var column := 128 if side == StandPlacement.WEST else 127
		var a := _req("A", PlaneClasses.MEDIUM, Vector2i(column, 20), side, 600)
		var found := {}
		for minute in range(600 + 60, 600 + 300):
			var b := _req("B", PlaneClasses.MEDIUM, Vector2i(column, 110), side, minute)
			var out := planner.plan_all([a, b])
			if not out["B"]["ok"]:
				continue
			for state: int in out["B"]["pauses"]:
				var pause: Dictionary = out["B"]["pauses"][state]
				if not pause.is_empty():
					found = {"minute": minute, "state": state, "pause": pause}
					var check := _clashes(planner.bookings())
					print(
						(
							"%s: B at +%d min pauses %s, clashes %s"
							% [side, minute - 600, found, check]
						)
					)
					assert_int(check[0]).is_equal(0)
					assert_int(check[1]).is_greater(0)
					break
			if not found.is_empty():
				break
		assert_dict(found).override_failure_message("%s: B never paused" % side).is_not_empty()


## A busy day at two west, two east and one north stand, each departing every
## four hours from 07:00, the stands 25 minutes apart: every planned flight's
## bookings are clear of every other's, pair by pair.
func test_a_busy_day_on_the_spurs_never_books_a_clash() -> void:
	var stands := {"N0": _kit.stand(Vector2i(170, 60))}
	for i in 2:
		stands["W%d" % i] = _kit.stand(Vector2i(128, 20 + 90 * i), StandPlacement.WEST)
		stands["E%d" % i] = _kit.stand(Vector2i(127, 30 + 90 * i), StandPlacement.EAST)
	var flights: Array = []
	var offset := 0
	for name: String in stands:
		for slot in 4:
			var minute := 420 + 240 * slot + offset
			flights.append(
				_kit.request("%s_%d" % [name, slot], PlaneClasses.MEDIUM, stands[name], 1, minute)
			)
		offset += 25
	var planner := _kit.planner()
	var out := planner.plan_all(flights)
	var planned := {"W": 0, "E": 0, "N": 0}
	var at_hold := {}
	for id: String in out:
		if out[id]["ok"]:
			planned[id.substr(0, 1)] += 1
			for pause: Dictionary in out[id]["pauses"].values():
				if not pause.is_empty():
					at_hold[pause["hold"]] = at_hold.get(pause["hold"], 0) + 1
	var check := _clashes(planner.bookings())
	print(
		(
			"busy day: planned %s of 4 per stand, pauses by hold %s, %d pairs compared, %d clashes"
			% [planned, at_hold, check[1], check[0]]
		)
	)
	assert_int(planned["W"]).is_greater(0)
	assert_int(planned["E"]).is_greater(0)
	assert_int(check[1]).is_greater(1000)
	assert_int(check[0]).is_equal(0)
