class_name TestStandaloneCorridorServices
extends GdUnitTestSuite
## Regression suite for Build Slice B1a (decisions c221025a and 593876df):
## ATM, Currency Exchange, Grab-and-go stall, and Nap pod are standalone
## corridor services (not RoomTypes), place directly on plain terminal floor or
## inside another room, run full passenger/staff/fee/mood/recovery lifecycles,
## recover cleanly when deleted mid-visit, and round-trip through SaveGame/sim
## snapshots.

const STANDALONE_IDS: Array[StringName] = [&"stall", &"exchange", &"atm", &"nap_pod"]
const STANDALONE_PIECES: Array[StringName] = [
	&"grab_and_go_stall",
	&"currency_exchange",
	&"atm",
	&"nap_pod",
]
const STANDALONE_TOOLS: Array[BuildMode.Tool] = [
	BuildMode.Tool.GRAB_STALL,
	BuildMode.Tool.EXCHANGE,
	BuildMode.Tool.ATM,
	BuildMode.Tool.NAP_POD,
]
const CELLS := {
	&"stall": Vector2i(22, 3),
	&"exchange": Vector2i(25, 3),
	&"atm": Vector2i(22, 6),
	&"nap_pod": Vector2i(25, 6),
}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _grid_with_standalone(service_id: StringName) -> Dictionary:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, [])
	var at := ReferenceTerminal.offset_on(grid)
	var def := ServiceTypes.get_service(service_id)
	var piece_id: StringName = (
		def.counter_pieces[0] if not def.counter_pieces.is_empty() else def.seat_piece
	)
	var res := grid.apply(BuildEdit.place_object(piece_id, CELLS[service_id] + at, 0))
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	return {"grid": grid, "piece": res.object_id, "at": at}


func _guest(world: PassengerTestWorld, boredom := 0, hunger := 0) -> Passenger:
	var p := ShopTestLayout.airside_guest(world, boredom, Vector2i(19, 5))
	p.mood = 60
	p.hunger = hunger
	p.cafe_cooldown = 0
	p.set_path(
		world.grid.find_path(p.at, Vector2i(21, 5) + ReferenceTerminal.offset_on(world.grid))
	)
	return p


