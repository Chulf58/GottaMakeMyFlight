class_name TestUnlockGuideFirsts
extends GdUnitTestSuite
## The phone ring and the short dialog also come the first time the runway
## works finish and the first time a major incident is presented (decision
## phone-ring-and-help-dialog-also-on-big-firsts-first-runway-u). Each shows
## once per game, is kept in the BuildUnlocks snapshot (the save's "unlocks"
## part), pauses the clock like a tier dialog, and leaves the tier dialog as it
## was.

var _port: SubViewport
var _rating: AirportRating
var _pax: PassengerSim
var _clock: SimClock
var _unlocks: BuildUnlocks
var _guide: UnlockGuide
var _save: SaveGame
var _runway: Runway
var _director: IncidentDirector
var _rings: Array[int] = []


func before_test() -> void:
	_rings.clear()
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_build_world()


func after_test() -> void:
	_port.free()


## A fresh set of unlocks, runway, director and guide: a new game, or the
## session that loads a save.
func _build_world(mode := UnlockGuide.Mode.PROFILE, runway: Runway = null) -> void:
	if is_instance_valid(_unlocks):
		_unlocks.queue_free()
	if is_instance_valid(_guide):
		_guide.queue_free()
	if is_instance_valid(_save):
		_save.queue_free()
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_save = SaveGame.new()
	_port.add_child(_save)
	_runway = runway if runway != null else Runway.new(PlaneClasses.SMALL)
	_director = auto_free(IncidentDirector.new())
	_guide = UnlockGuide.new()
	_guide.mode = mode
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_guide.save_game = _save
	_guide.runway = _runway
	_guide.director = _director
	_port.add_child(_guide)
	_guide.phone_ring.connect(func(tier: int) -> void: _rings.append(tier))


## The runway works book, run and end: the size changes at the finish tick.
func _finish_works(target: String) -> void:
	_runway.works.begin(target, 0)
	assert_bool(_runway.settle(_runway.works.finish)).is_true()


func _present_major(kind := IncidentCatalogue.INSPECTOR) -> void:
	_director.major_presented.emit({"id": 1, "kind": kind})


## Opens tier 2 by play, which shows the tier dialog.
func _open_tier_two() -> void:
	for i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 50:
		_pax.outcome.emit(i, true)
	_unlocks.check()


func test_the_first_finished_runway_works_ring_and_show_the_runway_dialog() -> void:
	assert_bool(_guide.is_open()).is_false()
	_finish_works(PlaneClasses.MEDIUM)
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_guide.is_ringing()).is_true()
	assert_object(_guide.dialog()).is_null()
	_guide.answer_ring()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.RUNWAY]))
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_true()
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_false()


## The size applies at once while the airport is closed (FlightSim.start_works),
## and that upgrade is the first one too.
func test_an_upgrade_before_the_airport_opens_is_the_first_upgrade() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	sim.runway.size = PlaneClasses.SMALL
	_build_world(UnlockGuide.Mode.PROFILE, sim.runway)
	assert_bool(sim.start_works(PlaneClasses.MEDIUM)).is_true()
	assert_str(sim.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_bool(_guide.is_open()).is_true()
	_guide.answer_ring()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.RUNWAY]))
	_guide.dismiss()
	_rings.clear()
	assert_bool(sim.start_works(PlaneClasses.LARGE)).is_true()
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


## With the airport open the works are only booked: the dialog waits for them
## to finish.
func test_works_booked_with_the_airport_open_show_nothing_until_they_finish() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	sim.runway.size = PlaneClasses.SMALL
	sim.open_airport()
	_build_world(UnlockGuide.Mode.PROFILE, sim.runway)
	assert_bool(sim.start_works(PlaneClasses.MEDIUM)).is_true()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(sim.runway.settle(sim.runway.works.finish)).is_true()
	assert_bool(_guide.is_open()).is_true()


func test_a_second_runway_upgrade_shows_nothing() -> void:
	_finish_works(PlaneClasses.MEDIUM)
	_guide.dismiss()
	_rings.clear()
	_finish_works(PlaneClasses.LARGE)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


