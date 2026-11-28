class_name TestCafeKioskTraffic
extends GdUnitTestSuite
## Regression test for realistic Tier-2 Cafe and Kiosk traffic across both
## airside and landside placements and arriving passengers, with zero missed
## flights from venue detours.

const SITE := preload("res://build/terminal_site.tres")
const FIRST_STATE := 1360
const SEEDS: Array[int] = [11, 22, 33]
const PAX_PER_FLIGHT := 12

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _build_tier2_terminal() -> Dictionary:
	var grid := SiteGrid.new(SITE)
	assert_bool(ReferenceTerminal.build(grid, SITE.starter_offset)).is_true()
	var at := SITE.starter_offset
	var gate_res := grid.apply(ReferenceTerminal.gate_desk_edit(at))
	assert_bool(gate_res.ok).override_failure_message(gate_res.reason_text()).is_true()
	var airside_exit := BuildEdit.place_object(
		BuildCatalog.AIRSIDE_EXIT_ID, at + Vector2i(13, 8), 2
	)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, airside_exit):
		var res := grid.apply(edit)
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()

	# East wing (x 22..32, y 3..15): airside (y 3..8) and landside (y 10..15),
	# with a staffed Cafe and staffed Kiosk on each side.
	var edits: Array[BuildEdit] = []
	for y in range(3, 16):
		for x in range(22, 33):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + at, BuildGrid.FLOOR_TILE, 1))
	for x in range(22, 33):
		edits.append(
			BuildEdit.place_wall(
				Vector2i(x, ReferenceTerminal.DIVIDER_Y) + at, BuildGrid.Side.NORTH
			)
		)
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y) + at, BuildGrid.Side.EAST))
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	EnclosureKit.close_floor(grid)

	var air_cafe := _place_cafe(grid, Rect2i(22, 3, 5, 5), at)
	var air_kiosk := _place_kiosk(grid, Rect2i(28, 3, 5, 4), at)
	var land_cafe := _place_cafe(grid, Rect2i(22, 10, 5, 5), at)
	var land_kiosk := _place_kiosk(grid, Rect2i(28, 10, 5, 4), at)
	return {
		"grid": grid,
		"air_cafe": air_cafe,
		"air_kiosk": air_kiosk,
		"land_cafe": land_cafe,
		"land_kiosk": land_kiosk,
	}


func _place_cafe(grid: BuildGrid, rel_rect: Rect2i, at: Vector2i) -> int:
	var rect := Rect2i(rel_rect.position + at, rel_rect.size)
	var room_id := _apply(grid, BuildEdit.place_room(rect, &"cafe")).room_id
	_apply(grid, BuildEdit.place_object(&"cafe_counter", rect.position + Vector2i(0, 1), 0))
	_apply(grid, BuildEdit.place_object(&"cafe_table", rect.position + Vector2i(3, 0), 1))
	var status := RoomRules.status(grid, room_id)
	assert_bool(status.ok).override_failure_message(str(status.notes)).is_true()
	return room_id


func _place_kiosk(grid: BuildGrid, rel_rect: Rect2i, at: Vector2i) -> int:
	var rect := Rect2i(rel_rect.position + at, rel_rect.size)
	var room_id := _apply(grid, BuildEdit.place_room(rect, &"kiosk")).room_id
	_apply(grid, BuildEdit.place_object(&"kiosk_counter", rect.position + Vector2i(0, 1), 0))
	_apply(grid, BuildEdit.place_object(&"kiosk_display", rect.position + Vector2i(3, 1), 1))
	var status := RoomRules.status(grid, room_id)
	assert_bool(status.ok).override_failure_message(str(status.notes)).is_true()
	return room_id


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var res := grid.apply(edit)
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	return res


