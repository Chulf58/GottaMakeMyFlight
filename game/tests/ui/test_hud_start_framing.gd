class_name TestHudStartFraming
extends GdUnitTestSuite
## PassengerHud frames the camera on the start view when the game opens and
## again after a save loads, but not on ordinary build edits.

const SEED := 4_402_026

var _main: Node
var _camera: TycoonCamera
var _mode: BuildMode
var _fresh_snap := {}
var _dirty := false
var _boot_home_pos := Vector3.ZERO
var _boot_cam_pos := Vector3.ZERO
var _boot_home_dist := 0.0
var _boot_expected := Vector3.ZERO


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_camera = _main.get_node("TycoonCamera")
	_mode = _main.get_node("BuildMode")
	_boot_home_pos = _camera.home_position
	_boot_cam_pos = _camera.position
	_boot_home_dist = _camera.home_distance
	_boot_expected = _framed(StartView.area_for(_mode.grid))
	# The edits here paint floor off a new game's land and building on unowned
	# land is refused (LandPlots), so plots are bought out to it; a save accepts that.
	# The first site's north-west plot (side land is locked).
	LandKit.buy_to(_mode.land_tool.land, Vector2i(4, 0))
	var save: SaveGame = _main.get_node("SaveGame")
	_fresh_snap = JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true))


func after() -> void:
	if _main != null:
		_main.free()
		_main = null


func _ensure_clean() -> void:
	if _dirty:
		var save: SaveGame = _main.get_node("SaveGame")
		assert_bool(save.load_world(_fresh_snap)).is_true()
		_dirty = false


func _framed(area: Rect2) -> Vector3:
	return _camera.framing_for(area)["position"]


func test_the_game_opens_framed_on_the_starter_terminal_floor() -> void:
	assert_vector(_boot_home_pos).is_equal_approx(_boot_expected, Vector3.ONE * 0.001)
	assert_vector(_boot_cam_pos).is_equal_approx(_boot_home_pos, Vector3.ONE * 0.001)
	assert_float(_boot_home_dist).is_less(60.0)


func test_a_refused_load_leaves_the_camera_alone() -> void:
	var save: SaveGame = _main.get_node("SaveGame")
	var prev_home := _camera.home_position
	_camera.home_position = Vector3(99.0, 0.0, 99.0)
	assert_bool(save.load_world({})).is_false()
	assert_vector(_camera.home_position).is_equal(Vector3(99.0, 0.0, 99.0))
	_camera.home_position = prev_home


func test_an_ordinary_build_edit_does_not_reframe_the_camera() -> void:
	_ensure_clean()
	var before_home := _camera.home_position
	var before_position := _camera.position
	var result := _mode.grid.apply(
		BuildEdit.paint_floor(Vector2i(3, 3) + LandKit.FIRST_SITE, BuildGrid.FLOOR_TILE, 1)
	)
	_dirty = true
	assert_bool(result.ok).is_true()
	assert_vector(_camera.home_position).is_equal(before_home)
	assert_vector(_camera.position).is_equal(before_position)


func test_loading_a_save_reframes_the_camera_on_what_it_built() -> void:
	var save: SaveGame = _main.get_node("SaveGame")
	var target := Vector2i(3, 3) + LandKit.FIRST_SITE
	if _mode.grid.floor_at(target) == BuildGrid.FLOOR_NONE:
		_mode.grid.apply(BuildEdit.paint_floor(target, BuildGrid.FLOOR_TILE, 1))
	_dirty = true
	# A build edit settles on the next tick, and a save waits for it.
	SaveTestKit.step(_main)
	var data := save.snapshot()
	assert_bool(data.is_empty()).is_false()
	data = JSON.parse_string(JSON.stringify(data, "", true, true))
	_camera.home_position = Vector3(99.0, 0.0, 99.0)
	_camera.position = Vector3(99.0, 0.0, 99.0)
	assert_bool(save.load_world(data)).is_true()
	# The new game's shell stands too, so the view frames the shell and the tile.
	var area := StartView.area_for(_mode.grid)
	var cell_centre := _mode.grid.cell_to_world(target)
	assert_bool(area.has_point(Vector2(cell_centre.x, cell_centre.z))).is_true()
	assert_vector(_camera.home_position).is_equal_approx(_framed(area), Vector3.ONE * 0.001)
	assert_vector(_camera.position).is_equal_approx(_camera.home_position, Vector3.ONE * 0.001)
