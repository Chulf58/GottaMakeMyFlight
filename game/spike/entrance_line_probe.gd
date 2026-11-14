extends SceneTree
## Headless probe for the line outside the entrance (board 66be00a0, decision
## arrivals-wait-in-a-tidy-line-outside-the-entrance-when-check): the starter
## terminal under N extra passengers booked through the real landside path.
## Prints, every 400 ticks and at the end, the most passengers standing still
## on one cell at the entrance (waiting outside, or waiting inside on the door
## cell), how long the line got (the control: the line was used), how many
## were kept aboard for it, and the made, missed and miss reasons.
## Env: PROBE_N (extra booked, default 72), PROBE_SEED (random when unset).
## Grown from the researcher lane's scratch measurement (finding 2b4693c4).
const StarterFlight := preload("res://spike/starter_flight.gd")

var _main: Node
var _clock: SimClock
var _sim: PassengerSim


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var n := 72
	if OS.has_environment("PROBE_N"):
		n = OS.get_environment("PROBE_N").to_int()
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	_main = load("res://main/main.tscn").instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	for i in 3:
		await process_frame
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	_sim = _main.get_node("PassengerSim")
	NeedFacilityKit.build(mode.grid)
	StarterFlight.add_gate_desk(mode.grid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	var flight := StarterFlight.first_flight()
	var lay := _sim.layout
	var door := lay.door_cell(_sim.grid, lay.passenger_entrances[0])
	_sim.entrance.derive(_sim)
	print(
		(
			"ENTRANCE seed=%d n=%d hired=%d tick=%d doors=%d landside=%s desks=%d door=%s places=%d"
			% [
				seed,
				n,
				hired,
				_clock.tick,
				doors,
				_sim.landside != null,
				lay.desks.size(),
				door,
				_sim.entrance.capacity()
			]
		)
	)
	if _sim.landside == null:
		print("PROBE_INVALID: no landside in main.tscn")
		quit(1)
		return
	_sim.arrivals.schedule(flight, n)
	var max_share := 0
	var max_line := 0
	var max_held := 0
	var max_door := 0
	while _clock.tick < doors:
		_clock.advance(SimClock.STEP)
		var counts := _standing(door)
		max_share = maxi(max_share, counts.x)
		max_door = maxi(max_door, counts.y)
		max_line = maxi(max_line, _sim.entrance.order.size())
		max_held = maxi(max_held, _sim.entrance.held.size())
		if posmod(_clock.tick, 400) == 0:
			var line := _sim.entrance.order.size()
			var held := _sim.entrance.held.size()
			print(
				(
					"ENTRANCE t=%d share=%d door=%d line=%d held=%d"
					% [_clock.tick, counts.x, counts.y, line, held]
				)
			)
	_clock.advance(SimClock.STEP * 2)
	var result := FlightResult.summarize(_sim, flight)
	var shape := "ENTRANCE RESULT n=%d seed=%d max_share=%d max_on_door=%d max_line=%d"
	shape += " max_held=%d made=%d missed=%d"
	print(
		shape % [n, seed, max_share, max_door, max_line, max_held, result["made"], result["missed"]]
	)
	print("ENTRANCE REASONS %s" % [result["reasons"]])
	quit(0)


## The most passengers standing still on one cell at the entrance (x): one
## waiting outside stands where its walk ended; one inside waiting for a desk
## (TO_CHECKIN, QUEUE_FULL) on its cell. y: how many wait on the door cell.
func _standing(door: Vector2i) -> Vector2i:
	var cells := {}
	var on_door := 0
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done():
			continue
		var cell := Passenger.NO_CELL
		if p.stage == Passenger.Stage.SPAWNED and p.apron_mm >= p.apron_total_mm():
			cell = _sim.grid.world_to_cell(p.apron_position()) if not p.apron.is_empty() else p.at
		elif p.stage == Passenger.Stage.TO_CHECKIN and p.stuck == Passenger.Stuck.QUEUE_FULL:
			cell = p.at
		if cell == Passenger.NO_CELL:
			continue
		cells[cell] = int(cells.get(cell, 0)) + 1
		if cell == door:
			on_door += 1
	var most := 0
	for cell in cells:
		most = maxi(most, cells[cell])
	return Vector2i(most, on_door)
