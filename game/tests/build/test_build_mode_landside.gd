class_name TestBuildModeLandside
extends GdUnitTestSuite
## BuildMode's landside tools (Landside 3/4): the curb, surface lot and
## multi-storey tools build on the authored spots through apply_at() on the
## y = 0 plane, Remove takes a built spot back off the grid, the Close tool
## opens and closes a car park, Ctrl+Z undoes the newest of the grid's and the
## landside's actions, and the menu lists the tools with their prices.

const STARTER := preload("res://landside/starter_landside.tres")
const SHELL := preload("res://build/toon_terminal_shell.tres")

const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)
const IN_MULTI := Vector3(0.0, 0.0, -8.0)
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)
const NOWHERE := Vector3(200.0, 0.0, 100.0)

var _finances: Finances
var _sim: LandsideSim
var _mode: BuildMode
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new(0)
	_mode = BuildMode.new()
	_mode.shell = SHELL
	_mode.finances = _finances
	_mode.landside = _sim
	add_child(_mode)
	_rng.seed = 5


func after_test() -> void:
	_mode.free()
	_finances.free()


func _balance() -> int:
	return _finances.wallet.balance


func _park_a_car() -> void:
	var bookings: Array[int] = [1]
	_sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
	for t in range(1, 1500):
		_sim.step(t, true, _rng)
	assert_int(_sim.lot_cars(0)).is_equal(1)


## The slabs the ghost shows now (a cleared ghost's are queued to be freed).
func _ghost_slabs() -> int:
	var count := 0
	for child in _mode.get_node("Ghost").get_children():
		count += int(not child.is_queued_for_deletion())
	return count


func test_the_three_build_tools_build_on_their_own_spots_and_pay() -> void:
	var start := _balance()
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.MULTI_STOREY)
	assert_bool(_mode.apply_at(IN_MULTI).ok).is_true()
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	assert_array(_sim.lots_built).is_equal([true, true])
	assert_array(_sim.curbs_built).is_equal([true, false])
	var spent := (
		PriceTable.price_of_landside(&"surface_lot")
		+ PriceTable.price_of_landside(&"multi_storey")
		+ PriceTable.price_of_landside(&"curb_bay")
	)
	assert_int(spent).is_equal(1200 + 5000 + 300)
	assert_int(_balance()).is_equal(start - spent)


func test_a_click_off_every_spot_builds_nothing_and_says_so() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	var result := _mode.apply_at(NOWHERE)
	assert_int(result.reason).is_equal(BuildResult.Reason.LANDSIDE_NOT_ON_SPOT)
	assert_array(_sim.lots_built).is_equal([false, false])
	_mode._update_ghost(NOWHERE)
	assert_str(_mode.status_text()).contains("marked landside spots")


func test_an_unaffordable_click_is_refused_and_the_cost_line_shows_the_shortfall() -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": "1000"})).is_true()
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	_mode._update_ghost(IN_LOT_0)
	assert_vector(_mode.landside_preview_price()).is_equal(Vector2i(1200, 1200))
	assert_str(_mode.status_text()).contains("Not enough money")
	var result := _mode.apply_at(IN_LOT_0)
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_balance()).is_equal(1000)


func test_hovering_a_spot_shows_its_capacity_and_walk_on_the_status_line() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	_mode._update_ghost(IN_LOT_0)
	assert_str(_mode.status_text()).contains("12 spaces")
	assert_str(_mode.status_text()).contains("m walk to the nearest landside door")
	assert_bool(_mode.pointer_on_grid()).is_true()
	# The one surface lot spot is the one under the pointer, tinted.
	assert_int(_ghost_slabs()).is_equal(1)
	# With the curb tool the other free bay is marked beside the tinted one.
	_mode.set_tool(BuildMode.Tool.CURB)
	_mode._update_ghost(IN_BAY_0)
	assert_str(_mode.status_text()).contains("2 berths")
	assert_int(_ghost_slabs()).is_equal(2)
	_mode._update_ghost(null)
	assert_str(_mode.status_text()).is_equal("")
	assert_vector(_mode.landside_preview_price()).is_equal(Vector2i.ZERO)


func test_the_landside_picks_on_the_y_0_plane_not_the_grids_height() -> void:
	var from := Vector3(0.0, 10.0, -57.0)
	var down := Vector3.DOWN
	var landside_hit: Vector3 = LandsidePlacement.ground_point(from, down)
	var grid_hit: Vector3 = _mode.grid_point(from, down)
	assert_float(landside_hit.y).is_equal(0.0)
	assert_float(grid_hit.y).is_equal_approx(_mode.grid.origin.y, 0.0001)
	assert_float(landside_hit.y).is_not_equal(grid_hit.y)


