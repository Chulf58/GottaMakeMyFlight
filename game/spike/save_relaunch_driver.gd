extends Node
## Drives the two-process save, quit and cold relaunch probe (board D2c). It is
## a Node so it runs in both builds: the editor build adds it from
## save_relaunch_probe.gd (an -s SceneTree script), and the Windows export, whose
## release template ignores -s, loads it as an autoload from an override.cfg
## placed beside the exe. Neither build ships it (export_presets.cfg leaves
## spike/ out), and it uses no class from tests/.
##
## --phase=save boots main.tscn from a new random world seed (printed; --seed=N
## replays one), builds the starter terminal, hires an agent and an officer, and
## plays on day 0 until a flight has paid its fees (the wallet moved) while
## passengers are still in the terminal. It then writes the manual save
## (SaveSlots.manual_path()) and, beside it, expected.json with the values it
## saved, and quits.
##
## --phase=load starts cold on the title screen and presses Continue, the real
## boot flow (TitleScreen, GameBoot.load_path, SaveGame's boot load). At the
## load point it prints the saved and loaded wallet, flight count, passenger
## count, tick and state checksum, which must match. It then plays --ticks=N
## ticks (default 2400) and prints how far it got. Last, a control presses New
## Airport (GameBoot.start_new) and prints the fresh world's values, all five of
## which must differ from the loaded ones.
##
## Both phases take --save-dir=<folder> and point SaveSlots.dir at it, so the
## player's user://saves is never read or written; the folder is outside
## user:// and is removed by whoever made it. A Logger counts every error from
## the start; any error fails the run. Pass lines start PROBE_, failures print
## PROBE_INVALID and exit 1. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).
##
## Editor build (save, then a second cold process for load):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/<repo>/game -s res://spike/save_relaunch_probe.gd \
##     -- --phase=load --save-dir=C:/<folder>
## Export (load only): put an override.cfg beside the exe that autoloads this
## file by its absolute path and moves user:// to a folder of the run's own, so
## the HUD settings and hint memory (not shielded without -s) stay off the
## player's files:
##   [application]
##   config/use_custom_user_dir=true
##   config/custom_user_dir_name="GottaMakeMyFlight_d2c_probe"
##   [autoload]
##   SaveRelaunch="*C:/<repo>/game/spike/save_relaunch_driver.gd"
## then run GottaMakeMyFlight.exe <windowed flags> -- --phase=load
## --save-dir=C:/<folder>, and delete the override.cfg and that user folder.

const MAIN := "res://main/main.tscn"
const EXPECTED_FILE := "expected.json"
const DEFAULT_TICKS := 2400
## Ticks stepped per frame, so the windowed game draws as it plays.
const TICKS_PER_FRAME := 10
const OPEN_LIMIT := 6000
const FRAME_LIMIT := 600
const SETTLE_FRAMES := 5
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000


## Counts errors from any thread (Godot calls a Logger for push_error, engine
## errors and GDScript runtime errors).
class ErrorCount:
	extends Logger
	var errors: Array[String] = []
	var warnings := 0
	var _lock := Mutex.new()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors.append(
				"%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
			)
		_lock.unlock()

	func error_list() -> Array[String]:
		_lock.lock()
		var out := errors.duplicate()
		_lock.unlock()
		return out


var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _errors := ErrorCount.new()

var _phase := ""
var _dir := ""
var _ticks := DEFAULT_TICKS
var _seed := -1
var _step := 0
var _frames := 0
var _main: Node
var _main_id := 0
var _loaded_ok := -1
var _expected := {}
var _at_load := {}
var _played := 0
var _made_at_load := 0
var _start_wallet := 0
var _opened_title := false


func _ready() -> void:
	OS.add_logger(_errors)
	_beat("boot")
	_guard.start(_watch)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			_phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--save-dir="):
			_dir = arg.trim_prefix("--save-dir=")
		elif arg.begins_with("--ticks="):
			_ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
	print(
		(
			"PROBE build=%s debug=%s phase=%s save_dir=%s user_dir=%s"
			% [
				"export" if OS.has_feature("template") else "editor",
				OS.is_debug_build(),
				_phase,
				_dir,
				OS.get_user_data_dir()
			]
		)
	)
	if _dir == "" or _dir.begins_with("user://") or not _phase in ["save", "load"]:
		_fail("needs --phase=save|load and --save-dir=<folder outside user://>")
		return
	SaveSlots.dir = _dir
	if _phase == "load":
		get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	_beat("%s step %d frame %d" % [_phase, _step, _frames])
	if _done:
		return
	_frames += 1
	if _frames > FRAME_LIMIT * 20:
		_fail("ran past its frame limit in step %d" % _step)
		return
	if _phase == "save":
		_save_process()
	else:
		_load_process()


