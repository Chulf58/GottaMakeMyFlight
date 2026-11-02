extends SceneTree
## Plates of passengers waiting at their own gate (Gates 4/4, user ruling
## 342df92a: they sit on the gate seats closest to their flight's gate desk, and
## with no seats near it they stand there and lose calm). One windowed run
## (take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/gates4_plates_probe.gd
## Boots main.tscn with a new random world seed (printed) and no starter shell
## (anti-pattern a-main-tscn-probe-that-builds-its-own-terminal-at-raw-cells),
## buys the land and builds one wide terminal at the site offset: an entrance
## and security at the west end, gate A's exit and desk with four seat rows
## beside them, and gate B's exit and desk 44 cells east with ONE seat row (3
## seats). Staff is hired, the airport opens, a second contract takes gate B.
## Before either flight boards, 5 passengers of B's flight and 2 of A's are put
## through security into the airside next to gate A (so A's seats are the
## nearest to their entry) and left to choose. The probe prints what they chose:
## B's 3 seats are taken by B passengers, the other 2 B passengers stand near
## B's desk, A's seats stay free, and a standing passenger's mood falls while a
## seated one's rises. Three plates go to tools/blender/out/gates-4/: B's
## seats and standing passengers, A's seated passengers, and the whole terminal.
## Each person in a plate must pass PlateSight.person_shown (nine sight lines
## against every visible mesh, in frame, HUD-free); otherwise PROBE_INVALID,
## exit 1. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/gates-4"
const TICKS_PER_FRAME := 40
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 40
const MIN_SUBJECT_PX := 40.0
## Scene nodes whose visible meshes can hide a person.
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews"
]
const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(65, 17)
const DIVIDER_Y := 9
const ENTRANCE_CELL := Vector2i(18, 17)
const EXIT_A := Vector2i(20, 2)
const EXIT_B := Vector2i(64, 2)
const DESK_A := Vector2i(19, 5)
const DESK_B := Vector2i(63, 5)
const SCANNER_XS: Array[int] = [17, 19]
const ROWS_A: Array[Vector2i] = [Vector2i(11, 3), Vector2i(14, 3), Vector2i(11, 6), Vector2i(14, 6)]
const ROW_B := Vector2i(60, 6)
## Where the passengers come through security: airside, beside gate A.
const ARRIVE: Array[Vector2i] = [
	Vector2i(12, 8),
	Vector2i(13, 8),
	Vector2i(14, 8),
	Vector2i(15, 8),
	Vector2i(16, 8),
	Vector2i(12, 7),
	Vector2i(13, 7),
]
const SECOND := "GMF202"
const B_PASSENGERS := 5
const A_PASSENGERS := 2
const SETTLE_LIMIT_TICKS := 1500
const MOOD_BEATS := 20

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _staff: StaffSim
var _grid: BuildGrid
var _mode: BuildMode
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _sim: PassengerSim
var _views: PassengerViews
var _offset := Vector2i.ZERO
var _row_ids: Dictionary = {}
var _b_people: Array[Passenger] = []
var _a_people: Array[Passenger] = []


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_staff = _main.get_node("Staff")
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode")
	_grid = _mode.grid
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _sim.get_parent().get_node("PassengerViews")
	(_mode.get_node("Ghost") as Node3D).visible = false
	_hud.dismiss_intro()
	_clock.set_paused(true)
	_offset = ReferenceTerminal.offset_on(_grid)
	if not _build_terminal():
		return
	await _frames(3)
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	if not await _open_with_two_flights(first):
		return
	var day: int = _flights.start_days[SECOND]
	var second := FlightTimetable.occurrence_id(SECOND, day)
	var boarding_a := _flights.boarding_window(first).x
	var boarding_b := _flights.boarding_window(second).x
	print(
		(
			"PROBE %s (gate %s) boards at %d, %s (gate %s) at %d, now %d"
			% [
				first,
				_flights.flight_gate(first),
				boarding_a,
				second,
				_flights.flight_gate(second),
				boarding_b,
				_clock.tick
			]
		)
	)
	var waits := SETTLE_LIMIT_TICKS + MOOD_BEATS * PassengerSim.BEAT_TICKS
	if (
		_flights.flight_gate(first) != "A"
		or _flights.flight_gate(second) != "B"
		or _clock.tick + waits > mini(boarding_a, boarding_b)
	):
		_fail("the flights are not at A and B with time to wait before boarding")
		return
	_spawn_people(first, second)
	if not await _settle() or not _verify():
		return
	await _check_mood()
	if _done:
		return
	await _plates()
	if not _done:
		print("PROBE_PASS plates and choices")
		_finish(0)


