extends SceneTree
## Windowed probe of the follow hint and the passenger card in the real main.tscn
## (board D3b, decision follow-invitation-and-passenger-card-a-click-a-passenger-
## fir).
##
## Run (one windowed Godot run project-wide; the caller holds the slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <the project's game folder> \
##     -s res://tests/ui/follow_card_plates_probe.gd -- --hints
##
## The --hints switch runs the hints in their isolated mode (an own memory file,
## emptied at start). main.tscn boots with a random sim seed (printed), the starter
## terminal, a check-in agent and a security officer, and the 300-passenger
## debug batch once a flight opens. The clock is stepped by hand and the hints are
## driven by advance() with the real world, so no real seconds are waited. Plates,
## each proving its subject in frame (projected inside the viewport with a margin)
## and its card on screen, else PROBE_INVALID:
##   follow_hint   passengers in the terminal, none selected: the hint card with its
##                 Show me button in the top-left column
##   card          after Show me: the camera follows one passenger and the card shows
##                 their name, trip line and bag line
## Plates go to tools/blender/out/d3b/.

const OUT_REL := "res://../tools/blender/out/d3b"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const TICK_LIMIT := 40000
const TICKS_PER_FRAME := 100
const HINT_STEPS := 4000

var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _hud: PassengerHud
var _inspect: PassengerInspect
var _hints: Hints
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	await _boot()
	if await _populate():
		await _plate_hint()
		await _plate_card()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab(file: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _boot() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_hud = _main.get_node("PassengerHud")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hints = _hud.find_child("Hints", true, false) as Hints
	_cam = _main.get_node("TycoonCamera/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	_hud.dismiss_intro()
	_hud.press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	await _frames(6)
	if _hints.mode() == Hints.Mode.OFF:
		_invalid("hints are off: pass -- --hints")
	_hints.reads_world = false


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


## Steps the clock, spawning the debug batch once a flight is open, until a
## passenger is in the terminal and a few have walked on.
func _populate() -> bool:
	var spawned_at := -1
	while _clock.tick < TICK_LIMIT:
		for i in TICKS_PER_FRAME:
			_tick()
		if _sim.last_batch_seed == 0:
			_hud.press_debug_spawn()
		elif spawned_at < 0 and FollowInvite.candidate(_sim, _views) != 0:
			spawned_at = _clock.tick
			print("BATCH tick=%d seed=%d" % [spawned_at, _sim.last_batch_seed])
		if spawned_at >= 0 and _clock.tick >= spawned_at + 600:
			return true
		await process_frame
	_invalid("no passengers by tick %d" % _clock.tick)
	return false


func _world() -> Dictionary:
	var world := HintRules.read_world(_sim, [])
	world.merge(FollowInvite.read(_sim, _views, null))
	return world


func _in_frame(label: String, point: Vector3) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if _cam.is_position_behind(point):
		_invalid("%s: behind the camera" % label)
		return false
	var s := _cam.unproject_position(point)
	var ok := rect.has_point(s)
	print("INFRAME %s screen=(%.0f, %.0f) ok=%s" % [label, s.x, s.y, ok])
	if not ok:
		_invalid("%s: leaves the viewport" % label)
	return ok


func _card_on_screen(label: String, card: Control) -> bool:
	var rect := card.get_global_rect()
	var inside := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX).encloses(rect)
	print("CARD %s rect=%s visible=%s inside=%s" % [label, rect, card.is_visible_in_tree(), inside])
	if not (card.is_visible_in_tree() and inside):
		_invalid("%s: card hidden or off screen" % label)
		return false
	return true


func _plate_hint() -> void:
	_views.selected_id = 0
	_hints.shown.connect(func(id: StringName) -> void: print("HINT shown %s" % id))
	for i in HINT_STEPS:
		_hints.advance(0.25, _world(), [])
		if _hints.shown_id() == HintRules.FOLLOW_PASSENGER:
			break
	if _hints.shown_id() != HintRules.FOLLOW_PASSENGER:
		_invalid("the follow hint never showed in %d steps" % HINT_STEPS)
		return
	await _frames(12)
	print("HINT text=%s button=%s" % [_hints.body_label().text, _hints.show_me_button().text])
	_card_on_screen("hint card", _hints.card())
	_card_on_screen("show me", _hints.show_me_button())
	var in_view := 0
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done() or not _views.shows(p):
			continue
		var at := _sim.world_position(p)
		if not _cam.is_position_behind(at) and rect.has_point(_cam.unproject_position(at)):
			in_view += 1
	print("INFRAME passengers drawn on screen=%d" % in_view)
	if in_view == 0:
		_invalid("no passenger of the terminal is on screen behind the hint")
	await _grab("follow_hint.png")


func _plate_card() -> void:
	var id := _hints.press_show_me()
	print("SHOW_ME selected=%d following=%s" % [id, _hud.camera.is_following()])
	if id == 0 or _views.selected_id != id:
		_invalid("Show me selected nobody")
		return
	await _frames(90)
	await _frames(60)
	print("CARD name=%s" % _inspect.name_text())
	print("CARD trip=%s" % _inspect.trip_text())
	print("CARD bags=%s" % _inspect.bags_text())
	print("CARD stage=%s" % _inspect.flight_text())
	if _inspect.name_text() == "" or _inspect.name_text().begins_with("Passenger"):
		_invalid("the card has no generated name")
	if _inspect.trip_text() == "" or _inspect.bags_text() == "":
		_invalid("the card lacks a trip or bag line")
	if _hints.is_showing():
		_invalid("the hint is still up after the selection")
	_card_on_screen("passenger card", _inspect)
	_in_frame("followed passenger", _views.follow_anchor.global_position)
	await _grab("follow_card.png")
