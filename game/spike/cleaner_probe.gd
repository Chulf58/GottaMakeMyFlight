extends SceneTree
## Headless probe of the cleaners (StaffSim, CleanerJobs) on the real main
## scene.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/cleaner_probe.gd
##
## Boots main.tscn with a new random world seed (printed) and builds the mess
## probe's terminal (mess_probe.gd: the reference terminal with an airside cafe
## and a landside toilet room), hires one member per station and a shop server,
## opens the airport, sends in hungry passengers and passengers who need the
## toilet, and runs until real visits have left at least MIN_MESSES messes. It
## saves the world through SaveGame there. The control run plays RUN_TICKS on
## with no cleaner; the world is loaded back from the save and the cleaner run
## hires CLEANERS cleaners and plays the same RUN_TICKS. Partway through the
## cleaner run, with a cleaner at work, the world is saved and loaded again.
## It prints the mess count before and after each run, how many of the messes
## from the save each run left, and the claims seen (cleaner -> jobs). The pass
## values are positives: messes that grew from 0, claims seen, original messes
## the cleaners cleared, and every original mess still there in the control.
## With no mess, no claim, a shared job, a cleaner run that cleared nothing,
## a control that lost a mess or a refused save it prints PROBE_INVALID and
## exits 1.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN := "res://main/main.tscn"
const TICKS_PER_FRAME := 200
const RUN_LIMIT := 30000
const EXTRA_GUESTS := 24
const MIN_MESSES := 3
const RUN_TICKS := 2400
const CLEANERS := 2

