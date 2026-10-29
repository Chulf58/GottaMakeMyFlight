class_name TestStoreText
extends GdUnitTestSuite
## What the screen says about the pharmacy, duty free and fashion stores
## (F4-5): the room panel lists a store's browse spots and its one spend
## number as it does a kiosk's, and the followed passenger's line names the
## store it is heading to or browsing at by its room type ("the kiosk" for a
## kiosk, as before).

const ROOM := Rect2i(3, 3, 4, 4)

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


func test_the_room_panel_over_each_store_shows_browse_spots_and_spend() -> void:
	for type: StringName in StoreTestLayout.STORES:
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
		var pieces: Array = StoreTestLayout.STORES[type]
		mode.grid.apply(BuildEdit.place_object(pieces[0], Vector2i(3, 3), 0))
		mode.grid.apply(BuildEdit.place_object(pieces[1], Vector2i(5, 5), 0))
		var panel := RoomPanel.new()
		add_child(panel)
		panel.watch(mode)
		panel.show_room(room)
		var texts := _texts(panel)
		print("%s panel: %s" % [type, texts])
		var spend := "Base spend $%d per visit" % RoomTypes.get_type(type).base_spend
		assert_array(texts).contains([RoomRules.READY, "Browse spots %d" % pieces[2], spend])
		assert_array(texts).not_contains(["Seats %d" % pieces[2]])
		panel.free()
		mode.free()


## A bored airside passenger on a visit to the airside shop of `grid`.
func _visitor(grid: BuildGrid) -> Passenger:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	return p


## The passenger's line while walking to the shop and then browsing there.
func _walk_and_browse(p: Passenger) -> Array:
	var seen := [PassengerHud.stage_text(_world.sim, p)]
	var until := _world.clock.tick + 3000
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < until:
		_world.step()
	seen.append(PassengerHud.stage_text(_world.sim, p))
	return seen


func test_a_kiosk_visitor_is_heading_to_and_browsing_at_the_kiosk() -> void:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid)
	var seen := _walk_and_browse(_visitor(grid))
	print("kiosk: %s" % [seen])
	assert_array(seen).is_equal(["Heading to the kiosk", "Browsing at the kiosk"])


func test_a_store_visitor_is_heading_to_and_browsing_at_that_store() -> void:
	var expected := {
		&"pharmacy": ["Heading to the pharmacy", "Browsing at the pharmacy"],
		&"duty_free": ["Heading to the duty free", "Browsing at the duty free"],
		&"fashion": ["Heading to the fashion store", "Browsing at the fashion store"],
	}
	for type: StringName in expected:
		var grid := BuildGrid.new()
		StoreTestLayout.build(grid, type)
		var seen := _walk_and_browse(_visitor(grid))
		print("%s: %s" % [type, seen])
		assert_array(seen).is_equal(expected[type])
		_world.free_all()
		_world = null


func test_a_shop_stage_with_no_visit_names_no_store() -> void:
	var grid := BuildGrid.new()
	ShopTestLayout.build(grid, [])
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p := ShopTestLayout.airside_guest(_world, 0)
	p.stage = Passenger.Stage.SHOP_WALK
	assert_str(PassengerHud.stage_text(_world.sim, p)).is_equal("Heading to a shop")
	p.stage = Passenger.Stage.SHOP_BROWSE
	assert_str(PassengerHud.stage_text(_world.sim, p)).is_equal("Browsing at a shop")
	p.stage = Passenger.Stage.TO_GATE
	assert_str(PassengerHud.stage_text(_world.sim, p)).is_equal("Heading to the gate")
