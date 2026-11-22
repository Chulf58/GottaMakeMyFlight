class_name TestBuildSessionLandsideUndo
extends GdUnitTestSuite
## Closing build mode keeps what could be undone, the landside's actions as well
## as the grid's, across tray closes and sim ticks (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete);
## a rescue grant, load, or outside grid edit still invalidates them.

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


func test_a_landside_only_action_can_be_undone_after_the_session_ends_and_ticks_run() -> void:
	var start := _balance()
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	_session.set_building(false)
	for i in 5:
		_clock.advance(SimClock.STEP)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.curbs_built[0]).is_false()
	assert_int(_balance()).is_equal(start)


func test_interleaved_grid_and_landside_actions_persist_across_ticks_and_undo_in_order() -> void:
	var start := _balance()
	var cell := Vector2i(10, 10) + LandKit.FIRST_SITE
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell + Vector2i.RIGHT)).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(2)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	_session.set_building(false)
	for i in 5:
		_clock.advance(SimClock.STEP)
	assert_int(_mode.undo_history().size()).is_equal(2)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(cell + Vector2i.RIGHT)).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(start)


func test_actions_across_sessions_and_ticks_undo_in_order() -> void:
	var start := _balance()
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
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.curbs_built[0]).is_false()
	assert_int(_balance()).is_equal(start)


## A rescue grant or an outside grid edit invalidates the whole history
## (decision build-mode-undo-design-action-receipts-with-before-values-at,
## point 5), landside actions included, even while it waits for a tick.
func test_a_rescue_grant_after_esc_forgets_a_landside_action_too() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	_session.set_building(false)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	assert_bool(_finances.wallet.credit(1000, Wallet.Category.GRANT)).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	var paid := _balance()
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
	assert_int(_balance()).is_equal(paid)


func test_an_outside_grid_edit_after_esc_forgets_a_landside_action_too() -> void:
	_session.set_building(true)
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	_session.set_building(false)
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	var edits: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(10, 10) + LandKit.FIRST_SITE, BuildGrid.FLOOR_TILE, 1)
	]
	_mode.grid.apply_batch(edits)
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	assert_object(_mode.undo()).is_null()
	assert_bool(_sim.curbs_built[0]).is_true()