## Hires, lets the airport open on the starter flight `first`, and takes the
## second contract, whose first flight is issued by the time this returns.
func _open_with_two_flights(first: String) -> bool:
	print("PROBE gates %s" % [(_main.get_node("GateDesks") as GateDesks).bindings])
	var two_gates: Array[String] = ["A", "B"]
	if _flights.gate_ids() != two_gates:
		_fail("the two gate desks did not make gates A and B: %s" % [_flights.gate_ids()])
		return false
	StarterFlight.hire_per_station(_sim, _staff)
	var done := func() -> bool: return _flights.flight_ids().has(first)
	_stage = "opening"
	if not StarterFlight.advance_until(_clock, done, StarterFlight.OPEN_LIMIT_TICKS):
		_fail("the airport did not open with the starter flight issued")
		return false
	if not _accept_second():
		return false
	var second := FlightTimetable.occurrence_id(SECOND, _flights.start_days[SECOND])
	_stage = "second flight"
	while not _flights.flight_ids().has(second):
		await _ticks(TICKS_PER_FRAME)
	await _frames(2)
	return true


## One wide terminal at the site offset, bought and built through the grid.
func _build_terminal() -> bool:
	var edits := _terminal_edits()
	var land := _mode.land_tool.land
	var wanted := {}
	for edit in edits:
		wanted[land.plot_of(edit.cell)] = true
	for plot: Vector2i in wanted:
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			if best == Vector2i(-1, -1) or not land.buy(best, null).ok:
				_fail("the land toward plot %s could not be bought" % plot)
				return false
	for edit in edits:
		var result := _grid.apply(edit)
		if not result.ok:
			_fail("edit at %s refused: %s" % [edit.cell, result.reason_text()])
			return false
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == &"seat_row":
			_row_ids[edit.cell - _offset] = result.object_id
	return true


func _terminal_edits() -> Array[BuildEdit]:
	var out: Array[BuildEdit] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			out.append(BuildEdit.paint_floor(Vector2i(x, y) + _offset, BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
		if x != EXIT_A.x and x != EXIT_B.x:
			out.append(
				BuildEdit.place_wall(Vector2i(x, FLOOR_MIN.y) + _offset, BuildGrid.Side.NORTH)
			)
		if x != ENTRANCE_CELL.x:
			out.append(
				BuildEdit.place_wall(Vector2i(x, FLOOR_MAX.y) + _offset, BuildGrid.Side.SOUTH)
			)
		if not SCANNER_XS.has(x):
			out.append(BuildEdit.place_wall(Vector2i(x, DIVIDER_Y) + _offset, BuildGrid.Side.NORTH))
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MIN.x, y) + _offset, BuildGrid.Side.WEST))
		out.append(BuildEdit.place_wall(Vector2i(FLOOR_MAX.x, y) + _offset, BuildGrid.Side.EAST))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11) + _offset, 0))
	out.append(BuildEdit.place_object(&"checkin_desk", Vector2i(14, 11) + _offset, 0))
	for x in SCANNER_XS:
		out.append(
			BuildEdit.place_object(&"security_scanner", Vector2i(x, DIVIDER_Y - 1) + _offset, 0)
		)
	for anchor in ROWS_A:
		out.append(BuildEdit.place_object(&"seat_row", anchor + _offset, 0))
	out.append(BuildEdit.place_object(&"seat_row", ROW_B + _offset, 0))
	out.append(BuildEdit.place_object(&"entrance_door", ENTRANCE_CELL + _offset, 2))
	out.append(BuildEdit.place_object(&"exit_door", EXIT_A + _offset, 0))
	out.append(BuildEdit.place_object(&"exit_door", EXIT_B + _offset, 0))
	out.append(BuildEdit.place_object(GateDesks.DESK, DESK_A + _offset, 0))
	out.append(BuildEdit.place_object(GateDesks.DESK, DESK_B + _offset, 0))
	return out


## Accepts a contract departing the fewest minutes after the starter that
## clears the shared runway and lane; it gets gate B, A being busy then.
func _accept_second() -> bool:
	var minute: int = _flights.contract_of(FlightSim.DEFAULT_ID)["departure_minute"]
	for later in range(40, 90):
		var terms := FlightSim.starter_terms(0)
		terms["id"] = SECOND
		terms["departure_minute"] = (minute + later) % GameCalendar.MINUTES_PER_DAY
		if _flights.accept_gate(terms) == "B":
			_flights.accept_contract(terms)
			print("PROBE second contract %d minutes after the starter, at gate B" % later)
			return true
	_fail("no departure after the starter's got gate B")
	return false