var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _staff: StaffSim
var _save: SaveGame
var _frames := 0
var _phase := 0
var _limit := 0
var _failed := false
## The save taken once enough messes exist, through JSON.
var _saved: Variant
var _originals: Array[int] = []


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
			_grow_messes()
		2:
			_control()
			_cleaners()
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
	_staff = _main.get_node("Staff") as StaffSim
	_save = _main.get_node("SaveGame") as SaveGame
	var grid := mode.grid
	var ids := CafeTestLayout.build(grid, false, mode.shell)
	for id: int in [ids["land_table"], ids["land_counter"]]:
		_apply(grid, BuildEdit.remove_object(id))
	_apply(grid, BuildEdit.remove_room(ids["land_room"]))
	_apply(grid, BuildEdit.place_room(ToiletTestLayout.LANDSIDE_ROOM, &"toilet"))
	for x in [ToiletTestLayout.STALL_X, ToiletTestLayout.STALL_X + 1]:
		_apply(grid, BuildEdit.place_object(&"toilet_stall", Vector2i(x, 10), 0))
	_apply(grid, BuildEdit.place_object(&"toilet_sink", Vector2i(ToiletTestLayout.SINK_X, 10), 0))
	(mode.get_node("BuildView") as BuildView).refresh(grid)
	var hired := StarterFlight.hire_per_station(_sim, _staff)
	hired += int(_staff.hire(StaffMember.Role.SHOP) != 0)
	var flights := _main.get_node("FlightSim") as FlightSim
	var doors := StarterFlight.advance_until_open(_clock, flights, _staff)
	_sim.cafes.refresh()
	_sim.toilets.refresh()
	print(
		(
			"PROBE built hired=%d opened_tick=%d doors_close_tick=%d messes=%d cleaners=%d"
			% [
				hired,
				_clock.tick,
				doors,
				_sim.messes.mess_count(),
				_staff.count(StaffMember.Role.CLEANER)
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


## Steps until MIN_MESSES messes exist, or RUN_LIMIT; then saves.
func _grow_messes() -> void:
	for i in TICKS_PER_FRAME:
		_clock.advance(SimClock.STEP)
	if _sim.messes.mess_count() < MIN_MESSES and _clock.tick < _limit:
		return
	_phase = 2
	_originals = _sim.messes.mess_ids()
	print(
		(
			"PROBE grew tick=%d messes=%d uses=%d caught=%d ids=%s"
			% [
				_clock.tick,
				_sim.messes.mess_count(),
				_sim.messes.sources().size(),
				_sim.messes.caught,
				_originals
			]
		)
	)
	if _sim.messes.mess_count() == 0:
		_invalid("no mess appeared by tick %d" % _clock.tick)
		_phase = 3
		return
	var data := _save.snapshot()
	if data.is_empty():
		_invalid("the save was refused: %s" % _save.message_text())
		_phase = 3
		return
	_saved = JSON.parse_string(JSON.stringify(data))


## RUN_TICKS with no cleaner: every mess from the save should still be there.
func _control() -> void:
	if _failed:
		return
	var before := _sim.messes.mess_count()
	var start := _clock.tick
	while _clock.tick < start + RUN_TICKS:
		_clock.advance(SimClock.STEP)
	var left := _left()
	print(
		(
			"PROBE control tick=%d cleaners=%d messes before=%d after=%d originals_left=%d/%d"
			% [
				_clock.tick,
				_staff.count(StaffMember.Role.CLEANER),
				before,
				_sim.messes.mess_count(),
				left,
				_originals.size()
			]
		)
	)
	if left != _originals.size():
		_invalid("a mess went with no cleaner hired")


## Loads the save back, hires CLEANERS cleaners and plays RUN_TICKS, saving and
## loading once with a cleaner at work.
func _cleaners() -> void:
	if _failed:
		return
	if not _save.load_world(_saved):
		_invalid("the save did not load back: %s" % _save.message_text())
		return
	_clock.set_paused(false)
	var before := _sim.messes.mess_count()
	var start := _clock.tick
	for i in CLEANERS:
		_staff.hire(StaffMember.Role.CLEANER)
	var claims := {}
	var shared := 0
	var reloaded := false
	while _clock.tick < start + RUN_TICKS:
		_clock.advance(SimClock.STEP)
		var jobs := {}
		for id in _staff.member_ids():
			var m := _staff.get_member(id)
			if m.role != StaffMember.Role.CLEANER or m.job == 0:
				continue
			var key := "%s%d" % ["bin" if m.job_bin else "mess", m.job]
			shared += int(jobs.has(key))
			jobs[key] = true
			if not claims.has(id):
				claims[id] = {}
			claims[id][key] = true
			if not reloaded and m.state == StaffMember.State.ON_DUTY:
				reloaded = _reload(m)
	var seen := {}
	for id: int in claims:
		seen[id] = (claims[id] as Dictionary).keys()
	var left := _left()
	print(
		(
			(
				"PROBE cleaners tick=%d hired=%d messes before=%d after=%d originals_left=%d/%d"
				+ " claims=%s shared=%d reloaded_mid_clean=%s"
			)
			% [
				_clock.tick,
				_staff.count(StaffMember.Role.CLEANER),
				before,
				_sim.messes.mess_count(),
				left,
				_originals.size(),
				seen,
				shared,
				reloaded
			]
		)
	)
	if claims.is_empty():
		_invalid("no cleaner claimed a job")
	if shared != 0:
		_invalid("two cleaners held one job")
	if left >= _originals.size():
		_invalid("the cleaners cleared none of the messes from the save")
	if not reloaded:
		_invalid("no save was taken with a cleaner at work")


## Saves and loads the world while `m` is at work; whether it went through
## and the cleaner is back at work on the same job.
func _reload(m: StaffMember) -> bool:
	var job := m.job
	var left := m.work_left
	var data := _save.snapshot()
	var ok := not data.is_empty() and _save.load_world(JSON.parse_string(JSON.stringify(data)))
	_clock.set_paused(false)
	var back := _staff.get_member(m.id)
	var same := back != null and back.job == job and back.work_left == left
	print(
		(
			"PROBE reload tick=%d cleaner=%d job=%d work_left=%d loaded=%s same=%s message='%s'"
			% [_clock.tick, m.id, job, left, ok, same, _save.message_text()]
		)
	)
	if not ok or not same:
		_invalid("a save with a cleaner at work did not load back the same")
	return ok and same


## How many of the messes from the save are still there.
func _left() -> int:
	var left := 0
	for id in _originals:
		left += int(not _sim.messes.get_mess(id).is_empty())
	return left


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	if not result.ok:
		_invalid("build edit refused: %s" % result.reason_text())
	return result


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true