func test_departing_passengers_visibly_use_cafe_and_kiosk_without_missing() -> void:
	var totals := {"early": 0, "cafe": 0, "kiosk": 0, "missed": 0}
	for seed in SEEDS:
		var built := _build_tier2_terminal()
		var grid: SiteGrid = built["grid"]
		var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(FIRST_STATE), seed)
		world.sim.site = SITE
		_worlds.append(world)
		var sim := world.sim
		var spawned := {}
		var room_visits := {}
		var run_counts := {"settled": 0, "cafe": 0, "kiosk": 0, "missed": 0}
		sim.passenger_spawned.connect(func(id: int) -> void: spawned[id] = sim.tick)
		sim.cafes.paid.connect(
			func(_id: int, room: int, _amount: int) -> void:
				run_counts["cafe"] += 1
				totals["cafe"] += 1
				room_visits[room] = int(room_visits.get(room, 0)) + 1
		)
		sim.shops.paid.connect(
			func(_id: int, room: int, _amount: int) -> void:
				run_counts["kiosk"] += 1
				totals["kiosk"] += 1
				room_visits[room] = int(room_visits.get(room, 0)) + 1
		)
		sim.outcome.connect(
			func(_id: int, made: bool) -> void:
				run_counts["settled"] += 1
				if not made:
					run_counts["missed"] += 1
					totals["missed"] += 1
		)
		assert_bool(sim.schedule_flight(PassengerTestWorld.FLIGHT, PAX_PER_FLIGHT)).is_true()
		var boarding := world.flights.boarding_window(PassengerTestWorld.FLIGHT).x
		var doors := world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
		while int(run_counts["settled"]) < PAX_PER_FLIGHT and world.clock.tick <= doors:
			world.step()
		for id: int in spawned:
			if int(spawned[id]) < boarding:
				totals["early"] += 1
		var air_c: int = room_visits.get(built["air_cafe"], 0)
		var land_c: int = room_visits.get(built["land_cafe"], 0)
		var air_k: int = room_visits.get(built["air_kiosk"], 0)
		var land_k: int = room_visits.get(built["land_kiosk"], 0)
		print(
			(
				"seed %d: cafe=%d (air=%d, land=%d), kiosk=%d (air=%d, land=%d), missed=%d"
				% [
					seed,
					run_counts["cafe"],
					air_c,
					land_c,
					run_counts["kiosk"],
					air_k,
					land_k,
					run_counts["missed"],
				]
			)
		)
	assert_int(totals["early"]).is_greater_equal(SEEDS.size() * 8)
	assert_int(totals["cafe"]).is_greater_equal(SEEDS.size() * 2)
	assert_int(totals["kiosk"]).is_greater_equal(SEEDS.size() * 2)
	assert_int(totals["missed"]).is_equal(0)


func test_arriving_passengers_visit_landside_cafe_and_kiosk_and_respect_hunger_gate() -> void:
	var built := _build_tier2_terminal()
	var grid: SiteGrid = built["grid"]
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 77)
	world.sim.site = SITE
	_worlds.append(world)
	var sim := world.sim

	# Tier-1 gate: with hunger_enabled false, arriving passengers spawn with 0 hunger.
	sim.cafes.hunger_enabled = false
	var gated := PassengerArrivals.spawn(sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(gated).is_not_null()
	assert_int(gated.hunger).is_equal(0)
	PassengerArrivals.finish(sim, gated)

	# Tier-2 enabled: 12 arriving passengers walk past landside Cafe and Kiosk.
	sim.cafes.hunger_enabled = true
	var counts := {"cafe": 0, "kiosk": 0, "finished": 0}
	sim.cafes.paid.connect(
		func(_id: int, room: int, _amount: int) -> void:
			if room == built["land_cafe"]:
				counts["cafe"] += 1
	)
	sim.shops.paid.connect(
		func(_id: int, room: int, _amount: int) -> void:
			if room == built["land_kiosk"]:
				counts["kiosk"] += 1
	)
	sim.arrival_finished.connect(func(_id: int) -> void: counts["finished"] += 1)

	for i in 12:
		var arr := PassengerArrivals.spawn(sim, PassengerTestWorld.FLIGHT, i % 2)
		assert_object(arr).is_not_null()
		world.run_to(world.clock.tick + 15)

	for _i in 2000:
		world.step()
		if int(counts["finished"]) >= 12 and sim.active_count() == 0:
			break

	print(
		(
			"arrivals: land_cafe=%d, land_kiosk=%d, finished=%d"
			% [counts["cafe"], counts["kiosk"], counts["finished"]]
		)
	)
	assert_int(counts["cafe"]).is_greater(0)
	assert_int(counts["kiosk"]).is_greater(0)
	assert_int(counts["finished"]).is_equal(12)
	assert_int(sim.active_count()).is_equal(0)
