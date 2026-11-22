class_name TestSaveGameRoundTrip
extends GdUnitTestSuite
## Save and continue equals never saved (board item economy-8-8-whole-world-
## save-and-save-files-design-decision). Two main scenes from one seed play in
## lockstep: a control that is never saved and a source. Just before the
## starter's first boarding starts (with its passengers in the terminal and
## none made yet), the source is saved to a file and plays on,
## and a third main scene, booted from another seed, loads that file. All
## three then play through the fee payout and past the first day rollover,
## matching on every tick: full SaveTestKit.checksum before the save, right
## after the load and at the end, and full dynamic SavePart snapshot equality
## (_dynamic_snapshot(), covering every non-grid part) on every tick in between
## (with the unchanging BuildGrid digest verified on all three worlds before and
## after the loop).
##
## Both worlds open on the held calendar (06:00 on day 0 becomes the opening
## tick), save just before the starter's first boarding, and play past the
## first midnight rollover into day 1. before() plays it all once and records
## what each case reads.

const SEED := 6_102_026
const OTHER_SEED := 99
## Ticks before the starter's first boarding starts at which the save is taken.
const SAVE_LEAD := 100
## Ticks played past the start of day 1.
const AFTER_ROLLOVER := 200
const OPEN_LIMIT := 2000

var _path := SaveTestKit.run_path("test_save_game_round_trip")
var _control: Node
var _source: Node
var _loaded: Node
var _run := {}


func before() -> void:
	_control = SaveTestKit.boot(self, SEED)
	_source = SaveTestKit.boot(self, SEED)
	for main in [_control, _source]:
		SaveTestKit.start_airport(main)
	var flights: FlightSim = _source.get_node("FlightSim")
	while flights.opened_tick < 0 and _clock(_source).tick < OPEN_LIMIT:
		_step([_control, _source])
	_run["opened_tick"] = flights.opened_tick
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	while not flights.flight_ids().has(first) and _clock(_source).tick < 2 * OPEN_LIMIT:
		_step([_control, _source])
	var save_at := flights.state_start(first, FlightSim.State.BOARDING) - SAVE_LEAD
	while _clock(_source).tick < save_at:
		_step([_control, _source])
	_run["saved_tick"] = _clock(_source).tick
	_run["same_before_save"] = SaveTestKit.checksum(_control) == SaveTestKit.checksum(_source)
	_run["made_before"] = _sim(_control).made_count()
	_run["balance_before"] = _wallet(_control).balance
	_run["saved"] = SaveTestKit.save_game(_source).save_to_file(_path)
	_loaded = SaveTestKit.boot(self, OTHER_SEED)
	_run["loaded"] = SaveTestKit.save_game(_loaded).load_from_file(_path)
	_play_on()


func after() -> void:
	for main in [_control, _source, _loaded]:
		if main != null:
			main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _play_on() -> void:
	var all := [_control, _source, _loaded]
	var epoch := _clock(_control).epoch
	var day1_start := GameCalendar.day_start(1, epoch)
	var end := day1_start + AFTER_ROLLOVER
	var first_bad := {_source: -1, _loaded: -1}
	var payouts := {_control: 0, _loaded: 0}
	var ticks := 0
	var grid_digests := {}
	var clocks := {}
	var sims := {}
	var wallets := {}
	var dynamic_parts := {}
	for main in all:
		var grid := (main.get_node("BuildMode") as BuildMode).grid
		grid_digests[main.get_instance_id()] = _grid_digest(grid)
		clocks[main] = _clock(main)
		sims[main] = _sim(main)
		wallets[main] = _wallet(main)
		dynamic_parts[main] = SaveTestKit.save_game(main).parts().filter(
			func(part: SavePart) -> bool: return part.key != "grid"
		)
	_run["same_after_load"] = SaveTestKit.checksum(_loaded) == SaveTestKit.checksum(_control)
	var ctrl_clock: SimClock = clocks[_control]
	while ctrl_clock.tick < end:
		var made := {}
		var balance := {}
		for main in payouts:
			made[main] = (sims[main] as PassengerSim).made_count()
			balance[main] = (wallets[main] as Wallet).balance
		for main in all:
			var c: SimClock = clocks[main]
			c.set_paused(false)
			c.advance(SimClock.STEP)
			c.set_paused(true)
		ticks += 1
		for main in payouts:
			var fees: int = (
				((sims[main] as PassengerSim).made_count() - made[main]) * _starter_fee()
			)
			if fees > 0 and (wallets[main] as Wallet).balance - balance[main] >= fees:
				payouts[main] += 1
		var expected := _dynamic_snapshot(dynamic_parts[_control])
		for main in first_bad:
			if first_bad[main] < 0 and _dynamic_snapshot(dynamic_parts[main]) != expected:
				first_bad[main] = (clocks[main] as SimClock).tick
	var grids_unchanged := true
	for main in all:
		var grid := (main.get_node("BuildMode") as BuildMode).grid
		if _grid_digest(grid) != grid_digests[main.get_instance_id()]:
			grids_unchanged = false
	var end_expected := SaveTestKit.checksum(_control)
	for main in first_bad:
		if first_bad[main] < 0 and SaveTestKit.checksum(main) != end_expected:
			first_bad[main] = _clock(main).tick
	_run["grids_unchanged"] = grids_unchanged
	_run["ticks_compared"] = ticks
	_run["first_bad_source"] = first_bad[_source]
	_run["first_bad_loaded"] = first_bad[_loaded]
	_run["payouts_control"] = payouts[_control]
	_run["payouts_loaded"] = payouts[_loaded]
	_run["made_after"] = _sim(_control).made_count()
	_run["epoch"] = epoch
	_run["day"] = GameCalendar.day_of(_clock(_control).tick, epoch)
	_run["day1_offers_control"] = _day_offers(_control, 1)
	_run["day1_offers_loaded"] = _day_offers(_loaded, 1)


