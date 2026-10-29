class_name TestLandsidePlaces
extends GdUnitTestSuite
## LandsidePlaces draws the curb bays and built car parks where the starter
## definition puts them: the starter curb's two bays with their Mount_Berth
## markers on its four berths, a bay on a built curb spot with its markers on
## that spot's berths, a surface lot with its barrier arms on the gate and the
## exit start, a multi-storey on its centre with every slot on a deck of the
## building, and a Closed sign over a closed car park's gate. Parked cars face
## into their stalls, away from the middle aisle.

const STARTER := preload("res://landside/starter_landside.tres")

var _landside: LandsideSim
var _places: LandsidePlaces


func before_test() -> void:
	_landside = auto_free(LandsideSim.new())
	_landside.use_definition(STARTER)
	_places = LandsidePlaces.new()
	_places.landside = _landside
	add_child(_places)


func after_test() -> void:
	_places.free()


## The berth marker positions of a drawn bay, in world space.
static func _markers(bay: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for marker in ["Mount_Berth_1", "Mount_Berth_2"]:
		out.append((bay.find_child(marker, true, false) as Node3D).global_position)
	return out


## Whether `point` matches one of `berths` in x and z.
static func _on_a_berth(point: Vector3, berths: PackedVector3Array) -> bool:
	for berth in berths:
		if absf(berth.x - point.x) < 0.01 and absf(berth.z - point.z) < 0.01:
			return true
	return false


func test_the_starter_curb_is_two_bays_with_their_markers_on_its_four_berths() -> void:
	_places.refresh()
	print("starter bays %s" % [LandsidePlaces.bay_origins(STARTER, 0.107)])
	assert_int(_places.bay_count()).is_equal(2)
	var found := 0
	for i in 2:
		var bay := _places.starter_bay(i)
		assert_float(bay.position.z).is_equal_approx(-58.7, 0.001)
		for at in _markers(bay):
			print("starter bay %d marker %s" % [i, at])
			assert_bool(_on_a_berth(at, STARTER.curb.berths)).is_true()
			found += 1
	assert_int(found).is_equal(STARTER.curb.berths.size())


func test_a_curb_bay_shows_while_its_spot_is_built() -> void:
	_places.refresh()
	assert_object(_places.bay_node(0)).is_null()
	assert_bool(_landside.build_curb(0)).is_true()
	_places.refresh()
	var bay := _places.bay_node(0)
	assert_object(bay).is_not_null()
	for at in _markers(bay):
		assert_bool(_on_a_berth(at, STARTER.curb_spots[0].berths)).is_true()
	assert_int(_places.bay_count()).is_equal(3)
	assert_bool(_landside.remove_curb(0)).is_true()
	_places.refresh()
	assert_object(_places.bay_node(0)).is_null()


func test_the_surface_lot_stands_with_its_barriers_on_the_gate_and_the_exit() -> void:
	assert_bool(_landside.build_lot(0)).is_true()
	_places.refresh()
	var lot := _places.lot_node(0)
	var spot: LandsideLotSpot = STARTER.lots[0]
	assert_object(lot).is_not_null()
	assert_str(lot.scene_file_path).is_equal("res://assets/landside/tp_parking_01a.glb")
	var entry := lot.find_child("TP_Parking_01A_Entry_Barrier", true, false) as MeshInstance3D
	var leave := lot.find_child("TP_Parking_01A_Exit_Barrier", true, false) as MeshInstance3D
	var entry_at := (entry.global_transform * entry.get_aabb()).get_center()
	var exit_at := (leave.global_transform * leave.get_aabb()).get_center()
	print(
		(
			"lot at %s entry arm %s gate %s exit arm %s exit %s"
			% [lot.position, entry_at, spot.access[2], exit_at, spot.exit[0]]
		)
	)
	assert_float(entry_at.x).is_equal_approx(spot.access[2].x, 0.2)
	assert_float(entry_at.z).is_equal_approx(spot.access[2].z, 0.2)
	assert_float(exit_at.x).is_equal_approx(spot.exit[0].x, 0.2)
	assert_float(exit_at.z).is_equal_approx(spot.exit[0].z, 0.2)


func test_the_multi_storey_stands_on_its_centre_with_every_slot_on_a_deck() -> void:
	assert_bool(_landside.build_lot(1)).is_true()
	_places.refresh()
	var lot := _places.lot_node(1)
	var spot: LandsideLotSpot = STARTER.lots[1]
	assert_str(lot.scene_file_path).is_equal("res://assets/landside/tc_parking_2a.glb")
	assert_vector(lot.position).is_equal(spot.centre)
	# Flat faces of the building, in world space.
	var flats: Array[PackedVector3Array] = []
	for mi: MeshInstance3D in lot.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := mi.global_transform * faces[i]
			var b := mi.global_transform * faces[i + 1]
			var c := mi.global_transform * faces[i + 2]
			var up := (b - a).cross(c - a)
			if up.length() > 0.0001 and absf(up.normalized().y) > 0.99:
				flats.append(PackedVector3Array([a, b, c]))
	# Every slot stands on a flat face right under it (within 2 cm), which is
	# a deck: a car is drawn with its wheels on its slot.
	var on_deck := 0
	for slot in spot.slots:
		var at := Vector2(slot.x, slot.z)
		for tri in flats:
			var inside := Geometry2D.point_is_inside_triangle(
				at,
				Vector2(tri[0].x, tri[0].z),
				Vector2(tri[1].x, tri[1].z),
				Vector2(tri[2].x, tri[2].z)
			)
			if inside and absf(tri[0].y - slot.y) < 0.02:
				on_deck += 1
				break
	print("flat faces %d, slots on a deck %d of %d" % [flats.size(), on_deck, spot.slots.size()])
	assert_int(on_deck).is_equal(spot.slots.size())


func test_a_closed_car_park_shows_a_closed_sign_over_its_gate() -> void:
	assert_bool(_landside.build_lot(0)).is_true()
	_places.refresh()
	assert_object(_places.closed_sign(0)).is_null()
	assert_bool(_landside.set_lot_closed(0, true)).is_true()
	_places.refresh()
	var sign := _places.closed_sign(0)
	assert_object(sign).is_not_null()
	assert_str((sign.get_node("Caption") as Label3D).text).is_equal("Closed")
	assert_float(sign.position.x).is_equal(STARTER.lots[0].access[2].x)
	assert_bool(_landside.set_lot_closed(0, false)).is_true()
	_places.refresh()
	assert_object(_places.closed_sign(0)).is_null()


func test_a_parked_car_faces_into_its_stall_away_from_the_aisle() -> void:
	for spot: LandsideLotSpot in STARTER.lots:
		for slot in spot.slots:
			var nose := LandsidePlaces.parked_heading(spot, slot)
			assert_float(nose.x * (slot.x - spot.centre.x)).is_greater(0.0)


func test_cars_parked_on_every_level_of_the_multi_storey_are_drawn_on_its_decks() -> void:
	assert_bool(_landside.build_lot(1)).is_true()
	_landside.wallet = Wallet.new()
	var views := LandsideViews.new()
	views.landside = _landside
	add_child(views)
	var rng := RandomNumberGenerator.new()
	var by_level := {}
	for tick in range(1, 3000):
		if tick % 15 == 1 and tick < 15 * 26:
			var bookings: Array[int] = [tick]
			_landside.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
		_landside.step(tick, false, rng)
	views.sync()
	views.draw()
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		if v.lane != LandsideVehicle.Lane.SLOT:
			continue
		var drawn := views.node_for(id).position
		var slot: Vector3 = STARTER.lots[1].slots[v.stop]
		assert_vector(drawn).is_equal_approx(slot, Vector3.ONE * 0.001)
		by_level[snappedf(drawn.y, 0.01)] = int(by_level.get(snappedf(drawn.y, 0.01), 0)) + 1
	print("parked cars drawn by deck height %s" % [by_level])
	views.free()
	assert_int(by_level.size()).is_equal(3)
	for level in [0.3, 5.33, 10.33]:
		assert_int(int(by_level.get(level, 0))).is_greater(0)
