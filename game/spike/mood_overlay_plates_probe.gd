extends SceneTree
## Windowed plates for the queue and mood floor overlay (HUD 5/7). Boots the
## real main scene with a new random sim seed (printed), builds the starter
## terminal, removes its east check-in desk so one desk serves a crowd, hires
## staff, lets the airport open and sends a crowd in, then pauses the clock
## once a queue has both a fresh place (green) and a long wait (red).
## Plates:
##   01 the queue with the overlay off (the shipped default)
##   02 the same view after the M key turned it on
## Each fails with PROBE_INVALID and exit 1 when a tinted cell leaves the
## frame, when the overlay did not turn on through the real key, or when the
## tint is not measured on screen (plate 02 against plate 01 over the tinted
## patch, with the tree paused so only the overlay differs).
##
## Windowed, hold tools/blender/out/.windowed.lock for the whole run:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy -s res://spike/mood_overlay_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/hud-floor-overlay"
const CROWD := 14
const CROWD_LEAD_TICKS := 600
const DISTANCE := 16.0
const MARGIN_PX := 24.0
## Plate pixels that must differ over the tinted patch for the tint to count.
const MIN_CHANGED_PX := 400
const WAIT_LIMIT_MS := 120000

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _hud: PassengerHud
var _overlay: MoodOverlay
var _doors_tick := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	if await _boot():
		await _plates()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	_overlay = _main.get_node("MoodOverlay") as MoodOverlay
	_overlay.settings_path = "user://mood_overlay_plates_probe.cfg"
	DirAccess.remove_absolute(_overlay.settings_path)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_hud = _main.get_node("PassengerHud")
	await _frames(5)
	_hud.press_starter_terminal()
	var desks: Array = ReferenceTerminal.object_ids(_sim.grid)["desks"]
	if desks.size() != 2:
		_invalid("starter terminal has %d desks, expected 2" % desks.size())
		return false
	var removed := _sim.grid.apply(BuildEdit.remove_object(desks[1]))
	if not removed.ok:
		_invalid("could not remove the east desk: %s" % removed.reason_text())
		return false
	(_main.get_node("BuildMode/BuildView") as BuildView).refresh(_sim.grid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	_doors_tick = StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print("PROBE hired=%d opened tick=%d doors_close_tick=%d" % [hired, _clock.tick, _doors_tick])
	if hired == 0 or _doors_tick < 0:
		_invalid("the staff were not hired and the airport did not open")
		return false
	var crowd_at := _doors_tick - CROWD_LEAD_TICKS
	StarterFlight.advance_until(_clock, func() -> bool: return _clock.tick >= crowd_at, _doors_tick)
	for i in CROWD:
		_sim.spawn_now(StarterFlight.first_flight())
	print("PROBE crowd tick=%d spawned=%d doors=%d" % [_clock.tick, CROWD, _doors_tick])
	_hud.press_speed(3)
	return true


func _spread() -> Array[float]:
	var values: Array[float] = []
	for value: float in MoodTint.cells_for(_sim).values():
		values.append(value)
	return values


func _queue_shows_both_ends() -> bool:
	var values := _spread()
	return not values.is_empty() and values.max() >= 0.7 and values.min() <= 0.05


func _plates() -> void:
	var started := Time.get_ticks_msec()
	while not _queue_shows_both_ends():
		if Time.get_ticks_msec() - started > WAIT_LIMIT_MS or _clock.tick > _doors_tick:
			_invalid("no queue with a green and a red end by tick %d" % _clock.tick)
			return
		await process_frame
	_hud.press_speed(0)
	await _frames(5)
	var cells := MoodTint.cells_for(_sim)
	print("PROBE paused tick=%d cells=%d badness=%s" % [_clock.tick, cells.size(), _spread()])
	if _overlay.is_shown():
		_invalid("the overlay starts on; the default is off")
		return
	var centre := Vector3.ZERO
	for cell: Vector2i in cells:
		centre += _sim.grid.cell_to_world(cell)
	centre /= cells.size()
	_rig.stop_follow()
	_rig.position = Vector3(centre.x, 0.0, centre.z)
	_rig.yaw = 0.0
	_rig.distance = DISTANCE
	await _frames(20)
	var rect := _screen_rect(cells)
	if not _framed(cells, rect):
		return
	paused = true
	var off_plate := await PlateSight.grab(self)
	paused = false
	_save(off_plate, "01_overlay_off")
	_press_m()
	await _frames(10)
	if not _overlay.is_shown():
		_invalid("the M key did not turn the overlay on")
		return
	var shown := _overlay.tinted_cells()
	print("PROBE overlay on cells=%d (probe read %d)" % [shown.size(), cells.size()])
	if shown.size() != cells.size():
		_invalid(
			"the overlay tints %d cells, the sim reading gives %d" % [shown.size(), cells.size()]
		)
		return
	paused = true
	var on_plate := await PlateSight.grab(self)
	paused = false
	var per_screen := root.get_visible_rect().size.y / float(on_plate.get_height())
	var patch := PlateSight.to_screen(rect, per_screen, on_plate.get_size())
	var changed := PlateSight.differing(on_plate, off_plate, patch, 1)
	print("PROBE tint patch=%s plate=%s changed_px=%d" % [patch, on_plate.get_size(), changed])
	if changed < MIN_CHANGED_PX:
		_invalid("only %d plate pixels changed over the tinted patch" % changed)
		return
	_save(on_plate, "02_overlay_on")


## The screen bounds, in layout pixels, of the tinted cells' corners.
func _screen_rect(cells: Dictionary) -> Rect2:
	var rect := Rect2()
	var first := true
	for cell: Vector2i in cells:
		var base := _sim.grid.cell_to_world(cell) + Vector3(0.0, MoodOverlay.LIFT_M, 0.0)
		for corner in [
			Vector3(-0.5, 0, -0.5),
			Vector3(0.5, 0, -0.5),
			Vector3(-0.5, 0, 0.5),
			Vector3(0.5, 0, 0.5)
		]:
			var at := _cam.unproject_position(base + corner)
			rect = Rect2(at, Vector2.ZERO) if first else rect.expand(at)
			first = false
	return rect


func _framed(cells: Dictionary, rect: Rect2) -> bool:
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var behind := false
	for cell: Vector2i in cells:
		behind = behind or _cam.is_position_behind(_sim.grid.cell_to_world(cell))
	print("INFRAME tint rect=%s frame=%s behind=%s" % [rect, frame, behind])
	if behind or not frame.encloses(rect) or rect.size.x < 40.0 or rect.size.y < 40.0:
		_invalid("the tinted patch is behind the camera, off the frame or too small to judge")
		return false
	return true


func _press_m() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_M
		event.physical_keycode = KEY_M
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
