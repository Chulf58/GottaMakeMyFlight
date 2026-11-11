extends SceneTree
## Headless timing probe for the per-edit cost of SiteRoutes.distances (board
## 4262b55f). It rules nothing: it prints numbers.
##
## A two-gate terminal on a SiteGrid with GateDesks, ApronStand and the
## passenger sim's TerminalLayout bound to it, the handlers a committed build
## edit runs. It then commits EDITS edits (a seat row placed, then removed,
## alternately) the way BuildMode does (hold_signals, apply, release_signals)
## and prints, per edit, the milliseconds and the SiteRoutes.searches made.
##
## Run headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/site_routes_edit_timing_probe.gd

const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ENTRANCE := Vector2i(24, 125)
const ROW := Vector2i(30, 118)
const EDITS := 6

var _world: PassengerTestWorld
var _grid: SiteGrid
var _gates: GateDesks
var _apron: ApronStand
var _row := 0


func _initialize() -> void:
	_grid = SiteGrid.new(SITE)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_grid.apply_batch(floor)
	PassengerTestWorld.place(_grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(_grid, &"checkin_desk", Vector2i(23, 121), 0)
	PassengerTestWorld.place(_grid, &"security_scanner", Vector2i(24, 116), 0)
	PassengerTestWorld.place(_grid, &"exit_door", EXIT_A, 0)
	PassengerTestWorld.place(_grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(_grid)
	var starts := FlightSim.schedule_starts(600 * GameCalendar.TICKS_PER_MINUTE)
	_world = PassengerTestWorld.make(_grid, starts, 4262)
	_world.sim.site = SITE
	_gates = GateDesks.new()
	_gates.bind(_grid, _world.flights)
	PassengerTestWorld.place(_grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(_grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	_apron = ApronStand.new()
	_apron.passengers = _world.sim
	_apron.bind(_grid, SITE, _world.flights, _gates)
	print("PROBE gates %s" % [_gates.gate_ids()])


func _process(_delta: float) -> bool:
	var total := 0.0
	var searches := 0
	for i in EDITS:
		var before := SiteRoutes.searches
		var t0 := Time.get_ticks_usec()
		_grid.hold_signals()
		var result := (
			_grid.apply(BuildEdit.place_object(&"seat_row", ROW, 0))
			if _row == 0
			else _grid.apply(BuildEdit.remove_object(_row))
		)
		_grid.release_signals()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if not result.ok:
			print("PROBE_INVALID edit refused: %s" % result.reason_text())
			quit(1)
			return true
		_row = result.object_id if _row == 0 else 0
		var made := SiteRoutes.searches - before
		print("EDIT %d ms=%.1f searches=%d" % [i, ms, made])
		total += ms
		searches += made
	print(
		(
			"TOTAL edits=%d mean_ms=%.1f mean_searches=%.1f"
			% [EDITS, total / EDITS, float(searches) / EDITS]
		)
	)
	quit(0)
	return true
