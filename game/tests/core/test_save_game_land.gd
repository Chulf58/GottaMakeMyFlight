class_name TestSaveGameLand
extends GdUnitTestSuite
## The land plots in the whole-world save (part "land", LandPlots): the plots
## owned and the count bought are saved and come back on a load through JSON,
## so the next plot keeps its price; a save whose land does not hold a built
## cell, or that was cut into another number of plots, is refused and the world is left
## as it was. One boot of main.tscn, with the starter terminal built.

const SEED := 4_401_011
## A plot touching a new game's land (columns 0 and 1, rows 3 to 5).
const BOUGHT := Vector2i(2, 4)

var _main: Node
var _save: SaveGame
var _mode: BuildMode


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	SaveTestKit.start_airport(_main)
	for i in 30:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


## A save taken on the next tick (a load or a build change settles there first).
func _taken() -> Dictionary:
	SaveTestKit.step(_main)
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _land() -> LandPlots:
	return _mode.land_tool.land


func test_a_bought_plot_is_saved_and_loaded_with_the_count_bought() -> void:
	var start := _land().owned_plots()
	assert_int(start.size()).is_equal(6)
	var bought := _land().buy(BOUGHT, _mode.wallet())
	assert_bool(bought.ok).is_true()
	var data := _taken()
	assert_array((data["land"] as Dictionary).keys()).contains_exactly_in_any_order(
		["plot_counts", "owned", "bought"]
	)
	assert_int(int(data["land"]["bought"])).is_equal(1)
	assert_int((data["land"]["owned"] as Array).size()).is_equal(7)
	# Put the live land back to a new game's, so the load has to restore it.
	(
		assert_bool(
			_land().from_snapshot(
				{"plot_counts": [4, 6], "owned": start.map(func(p): return [p.x, p.y]), "bought": 0}
			)
		)
		. is_true()
	)
	assert_bool(_land().is_owned(BOUGHT)).is_false()
	assert_bool(_save.load_world(data)).is_true()
	assert_bool(_land().is_owned(BOUGHT)).is_true()
	assert_int(_land().bought).is_equal(1)
	assert_int(_land().next_price()).is_equal(PriceTable.price_of_land_plot(1))
	# The live grid refuses building off the loaded land and takes it on it.
	var off := BuildEdit.paint_floor(Vector2i(80, 10), BuildGrid.FLOOR_TILE, 1)
	var on := BuildEdit.paint_floor(Vector2i(60, 110), BuildGrid.FLOOR_TILE, 1)
	assert_int(_mode.grid.validate(off).reason).is_equal(BuildResult.Reason.LAND_NOT_OWNED)
	assert_bool(_mode.grid.validate(on).ok).is_true()


func test_a_save_whose_land_misses_a_built_cell_is_refused() -> void:
	var data := _taken()
	# The starter terminal stands on column 0, rows 4 and 5: drop row 5.
	var owned: Array = (data["land"]["owned"] as Array).filter(
		func(p: Array) -> bool: return not (int(p[0]) == 0 and int(p[1]) == 5)
	)
	data["land"]["owned"] = owned
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("land")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


func test_a_save_cut_into_another_number_of_plots_is_refused() -> void:
	var data := _taken()
	data["land"]["plot_counts"] = [5, 6]
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(data)).is_false()
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	# The control: the same save as taken loads.
	assert_bool(_save.load_world(_taken())).is_true()
