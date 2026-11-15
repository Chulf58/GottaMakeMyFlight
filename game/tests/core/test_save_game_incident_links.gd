class_name TestSaveGameIncidentLinks
extends GdUnitTestSuite
## The incident-plan flight link on a whole-world save of main.tscn (SaveLinks,
## board incident-plan-flight-ids-are-not-linked-against-the-saved-fl): a saved
## VIP accepted on a flight the saved flights cannot answer is refused with its
## reason and leaves the world as it was, and the same VIP on a flight not yet
## issued loads. The cases on a live, a landed and a forgotten flight, which
## need a world played for days, are in test_save_links_incidents.gd.

const SEED := 31_102_027
const LIMIT_TICKS := 5000

var _main: Node
var _save: SaveGame
var _contract := ""


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	SaveTestKit.start_airport(_main)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	while flights.opened_tick < 0 and clock.tick < LIMIT_TICKS:
		SaveTestKit.step(_main)
	_contract = flights.active_contract_ids()[0]


func after() -> void:
	_main.free()


## The snapshot with one accepted VIP naming `flight`.
func _with_vip(flight: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))
	var incidents: Dictionary = data["incidents"]
	var id := int(incidents["next_id"])
	incidents["next_id"] = id + 1
	var record := {
		"id": id,
		"kind": IncidentCatalogue.VIP,
		"roll_day": 0,
		"state": IncidentCatalogue.ACCEPTED,
		"fire_tick": 0,
		"cell": [-1, -1],
		"mess_id": 0,
		"place": "",
		"outcome": "",
		"shown": false,
		"plan":
		{
			"flight": flight,
			"departs": 99_999,
			"bonus": 100,
			"target": 0,
			"good_mood": 50,
			"miss_half_stars": 1,
		},
	}
	(incidents["incidents"] as Array).append(record)
	return data


func test_a_vip_on_a_flight_the_flights_part_cannot_answer_is_refused() -> void:
	var bad := _with_vip("Q-d9")
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(bad)).is_false()
	print("refused: %s" % _save.message_text())
	assert_str(_save.message_text()).contains("names flight Q-d9, neither live, landed nor to come")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


func test_a_vip_on_a_flight_not_yet_issued_loads() -> void:
	var data := _with_vip("placeholder")
	var next_day := int(data["flights"]["next_day"][_contract])
	var good := _with_vip(FlightTimetable.occurrence_id(_contract, next_day + 1))
	assert_bool(_save.load_world(good)).override_failure_message(_save.message_text()).is_true()
