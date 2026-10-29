class_name TestLandsidePlacesMain
extends GdUnitTestSuite
## In the real main scene, every built landside facility is drawn: a curb bay
## on curb spot 0, the surface lot on lot spot 0 (closed, so its Closed sign
## shows) and the multi-storey on lot spot 1 appear on the next frames after
## they are built, with the clock paused and nothing but the scene's own
## frame processing drawing them; opened, the lot drops its sign; taken off,
## every one disappears the same way; and a load of the save taken while they stood
## brings every one back, sign included, while the clock is paused.

const SEED := 6_200_301
const BUILT := {
	"bays": 3,
	"curb_0": "res://assets/landside/tp_curb_bay_01a.glb",
	"lot_0": "res://assets/landside/tp_parking_01a.glb",
	"lot_1": "res://assets/landside/tc_parking_2a.glb",
	"sign_0": true,
	"sign_1": false,
}

var _path := SaveTestKit.run_path("test_landside_places_main")
var _main: Node


func after() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func after_test() -> void:
	if _main != null:
		_main.free()
		_main = null


## What LandsidePlaces draws now, by facility, as the asset each one shows.
func _drawn() -> Dictionary:
	var places := (_main.get_node("LandsideViews") as LandsideViews).places()
	var out := {"bays": places.bay_count()}
	var curb := places.bay_node(0)
	out["curb_0"] = curb.scene_file_path if curb != null else ""
	for spot in 2:
		var lot := places.lot_node(spot)
		out["lot_%d" % spot] = lot.scene_file_path if lot != null else ""
		out["sign_%d" % spot] = places.closed_sign(spot) != null
	return out


## Lets the scene draw itself: two frames of its own _process.
func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_built_facilities_come_and_go_with_the_frames_and_return_after_a_load() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var landside: LandsideSim = _main.get_node("LandsideSim")
	var clock: SimClock = _main.get_node("SimClock")
	await _frames()
	var before := _drawn()
	assert_bool(landside.build_curb(0)).is_true()
	assert_bool(landside.build_lot(0)).is_true()
	assert_bool(landside.build_lot(1)).is_true()
	assert_bool(landside.set_lot_closed(0, true)).is_true()
	await _frames()
	var built := _drawn()
	var saved := SaveTestKit.save_game(_main).save_to_file(_path)
	assert_bool(landside.remove_curb(0)).is_true()
	assert_bool(landside.remove_lot(1)).is_true()
	assert_bool(landside.set_lot_closed(0, false)).is_true()
	await _frames()
	var opened := _drawn()
	var lot_removed := landside.remove_lot(0)
	await _frames()
	var removed := _drawn()
	var loaded := SaveTestKit.save_game(_main).load_from_file(_path)
	var after_load := _drawn()
	print(
		(
			"paused %s; before %s; built %s; opened %s; removed %s; after load %s"
			% [clock.paused, before, built, opened, removed, after_load]
		)
	)
	assert_bool(clock.paused).is_true()
	assert_dict(before).is_equal(
		{"bays": 2, "curb_0": "", "lot_0": "", "lot_1": "", "sign_0": false, "sign_1": false}
	)
	assert_dict(built).is_equal(BUILT)
	# Opened again, the surface lot stands without its sign; removed, it is gone.
	(
		assert_dict(opened)
		. is_equal(
			{
				"bays": 2,
				"curb_0": "",
				"lot_0": "res://assets/landside/tp_parking_01a.glb",
				"lot_1": "",
				"sign_0": false,
				"sign_1": false,
			}
		)
	)
	assert_bool(lot_removed).is_true()
	assert_dict(removed).is_equal(
		{"bays": 2, "curb_0": "", "lot_0": "", "lot_1": "", "sign_0": false, "sign_1": false}
	)
	assert_bool(saved).is_true()
	assert_bool(loaded).is_true()
	assert_dict(after_load).is_equal(BUILT)