func test_remove_takes_a_built_spot_off_the_grid_and_refunds_half() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	var built := _balance()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode._update_ghost(IN_LOT_0)
	assert_str(_mode.status_text()).contains("Refunds 600")
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_balance()).is_equal(built + 600)


func test_remove_on_the_grid_still_removes_grid_things() -> void:
	var cell := Vector2i(10, 10)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)


func test_remove_is_refused_while_a_car_is_in_the_spot_until_it_drains() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_park_a_car()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var refused := _mode.apply_at(IN_LOT_0)
	assert_int(refused.reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	assert_bool(_sim.lots_built[0]).is_true()
	# Close it, wait for the car to leave, then it can go.
	_mode.set_tool(BuildMode.Tool.LOT_GATE)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lot_open(0)).is_false()
	var leaves := _sim.get_vehicle(_sim.vehicle_ids()[0]).leave_tick
	for t in range(leaves, leaves + 600):
		_sim.step(t, true, _rng)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()


func test_the_close_tool_opens_a_closed_car_park_again() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.LOT_GATE)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lots_closed[0]).is_true()
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	assert_bool(_sim.lots_closed[0]).is_false()
	# Pointing at no car park does nothing.
	assert_object(_mode.apply_at(NOWHERE)).is_null()


func test_ctrl_z_undoes_the_newest_of_the_grid_and_landside_actions_in_order() -> void:
	var start := _balance()
	var cell := Vector2i(10, 10)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	# Newest first: the bay, then the lot, then the floor.
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.curbs_built[0]).is_false()
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_str(_mode.status_text()).is_equal(UndoStack.UNDONE)
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()
	assert_int(_mode.grid.floor_at(cell)).is_not_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(start)
	assert_object(_mode.undo()).is_null()
	assert_str(_mode.status_text()).is_equal(UndoStack.NOTHING_TO_UNDO)


func test_a_landside_action_before_a_grid_action_is_undone_after_it() -> void:
	var cell := Vector2i(10, 10)
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(cell)).ok).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_sim.lots_built[0]).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_sim.lots_built[0]).is_false()


func test_a_refused_landside_undo_says_why_and_changes_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.SURFACE_LOT)
	assert_bool(_mode.apply_at(IN_LOT_0).ok).is_true()
	_park_a_car()
	var balance := _balance()
	var result := _mode.undo()
	assert_int(result.reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	assert_str(_mode.status_text()).contains(UndoStack.CANT_UNDO)
	assert_bool(_sim.lots_built[0]).is_true()
	assert_int(_balance()).is_equal(balance)


func test_a_load_clears_the_landside_undo() -> void:
	_mode.set_tool(BuildMode.Tool.CURB)
	assert_bool(_mode.apply_at(IN_BAY_0).ok).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(1)
	assert_bool(_mode.load_snapshot(_mode.grid.to_snapshot())).is_true()
	assert_int(_mode.landside_placement().undo_size()).is_equal(0)
	assert_object(_mode.undo()).is_null()


func test_without_a_landside_the_tools_do_nothing() -> void:
	_mode.landside = null
	var balance := _balance()
	for tool in [BuildMode.Tool.CURB, BuildMode.Tool.SURFACE_LOT, BuildMode.Tool.LOT_GATE]:
		_mode.set_tool(tool)
		assert_object(_mode.apply_at(IN_LOT_0)).is_null()
	assert_int(_balance()).is_equal(balance)
	assert_array(_sim.lots_built).is_equal([false, false])


func test_the_menu_lists_the_tools_with_their_prices() -> void:
	var category := BuildMenu.category_of(BuildMode.Tool.SURFACE_LOT)
	assert_str(BuildMenu.CATEGORIES[category]["name"]).is_equal("Landside")
	for tool in BuildMode.LANDSIDE_BUILD_TOOLS:
		assert_int(BuildMenu.category_of(tool)).is_equal(category)
		assert_array(BuildMenu.item(tool)).is_not_empty()
	assert_int(BuildMenu.category_of(BuildMode.Tool.LOT_GATE)).is_equal(category)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.CURB)).is_equal(300)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.SURFACE_LOT)).is_equal(1200)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.MULTI_STOREY)).is_equal(5000)
	assert_int(BuildMenu.tool_price(BuildMode.Tool.LOT_GATE)).is_equal(0)
	assert_int(BuildMenu.REMOVE_CATEGORY).is_equal(BuildMenu.CATEGORIES.size() - 1)