func test_the_first_major_incident_rings_and_shows_the_incident_dialog() -> void:
	_present_major()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_guide.is_ringing()).is_true()
	_guide.answer_ring()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.INCIDENT]))
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_true()
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_false()


func test_a_second_major_incident_shows_nothing() -> void:
	_present_major()
	_guide.dismiss()
	_rings.clear()
	_present_major(IncidentCatalogue.VIP)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


func test_the_two_firsts_are_separate_each_shows_once() -> void:
	_present_major()
	_guide.dismiss()
	_finish_works(PlaneClasses.MEDIUM)
	assert_bool(_guide.is_open()).is_true()
	_guide.answer_ring()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER, UnlockGuide.NO_TIER])
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.RUNWAY]))


func test_a_load_that_installs_a_bigger_runway_shows_nothing() -> void:
	var saved := Runway.new(PlaneClasses.MEDIUM).to_snapshot()
	assert_bool(_runway.from_snapshot(saved)).is_true()
	assert_int(PlaneClasses.ORDER.find(_runway.size)).is_equal(1)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_false()


func test_a_shown_first_stays_shown_after_a_save_and_a_load_of_the_snapshot() -> void:
	_present_major()
	_guide.dismiss()
	var data := JSON.parse_string(JSON.stringify(_unlocks.to_snapshot())) as Dictionary
	assert_array(data["firsts"]).is_equal([BigFirsts.INCIDENT])
	_build_world()
	_rings.clear()
	assert_bool(_unlocks.from_snapshot(data)).is_true()
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_true()
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_false()
	_present_major()
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()
	_finish_works(PlaneClasses.MEDIUM)
	assert_bool(_guide.is_open()).is_true()


func test_a_new_game_shows_the_firsts_again() -> void:
	_present_major()
	_guide.dismiss()
	_build_world()
	_rings.clear()
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_false()
	_present_major()
	assert_bool(_guide.is_open()).is_true()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])


func test_a_first_pauses_the_clock_and_closing_gives_back_the_players_speed() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	_present_major()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_first_that_comes_while_the_tier_dialog_is_open_shows_when_it_closes() -> void:
	_open_tier_two()
	_guide.answer_ring()
	assert_bool(_guide.is_open()).is_true()
	assert_array(Array(_guide.dialog().chip_texts())).contains(["Food"])
	_present_major()
	# One dialog at a time: the tier dialog keeps the screen, the first waits.
	assert_array(Array(_guide.dialog().chip_texts())).contains(["Food"])
	assert_array(_rings).is_equal([2])
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_true()
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.INCIDENT]))
	assert_array(_rings).is_equal([2, UnlockGuide.NO_TIER])
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()


func test_a_tier_unlock_still_rings_with_its_tier_and_shows_its_families() -> void:
	_open_tier_two()
	_guide.answer_ring()
	assert_array(_rings).is_equal([2])
	assert_array(Array(_guide.dialog().chip_texts())).contains(["Runway"])
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_false()
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_false()


func test_a_load_with_a_first_waiting_drops_it() -> void:
	_open_tier_two()
	_present_major()
	_clock.set_paused(true)
	_clock.set_speed(1)
	_save.loaded.emit(true)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_equal([2])


func test_leaving_the_tree_with_a_first_queued_opens_nothing_and_frees_the_clock() -> void:
	_clock.set_paused(false)
	_open_tier_two()
	_present_major()
	_port.remove_child(_guide)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	_guide.free()


func test_a_guide_that_is_off_shows_and_marks_nothing_for_a_first() -> void:
	_build_world(UnlockGuide.Mode.OFF)
	_present_major()
	_finish_works(PlaneClasses.MEDIUM)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_unlocks.first_shown(BigFirsts.INCIDENT)).is_false()
	assert_bool(_unlocks.first_shown(BigFirsts.RUNWAY)).is_false()
	assert_array(_rings).is_empty()