## Process 1: a seeded new airport, set as the current scene.
func _boot_new() -> void:
	if _seed < 0:
		_seed = randi()
	print("PROBE world_seed=%d" % _seed)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = load(MAIN).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	clock.seed_rng(_seed)
	clock.set_paused(true)
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main


func _save_process() -> void:
	if _main == null:
		_boot_new()
		return
	match _step:
		0:
			# The scene is ready from the first frame on. The intro and the
			# incidents question hold the clock; IntroClose is loaded, not
			# preloaded, because the export leaves spike/ out.
			var held: String = load("res://spike/intro_close.gd").close(_main)
			if held != "":
				_fail(held)
				return
			_clock(_main).set_paused(true)
			(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
			var staff: StaffSim = _main.get_node("Staff")
			staff.hire(StaffMember.Role.CHECKIN)
			staff.hire(StaffMember.Role.SECURITY)
			staff.hire(StaffMember.Role.GATE)
			_start_wallet = (_main.get_node("Finances") as Finances).wallet.balance
			_step = 1
		1:
			# Until the airport is open with passengers in the terminal.
			for i in TICKS_PER_FRAME:
				_tick(_main)
			var flights: FlightSim = _main.get_node("FlightSim")
			if flights.opened_tick >= 0 and _sim(_main).active_count() > 0:
				_played = 0
				_step = 2
			elif _clock(_main).tick > OPEN_LIMIT:
				_fail("no passengers in the terminal by tick %d" % _clock(_main).tick)
		2:
			for i in TICKS_PER_FRAME:
				_tick(_main)
			_played += TICKS_PER_FRAME
			var wallet := (_main.get_node("Finances") as Finances).wallet.balance
			if wallet != _start_wallet and _sim(_main).active_count() > 0:
				_step = 3
			elif GameCalendar.day_of(_clock(_main).tick, _clock(_main).epoch) > 0:
				_fail("day 0 ended before a paid flight with passengers still in the terminal")
		3:
			_save()


func _save() -> void:
	var save_game: SaveGame = _main.get_node("SaveGame")
	if save_game.save_problem() != "":
		_tick(_main)
		return
	var values := _values(_main)
	var path := SaveSlots.manual_path()
	if not save_game.save_to_file(path):
		_fail("save_to_file(%s) failed: %s" % [path, save_game.message_text()])
		return
	values["seed"] = str(_seed)
	values["day"] = str(GameCalendar.day_of(int(values["tick"]), _clock(_main).epoch))
	var file := FileAccess.open(_dir.path_join(EXPECTED_FILE), FileAccess.WRITE)
	if file == null:
		_fail("cannot write %s" % _dir.path_join(EXPECTED_FILE))
		return
	file.store_string(JSON.stringify(values, "", true))
	file.close()
	print("PROBE saved %s %s" % [path, _line(values)])
	print("PROBE save_day=%d (mid-day: day 0, after the opening)" % int(values["day"]))
	if int(values["passengers"]) <= 0 or int(values["day"]) != 0:
		_fail("the save is not mid-day with passengers in the terminal")
		return
	_finish()


## Process 2: connects to the boot load as main.tscn's SaveGame enters.
func _on_node_added(node: Node) -> void:
	if node is SaveGame and _loaded_ok < 0:
		(node as SaveGame).loaded.connect(_on_loaded)
		print("PROBE SaveGame entered with boot path pending=%s" % (GameBoot.load_path != ""))


## SaveGame emits loaded(false) only on failure; a good load is seen by its tick.
func _on_loaded(ok: bool) -> void:
	_loaded_ok = int(ok)


func _load_process() -> void:
	match _step:
		0:
			var title := get_tree().current_scene as TitleScreen
			if title == null:
				# An -s run has no main scene; the export starts on the title.
				if get_tree().current_scene == null and not _opened_title:
					_opened_title = true
					get_tree().change_scene_to_file(GameBoot.TITLE_SCENE)
				return
			var text := FileAccess.get_file_as_string(_dir.path_join(EXPECTED_FILE))
			_expected = JSON.parse_string(text) if text != "" else {}
			if _expected.is_empty():
				_fail("no %s in %s" % [EXPECTED_FILE, _dir])
				return
			print(
				(
					"PROBE title latest=%s continue_enabled=%s"
					% [SaveSlots.latest(), not title.button("Continue").disabled]
				)
			)
			if SaveSlots.latest() != SaveSlots.manual_path():
				_fail("Continue would not load the probe's save")
				return
			title.press_continue()
			_frames = 0
			_step = 1
		1:
			_wait_for_load()
		2:
			_play_loaded()
		3:
			_check_control()


func _wait_for_load() -> void:
	if _loaded_ok == 0:
		_fail("the boot load was refused: %s" % GameBoot.refusal)
		return
	var scene := get_tree().current_scene
	if scene == null or scene.get_node_or_null("SaveGame") == null:
		if _frames > FRAME_LIMIT:
			_fail("main.tscn never became the current scene")
		return
	if str(_clock(scene).tick) != _expected["tick"]:
		if _frames > FRAME_LIMIT:
			_fail("the clock never reached the saved tick %s" % _expected["tick"])
		return
	_main = scene
	_main_id = scene.get_instance_id()
	_at_load = _values(_main)
	print("PROBE expected %s" % _line(_expected))
	print("PROBE loaded   %s" % _line(_at_load))
	print("PROBE loaded paused=%s speed=%d" % [_clock(_main).paused, _clock(_main).speed])
	for key in ["wallet", "flights", "passengers", "tick", "checksum"]:
		var same: bool = _at_load[key] == str(_expected[key])
		print(
			(
				"PROBE compare %s saved=%s loaded=%s match=%s"
				% [key, _expected[key], _at_load[key], same]
			)
		)
		if not same:
			_fail("%s differs at the load point" % key)
			return
	_made_at_load = _sim(_main).made_count()
	_played = 0
	_step = 2


func _play_loaded() -> void:
	for i in TICKS_PER_FRAME:
		_tick(_main)
	_played += TICKS_PER_FRAME
	if _played < _ticks:
		return
	var now := _values(_main)
	var made := _sim(_main).made_count() - _made_at_load
	print(
		(
			"PROBE played ticks=%d tick %s -> %s made_since_load=%d %s"
			% [_played, _at_load["tick"], now["tick"], made, _line(now)]
		)
	)
	if int(now["tick"]) - int(_at_load["tick"]) < _ticks or made <= 0:
		_fail("the loaded game did not play on")
		return
	_frames = 0
	GameBoot.start_new(get_tree().change_scene_to_file)
	_step = 3


## The control: New Airport after the run, a fresh world from the real flow.
func _check_control() -> void:
	var scene := get_tree().current_scene
	if (
		scene == null
		or scene.get_instance_id() == _main_id
		or scene.get_node_or_null("SaveGame") == null
	):
		if _frames > FRAME_LIMIT:
			_fail("New Airport never booted")
		return
	if _frames < SETTLE_FRAMES:
		return
	_clock(scene).set_paused(true)
	var fresh := _values(scene)
	print("PROBE control_fresh %s" % _line(fresh))
	var differs := 0
	for key in ["wallet", "flights", "passengers", "tick", "checksum"]:
		var diff: bool = fresh[key] != _at_load[key]
		differs += int(diff)
		print(
			(
				"PROBE control %s fresh=%s loaded=%s differs=%s"
				% [key, fresh[key], _at_load[key], diff]
			)
		)
	print("PROBE control fields_differing=%d of 5" % differs)
	if differs < 5 or int(_at_load["passengers"]) <= 0:
		_fail("the loaded state is not distinguishable from a fresh boot")
		return
	_finish()


func _finish() -> void:
	var errors := _errors.error_list()
	print("PROBE errors=%d warnings=%d" % [errors.size(), _errors.warnings])
	for line in errors:
		print("PROBE error: %s" % line)
	if not errors.is_empty():
		_fail("errors were logged during the run")
		return
	print("PROBE_PASS phase=%s" % _phase)
	_end(0)


func _fail(reason: String) -> void:
	if _done:
		return
	print("PROBE_INVALID %s" % reason)
	_end(1)


func _end(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	OS.remove_logger(_errors)
	get_tree().quit(code)


## One tick, the way the game runs one (as SaveTestKit.step does).
func _tick(main: Node) -> void:
	var clock := _clock(main)
	var before := clock.tick
	clock.set_paused(false)
	clock.advance(SimClock.STEP)
	clock.set_paused(true)
	if clock.tick == before:
		_fail("the clock did not tick at %d (holds: %d)" % [before, clock.holds.count()])


## The compared values. The checksum hashes every SaveGame part's snapshot,
## as SaveTestKit.checksum does (that class is in tests/, which the export
## leaves out); each snapshot only reads.
func _values(main: Node) -> Dictionary:
	var data := {}
	for part in (main.get_node("SaveGame") as SaveGame).parts():
		data[part.key] = part.save.call()
	# Strings, so the values read back from expected.json compare exactly.
	return {
		"tick": str(_clock(main).tick),
		"wallet": str((main.get_node("Finances") as Finances).wallet.balance),
		"flights": str((main.get_node("FlightSim") as FlightSim).flight_ids().size()),
		"passengers": str(_sim(main).active_count()),
		"checksum": JSON.stringify(data, "", true, true).sha256_text(),
	}


static func _line(values: Dictionary) -> String:
	return (
		"tick=%s wallet=%s flights=%s passengers=%s checksum=%s"
		% [
			values["tick"],
			values["wallet"],
			values["flights"],
			values["passengers"],
			values["checksum"]
		]
	)


static func _clock(main: Node) -> SimClock:
	return main.get_node("SimClock")


static func _sim(main: Node) -> PassengerSim:
	return main.get_node("PassengerSim")


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
			OS.crash("save relaunch probe hung")
