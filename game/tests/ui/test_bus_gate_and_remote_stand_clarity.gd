class_name TestBusGateAndRemoteStandClarity
extends GdUnitTestSuite
## Integration and unit checks for decision
## bus-gate-and-remote-stand-clarity-inspect-cards-distinct-icons-tooltips-and-unpaired-alert
## (b4a4d6d1): Kind.REMOTE_STAND & upgraded BUS_GATE_DESK inspect cards,
## distinct thumbnails & 3D bus_gate_desk.glb, ItemInfo + CARD_NEEDS +
## GATE_DESK staffed copy, and self-clearing AlertSources pairing notices.

const SEED := 7_204_211
const SITE := preload("res://build/terminal_site.tres")

var _main: Node
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _sim: PassengerSim
var _bus_shuttle: BusShuttleSim
var _hud: PassengerHud
var _inspect: PassengerInspect
var _wing := Vector2i.ZERO
var _desk_cell := Vector2i.ZERO
var _flight_snap := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_gates = _main.get_node("GateDesks")
	_sim = _main.get_node("PassengerSim")
	_bus_shuttle = _main.get_node("BusShuttleSim")
	_hud = _main.get_node("PassengerHud")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	_hud.dismiss_intro()
	SaveTestKit.start_airport(_main)
	for i in 4000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)
	_wing = _build_west_wing()
	_desk_cell = _wing + Vector2i(1, 2)
	SaveTestKit.step(_main)
	_flight_snap = _flights.to_snapshot()


func after() -> void:
	_main.free()


func after_test() -> void:
	if not _flight_snap.is_empty():
		_flights.from_snapshot(_flight_snap.duplicate(true))
	_clear_bus_and_remote_placements()
	_inspect.built_card.selection.kind = BuiltSelection.Kind.NONE
	_inspect.built_card.selection.id = 0
	_hud.refresh()
	await get_tree().process_frame


func _clear_bus_and_remote_placements() -> void:
	if _mode == null or _mode.grid == null:
		return
	var to_remove: Array[int] = []
	for id in _mode.grid.object_ids():
		if GateDesks.is_bus_desk(_mode.grid, id) or _is_remote_stand_id(id):
			to_remove.append(id)
	for id in to_remove:
		_mode.grid.apply(BuildEdit.remove_object(id))
	_gates.refresh()
	_bus_shuttle.sync_gates()


func _is_remote_stand_id(id: int) -> bool:
	var rec := _mode.grid.get_object(id)
	return not rec.is_empty() and StringName(rec["def"]) == RemoteStands.STAND_ID


func _buy_plot_area(cell: Vector2i) -> void:
	for dy in [-20, 0, 20]:
		for dx in [-20, 0, 20]:
			var target := cell + Vector2i(dx, dy)
			var plot := _mode.land_tool.land.plot_of(target)
			if _mode.land_tool.land.in_site(plot) and not _mode.land_tool.land.is_owned(plot):
				LandKit.buy_to(_mode.land_tool.land, plot)


func _build_west_wing() -> Vector2i:
	var wing := SITE.starter_offset + Vector2i(-42, 0)
	for x in range(0, 20):
		for y in range(0, 6):
			var c := wing + Vector2i(x, y)
			_buy_plot_area(c)
			_mode.grid.apply(BuildEdit.paint_floor(c, 1, 0))
	for x in range(0, 20):
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing + Vector2i(x, 0), BuildGrid.Side.NORTH, BuildGrid.WallKind.PLAIN
			)
		)
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing + Vector2i(x, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.PLAIN
			)
		)
	for y in range(0, 6):
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing + Vector2i(0, y), BuildGrid.Side.WEST, BuildGrid.WallKind.PLAIN
			)
		)
		_mode.grid.apply(
			BuildEdit.place_wall(
				wing + Vector2i(19, y), BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN
			)
		)
	var exit1 := wing + Vector2i(2, 0)
	var exit_res := _mode.grid.apply(BuildEdit.place_object(&"exit_door", exit1, 0))
	assert_bool(exit_res.ok).override_failure_message(exit_res.reason_text()).is_true()
	return wing


