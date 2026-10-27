class_name TestSaveGameLinks
extends GdUnitTestSuite
## The checks across the parts of a whole-world save (SaveLinks, Sol review
## of the whole-world save, finding 2): an id saved in one part must name
## something another part holds, or the load is refused and the world is left
## as it was. One boot of main.tscn for the file: the airport opens, an offer
## is accepted, and play goes on until passengers queue at a station and sit
## on gate seats.

const SEED := 31_102_026
const LIMIT_TICKS := 5000

var _main: Node
var _save: SaveGame
var _accepted := ""


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	SaveTestKit.start_airport(_main)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	while flights.opened_tick < 0 and clock.tick < LIMIT_TICKS:
		SaveTestKit.step(_main)
	var board := (_main.get_node("OfferDesk") as OfferDesk).board
	for offer in board.open_offers():
		if _accepted == "" and flights.accept_problem(OfferBoard.terms_of(offer)) == "":
			assert_bool(board.accept(offer["id"], flights)).is_true()
			_accepted = offer["id"]
	while not _busy() and clock.tick < LIMIT_TICKS:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


## A passenger at a station, one on a gate seat and a queue, all at once.
func _busy() -> bool:
	var data: Dictionary = _save.snapshot()["passengers"]
	return (
		_record_with(data, "station") >= 0
		and _record_with(data, "seat_object") >= 0
		and not (data["queues"] as Array).is_empty()
	)


static func _record_with(passengers: Dictionary, field: String) -> int:
	var records: Array = passengers["passengers"]
	for i in records.size():
		if int(records[i][field]) != 0:
			return i
	return -1


func _taken() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))


func _offer_index(data: Dictionary, id: String) -> int:
	var offers: Array = data["offers"]["offers"]
	for i in offers.size():
		if offers[i]["id"] == id:
			return i
	return -1


func _open_index(data: Dictionary) -> int:
	var offers: Array = data["offers"]["offers"]
	for i in offers.size():
		if offers[i]["status"] == OfferBoard.OPEN:
			return i
	return -1


func _assert_refused(bad: Dictionary, reason: String) -> void:
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).override_failure_message(reason).is_false()
	assert_str(_save.message_text()).override_failure_message(reason).contains(reason)
	assert_str(SaveTestKit.checksum(_main)).override_failure_message(reason).is_equal(before)


func test_the_world_holds_what_the_links_name() -> void:
	assert_str(_accepted).is_not_empty()
	assert_bool(_busy()).is_true()
	var data := _taken()
	assert_int(_open_index(data)).is_greater_equal(0)
	assert_bool(_save.load_world(data)).is_true()


func test_an_open_offer_marked_accepted_without_a_contract_is_refused() -> void:
	var bad := _taken()
	bad["offers"]["offers"][_open_index(bad)]["status"] = OfferBoard.ACCEPTED
	_assert_refused(bad, "is accepted but flights hold no contract")


func test_an_accepted_offer_whose_terms_differ_from_its_contract_is_refused() -> void:
	var bad := _taken()
	var offer: Dictionary = bad["offers"]["offers"][_offer_index(bad, _accepted)]
	offer["fee_per_passenger"] = int(offer["fee_per_passenger"]) + 1
	if int(offer["fee_per_passenger"]) > OfferBoard.FEE_MAX:
		offer["fee_per_passenger"] = OfferBoard.FEE_MIN
	_assert_refused(bad, "has another fee_per_passenger than its offer")


func test_a_contract_whose_offer_is_not_accepted_is_refused() -> void:
	var bad := _taken()
	bad["offers"]["offers"][_offer_index(bad, _accepted)]["status"] = OfferBoard.DECLINED
	_assert_refused(bad, "flights hold its contract")


func test_a_passenger_on_an_unknown_flight_is_refused() -> void:
	var bad := _taken()
	bad["passengers"]["passengers"][0]["flight_id"] = "NOPE"
	_assert_refused(bad, "flight NOPE is named")


func test_a_passenger_at_a_station_that_is_not_there_is_refused() -> void:
	var bad := _taken()
	var i := _record_with(bad["passengers"], "station")
	bad["passengers"]["passengers"][i]["station"] = 99999
	_assert_refused(bad, "which is not a usable station")


func test_a_queue_at_a_station_that_is_not_there_is_refused() -> void:
	var bad := _taken()
	bad["passengers"]["queues"][0]["station"] = 99999
	_assert_refused(bad, "a queue is at 99999")


func test_a_passenger_on_a_seat_that_is_not_there_is_refused() -> void:
	var bad := _taken()
	var i := _record_with(bad["passengers"], "seat_object")
	bad["passengers"]["passengers"][i]["seat_object"] = 99999
	_assert_refused(bad, "holds a seat that is not there")
