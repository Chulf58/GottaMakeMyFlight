extends SceneTree
## Headless timing probe for boarding through the jet bridge (board 927ed9e0;
## rulings jet-bridge-walk-length-counts-toward-boarding-time-lateness and
## bridge-boarding-sim-route-chosen-at-departure-from-the-fligh). It rules
## nothing: it prints numbers.
##
## One terminal on the site with two north exits 44 m apart, each with a gate
## desk: gate A gets a medium contract drawn with model 05 (Nordic Wing), gate
## B one drawn with model 04 (Meridian Air), both on a fixed seed. For each
## gate it prints the walk out a passenger takes (apron_of(): length in mm and
## walk ticks) and the ground walk over open cells to the stand's door beside
## the plane (SiteRoutes.departure(), the walk before the bridge), then runs the
## day and prints every passenger's outcome as one OUTCOME line, so two runs
## (before and after a change) can be compared line by line for flips.
##
## Run headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/bridge_walk_timing_probe.gd

const SITE := preload("res://build/terminal_site.tres")
const SEED := 927
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ENTRANCE := Vector2i(24, 125)
const BOOKED := 40
## The one-off flight make() adds leaves this long after the contracts, so it
## never meets them at a gate.
const ONE_OFF_LATER_MIN := 600
const CONTRACTS := [
	{"id": "C05", "airline": "Nordic Wing", "gate": "A", "later_min": 0},
	{"id": "C04", "airline": "Meridian Air", "gate": "B", "later_min": 30},
]

var _world: PassengerTestWorld
var _apron: ApronStand
var _gates: GateDesks
var _exits := {}
var _outcomes := {}
var _arrived := {}


func _initialize() -> void:
	print("PROBE seed=%d" % SEED)
	if not _build():
		quit(1)
		return
	var flights := {}
	for c: Dictionary in CONTRACTS:
		flights[c["id"]] = _flight_of(c["id"])
	var last_doors := 0
	for c: Dictionary in CONTRACTS:
		var id: String = flights[c["id"]]
		var gate := _world.flights.flight_gate(id)
		var model := PlaneClasses.flight_model(_world.flights, id)
		var doors := _world.flights.doors_close_tick(id)
		last_doors = maxi(last_doors, doors)
		print(
			(
				"FLIGHT %s id=%s gate=%s model=%s boarding=%d doors=%d"
				% [
					c["id"],
					id,
					gate,
					model,
					_world.flights.state_start(id, FlightSim.State.BOARDING),
					doors
				]
			)
		)
		_print_walks(c["id"], id, gate, model)
	_world.sim.outcome.connect(_on_outcome)
	_world.sim.stage_changed.connect(_on_stage)
	_world.run_to(last_doors + 10)
	var ids := _outcomes.keys()
	ids.sort()
	var made := 0
	for pid: int in ids:
		var o: Dictionary = _outcomes[pid]
		made += 1 if o["made"] else 0
		print(
			(
				"OUTCOME id=%d flight=%s made=%s tick=%d doors=%d margin=%d"
				% [pid, o["flight"], o["made"], o["tick"], o["doors"], o["doors"] - o["tick"]]
			)
		)
	print("TOTAL passengers=%d made=%d missed=%d" % [ids.size(), made, ids.size() - made])
	quit(0)


func _build() -> bool:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(23, 121), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(24, 116), 0)
	_exits["A"] = PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	_exits["B"] = PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(grid)
	var starts := FlightSim.schedule_starts(ONE_OFF_LATER_MIN * GameCalendar.TICKS_PER_MINUTE)
	_world = PassengerTestWorld.make(grid, starts, SEED)
	_world.sim.site = SITE
	_gates = GateDesks.new()
	_gates.bind(grid, _world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	_apron = ApronStand.new()
	_apron.passengers = _world.sim
	_apron.bind(grid, SITE, _world.flights, _gates)
	_world.flights.open_airport()
	for c: Dictionary in CONTRACTS:
		var terms := {
			"id": c["id"],
			"airline": c["airline"],
			"destination": "Oslo",
			"departure_minute": TestFlightContracts.bootstrap_minute() + int(c["later_min"]),
			"plane_size": PlaneClasses.MEDIUM,
			"booked_passengers": BOOKED,
			"fee_per_passenger": 25,
		}
		var problem := _world.flights.accept_problem(terms)
		if problem != "" or not _world.flights.accept_contract(terms):
			print("PROBE_INVALID contract %s refused: %s" % [c["id"], problem])
			return false
		if _world.flights.contract_of(c["id"])["gate"] != c["gate"]:
			if not _world.flights.reassign_gate(c["id"], c["gate"]):
				print("PROBE_INVALID contract %s cannot move to gate %s" % [c["id"], c["gate"]])
				return false
	return true


func _flight_of(contract_id: String) -> String:
	for id in _world.flights.flight_ids():
		if _world.flights.flight_contract_id(id) == contract_id:
			return id
	return ""


## The walk a passenger of `flight` takes out of its gate's exit, and the
## ground walk to the stand's door beside the plane.
func _print_walks(label: String, flight: String, gate: String, model: String) -> void:
	var exit: int = _exits[gate]
	var p := Passenger.new()
	p.flight_id = flight
	var apron := _world.sim.files.apron_of(_world.sim, exit, p)
	var layout := _world.sim.layout
	var cells: Array[Vector2i] = []
	cells.assign(layout.outside_routes.get(exit, []))
	var ground := Passenger.new()
	if not cells.is_empty():
		ground.apron.assign(
			SiteRoutes.departure(
				_world.grid, SITE, cells, layout.stand_of(_world.grid, exit), model
			)
		)
	print(
		(
			(
				"WALK %s gate=%s model=%s taken_mm=%d taken_ticks=%d points=%d end=%s"
				+ " | ground_mm=%d ground_ticks=%d | delta_mm=%d delta_ticks=%d"
			)
			% [
				label,
				gate,
				model,
				apron["mm"],
				JourneyForecast.walk_ticks(apron["mm"]),
				(apron["points"] as Array).size(),
				(
					(apron["points"] as Array).back()
					if not (apron["points"] as Array).is_empty()
					else null
				),
				ground.apron_total_mm(),
				JourneyForecast.walk_ticks(ground.apron_total_mm()),
				int(apron["mm"]) - ground.apron_total_mm(),
				(
					JourneyForecast.walk_ticks(apron["mm"])
					- JourneyForecast.walk_ticks(ground.apron_total_mm())
				),
			]
		)
	)


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	if stage == Passenger.Stage.APRON:
		_arrived[id] = _world.clock.tick


func _on_outcome(id: int, made: bool) -> void:
	var p := _world.sim.get_passenger(id)
	var flight := p.flight_id if p != null else ""
	_outcomes[id] = {
		"made": made,
		"flight": flight,
		"tick": _world.clock.tick,
		"doors": _world.flights.doors_close_tick(flight) if flight != "" else 0,
	}