func _place_bus_gate() -> int:
	var res := _mode.grid.apply(BuildEdit.place_object(GateDesks.BUS_DESK, _desk_cell, 0))
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	_gates.refresh()
	_bus_shuttle.sync_gates()
	return res.object_id


func _place_remote_stand(offset_cells: Vector2i) -> int:
	_buy_plot_area(offset_cells)
	var res := _mode.grid.apply(BuildEdit.place_object(RemoteStands.STAND_ID, offset_cells, 0))
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	_gates.refresh()
	return res.object_id


func _select_object(object_id: int) -> BuiltItemCard:
	_inspect.built_card.selection.kind = BuiltSelection.Kind.OBJECT
	_inspect.built_card.selection.id = object_id
	_inspect.built_card.invalidate()
	_hud.refresh()
	return _inspect.built_card


func test_remote_stand_inspect_card_shows_id_class_pairing_and_flight() -> void:
	var r1_cell := SITE.starter_offset + Vector2i(-25, -45)
	var stand_id := _place_remote_stand(r1_cell)
	var card := _select_object(stand_id)
	assert_str(card.name_text()).is_equal("Remote stand")
	assert_str(card.field_text("status")).is_equal("Stand: R1")
	assert_str(card.field_text("planes")).starts_with("Biggest plane: ")
	assert_str(card.field_text("shuttle")).is_equal("Needs a Bus gate")
	assert_str(card.field_text("flight")).is_equal("Next flight: none scheduled")

	var bus_id := _place_bus_gate()
	assert_int(bus_id).is_greater(0)
	card = _select_object(stand_id)
	assert_str(card.field_text("shuttle")).is_equal("Auto-paired with Bus gate")

	var gate_letter := _gates.bus_gate_ids()[0]
	var stand_dict: Dictionary = _flights.remote_stand_grounds()["R1"]["stand"]
	var terms := {
		"id": "SK104",
		"airline": "Gotta Air",
		"destination": "Bergen",
		"departure_minute": 18 * 60,
		"plane_size": PlaneClasses.SMALL,
		"booked_passengers": 6,
		"fee_per_passenger": 20,
		FlightContract.TRAITS_KEY: {},
	}
	var today := GameCalendar.day_of(_sim.tick, _flights.epoch)
	var active_c := FlightContract.assigned(terms, gate_letter, stand_dict, "R1")
	active_c = FlightContract.make(active_c.merged({"first_day": today}))
	var snap := _flights.to_snapshot()
	(snap["contracts"] as Array).append(active_c)
	snap["start_day"]["SK104"] = today
	snap["next_day"]["SK104"] = today
	assert_bool(_flights.from_snapshot(snap)).is_true()
	_gates.refresh()
	card.invalidate()
	_hud.refresh()
	assert_str(card.field_text("flight")).contains("Bergen")

	var starts := FlightTimetable.starts_for(active_c, today, _flights.epoch)
	var shift := (_sim.tick - 5) - starts[FlightSim.State.BOARDING]
	var live_starts: Array[int] = []
	for t in starts:
		live_starts.append(int(t) + shift)
	_flights._insert(
		_flights._record("SK104-d%d" % today, live_starts, gate_letter, "SK104", today, "R1")
	)
	card.invalidate()
	_hud.refresh()
	assert_str(card.field_text("flight")).contains("Bergen")
	assert_str(card.field_text("flight")).contains("Boarding")


