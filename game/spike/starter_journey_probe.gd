extends SceneTree
## Measures the first passenger party's journey on the starter terminal, for
## StarterSlot.JOURNEY_TICKS (decision closed-airport-calendar-design-an-
## explicit-calendar-epoch-pa, point 5). Headless, no plates:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/starter_journey_probe.gd [-- --seed=N]
## Two worlds on main.tscn, each with a new random world seed (printed), or N
## to replay: BASE, the starter terminal with its north gate A; FAR, the same
## plus a west wing on side land with gate B by its west exit (cells from the
## starter offset, as side_land_west_wing_probe.gd builds it), and gate A's desk
## taken away, so the starter flies from the far gate. Each hires one member per
## station and runs until the airport opens, then follows the first party of
## the starter's first flight (FirstParty) through the real landside flow: the
## tick its vehicle enters the road, each member's release at the curb, the tick
## each reaches the gate (sitting down, standing or already boarding), and the
## tick each made or missed the flight. It prints the gate's taxi pair, the
## opening tick, the departure and every tick relative to the opening, and the
## journey (opening to the last member at the gate) with the lead StarterSlot
## gives. Pass values are positives: the party has members, every member got
## out, reached the gate and made the flight. Otherwise PROBE_INVALID, exit 1.

const MAIN := "res://main/main.tscn"
const IntroClose := preload("res://spike/intro_close.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const SITE := preload("res://build/terminal_site.tres")
const OPEN_LIMIT := 6000
const FLY_LIMIT := 12000
const WING := Rect2i(-20, 4, 12, 8)
const CORRIDOR := Rect2i(-8, 7, 18, 2)
const WING_EXIT := Vector2i(-20, 8)
const WING_DESK := Vector2i(-18, 7)
const AT_GATE: Array[int] = [
	Passenger.Stage.SITTING_DOWN,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING,
	Passenger.Stage.STANDING_UP,
	Passenger.Stage.TO_EXIT,
	Passenger.Stage.APRON,
]

var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _grid: BuildGrid
var _gates: GateDesks
## booking id -> {"passenger", "released", "at_gate", "made", "outcome"}.
var _party := {}
var _by_passenger := {}
var _journeys := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for label in ["BASE", "FAR"]:
		if not await _measure(label):
			quit(1)
			return
	print(
		(
			"PROBE journeys BASE=%d FAR=%d longest=%d"
			% [_journeys["BASE"], _journeys["FAR"], maxi(_journeys["BASE"], _journeys["FAR"])]
		)
	)
	print("PROBE_PASS starter journey")
	quit(0)


func _measure(label: String) -> bool:
	_party = {}
	_by_passenger = {}
	var world_seed := IntroClose.seed_or_random()
	print("PROBE %s world_seed=%d" % [label, world_seed])
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	for i in 3:
		await process_frame
	_grid = (_main.get_node("BuildMode") as BuildMode).grid
	_gates = _main.get_node("GateDesks")
	var problem := IntroClose.close(_main)
	if problem == "":
		problem = _build(label == "FAR")
	if problem == "":
		problem = _open()
	if problem == "":
		problem = _follow(label)
	_main.free()
	_main = null
	if problem != "":
		print("PROBE_INVALID %s: %s" % [label, problem])
		return false
	return true


## The starter terminal; for the far world also the west wing and its gate B,
## with gate A's desk taken away. "" or what was refused.
func _build(far: bool) -> String:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	if _gates.gate_ids() != ["A"]:
		return "the starter gate desk made no gate A"
	if not far:
		return ""
	var problem := _build_wing()
	if problem != "":
		return problem
	var sides := {}
	for gate: String in _gates.stands:
		sides[gate] = StandPlacement.side_of(_gates.stands[gate])
	print("PROBE FAR gates %s" % [sides])
	if sides.size() != 1 or sides.values()[0] != StandPlacement.WEST:
		return "the far world does not have one west gate"
	return ""


## The west wing, its gate B, and gate A's desk taken away. "" or what was
## refused.
func _build_wing() -> String:
	var at := ReferenceTerminal.offset_on(_grid)
	var cells := {}
	for rect in [WING, CORRIDOR]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y) + at] = true
	var bought := _buy_under(cells.keys())
	if bought != "":
		return bought
	var edits: Array[BuildEdit] = []
	for cell: Vector2i in cells:
		edits.append(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	var exit := WING_EXIT + at
	for cell: Vector2i in cells:
		for side in 4:
			var next: Vector2i = cell + BuildGrid.SIDE_STEP[side]
			if cells.has(next) or (cell == exit and side == BuildGrid.Side.WEST):
				continue
			if _grid.floor_at(next) != BuildGrid.FLOOR_NONE:
				edits.append(BuildEdit.remove_wall(next, (side + 2) % 4))
				continue
			edits.append(BuildEdit.place_wall(cell, side))
	edits.append(BuildEdit.place_object(&"exit_door", exit, 3))
	for result in _grid.apply_batch(edits):
		if not result.ok:
			return "a wing edit was refused: %s" % result.reason_text()
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, WING_DESK + at, 0))
	if not desk.ok:
		return "the wing gate desk was refused: %s" % desk.reason_text()
	var starter_desk := -1
	for id in GateDesks.desk_ids(_grid):
		if _grid.object_at(WING_DESK + at) != id:
			starter_desk = id
	var removed := _grid.apply(BuildEdit.remove_object(starter_desk))
	if not removed.ok:
		return "gate A's desk could not be taken away: %s" % removed.reason_text()
	return ""


