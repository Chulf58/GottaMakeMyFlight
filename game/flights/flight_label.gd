class_name FlightLabel
extends RefCounted
## Names a contract or a live flight for the player, as the departures board
## does: by departure time, airline and destination, never by id. FlightSim
## names things by id in its refusals ("contract Y clashes with flight X-d0 on
## the runway"); this reads those ids back into words.

## What FlightSim's clash refusal reads like: "contract Y clashes with X at
## gate A", "... with flight X-d0 on the runway".
static var _clash := RegEx.create_from_string(
	"^contract \\S+ clashes with (flight )?(\\S+) (at gate (\\S+)|on the runway|on the taxi lane)$"
)


## {"is_flight", "id", "where", "gate"} for a FlightSim clash `reason`, or {}
## when it is not one. `where` is "at gate A", "on the runway" or "on the taxi
## lane"; `gate` is the letter, or "" off the gate.
static func parse_clash(reason: String) -> Dictionary:
	var found := _clash.search(reason)
	if found == null:
		return {}
	return {
		"is_flight": found.get_string(1) != "",
		"id": found.get_string(2),
		"where": found.get_string(3),
		"gate": found.get_string(4),
	}


## [departure time, destination, airline] of the contract (or, when
## `is_flight`, the live flight) `id`, or [] when it is not known. A one-off
## flight has no airline or destination (both ""). A flight of a contract
## shows its pushback time; a contract shows its daily departure time.
static func parts(sim: FlightSim, is_flight: bool, id: String) -> PackedStringArray:
	if is_flight:
		var tick := sim.state_start(id, FlightSim.State.PUSHBACK)
		if tick < 0:
			return PackedStringArray()
		var source := sim.contract_of(sim.flight_contract_id(id))
		var named: String = source["destination"] if not source.is_empty() else ""
		var airline: String = source["airline"] if not source.is_empty() else ""
		return PackedStringArray([GameCalendar.clock_text(tick), named, airline])
	var contract := sim.contract_of(id)
	if contract.is_empty():
		return PackedStringArray()
	var at := GameCalendar.tick_at(0, int(contract["departure_minute"]))
	var when := GameCalendar.clock_text(at)
	return PackedStringArray([when, contract["destination"], contract["airline"]])


## "the 20:30 Blue Fjord flight to Oslo", or "" when the flight or contract is
## not known. A one-off flight has no airline or destination and reads "the 10:00 flight".
static func of(sim: FlightSim, is_flight: bool, id: String) -> String:
	var label := parts(sim, is_flight, id)
	if label.is_empty():
		return ""
	if label[2] == "" or label[1] == "":
		return "the %s flight" % label[0]
	return "the %s %s flight to %s" % [label[0], label[2], label[1]]


## What a FlightSim clash `reason` ran into, in words: "the 20:30 Blue Fjord
## flight to Oslo on the runway". An unknown flight reads "another flight".
## "" when `reason` is not a clash.
static func clash_with(sim: FlightSim, reason: String) -> String:
	var found := parse_clash(reason)
	if found.is_empty():
		return ""
	var label := of(sim, found["is_flight"], found["id"])
	return "%s %s" % [label if label != "" else "another flight", found["where"]]