func test_bus_gate_inspect_card_shows_served_stands_and_live_shuttle_state() -> void:
	var bus_id := _place_bus_gate()
	var card := _select_object(bus_id)
	assert_str(card.name_text()).is_equal("Bus gate desk")
	assert_str(card.field_text("status")).starts_with("Status: Linked to Gate ")
	assert_str(card.field_text("planes")).is_equal("Needs a Remote stand")
	assert_str(card.field_text("shuttle")).is_equal("Shuttle: Idle at bay")

	var r1 := _place_remote_stand(SITE.starter_offset + Vector2i(-25, -45))
	assert_int(r1).is_greater(0)
	card = _select_object(bus_id)
	assert_str(card.field_text("planes")).is_equal("Serves 1 remote stand (R1)")

	var r2 := _place_remote_stand(SITE.starter_offset + Vector2i(-50, -45))
	assert_int(r2).is_greater(0)
	card = _select_object(bus_id)
	assert_str(card.field_text("planes")).is_equal("Serves 2 remote stands (R1, R2)")

	var gate_letter := _gates.bus_gate_ids()[0]
	var bus_entry: Dictionary = _bus_shuttle._buses[gate_letter]
	bus_entry["stand_id"] = "R1"
	for state_and_expected in [
		[BusShuttleSim.State.LOADING, "Shuttle: Boarding for R1 (0)"],
		[BusShuttleSim.State.DRIVING_OUT, "Shuttle: Driving to R1"],
		[BusShuttleSim.State.UNLOADING, "Shuttle: Unloading at R1"],
		[BusShuttleSim.State.DRIVING_BACK, "Shuttle: Returning to bay"],
	]:
		bus_entry["state"] = state_and_expected[0]
		card.invalidate()
		_hud.refresh()
		assert_str(card.field_text("shuttle")).is_equal(state_and_expected[1])


func test_distinct_thumbnails_and_3d_bus_gate_desk_piece() -> void:
	assert_str(InteriorKit.object_piece(GateDesks.DESK)).is_equal("gate_desk")
	assert_str(InteriorKit.object_piece(GateDesks.BUS_DESK)).is_equal("bus_gate_desk")
	assert_bool(InteriorKit.meshes("bus_gate_desk").is_empty()).is_false()
	var inst := InteriorKit.instantiate("bus_gate_desk")
	assert_object(inst).is_not_null()
	assert_object(inst.find_child("Sign_Face", true, false)).is_not_null()
	inst.free()

	assert_str(BuildMenuCatalog.ITEMS[BuildMode.Tool.GATE_DESK][1]).is_equal("gate_desk")
	assert_str(BuildMenuCatalog.ITEMS[BuildMode.Tool.BUS_GATE_DESK][1]).is_equal("bus_gate_desk")
	assert_str(BuildMenuCatalog.ITEMS[BuildMode.Tool.REMOTE_STAND][1]).is_equal("remote_stand")

	var gate_img := (load(BuildMenu.THUMBNAIL_DIR % "gate_desk") as Texture2D).get_image()
	var bus_img := (load(BuildMenu.THUMBNAIL_DIR % "bus_gate_desk") as Texture2D).get_image()
	var curb_img := (load(BuildMenu.THUMBNAIL_DIR % "curb_bay") as Texture2D).get_image()
	var stand_img := (load(BuildMenu.THUMBNAIL_DIR % "remote_stand") as Texture2D).get_image()
	assert_vector(bus_img.get_size()).is_equal(Vector2i(256, 256))
	assert_vector(stand_img.get_size()).is_equal(Vector2i(256, 256))
	assert_bool(bus_img.get_data() != gate_img.get_data()).is_true()
	assert_bool(stand_img.get_data() != curb_img.get_data()).is_true()


