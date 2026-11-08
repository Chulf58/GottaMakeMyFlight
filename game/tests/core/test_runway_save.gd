class_name TestRunwaySave
extends GdUnitTestSuite
## The runway's size is part "runway" of the whole-world save (SaveGame version
## 13; decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses, point 8). A version 12 save has no runway and is
## refused, with no migration. One boot of main.tscn.

const SEED := 6_130_813

var _main: Node
var _save: SaveGame
var _flights: FlightSim
var _new_game_size := ""
var _path := SaveTestKit.run_path("test_runway_save")


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_flights = _main.get_node("FlightSim")
	_new_game_size = _flights.runway.size
	_save.quick_save_path = _path
	SaveTestKit.step(_main)


func after() -> void:
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_main.free()


func before_test() -> void:
	_flights.runway.size = PlaneClasses.SMALL


func _taken() -> Dictionary:
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func test_a_new_game_has_a_medium_runway_and_the_save_holds_it() -> void:
	assert_str(_new_game_size).is_equal(PlaneClasses.MEDIUM)
	_flights.runway.size = _new_game_size
	var data := _taken()
	assert_int(int(data["save_version"])).is_equal(13)
	assert_int(int(data["runway"]["save_version"])).is_equal(Runway.SAVE_VERSION)
	assert_str(data["runway"]["size"]).is_equal("medium")


## The day-0 offers the scene drew are all ones the new game's runway takes, and
## the same desk draws medium ones over a month (no small-only start).
func test_a_new_game_draws_offers_its_runway_takes_and_medium_ones_among_them() -> void:
	var desk: OfferDesk = _main.get_node("OfferDesk")
	for offer in desk.board.open_offers():
		assert_bool(_flights.runway.takes(offer["plane_size"])).is_true()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var board := OfferBoard.new()
	var sizes := {}
	for day in 30:
		for id in board.ensure_day(day, rng, 0, _new_game_size):
			sizes[board.offer_of(id)["plane_size"]] = true
	assert_bool(sizes.has(PlaneClasses.MEDIUM)).is_true()


func test_the_size_survives_a_save_and_a_load() -> void:
	_flights.runway.size = PlaneClasses.LARGE
	SaveTestKit.step(_main)
	assert_bool(_save.save_to_file(_path)).is_true()
	_flights.runway.size = PlaneClasses.SMALL
	assert_bool(_save.load_from_file(_path)).is_true()
	print("runway after load: %s" % _flights.runway.size)
	assert_str(_flights.runway.size).is_equal(PlaneClasses.LARGE)
	assert_bool(_flights.runway.takes(PlaneClasses.LARGE)).is_true()


func test_a_version_12_save_without_a_runway_is_refused_and_changes_nothing() -> void:
	_flights.runway.size = PlaneClasses.MEDIUM
	var old := _taken()
	old["save_version"] = 12
	old.erase("runway")
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(old)).is_false()
	print("version 12: '%s'" % _save.message_text())
	# The missing key is found before the version is read.
	assert_str(_save.message_text()).starts_with("Load failed")
	assert_str(_save.message_text()).contains("missing key 'runway'")
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


func test_a_bad_runway_part_is_refused_and_changes_nothing() -> void:
	_flights.runway.size = PlaneClasses.MEDIUM
	var bad := _taken()
	bad["runway"] = {"save_version": 1, "size": "huge"}
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).is_false()
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var missing := _taken()
	missing.erase("runway")
	assert_bool(_save.load_world(missing)).is_false()
	assert_str(_save.message_text()).contains("missing key 'runway'")