## Passengers that have been through security, next to gate A, bound for the
## gate: 5 of B's flight, then 2 of A's.
func _spawn_people(first: String, second: String) -> void:
	_stage = "spawn"
	var n := 0
	for flight in [second, first]:
		var count := B_PASSENGERS if flight == second else A_PASSENGERS
		for i in count:
			var p := _sim.get_passenger(_sim.spawn_now(flight))
			p.carry_on = 0
			p.liquids = false
			p.alarm = false
			p.cleared = true
			p.stage = Passenger.Stage.TO_GATE
			p.stage_tick = _clock.tick + 1
			p.at = ARRIVE[n] + _offset
			p.clear_path()
			p.apron = []
			p.apron_mm = 0
			p.mood = 60
			n += 1
			(_b_people if flight == second else _a_people).append(p)


## Steps until every spawned passenger sits or stands, or the limit passes.
func _settle() -> bool:
	_stage = "settle"
	var until := _clock.tick + SETTLE_LIMIT_TICKS
	var all: Array[Passenger] = _b_people + _a_people
	while _clock.tick < until:
		var waiting := 0
		for p in all:
			if p.stage != Passenger.Stage.SEATED and p.stage != Passenger.Stage.STANDING:
				waiting += 1
		if waiting == 0:
			await _ticks(5)
			return true
		await _ticks(TICKS_PER_FRAME)
	_fail("the passengers did not all sit or stand in %d ticks" % SETTLE_LIMIT_TICKS)
	return false


func _desk_cells(desk: Vector2i) -> Array[Vector2i]:
	return BuildCatalog.get_def(GateDesks.DESK).footprint(desk + _offset, 0)


func _cells_from(cell: Vector2i, anchors: Array[Vector2i]) -> int:
	return GateReach.cells_from(cell, anchors)


## What the passengers chose, printed with the values compared.
func _verify() -> bool:
	var desk_b := _desk_cells(DESK_B)
	var row_b: int = _row_ids[ROW_B]
	var rows_a: Array[int] = []
	for anchor in ROWS_A:
		rows_a.append(_row_ids[anchor])
	var entry := ARRIVE[0] + _offset
	var nearest_a := 1 << 30
	var nearest_b := 1 << 30
	for seat in _sim.layout.seats:
		var d := maxi(absi(seat["cell"].x - entry.x), absi(seat["cell"].y - entry.y))
		if seat["object_id"] == row_b:
			nearest_b = mini(nearest_b, d)
		else:
			nearest_a = mini(nearest_a, d)
	print(
		(
			"PROBE entry %s: nearest A seat %d cells away, nearest B seat %d"
			% [entry, nearest_a, nearest_b]
		)
	)
	var seated_b := 0
	var standing_b := 0
	var ok := nearest_a < nearest_b
	for p in _b_people:
		if p.stage == Passenger.Stage.SEATED:
			seated_b += 1
			ok = ok and p.seat_object == row_b
			print(
				(
					"PROBE B passenger %d seated on object %d (B's row %d)"
					% [p.id, p.seat_object, row_b]
				)
			)
		else:
			standing_b += 1
			var spot := _sim.standing.spot_of(p.id)
			var cell := _sim.standing.cell_of(spot)
			var reach := _cells_from(cell, desk_b)
			print(
				(
					"PROBE B passenger %d stands on spot %d at cell %s, %d cells from B's desk"
					% [p.id, spot, cell, reach]
				)
			)
			ok = (
				ok
				and p.seat_object == 0
				and spot != StandingSpots.NO_SPOT
				and reach <= GateReach.NEAR_CELLS
			)
	var free_a := 0
	for seat in _sim.layout.seats:
		if rows_a.has(seat["object_id"]):
			free_a += 1
	for p in _a_people:
		ok = ok and p.stage == Passenger.Stage.SEATED and rows_a.has(p.seat_object)
		free_a -= int(p.seat_object != 0)
		print("PROBE A passenger %d on object %d (A's rows %s)" % [p.id, p.seat_object, rows_a])
	print(
		"PROBE B seated %d, B standing %d, A seats still free %d" % [seated_b, standing_b, free_a]
	)
	ok = ok and seated_b == 3 and standing_b == B_PASSENGERS - 3 and free_a > 0
	if not ok:
		_fail("the passengers did not choose by their gate")
	return ok


## Mood after MOOD_BEATS beats: a seated B passenger gains, a standing one loses.
func _check_mood() -> void:
	_stage = "mood"
	var seated: Passenger = null
	var standing: Passenger = null
	for p in _b_people:
		if p.stage == Passenger.Stage.SEATED and seated == null:
			seated = p
		if p.stage == Passenger.Stage.STANDING and standing == null:
			standing = p
	if seated == null or standing == null:
		_fail("no seated and standing B passenger to compare")
		return
	seated.mood = 60
	standing.mood = 60
	var until := _clock.tick + MOOD_BEATS * PassengerSim.BEAT_TICKS
	while _clock.tick < until:
		await _ticks(mini(TICKS_PER_FRAME, until - _clock.tick))
	print(
		(
			"PROBE mood after %d beats: seated %d, standing %d (both started at 60)"
			% [MOOD_BEATS, seated.mood, standing.mood]
		)
	)
	if not (seated.mood > 60 and standing.mood < 60):
		_fail("seated mood should rise and standing mood fall")