func test_tooltips_card_needs_and_gate_desk_staff_copy() -> void:
	var gate_lines := "\n".join(ItemInfo.of(BuildMode.Tool.GATE_DESK))
	assert_str(gate_lines).not_contains("No staff needed")
	assert_str(gate_lines).contains("Gate Agent")

	var bus_lines := "\n".join(ItemInfo.of(BuildMode.Tool.BUS_GATE_DESK))
	assert_str(bus_lines).contains("wall space")
	assert_str(bus_lines).contains("automatically")
	assert_str(bus_lines).contains("no manual linking")
	assert_str(bus_lines).contains("Remote stand")
	assert_str(bus_lines).contains("Gate Agent")

	var stand_lines := "\n".join(ItemInfo.of(BuildMode.Tool.REMOTE_STAND))
	assert_str(stand_lines).contains("apron")
	assert_str(stand_lines).contains("automatically")
	assert_str(stand_lines).contains("no manual linking")
	assert_str(stand_lines).contains("Bus gate")

	assert_str(BuildMenuCatalog.CARD_NEEDS.get(BuildMode.Tool.BUS_GATE_DESK, "")).is_equal(
		"Needs Remote stand"
	)
	assert_str(BuildMenuCatalog.CARD_NEEDS.get(BuildMode.Tool.REMOTE_STAND, "")).is_equal(
		"Needs Bus gate"
	)
	assert_array(BuildMenuCatalog.card_details(BuildMode.Tool.BUS_GATE_DESK)).contains(
		[["Needs Remote stand", &"HudAttentionText"]]
	)
	assert_array(BuildMenuCatalog.card_details(BuildMode.Tool.REMOTE_STAND)).contains(
		[["Needs Bus gate", &"HudAttentionText"]]
	)


func test_unpaired_bus_gate_and_remote_stand_alerts_fire_and_self_clear() -> void:
	var stack := AlertStack.new()
	stack.sim = _sim
	stack.flights = _flights
	stack.settings_path = SaveTestKit.run_path("bus_pairing_alert")
	add_child(stack)
	SaveTestKit.step(_main)
	stack.refresh()
	assert_array(AlertSources.bus_pairing(_sim)).is_empty()

	var bus_id := _place_bus_gate()
	var bus_only := AlertSources.bus_pairing(_sim)
	assert_int(bus_only.size()).is_equal(1)
	assert_bool(bus_only[0]["key"] == AlertSources.BUS_GATE_NEEDS_STAND).is_true()
	assert_str(bus_only[0]["title"]).is_equal("Bus gate needs a Remote stand")
	assert_bool(bool(bus_only[0].get("subtle", false))).is_true()
	SaveTestKit.step(_main)
	stack.refresh()
	assert_array(stack.card_keys()).contains([AlertSources.BUS_GATE_NEEDS_STAND])

	var stand_id := _place_remote_stand(SITE.starter_offset + Vector2i(-25, -45))
	assert_array(AlertSources.bus_pairing(_sim)).is_empty()
	SaveTestKit.step(_main)
	stack.refresh()
	assert_array(stack.card_keys()).not_contains([AlertSources.BUS_GATE_NEEDS_STAND])
	assert_array(stack.card_keys()).not_contains([AlertSources.STAND_NEEDS_BUS_GATE])

	_mode.grid.apply(BuildEdit.remove_object(bus_id))
	var stand_only := AlertSources.bus_pairing(_sim)
	assert_int(stand_only.size()).is_equal(1)
	assert_bool(stand_only[0]["key"] == AlertSources.STAND_NEEDS_BUS_GATE).is_true()
	assert_str(stand_only[0]["title"]).is_equal("Remote stand needs a Bus gate")
	SaveTestKit.step(_main)
	stack.refresh()
	assert_array(stack.card_keys()).contains([AlertSources.STAND_NEEDS_BUS_GATE])

	_mode.grid.apply(BuildEdit.remove_object(stand_id))
	assert_array(AlertSources.bus_pairing(_sim)).is_empty()
	SaveTestKit.step(_main)
	stack.refresh()
	assert_array(stack.card_keys()).not_contains([AlertSources.STAND_NEEDS_BUS_GATE])
	DirAccess.remove_absolute(stack.settings_path)
	stack.free()
