class_name TestLandsideWords
extends GdUnitTestSuite
## The landside plan lines and the occupied-spot refusal reach the screen
## translated (board e68913dc): whole sentences with named placeholders, plurals
## through tr_n(), the lower-case place name its own msgid. Pseudolocalization
## brackets tr() lines but never tr_n() lines (PseudoLocale), so each plural is
## proved with a run-time Translation whose lines are found only through the
## plural path and its context.

const STARTER := preload("res://landside/starter_landside.tres")
const SITE := preload("res://build/terminal_site.tres")
const SIDE_LAND := Vector2i(85, 0)
const IN_LOT_0 := Vector3(32.0, 0.0, -22.0)
const IN_BAY_0 := Vector3(4.0, 0.0, -57.0)
const ENTRANCE := Vector2i(63, 149) + SIDE_LAND

var _sim: LandsideSim
var _placement: LandsidePlacement
var _translation: Translation
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new(0)
	_placement = LandsidePlacement.new()
	_placement.sim = _sim
	_placement.grid = _site_grid()
	_placement.wallet = Wallet.new(20000)
	_rng.seed = 3


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _site_grid() -> BuildGrid:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var edits: Array[BuildEdit] = []
	for y in range(146, 150):
		for x in range(60 + SIDE_LAND.x, 67 + SIDE_LAND.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	return grid


func _build(kind: LandsidePlacement.Kind, point: Vector3) -> void:
	assert_bool(_placement.apply(_placement.plan_build(kind, point), null).ok).is_true()


func _park_a_car() -> void:
	var bookings: Array[int] = [1]
	_sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)
	for t in range(1, 1500):
		_sim.step(t, true, _rng)
	assert_int(_sim.lot_cars(0)).is_equal(1)


func _translate_plurals(lines: Dictionary) -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	for msgid: String in lines:
		_translation.add_plural_message(
			msgid, PackedStringArray([lines[msgid][0], lines[msgid][1]]), "landside plan"
		)
	TranslationServer.add_translation(_translation)


func test_the_plan_lines_read_as_before_in_english() -> void:
	assert_str(_placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).text).contains(
		"Surface lot: 12 spaces, "
	)
	assert_str(_placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0).text).contains(
		"Curb bay: 2 berths, "
	)
	_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	var remove := _placement.plan_remove(IN_LOT_0)
	assert_str(remove.text).starts_with("Remove surface lot: 12 spaces").contains(". Refunds ")
	var toggle := _placement.plan_toggle(IN_LOT_0)
	assert_str(toggle.text).is_equal("Surface lot (open, 0 cars): click to close it")


func test_each_plan_line_is_one_translated_sentence() -> void:
	_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	PseudoLocale.enable(0.4)
	var build := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0).text
	var remove := _placement.plan_remove(IN_LOT_0).text
	var toggle := _placement.plan_toggle(IN_LOT_0).text
	print("build: %s\nremove: %s\ntoggle: %s" % [build, remove, toggle])
	assert_str(build).starts_with("[").contains("Curb bay")
	assert_str(remove).starts_with("[").contains("surface lot")
	assert_str(remove).not_contains("Surface lot")
	assert_str(toggle).starts_with("[").contains("click to close it")


func test_a_place_name_is_translated_and_a_remove_line_keeps_its_own_lower_case_name() -> void:
	_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message("Surface lot", "Parkplatz", "landside place")
	_translation.add_message("surface lot", "Parkplatz", "landside place, mid-sentence")
	TranslationServer.add_translation(_translation)
	var remove := _placement.plan_remove(IN_LOT_0).text
	print("remove with a German place name: %s" % remove)
	assert_str(remove).starts_with("Remove Parkplatz: ")


func test_the_capacity_and_the_toggle_cars_follow_the_plural_rule() -> void:
	_translate_plurals(
		{
			"{count} space": ["SP1 {count}", "SPN {count}"],
			"{count} berth": ["BE1 {count}", "BEN {count}"],
			"{count} car": ["CA1 {count}", "CAN {count}"],
		}
	)
	_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	var lot := _placement.plan_toggle(IN_LOT_0).text
	var bay := _placement.plan_build(LandsidePlacement.Kind.CURB, IN_BAY_0).text
	_park_a_car()
	var one_car := _placement.plan_toggle(IN_LOT_0).text
	print("lot: %s | bay: %s | one car: %s" % [lot, bay, one_car])
	assert_str(lot).contains("CAN 0")
	assert_str(bay).contains("BEN 2")
	assert_str(one_car).contains("CA1 1")
	assert_str(_placement.plan_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0).text).contains(
		"SPN"
	)


func test_the_occupied_refusal_is_one_plural_sentence() -> void:
	_translate_plurals(
		{
			"{count} car is still in it. Close it and wait until it is empty":
			["OCC1 {count}", "OCCN {count}"],
		}
	)
	_build(LandsidePlacement.Kind.SURFACE_LOT, IN_LOT_0)
	_park_a_car()
	var plan := _placement.plan_remove(IN_LOT_0)
	assert_int(plan.result.reason).is_equal(BuildResult.Reason.LANDSIDE_OCCUPIED)
	print("occupied with a plural translation: %s" % plan.text)
	assert_str(plan.text).ends_with("OCC1 1")
