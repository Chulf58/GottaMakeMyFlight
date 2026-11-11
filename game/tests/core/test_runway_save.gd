class_name TestRunwaySave
extends GdUnitTestSuite
## The runway's size is part "runway" of the whole-world save (SaveGame version
## 13, 14 with the works; decision runway-and-taxi-technical-design-movement-plan-analytic-
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


func test_a_new_game_has_a_small_runway_and_the_save_holds_it() -> void:
	assert_str(_new_game_size).is_equal(PlaneClasses.SMALL)
	_flights.runway.size = _new_game_size
	var data := _taken()
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_int(int(data["runway"]["save_version"])).is_equal(Runway.SAVE_VERSION)
	assert_str(data["runway"]["size"]).is_equal("small")
	var works: Dictionary = data["runway"]["works"]
	assert_str(works["target"]).is_empty()
	assert_int(int(works["start"])).is_equal(-1)
	assert_int(int(works["finish"])).is_equal(-1)


## The day-0 offers the scene drew are all small ones, which the small start
## takes; control: a medium runway draws medium ones over a month.
func test_a_new_game_draws_only_offers_its_runway_takes() -> void:
	var desk: OfferDesk = _main.get_node("OfferDesk")
	assert_array(desk.board.open_offers()).is_not_empty()
	for offer in desk.board.open_offers():
		assert_str(offer["plane_size"]).is_equal(PlaneClasses.SMALL)
		assert_bool(_flights.runway.takes(offer["plane_size"])).is_true()
	var sizes := {}
	for size in [_new_game_size, PlaneClasses.MEDIUM]:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED
		var board := OfferBoard.new()
		sizes[size] = {}
		for day in 30:
			for id in board.ensure_day(day, rng, 0, size):
				sizes[size][board.offer_of(id)["plane_size"]] = true
	assert_array(sizes[_new_game_size].keys()).is_equal([PlaneClasses.SMALL])
	assert_bool(sizes[PlaneClasses.MEDIUM].has(PlaneClasses.MEDIUM)).is_true()


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
	bad["runway"] = {"save_version": 2, "size": "huge", "works": RunwayWorks.new().to_snapshot()}
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).is_false()
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var missing := _taken()
	missing.erase("runway")
	assert_bool(_save.load_world(missing)).is_false()
	assert_str(_save.message_text()).contains("missing key 'runway'")


## A runway too small for a saved offer is refused whole while the load is still
## staged, and the world is as it was. (The same for a saved contract, in
## test_save_game_gates.)
func test_a_small_runway_with_a_medium_offer_is_refused_unchanged() -> void:
	_flights.runway.size = PlaneClasses.MEDIUM
	var board := (_main.get_node("OfferDesk") as OfferDesk).board
	var offers := board.to_snapshot()
	for offer: Dictionary in offers["offers"]:
		offer["plane_size"] = PlaneClasses.MEDIUM
		offer["booked_passengers"] = PlaneClasses.passenger_range(PlaneClasses.MEDIUM)[0]
	assert_bool(board.from_snapshot(offers)).is_true()
	var data := _taken()
	var before := SaveTestKit.checksum(_main)
	# Control: the unchanged save loads.
	assert_bool(_save.load_world(data.duplicate(true))).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	data["runway"]["size"] = "small"
	assert_bool(_save.load_world(data)).is_false()
	print("medium offers, small runway: '%s'" % _save.message_text())
	assert_str(_save.message_text()).contains("offers: offer")
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
