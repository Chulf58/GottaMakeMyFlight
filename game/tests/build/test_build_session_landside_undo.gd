class_name TestBuildSessionLandsideUndo
extends GdUnitTestSuite
## Closing build mode forgets what could be undone, the landside's actions as
## well as the grid's: Ctrl+Z after reopening cannot take back (and refund) a
## curb built in the session before (BuildMode.clear_undo(), called by
## BuildSession).

const STARTER := preload("res://landside/starter_landside.tres")
const SHELL := preload("res://build/toon_terminal_shell.tres")
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)
const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)

var _finances: Finances
var _sim: LandsideSim
var _mode: BuildMode
var _session: BuildSession


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_mode = BuildMode.new()
	_mode.shell = SHELL
	_mode.finances = _finances
	_mode.landside = _sim
	add_child(_mode)
	_session = BuildSession.new()
	_session.build_mode = _mode
	add_child(_session)


func after_test() -> void:
	_session.free()
	_mode.free()
	_finances.free()


func _balance() -> int:
	return _finances.wallet.balance


func test_a_landside_only_action_cannot_be_undone_after_the_session_ends() -> void:
	var start := _balance()
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	_session.set_building(false)
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	_session.set_building(true)
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
	assert_int(_balance()).is_equal(start - 300)


func test_interleaved_grid_and_landside_actions_are_all_forgotten() -> void:
	var start := _balance()
	var cell := Vector2i(10, 10)
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell + Vector2i.RIGHT)).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(2)
	_session.set_building(false)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	_session.set_building(true)
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(start - 25 - 1200 - 25)


func test_actions_in_the_new_session_are_undone_in_order_without_the_old_ones() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	_session.set_building(false)
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	# The curb from before the reopening stays.
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