## Buys, free, the plots under `cells`, each toward the nearest buyable plot.
func _buy_under(cells: Array) -> String:
	var land := (_main.get_node("BuildMode") as BuildMode).land_tool.land
	var wanted := {}
	for cell: Vector2i in cells:
		wanted[land.plot_of(cell)] = true
	for plot: Vector2i in wanted:
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			var result := land.buy(best, null) if best != Vector2i(-1, -1) else null
			if result == null or not result.ok:
				return "the land toward plot %s could not be bought" % plot
	return ""


## Hires a member per station and steps until the airport opens.
func _open() -> String:
	var staff: StaffSim = _main.get_node("Staff")
	print("PROBE hired %d" % StarterFlight.hire_per_station(_sim, staff))
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		_step()
		if _clock.tick - hired_at > OPEN_LIMIT:
			return "the airport did not open %d ticks after hiring" % OPEN_LIMIT
	return ""


## Follows the first party of the starter's first flight to its outcome.
func _follow(label: String) -> String:
	var opened := _flights.opened_tick
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var contract := _flights.contract_of(FlightSim.DEFAULT_ID)
	if contract.is_empty() or _flights.state_of(first) < 0:
		return "the opening issued no starter flight %s" % first
	var party := 1 << 30
	for id in _sim.arrivals.booking_ids():
		var b := _sim.arrivals.get_booking(id)
		if b.flight_id == first:
			party = mini(party, b.party)
	for id in _sim.arrivals.booking_ids():
		var b := _sim.arrivals.get_booking(id)
		if b.flight_id == first and b.party == party:
			_party[id] = {"unload": b.unload_tick, "vehicle": b.vehicle}
	if _party.is_empty():
		return "the starter's first flight has no party booked"
	_sim.arrivals.released.connect(_on_released)
	_sim.stage_changed.connect(_on_stage)
	_sim.outcome.connect(_on_outcome)
	var limit := _clock.tick + FLY_LIMIT
	while not _settled() and _clock.tick < limit:
		_step()
	var departs := _flights.state_start(first, FlightSim.State.PUSHBACK)
	var doors := _flights.state_start(first, FlightSim.State.DOORS_CLOSED)
	var boarding := _flights.state_start(first, FlightSim.State.BOARDING)
	print(
		(
			"PROBE %s gate=%s taxi=%s opened=%d boarding=+%d doors=+%d departs=+%d (%s)"
			% [
				label,
				contract["gate"],
				contract[FlightContract.TAXI_KEY],
				opened,
				boarding - opened,
				doors - opened,
				departs - opened,
				GameCalendar.clock_text(departs, _clock.epoch),
			]
		)
	)
	var last_at_gate := 0
	for id: int in _party:
		var row: Dictionary = _party[id]
		print(
			(
				"PROBE %s booking %d vehicle_boarded=%s unload=+%d released=%s at_gate=%s outcome=%s"
				% [
					label,
					id,
					row["vehicle"] != 0,
					int(row["unload"]) - opened,
					_rel(row, "released", opened),
					_rel(row, "at_gate", opened),
					row.get("outcome", "none"),
				]
			)
		)
		if not row.has("at_gate") or row.get("outcome", "") != "made":
			return "booking %d did not reach the gate and make the flight" % id
		last_at_gate = maxi(last_at_gate, int(row["at_gate"]) - opened)
	_journeys[label] = last_at_gate
	print(
		(
			"PROBE %s party=%d journey=%d lead_now=%d plane_lead=%d"
			% [
				label,
				_party.size(),
				last_at_gate,
				StarterSlot.lead(contract[FlightContract.TAXI_KEY]),
				FlightTimetable.departure_offset(contract[FlightContract.TAXI_KEY]),
			]
		)
	)
	return ""


func _rel(row: Dictionary, key: String, opened: int) -> String:
	return "+%d" % (int(row[key]) - opened) if row.has(key) else "never"


func _settled() -> bool:
	for id: int in _party:
		if not (_party[id] as Dictionary).has("outcome"):
			return false
	return true


func _on_released(booking_id: int, passenger_id: int) -> void:
	if _party.has(booking_id):
		_party[booking_id]["passenger"] = passenger_id
		_party[booking_id]["released"] = _clock.tick
		_by_passenger[passenger_id] = booking_id


func _on_stage(passenger_id: int, stage: Passenger.Stage) -> void:
	if not _by_passenger.has(passenger_id) or not AT_GATE.has(stage):
		return
	var row: Dictionary = _party[_by_passenger[passenger_id]]
	if not row.has("at_gate"):
		row["at_gate"] = _clock.tick


func _on_outcome(passenger_id: int, made: bool) -> void:
	if _by_passenger.has(passenger_id):
		_party[_by_passenger[passenger_id]]["outcome"] = "made" if made else "missed"


func _step() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
