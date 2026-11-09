class_name TestRunwayWorksSave
extends GdUnitTestSuite
## Runway upgrade works on the real main scene (Runway R9; board 48f9bf52): a
## new game starts with a small runway and the drawn runway matches it, the
## player can buy the upgrade, the works survive a save made in the middle of
## them, and a save whose works are already over is refused. One boot of
## main.tscn.

const SEED := 6_130_909

var _main: Node
var _save: SaveGame
var _flights: FlightSim
var _unlocks: BuildUnlocks
var _finances: Finances
var _view: RunwayView
var _new_game_size := ""
var _new_game_pieces := 0
var _path := SaveTestKit.run_path("test_runway_works_save")


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_flights = _main.get_node("FlightSim")
	_unlocks = _main.get_node("BuildUnlocks")
	_finances = _main.get_node("Finances")
	_view = _main.get_node("Airside/RunwayView")
	_new_game_size = _flights.runway.size
	_new_game_pieces = _view.get_child(0).get_child_count()
	_save.quick_save_path = _path
	SaveTestKit.step(_main)


func after() -> void:
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_main.free()


## The tests jump the sim to the end of the works with on_tick; the clock stays
## where it was, and a save needs every part on the clock's tick.
func after_test() -> void:
	_flights.tick = (_main.get_node("SimClock") as SimClock).tick


func before_test() -> void:
	_flights.runway.size = PlaneClasses.SMALL
	_flights.runway.works.clear()
	_unlocks.from_snapshot({"tier": 2, "made": 50})


func test_a_new_game_starts_small_and_draws_a_small_runway() -> void:
	assert_str(_new_game_size).is_equal(PlaneClasses.SMALL)
	assert_int(_new_game_pieces).is_equal(Runway.pieces(PlaneClasses.SMALL).size())
	assert_str(_view.shown_size()).is_equal(PlaneClasses.SMALL)


func test_a_new_game_can_upgrade_and_the_drawn_runway_follows_the_works() -> void:
	_flights.open_airport()
	assert_str(RunwayWorks.buy(_flights, _unlocks, _finances.wallet)).is_empty()
	var works := _flights.runway.works
	assert_bool(works.scheduled()).is_true()
	assert_str(_view.shown_size()).is_equal(PlaneClasses.SMALL)
	_flights.on_tick(works.finish)
	print(
		(
			"drawn after the works: %s, %d pieces"
			% [_view.shown_size(), _view.get_child(0).get_child_count()]
		)
	)
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(_view.shown_size()).is_equal(PlaneClasses.MEDIUM)
	assert_int(_view.get_child(0).get_child_count()).is_equal(
		Runway.pieces(PlaneClasses.MEDIUM).size()
	)


func test_a_save_made_mid_works_keeps_them_and_the_drawn_runway_follows_a_load() -> void:
	_flights.runway.works.begin(PlaneClasses.MEDIUM, _flights.tick + 400)
	SaveTestKit.step(_main)
	var works := _flights.runway.works
	var target := works.target
	var start := works.start
	var finish := works.finish
	assert_bool(_save.save_to_file(_path)).is_true()
	works.clear()
	_flights.runway.size = PlaneClasses.LARGE
	assert_bool(_save.load_from_file(_path)).is_true()
	print(
		(
			"after load: %s %d-%d, runway %s"
			% [works.target, works.start, works.finish, _flights.runway.size]
		)
	)
	assert_str(works.target).is_equal(target)
	assert_int(works.start).is_equal(start)
	assert_int(works.finish).is_equal(finish)
	assert_str(_flights.runway.size).is_equal(PlaneClasses.SMALL)
	assert_str(_view.shown_size()).is_equal(PlaneClasses.SMALL)
	assert_int(_view.get_child(0).get_child_count()).is_equal(
		Runway.pieces(PlaneClasses.SMALL).size()
	)
	# The works still end and switch the size after the load.
	_flights.on_tick(finish)
	assert_str(_flights.runway.size).is_equal(PlaneClasses.MEDIUM)


## The check SaveGame stages a load with: works that already ended on the saved
## clock tick are not a state of play (Runway.settle() runs on every tick).
func test_a_save_whose_works_are_already_over_is_refused() -> void:
	var runway := Runway.new(PlaneClasses.SMALL)
	runway.works.begin(PlaneClasses.MEDIUM, 3000)
	var data := {"clock": {"tick": "4199"}, "offers": {"offers": []}}
	var staged := {"runway": runway}
	assert_str(_save._runway_problem(data, staged)).is_empty()
	data["clock"]["tick"] = "4200"
	var problem := _save._runway_problem(data, staged)
	print("works over: '%s'" % problem)
	assert_str(problem).is_equal("runway: the works end at tick 4200, the clock is on tick 4200")


func test_a_version_1_runway_part_without_works_is_refused_unchanged() -> void:
	var data := JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true)) as Dictionary
	assert_int(int(data["save_version"])).is_equal(14)
	data["runway"] = {"save_version": 1, "size": "small"}
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).starts_with("Load failed: runway")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
