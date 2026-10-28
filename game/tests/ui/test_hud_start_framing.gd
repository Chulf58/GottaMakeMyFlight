class_name TestHudStartFraming
extends GdUnitTestSuite
## PassengerHud frames the camera on the start view when the game opens and
## again after a save loads, but not on ordinary build edits.

const SEED := 4_402_026

var _main: Node
var _camera: TycoonCamera
var _mode: BuildMode


func before_test() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_mode = _main.get_node("BuildMode")


func after_test() -> void:
	_main.free()


func _framed(area: Rect2) -> Vector3:
	return _camera.framing_for(area)["position"]


func test_the_game_opens_framed_on_the_starter_terminal_floor() -> void:
	var area := StartView.area_for(_mode.grid, _mode.shell)
	assert_vector(_camera.home_position).is_equal_approx(_framed(area), Vector3.ONE * 0.001)
	assert_vector(_camera.position).is_equal_approx(_camera.home_position, Vector3.ONE * 0.001)
	assert_float(_camera.home_distance).is_less(60.0)


func test_an_ordinary_build_edit_does_not_reframe_the_camera() -> void:
	var before_home := _camera.home_position
	var before_position := _camera.position
	var result := _mode.grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	assert_bool(result.ok).is_true()
	assert_vector(_camera.home_position).is_equal(before_home)
	assert_vector(_camera.position).is_equal(before_position)


func test_loading_a_save_reframes_the_camera_on_what_it_built() -> void:
	var save: SaveGame = _main.get_node("SaveGame")
	_mode.grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	# A build edit settles on the next tick, and a save waits for it.
	SaveTestKit.step(_main)
	var data := save.snapshot()
	assert_bool(data.is_empty()).is_false()
	data = JSON.parse_string(JSON.stringify(data, "", true, true))
	_camera.home_position = Vector3(99.0, 0.0, 99.0)
	_camera.position = Vector3(99.0, 0.0, 99.0)
	assert_bool(save.load_world(data)).is_true()
	var cell_centre := _mode.grid.cell_to_world(Vector2i(3, 3))
	assert_vector(_camera.home_position).is_equal_approx(
		Vector3(cell_centre.x, 0.0, cell_centre.z), Vector3.ONE * 0.001
	)
	assert_vector(_camera.position).is_equal_approx(_camera.home_position, Vector3.ONE * 0.001)


func test_a_refused_load_leaves_the_camera_alone() -> void:
	var save: SaveGame = _main.get_node("SaveGame")
	_camera.home_position = Vector3(99.0, 0.0, 99.0)
	assert_bool(save.load_world({})).is_false()
	assert_vector(_camera.home_position).is_equal(Vector3(99.0, 0.0, 99.0))