static func _grid_digest(grid: BuildGrid) -> String:
	return JSON.stringify(grid.to_snapshot(), "", true, true).sha256_text()


static func _dynamic_snapshot(parts: Array) -> Dictionary:
	var data := {}
	for part: SavePart in parts:
		data[part.key] = part.save.call()
	return data


static func _step(worlds: Array) -> void:
	for main in worlds:
		SaveTestKit.step(main)


static func _starter_fee() -> int:
	return FlightSim.STARTER_TERMS["fee_per_passenger"]


static func _day_offers(main: Node, day: int) -> Array:
	var out := []
	for offer in (main.get_node("OfferDesk") as OfferDesk).board.open_offers():
		if offer["day"] == day:
			out.append(offer)
	return out


static func _clock(main: Node) -> SimClock:
	return main.get_node("SimClock")


static func _sim(main: Node) -> PassengerSim:
	return main.get_node("PassengerSim")


static func _wallet(main: Node) -> Wallet:
	return (main.get_node("Finances") as Finances).wallet


func test_the_source_was_saved_to_a_file_and_loaded_into_a_fresh_scene() -> void:
	assert_int(_run["opened_tick"]).is_greater(0)
	assert_bool(_run["same_before_save"]).is_true()
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()
	assert_bool(_run["same_after_load"]).is_true()


func test_save_and_continue_matches_the_unsaved_control_on_every_tick() -> void:
	assert_bool(_run["grids_unchanged"]).is_true()
	assert_int(_run["ticks_compared"]).is_greater(SAVE_LEAD + AFTER_ROLLOVER)
	(
		assert_int(_run["first_bad_source"])
		. override_failure_message("first differing tick %d" % _run["first_bad_source"])
		. is_equal(-1)
	)


func test_the_loaded_world_matches_the_unsaved_control_on_every_tick() -> void:
	(
		assert_int(_run["first_bad_loaded"])
		. override_failure_message("first differing tick %d" % _run["first_bad_loaded"])
		. is_equal(-1)
	)


func test_the_compared_ticks_hold_a_fee_payout() -> void:
	assert_int(_run["made_before"]).is_equal(0)
	assert_int(_run["made_after"]).is_greater(0)
	assert_int(_run["payouts_control"]).is_greater(0)
	assert_int(_run["payouts_loaded"]).is_equal(_run["payouts_control"])


func test_the_compared_ticks_hold_the_day_rollover_and_its_offer_draw() -> void:
	assert_int(GameCalendar.day_of(_run["saved_tick"], _run["epoch"])).is_equal(0)
	assert_int(_run["day"]).is_equal(1)
	assert_int((_run["day1_offers_control"] as Array).size()).is_equal(OfferBoard.OFFERS_PER_DAY)
	assert_array(_run["day1_offers_loaded"]).is_equal(_run["day1_offers_control"])
