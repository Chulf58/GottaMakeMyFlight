class_name TestSaveGameGateExit
extends GdUnitTestSuite
## A whole-world save (SaveGame, with SaveLinks) taken while a gate-seated
## passenger gets up from a seat row that moved (board fee68e85,
## GateRelocation) loads: the passenger keeps the seat cell of the old spot, a
## cell the live layout no longer holds, and SaveLinks must not call that a seat
## that is not there. The loaded world plays on to the passenger's next seat
## choice. One boot of main.tscn: the airport opens and play goes on until a
## passenger sits on a gate seat.

const SEED := 41_102_026
const OTHER_SEED := 77
const LIMIT_TICKS := 5000
## Ticks left before boarding a seated passenger must have to be moved.
const SLACK_TICKS := 400
## Where the seat row is set down (terminal cells), as the strip probe does.
const MOVED_TO := Vector2i(17, 6)

var _main: Node
var _loaded: Node
var _path := SaveTestKit.run_path("test_save_game_gate_exit")


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	SaveTestKit.start_airport(_main)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	while flights.opened_tick < 0 and clock.tick < LIMIT_TICKS:
		SaveTestKit.step(_main)
	var board := (_main.get_node("OfferDesk") as OfferDesk).board
	var accepted := false
	for offer in board.open_offers():
		if not accepted and flights.accept_problem(OfferBoard.terms_of(offer)) == "":
			assert_bool(board.accept(offer["id"], flights)).is_true()
			accepted = true
	while _seated() == null and clock.tick < LIMIT_TICKS:
		SaveTestKit.step(_main)


func after() -> void:
	for main in [_main, _loaded]:
		if main != null:
			main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _sim(main: Node) -> PassengerSim:
	return main.get_node("PassengerSim")


## A passenger seated on a gate chair with time to spare before boarding.
func _seated() -> Passenger:
	var sim := _sim(_main)
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if (
			p.stage == Passenger.Stage.SEATED
			and p.seat_object != 0
			and p.boarding_tick - sim.tick > SLACK_TICKS
		):
			return p
	return null


## Moves the passenger's seat row to MOVED_TO as a room move does.
func _move_row(p: Passenger) -> void:
	var grid := _sim(_main).grid
	var record := grid.get_object(p.seat_object)
	var at := ReferenceTerminal.offset_on(grid)
	var place := BuildEdit.place_object(record["def"], MOVED_TO + at, record["facing"])
	place.object_id = p.seat_object
	place.paid = int(record.get("paid", 0))
	for result in grid.apply_batch([BuildEdit.remove_object(p.seat_object), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func test_a_save_mid_exit_from_a_moved_row_loads_and_plays_on_to_a_new_seat() -> void:
	var p := _seated()
	assert_object(p).is_not_null()
	_move_row(p)
	var clock: SimClock = _main.get_node("SimClock")
	var until := clock.tick + 20
	while p.stage != Passenger.Stage.STANDING_UP and clock.tick < until:
		SaveTestKit.step(_main)
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(p.seat_exiting).is_true()
	assert_bool(SaveTestKit.save_game(_main).save_to_file(_path)).is_true()
	_loaded = SaveTestKit.boot(self, OTHER_SEED)
	assert_bool(SaveTestKit.save_game(_loaded).load_from_file(_path)).is_true()
	var q := _sim(_loaded).get_passenger(p.id)
	assert_int(q.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(q.seat_exiting).is_true()
	assert_dict(q.seat_piece).is_equal(p.seat_piece)
	# Play on: the stand-up ends, the seat is given up and chosen again.
	var after := _loaded.get_node("SimClock") as SimClock
	var limit := after.tick + PassengerSim.STAND_UP_TICKS + 400
	var stages: Array[int] = []
	while after.tick < limit and not (q.seat_object != 0 and q.stage == Passenger.Stage.SEATED):
		SaveTestKit.step(_loaded)
		if stages.is_empty() or stages[-1] != q.stage:
			stages.append(q.stage)
	print("loaded passenger stages: ", stages, " seat_object ", q.seat_object)
	assert_bool(q.seat_exiting).is_false()
	assert_array(stages).contains([Passenger.Stage.TO_GATE])
	(
		assert_bool(
			stages.has(Passenger.Stage.SITTING_DOWN) or stages.has(Passenger.Stage.STANDING)
		)
		. is_true()
	)
