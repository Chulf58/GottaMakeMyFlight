class_name TestBuildSessionLandsideUndo
extends GdUnitTestSuite
## Closing build mode keeps what could be undone, the landside's actions as well
## as the grid's, until the sim clock advances a tick (user-ruled 2026-11-11);
## then BuildSession forgets them (BuildMode.clear_undo()): Ctrl+Z cannot take
## back (and refund) a curb built before the tick.

const STARTER := preload("res://landside/starter_landside.tres")
const SITE := preload("res://build/terminal_site.tres")
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)
const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)

var _finances: Finances
var _sim: LandsideSim
var _mode: BuildMode
var _session: BuildSession
var _clock: SimClock


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_mode = BuildMode.new()
	_mode.site = SITE
	_mode.finances = _finances
	_mode.landside = _sim
	add_child(_mode)
	# Building on land the player does not own is refused (LandPlots); the cells
	# here lie off a new game's land, so the whole site is owned.
	LandKit.own_all(_mode.land_tool.land)
	_clock = auto_free(SimClock.new())
	add_child(_clock)
	_session = BuildSession.new()
	_session.build_mode = _mode
	_session.clock = _clock
	add_child(_session)


func after_test() -> void:
	_session.free()
	_mode.free()
	_finances.free()


func _balance() -> int:
	return _finances.wallet.balance


func test_a_landside_only_action_can_be_undone_after_the_session_ends_until_a_tick() -> void:
	var start := _balance()
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	_session.set_building(false)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.curbs_built[0]).is_false()
	assert_int(_balance()).is_equal(start)


func test_a_landside_only_action_cannot_be_undone_after_a_tick() -> void:
	var start := _balance()
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	_session.set_building(false)
	_clock.advance(SimClock.STEP)
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	_session.set_building(true)
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
	assert_int(_balance()).is_equal(start - 300)


func test_interleaved_grid_and_landside_actions_are_all_forgotten_by_a_tick() -> void:
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
	_clock.advance(SimClock.STEP)
	assert_int(_mode.undo_history().size()).is_equal(0)
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	_session.set_building(true)
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(start - 25 - 1200 - 25)


func test_actions_in_the_new_session_are_undone_in_order_without_the_ones_before_a_tick() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	_session.set_building(false)
	_clock.advance(SimClock.STEP)
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	# The curb from before the reopening stays.
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
