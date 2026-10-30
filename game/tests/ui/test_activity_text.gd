class_name TestActivityText
extends GdUnitTestSuite
## What the screen says about the activity and rest rooms (F4-7): the room
## panel lists their spots and a fee, or "Free to use", and the followed
## passenger's line says what it does there (playing, relaxing, using the
## shower, resting) instead of "Browsing at".

const ROOM := Rect2i(3, 3, 6, 6)
## Where ActivityTestLayout's pieces go in the 20x20 build grid.
const SHIFT := Vector2i(-19, 0)
const WORDS := {
	&"play_area": ["Heading to the play area", "Playing in the play area"],
	&"lounge": ["Heading to the lounge", "Relaxing in the lounge"],
	&"shower": ["Heading to the shower", "Using the shower"],
	&"nap_pod": ["Heading to the nap pod", "Resting in the nap pod"],
}

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_the_room_panel_shows_spots_and_a_fee_or_free_to_use() -> void:
	for type in ActivityTestLayout.TYPES:
		var mode := BuildMode.new()
		mode.grid_size = Vector2i(20, 20)
		add_child(mode)
		mode.set_process(false)
		var edits: Array[BuildEdit] = []
		for y in range(2, 12):
			for x in range(2, 14):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
		mode.grid.apply_batch(edits)
		var room := mode.grid.apply(BuildEdit.place_room(ROOM, type)).room_id
		for piece: Array in ActivityTestLayout.PIECES[type]:
			mode.grid.apply(BuildEdit.place_object(piece[0], piece[1] + SHIFT, 0))
		var panel := RoomPanel.new()
		add_child(panel)
		panel.watch(mode)
		panel.show_room(room)
		var texts := _texts(panel)
		print("%s panel: %s" % [type, texts])
		var fee := RoomTypes.get_type(type).base_spend
		var want := "Fee $%d per visit" % fee if fee > 0 else "Free to use"
		assert_array(texts).contains([RoomRules.READY, want])
		assert_array(texts).not_contains(["Base spend $%d per visit" % fee])
		panel.free()
		mode.free()


func test_a_visitor_is_heading_to_and_then_doing_what_the_room_is_for() -> void:
	for type in ActivityTestLayout.TYPES:
		var grid := BuildGrid.new()
		ActivityTestLayout.build(grid, type)
		_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
		_world.run_to(10)
		var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		var seen := [PassengerHud.stage_text(_world.sim, p)]
		var until := _world.clock.tick + 3000
		while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
			_world.step()
		seen.append(PassengerHud.stage_text(_world.sim, p))
		print("%s: %s" % [type, seen])
		assert_array(seen).is_equal(WORDS[type])
		_world.free_all()
		_world = null