func _plates() -> void:
	var desk_b_world := _grid.cell_to_world(DESK_B + _offset) + Vector3(0.5, 1.0, 0.0)
	var focus_b := _grid.cell_to_world(Vector2i(62, 5) + _offset)
	_view(focus_b, 22.0, 1.45)
	await _plate("a_gate_b_seated_and_standing", _b_people, [desk_b_world])
	if _done:
		return
	var focus_a := _grid.cell_to_world(Vector2i(14, 5) + _offset)
	_view(focus_a, 24.0, 0.7)
	await _plate(
		"b_gate_a_seated",
		_a_people,
		[_grid.cell_to_world(DESK_A + _offset) + Vector3(0.5, 1.0, 0.0)]
	)
	if _done:
		return
	var middle := _grid.cell_to_world(Vector2i(38, 6) + _offset)
	_view(middle, 62.0, 0.0)
	await _plate(
		"c_whole_terminal",
		[],
		[
			_grid.cell_to_world(DESK_A + _offset),
			_grid.cell_to_world(DESK_B + _offset),
			_grid.cell_to_world(ROW_B + _offset),
			_grid.cell_to_world(ROWS_A[0] + _offset)
		]
	)


func _view(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


## Saves a plate once every `people` passes person_shown and every `points`
## projects inside the frame.
func _plate(label: String, people: Array, points: Array) -> void:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	print(
		(
			"PLATE %s rig %s distance %.1f camera %s"
			% [label, _rig.position, _rig.distance, _cam.global_position]
		)
	)
	var frame := _frame_rect()
	var ok := true
	for point: Vector3 in points:
		var px := _cam.unproject_position(point)
		var in_frame := frame.has_point(px) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, px, in_frame])
		ok = ok and in_frame
	# The plate is the world with the HUD layers hidden (PlateSight.hud_twin).
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var img: Image = twin["image"]
	if not people.is_empty():
		ok = (await _people_shown(people, img)) and ok
	if not ok:
		_fail("%s: a subject check failed" % label)
		return
	var path := _out_dir.path_join(label + ".png")
	var err := img.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)
		return
	if not people.is_empty():
		_save_crop(label, img, people)


## The part of the plate around `people`, saved beside it for a closer look.
func _save_crop(label: String, img: Image, people: Array) -> void:
	var box := Rect2(_cam.unproject_position(_sim.world_position(people[0])), Vector2.ZERO)
	for p: Passenger in people:
		var feet := _sim.world_position(p)
		box = box.expand(_cam.unproject_position(feet))
		box = box.expand(_cam.unproject_position(feet + Vector3.UP * 1.9))
	var scale := img.get_size().x / root.get_visible_rect().size.x
	var grown := box.grow(70.0)
	var rect := Rect2i(grown.position * scale, grown.size * scale).intersection(
		Rect2i(Vector2i.ZERO, img.get_size())
	)
	var path := _out_dir.path_join(label + "_crop.png")
	var err := img.get_region(rect).save_png(path)
	print("PLATE saved crop %s rect %s err=%d" % [path, rect, err])
	if err != OK:
		_fail("%s: crop not saved" % label)


func _people_shown(people: Array, img: Image) -> bool:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var subjects := {}
	for p: Passenger in people:
		var node := _views.node_for(p.id)
		if node != null:
			subjects[node] = "p%d" % p.id
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	await physics_frame
	await physics_frame
	var boxes: Dictionary = holder.get_meta("bounds")
	var ok := unbaked.is_empty()
	for p: Passenger in people:
		var tag := "p%d" % p.id
		var seen := PlateSight.person_shown(
			_cam, boxes.get(tag, AABB()), tag, _frame_rect(), img, img, MIN_SUBJECT_PX
		)
		print(
			(
				(
					"VISIBLE passenger=%d stage=%s px=%s height_px=%.0f on=%d past=%d"
					+ " blockers=%s in_frame=%s hud_px=%d ok=%s"
				)
				% [
					p.id,
					Passenger.Stage.keys()[p.stage],
					seen.get("px"),
					seen.get("height_px", 0.0),
					seen["on"],
					seen["past"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					seen["ok"]
				]
			)
		)
		ok = ok and seen["ok"]
	holder.free()
	if not unbaked.is_empty():
		print("PROBE skinned meshes not baked: %s" % [unbaked])
	return ok


func _ticks(count: int) -> void:
	for i in count:
		_clock.set_paused(false)
		_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
	_beat("tick %d" % _clock.tick)
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("gates 4 plates probe hung")


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)
