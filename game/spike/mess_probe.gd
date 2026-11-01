extends SceneTree
## Headless probe of the mess sim (MessSim) on the real main scene.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/mess_probe.gd
##
## Boots main.tscn with a new random world seed (printed) and builds the
## reference terminal on the shell's doors with an airside cafe and a landside
## toilet room beside it (CafeTestLayout's floor, its landside cafe swapped for
## a toilet room with two stalls and a sink). It hires one member per station,
## waits for the airport to open, sends in extra hungry passengers and passengers
## who need the toilet, and runs the sim until real visits have left messes of
## both kinds. It prints the mess count it grew to, the use counters of the
## sources that made them and each mess. It saves the world through SaveGame,
## loads it back and prints the mess part before and after. Last it holds two
## passengers standing for BEATS beats, one on a mess and a control out of sight
## of any, and prints both moods. The pass values are positives: messes
## that grew from 0, counters above 0, a mood gap. With no visit, no litter or
## no toilet mess, a
## near passenger whose loss does not match the mess dirt cadence, a control that
## sees a mess or loses mood, or a refused save it prints
## PROBE_INVALID and exits 1.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN := "res://main/main.tscn"
const TICKS_PER_FRAME := 200
const RUN_LIMIT := 30000
const EXTRA_GUESTS := 24
const BEATS := 30

var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _frames := 0
var _phase := 0
var _limit := 0
var _failed := false


func _initialize() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	match _phase:
		0:
			_build()
		1:
			_run()
		2:
			_save_and_load()
			_measure_mood()
			_phase = 3
		3:
			print("PROBE done tick=%d failed=%s" % [_clock.tick, _failed])
			_main.free()
			quit(1 if _failed else 0)
			return true
	return false