func _snapshot_of(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _restore(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 77)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


func test_services_absent_from_room_types_and_place_on_corridor_or_in_rooms() -> void:
	for id: StringName in STANDALONE_IDS:
		assert_object(RoomTypes.get_type(id)).override_failure_message(str(id)).is_null()
		assert_bool(RoomTypes.ids().has(id)).override_failure_message(str(id)).is_false()
		assert_object(ServiceTypes.get_service(id)).is_not_null()
		for tool: BuildMode.Tool in BuildMode.TOOL_ROOMS:
			assert_str(str(BuildMode.TOOL_ROOMS[tool])).is_not_equal(str(id))

	var mode := BuildMode.new()
	mode.grid_size = Vector2i(32, 22)
	add_child(mode)
	mode.set_process(false)
	ShopTestLayout.build(mode.grid, [])
	var at := ReferenceTerminal.offset_on(mode.grid)

	# Place directly on plain walkable corridor floor (room_at == 0).
	for i in STANDALONE_TOOLS.size():
		var tool := STANDALONE_TOOLS[i]
		var svc_id := STANDALONE_IDS[i]
		var cell: Vector2i = CELLS[svc_id] + at
		assert_int(mode.grid.room_at(cell)).is_equal(0)
		mode.set_tool(tool)
		var placed := mode.apply_at(mode.grid.cell_to_world(cell))
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
		assert_int(mode.grid.room_at(cell)).is_equal(0)
		if ShopCounters.ROOMLESS.has(BuildMode.tool_object(tool)):
			assert_bool(ShopCounters.is_roomless(mode.grid, placed.object_id)).is_true()
			assert_int(ShopCounters.room_of(mode.grid, placed.object_id)).is_equal(0)

	var terminal := TerminalLayout.new()
	terminal.rebuild(mode.grid)
	var cafes := CafeLayout.new()
	cafes.rebuild(mode.grid, terminal)
	assert_int(cafes.cafes.size()).is_equal(1)
	assert_int(cafes.cafes[0]["room"]).is_equal(0)
	assert_str(str(cafes.cafes[0]["type"])).is_equal("stall")

	var shops := ShopLayout.new()
	shops.rebuild(mode.grid)
	assert_int(shops.shops.size()).is_equal(3)
	for entry: Dictionary in shops.shops:
		assert_int(entry["room"]).is_equal(0)

	# Remove and place all 4 inside another enclosed room (a lounge): still valid and roomless!
	for svc_id: StringName in STANDALONE_IDS:
		mode.set_tool(BuildMode.Tool.REMOVE)
		mode.apply_at(mode.grid.cell_to_world(CELLS[svc_id] + at))
	var lounge := (
		mode
		. grid
		. apply(
			BuildEdit.place_room(Rect2i(Vector2i(22, 3) + at, Vector2i(6, 6)), &"lounge"),
		)
	)
	assert_bool(lounge.ok).is_true()
	for i in STANDALONE_TOOLS.size():
		var tool := STANDALONE_TOOLS[i]
		var svc_id := STANDALONE_IDS[i]
		var cell: Vector2i = CELLS[svc_id] + at
		mode.set_tool(tool)
		var placed := mode.apply_at(mode.grid.cell_to_world(cell))
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
		if ShopCounters.ROOMLESS.has(BuildMode.tool_object(tool)):
			assert_bool(ShopCounters.is_roomless(mode.grid, placed.object_id)).is_true()
			assert_int(ShopCounters.room_of(mode.grid, placed.object_id)).is_equal(0)
	cafes.rebuild(mode.grid, terminal)
	assert_int(cafes.cafes.size()).is_equal(1)
	assert_int(cafes.cafes[0]["room"]).is_equal(0)
	shops.rebuild(mode.grid)
	assert_int(shops.shops.size()).is_equal(3)
	mode.free()


func test_passengers_discover_use_pay_and_finish_at_all_four_standalone_services() -> void:
	# 1. Grab-and-go stall: food/hunger pipeline, staffed, pays, clears hunger, finishes.
	var built := _grid_with_standalone(&"stall")
	var world := PassengerTestWorld.make(built["grid"], FlightSim.schedule_starts(0), 101)
	world.auto_staff = false
	world.run_to(10)
	assert_bool(ShopCounters.piece_open(world.sim, built["piece"])).is_false()
	StaffTestKit.seat_server(world.staff, built["piece"])
	assert_bool(ShopCounters.piece_open(world.sim, built["piece"])).is_true()
	var hungry := _guest(world, 0, CafeSim.HUNGRY_AT)
	assert_int(NeedsPolicy.arbitrate(world.sim, hungry)).is_equal(NeedsPolicy.Need.HUNGER)
	var stall_visit := world.sim.cafes.visit_of(hungry.id)
	assert_object(stall_visit).is_not_null()
	assert_int(stall_visit.room).is_equal(0)
	assert_int(stall_visit.counter).is_equal(built["piece"])
	var before_balance := world.sim.wallet.balance
	var guard := world.clock.tick + 1500
	while world.sim.cafes.visit_of(hungry.id) != null and world.clock.tick < guard:
		world.step()
	assert_int(stall_visit.outcome).is_equal(CafeVisit.Outcome.COMPLETE)
	assert_int(world.sim.wallet.balance).is_greater(before_balance)
	assert_int(hungry.hunger).is_equal(0)
	assert_int(hungry.stage).is_equal(Passenger.Stage.TO_GATE)
	world.free_all()

	# 2 & 3. Currency Exchange (staffed) and ATM (unstaffed): browse, pay fee, finish.
	for svc_id: StringName in [&"exchange", &"atm"]:
		built = _grid_with_standalone(svc_id)
		world = PassengerTestWorld.make(built["grid"], FlightSim.schedule_starts(0), 102)
		world.auto_staff = false
		world.run_to(10)
		if svc_id == &"exchange":
			assert_bool(ShopCounters.piece_open(world.sim, built["piece"])).is_false()
			StaffTestKit.seat_server(world.staff, built["piece"])
		assert_bool(ShopCounters.piece_open(world.sim, built["piece"])).is_true()
		var browser := _guest(world, 0, 0)
		assert_int(NeedsPolicy.arbitrate(world.sim, browser)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
		var visit := world.sim.shops.visit_of(browser.id)
		assert_object(visit).is_not_null()
		assert_int(visit.room).is_equal(0)
		assert_int(visit.display).is_equal(built["piece"])
		before_balance = world.sim.wallet.balance
		guard = world.clock.tick + 1500
		while world.sim.shops.visit_of(browser.id) != null and world.clock.tick < guard:
			world.step()
		assert_int(world.sim.wallet.balance).is_greater(before_balance)
		assert_int(browser.stage).is_equal(Passenger.Stage.TO_GATE)
		world.free_all()

	# 4. Nap pod (unstaffed): relieves boredom, lifts mood, pays fee, finishes.
	built = _grid_with_standalone(&"nap_pod")
	world = PassengerTestWorld.make(built["grid"], FlightSim.schedule_starts(0), 103)
	world.auto_staff = false
	world.run_to(10)
	assert_bool(ShopCounters.piece_open(world.sim, built["piece"])).is_true()
	var tired := _guest(world, 80, 0)
	var mood_before := tired.mood
	assert_int(NeedsPolicy.arbitrate(world.sim, tired)).is_equal(NeedsPolicy.Need.BOREDOM)
	var nap_visit := world.sim.shops.visit_of(tired.id)
	assert_object(nap_visit).is_not_null()
	assert_int(nap_visit.room).is_equal(0)
	assert_int(nap_visit.display).is_equal(built["piece"])
	before_balance = world.sim.wallet.balance
	guard = world.clock.tick + 1500
	while world.sim.shops.visit_of(tired.id) != null and world.clock.tick < guard:
		world.step()
	assert_int(world.sim.wallet.balance).is_greater(before_balance)
	assert_int(tired.boredom).is_equal(0)
	assert_int(tired.mood).is_equal(mood_before + ServiceTypes.get_service(&"nap_pod").mood_bonus)
	assert_int(tired.stage).is_equal(Passenger.Stage.TO_GATE)
	world.free_all()


func test_deleting_each_standalone_service_mid_visit_recovers_passenger_cleanly() -> void:
	for svc_id: StringName in STANDALONE_IDS:
		var built := _grid_with_standalone(svc_id)
		var world := PassengerTestWorld.make(built["grid"], FlightSim.schedule_starts(0), 200)
		world.run_to(10)
		var p: Passenger
		if svc_id == &"stall":
			p = _guest(world, 0, CafeSim.HUNGRY_AT)
			assert_int(NeedsPolicy.arbitrate(world.sim, p)).is_equal(NeedsPolicy.Need.HUNGER)
		elif svc_id == &"nap_pod":
			p = _guest(world, 80, 0)
			assert_int(NeedsPolicy.arbitrate(world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		else:
			p = _guest(world, 0, 0)
			assert_int(NeedsPolicy.arbitrate(world.sim, p)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
		# Advance until the guest is partway into the visit, then delete the piece.
		for _t in 10:
			world.step()
		assert_bool(world.grid.apply(BuildEdit.remove_object(built["piece"])).ok).is_true()
		world.step()
		if svc_id == &"stall":
			assert_object(world.sim.cafes.visit_of(p.id)).is_null()
		else:
			assert_object(world.sim.shops.visit_of(p.id)).is_null()
		world.run_to(world.flights.doors_close_tick(p.flight_id) + 1)
		assert_int(p.stage).override_failure_message(str(svc_id)).is_equal(Passenger.Stage.MADE)
		world.free_all()


func test_standalone_corridor_services_and_active_visits_survive_save_load_round_trip() -> void:
	assert_int(PassengerSim.SAVE_VERSION).is_equal(37)
	assert_int(SaveGame.SAVE_VERSION).is_equal(32)
	for svc_id: StringName in [&"stall", &"exchange"]:
		var built := _grid_with_standalone(svc_id)
		var a := PassengerTestWorld.make(built["grid"], FlightSim.schedule_starts(0), 300)
		a.run_to(10)
		var p := _guest(a, 0, CafeSim.HUNGRY_AT if svc_id == &"stall" else 0)
		var want_need := (
			NeedsPolicy.Need.HUNGER if svc_id == &"stall" else NeedsPolicy.Need.SHOP_BROWSE
		)
		assert_int(NeedsPolicy.arbitrate(a.sim, p)).is_equal(want_need)
		for _t in 10:
			a.step()
		var saved := _snapshot_of(a)
		var b := _restore(saved)
		assert_int(b.grid.room_at(CELLS[svc_id] + built["at"])).is_equal(0)
		assert_int(b.grid.object_at(CELLS[svc_id] + built["at"])).is_equal(built["piece"])
		if svc_id == &"stall":
			var v := b.sim.cafes.visit_of(p.id)
			assert_object(v).is_not_null()
			assert_int(v.room).is_equal(0)
			assert_int(v.counter).is_equal(built["piece"])
		else:
			var v := b.sim.shops.visit_of(p.id)
			assert_object(v).is_not_null()
			assert_int(v.room).is_equal(0)
			assert_int(v.display).is_equal(built["piece"])
		var guard := b.clock.tick + 1500
		while b.clock.tick < guard:
			if svc_id == &"stall" and b.sim.cafes.visit_of(p.id) == null:
				break
			if svc_id != &"stall" and b.sim.shops.visit_of(p.id) == null:
				break
			b.step()
		var bp := b.passenger(p.id)
		assert_int(b.sim.wallet.balance).is_greater(0)
		assert_int(bp.stage).is_equal(Passenger.Stage.TO_GATE)
		a.free_all()
		b.free_all()
