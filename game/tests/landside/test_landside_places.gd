class_name TestLandsidePlaces
extends GdUnitTestSuite
## LandsidePlaces draws the curb bays and built car parks where the starter
## definition puts them (provisional layout, see landside_places.gd): the
## 2-berth bay over berths 0 and 1 (x -17 and -10.5) on the kerb line, the
## third berth with no paint; no lot until spot 0 is built, then a surface
## lot facing the road with its entrance edge on the gate (z -37.5).

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


func test_the_starter_curb_gets_one_bay_over_its_first_two_berths_on_the_kerb() -> void:
	var origins := LandsidePlaces.bay_origins(STARTER, -58.7, 0.107)
	print("bay origins %s" % [origins])
	assert_array(origins).is_equal([Vector3(-13.75, 0.107, -58.7)])
	_places.refresh()
	assert_int(_places.bay_count()).is_equal(1)
	assert_vector(_places.bay(0).position).is_equal(Vector3(-13.75, 0.107, -58.7))
	# The bay's berth markers stand over berths 0 and 1 along the kerb.
	for marker in ["Mount_Berth_1", "Mount_Berth_2"]:
		var at := (_places.bay(0).find_child(marker, true, false) as Node3D).global_position
		print("%s at %s" % [marker, at])
		assert_bool(is_equal_approx(at.x, -17.0) or is_equal_approx(at.x, -10.5)).is_true()


func test_a_lot_stands_on_a_spot_only_once_it_is_built_facing_the_road() -> void:
	_places.refresh()
	assert_object(_places.lot_node(0)).is_null()
	assert_bool(_landside.build_lot(0)).is_true()
	_places.refresh()
	var lot := _places.lot_node(0)
	assert_object(lot).is_not_null()
	var spot: LandsideLotSpot = STARTER.lots[0]
	var entrance := lot.transform * Vector3(LandsidePlaces.LOT_ENTRANCE_X, 0.0, 0.0)
	print("lot at %s entrance edge %s gate %s" % [lot.position, entrance, spot.access[2]])
	assert_float(entrance.z).is_equal_approx(spot.access[2].z, 0.001)
	# Its entrance side (local -x) faces the road, toward -z.
	assert_float((lot.basis * Vector3(-1, 0, 0)).z).is_less(-0.99)
	assert_float(lot.position.x).is_equal_approx(2.25, 0.001)