func _build() -> void:
	_clock.set_process(false)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	_sim = _main.get_node("PassengerSim") as PassengerSim
	var grid := mode.grid
	var ids := CafeTestLayout.build(grid, false)
	for id: int in [ids["land_table"], ids["land_counter"]]:
		_apply(grid, BuildEdit.remove_object(id))
	_apply(grid, BuildEdit.remove_room(ids["land_room"]))
	var toilet := _apply(grid, BuildEdit.place_room(ToiletTestLayout.LANDSIDE_ROOM, &"toilet"))
	for x in [ToiletTestLayout.STALL_X, ToiletTestLayout.STALL_X + 1]:
		_apply(grid, BuildEdit.place_object(&"toilet_stall", Vector2i(x, 10), 0))
	_apply(grid, BuildEdit.place_object(&"toilet_sink", Vector2i(ToiletTestLayout.SINK_X, 10), 0))
	(mode.get_node("BuildView") as BuildView).refresh(grid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	# The cafe counter serves only with a server on duty.
	hired += int(staff.hire(StaffMember.Role.SHOP) != 0)
	var flights := _main.get_node("FlightSim") as FlightSim
	var doors := StarterFlight.advance_until_open(_clock, flights, staff)
	_sim.cafes.refresh()
	_sim.toilets.refresh()
	print(
		(
			(
				"PROBE built cafe_room=%d toilet_room=%d usable_cafes=%d stalls=%d hired=%d"
				+ " opened_tick=%d doors_close_tick=%d messes=%d"
			)
			% [
				ids["air_room"],
				toilet.room_id,
				_sim.cafes.layout.cafes.size(),
				_sim.toilets.layout.stalls.size(),
				hired,
				_clock.tick,
				doors,
				_sim.messes.mess_count()
			]
		)
	)
	if hired == 0 or doors < 0 or _sim.cafes.layout.cafes.is_empty():
		_invalid("the cafe, the staff or the opening is missing")
		_phase = 3
		return
	for i in EXTRA_GUESTS:
		var p := _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		p.hunger = 59 if i % 2 == 0 else 45
		p.toilet_need = 85 if i % 3 != 2 else 30
	_limit = _clock.tick + RUN_LIMIT
	_clock.set_paused(false)
	_phase = 1


## Steps until messes of both kinds exist, or RUN_LIMIT.
func _run() -> void:
	for i in TICKS_PER_FRAME:
		_clock.advance(SimClock.STEP)
	var kinds := _kinds()
	if (kinds.has(MessSim.Kind.LITTER) and kinds.has(MessSim.Kind.TOILET)) or _clock.tick >= _limit:
		_report_messes(kinds)
		_phase = 2


func _kinds() -> Dictionary:
	var kinds := {}
	for id in _sim.messes.mess_ids():
		var kind: int = _sim.messes.get_mess(id)["kind"]
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	return kinds


func _report_messes(kinds: Dictionary) -> void:
	var messes := _sim.messes
	var uses := {}
	for source in messes.sources():
		uses[source] = messes.uses_of(source)
	print(
		(
			"PROBE ran tick=%d messes=%d litter=%d toilet=%d spill=%d caught=%d overflow=%d"
			% [
				_clock.tick,
				messes.mess_count(),
				kinds.get(MessSim.Kind.LITTER, 0),
				kinds.get(MessSim.Kind.TOILET, 0),
				kinds.get(MessSim.Kind.SPILL, 0),
				messes.caught,
				messes.overflow
			]
		)
	)
	print("PROBE uses=%s" % uses)
	for id in messes.mess_ids():
		var mess := messes.get_mess(id)
		print(
			(
				"PROBE mess id=%d kind=%s cell=%s approach=%s born_tick=%d grown=%s"
				% [
					id,
					MessSim.Kind.keys()[mess["kind"]],
					mess["cell"],
					mess["approach"],
					mess["born_tick"],
					mess["grown"]
				]
			)
		)
	if uses.is_empty():
		_invalid("no real visit was counted")
	if kinds.get(MessSim.Kind.LITTER, 0) <= 0 or kinds.get(MessSim.Kind.TOILET, 0) <= 0:
		_invalid("real visits did not leave both litter and a toilet mess by tick %d" % _clock.tick)
	if messes.mess_count() == 0:
		_invalid("no mess appeared by tick %d" % _clock.tick)


## A passenger held standing on the first mess's cell and a control held on a
## cell no mess is seen from, both at mood 50, over BEATS beats.
func _measure_mood() -> void:
	if _failed:
		return
	var messes := _sim.messes
	var mess := messes.get_mess(messes.mess_ids()[0])
	var near_cell: Vector2i = mess["approach"]
	var control_cell := _clear_cell()
	var near := _held(near_cell)
	var control := _held(control_cell)
	var dirt := messes.dirt_at(near_cell)
	# The loss the mess cadence predicts: on each of the near passenger's beats,
	# DecorEffect.due() of the capped dirt it sees then.
	var expected := 0
	var control_dirt := 0
	var beats := 0
	while beats < BEATS:
		for p in [near, control]:
			ToiletTestLayout.calm(p)
			p.late = false
		_clock.advance(SimClock.STEP)
		control_dirt = maxi(control_dirt, messes.dirt_at(control_cell))
		if posmod(_clock.tick, PassengerSim.BEAT_TICKS) == posmod(near.id, PassengerSim.BEAT_TICKS):
			beats += 1
			var seen := mini(messes.dirt_at(near_cell), MessSim.MAX_DIRT)
			@warning_ignore("integer_division")
			expected += DecorEffect.due(seen, _clock.tick / PassengerSim.BEAT_TICKS)
	var near_calm := _sim.decor.net_calm_at(near_cell)
	var control_calm := _sim.decor.net_calm_at(control_cell)
	var loss := 50 - near.mood
	print(
		(
			(
				"PROBE mood near cell=%s dirt=%d calm=%d stage=%s mood=%d loss=%d expected_loss=%d"
				+ " | control cell=%s max_dirt=%d calm=%d stage=%s mood=%d | beats=%d"
			)
			% [
				near_cell,
				dirt,
				near_calm,
				Passenger.Stage.keys()[near.stage],
				near.mood,
				loss,
				expected,
				control_cell,
				control_dirt,
				control_calm,
				Passenger.Stage.keys()[control.stage],
				control.mood,
				BEATS
			]
		)
	)
	if near_calm != 0 or control_calm != 0 or control_dirt != 0:
		_invalid("decor reaches a held passenger, or a mess is seen from the control")
	if dirt <= 0 or loss <= 0 or loss != expected or control.mood != 50:
		_invalid("the mood loss on the mess does not match its dirt, or the control lost mood")


## A walkable cell in the terminal that no mess is seen from and no decor or
## bin reaches.
func _clear_cell() -> Vector2i:
	var grid := _sim.grid
	for y in range(ReferenceTerminal.FLOOR_MAX.y, ReferenceTerminal.FLOOR_MIN.y - 1, -1):
		for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
			var cell := Vector2i(x, y)
			if not grid.is_walkable(cell) or _sim.messes.dirt_at(cell) != 0:
				continue
			if _sim.decor.net_calm_at(cell) == 0:
				return cell
	return ReferenceTerminal.ENTRANCE_CELL


## A passenger of a flight still open, held standing on `cell` at mood 50.
func _held(cell: Vector2i) -> Passenger:
	var flights := _main.get_node("FlightSim") as FlightSim
	var open := ""
	for id in flights.flight_ids():
		if not flights.is_doors_closed(id) and flights.doors_close_tick(id) > _clock.tick + 2000:
			open = id
			break
	if open == "":
		_invalid("no flight is open long enough to hold a passenger")
		open = StarterFlight.first_flight()
	var p := _sim.get_passenger(_sim.spawn_now(open))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _clock.tick
	p.boarding_tick = 1 << 40
	p.at = cell
	p.clear_path()
	p.mood = 50
	return p


func _save_and_load() -> void:
	if _failed:
		return
	var save := _main.get_node("SaveGame") as SaveGame
	var before := JSON.stringify(_sim.messes.to_snapshot(), "", true)
	var data := save.snapshot()
	var saved: Dictionary = data.get("messes", {})
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var loaded := save.load_world(json)
	var after := JSON.stringify(_sim.messes.to_snapshot(), "", true)
	print(
		(
			"PROBE save version=%s saved_messes=%d loaded=%s messes_after=%d same=%s message='%s'"
			% [
				data.get("save_version", -1),
				(saved.get("messes", []) as Array).size(),
				loaded,
				_sim.messes.mess_count(),
				before == after,
				save.message_text()
			]
		)
	)
	if data.is_empty() or not loaded or before != after:
		_invalid("the messes did not survive a save and load")


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	if not result.ok:
		_invalid("build edit refused: %s" % result.reason_text())
	return result


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true
