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
		return PackedStringArray([GameCalendar.clock_text(tick, sim.epoch), named, airline])
	var contract := sim.contract_of(id)
	if contract.is_empty():
		return PackedStringArray()
	var at := GameCalendar.tick_at(0, int(contract["departure_minute"]), sim.epoch)
	var when := GameCalendar.clock_text(at, sim.epoch)
	return PackedStringArray([when, contract["destination"], contract["airline"]])


## {"time", "airline", "city"} naming the contract (or, when `is_flight`, the
## live flight) `id`, the values FlightLabel.words() puts into one whole
## sentence, or {} when it is not known. A one-off flight has "" airline and city.
static func label_args(sim: FlightSim, is_flight: bool, id: String) -> Dictionary:
	var label := parts(sim, is_flight, id)
	if label.is_empty():
		return {}
	return {"time": label[0], "airline": label[2], "city": label[1]}


## The English of a label_args() label, kept as data: "the 20:30 Blue Fjord
## flight to Oslo", "the 10:00 flight" for a one-off flight, "" for {}.
static func english(label: Dictionary) -> String:
	if label.is_empty():
		return ""
	if label["airline"] == "" or label["city"] == "":
		return "the %s flight" % label["time"]
	return "the %s %s flight to %s" % [label["time"], label["airline"], label["city"]]


## The English of each label_args() label in `labels`, comma separated: the
## stored detail of a refusal that names flights.
static func english_list(labels: Array[Dictionary]) -> String:
	var out := PackedStringArray()
	for label in labels:
		out.append(english(label))
	return ", ".join(out)


## "the 20:30 Blue Fjord flight to Oslo" in English, or "" when the flight or
## contract is not known. A one-off flight reads "the 10:00 flight". English
## is data; the player sees words().
static func of(sim: FlightSim, is_flight: bool, id: String) -> String:
	return english(label_args(sim, is_flight, id))


## A label_args() label in the player's words, one whole msgid per shape, or ""
## for {}.
static func words(label: Dictionary) -> String:
	if label.is_empty():
		return ""
	return Words.new().label(label)


## The clash in a FlightSim `reason`, in the player's words: "it clashes with
## the 20:30 Blue Fjord flight to Oslo on the runway", one whole msgid per
## shape. An unknown flight reads "another flight". "" when `reason` is not a clash.
static func clash_sentence(sim: FlightSim, reason: String) -> String:
	var found := parse_clash(reason)
	if found.is_empty():
		return ""
	return Words.new().clash(label_args(sim, found["is_flight"], found["id"]), found)


## tr() is an instance method, so the static functions of this file ask a Words.
class Words:
	extends RefCounted

	func label(named: Dictionary) -> String:
		if named["airline"] == "" or named["city"] == "":
			return tr("the {time} flight", "flight label").format(named)
		return tr("the {time} {airline} flight to {city}", "flight label").format(named)

	## `named` is a label_args() label, or {} for an unknown flight; `found` is
	## parse_clash(), whose "where" picks the sentence.
	func clash(named: Dictionary, found: Dictionary) -> String:
		var shape := "full"
		if named.is_empty():
			shape = "unknown"
		elif named["airline"] == "" or named["city"] == "":
			shape = "one-off"
		var text := ""
		match [shape, found["where"]]:
			["full", "on the runway"]:
				text = tr(
					"it clashes with the {time} {airline} flight to {city} on the runway",
					"offer clash"
				)
			["full", "on the taxi lane"]:
				text = tr(
					"it clashes with the {time} {airline} flight to {city} on the taxi lane",
					"offer clash"
				)
			["full", _]:
				text = tr(
					"it clashes with the {time} {airline} flight to {city} at gate {gate}",
					"offer clash"
				)
			["one-off", "on the runway"]:
				text = tr("it clashes with the {time} flight on the runway", "offer clash")
			["one-off", "on the taxi lane"]:
				text = tr("it clashes with the {time} flight on the taxi lane", "offer clash")
			["one-off", _]:
				text = tr("it clashes with the {time} flight at gate {gate}", "offer clash")
			[_, "on the runway"]:
				text = tr("it clashes with another flight on the runway", "offer clash")
			[_, "on the taxi lane"]:
				text = tr("it clashes with another flight on the taxi lane", "offer clash")
			_:
				text = tr("it clashes with another flight at gate {gate}", "offer clash")
		var values := named.duplicate()
		values["gate"] = found["gate"]
		return text.format(values)
