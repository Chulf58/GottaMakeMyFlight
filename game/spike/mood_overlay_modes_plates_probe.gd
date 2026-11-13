extends SceneTree
## Windowed plates for the mood overlay's Mood, Hunger, Toilet and Boredom
## modes (board: crowd need display). Boots the real main scene with a new
## random sim seed (printed), builds the starter terminal, lets the airport open
## and sends a crowd in, then pauses the clock on a busy terminal. The sim's
## own needs have barely risen by then, so the probe spreads hunger, toilet need
## and boredom over the passengers (printed), to show every colour band; the sim
## is paused, so nothing changes them back. The same camera frames:
##   01 Mood mode (no need icons)
##   02 Hunger mode   03 Toilet mode   04 Boredom mode (that need's icons)
## each through the real legend buttons. Each fails with PROBE_INVALID and exit 1
## when the tinted patch leaves the frame or sits under a HUD panel, when a mode
## button did not switch the mode, or when a plate's tint did not change on
## screen against the Mood plate.
##
## Windowed, hold tools/blender/out/.windowed.lock for the whole run:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/mood_overlay_modes_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/overlay-modes"
const CROWD := 14
const CROWD_LEAD_TICKS := 600
const DISTANCE := 14.0
## Cells at or past 0.9 badness the paused queue must show, beside a green one.
const RED_CELLS := 1
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
	_overlay.settings_path = "user://mood_overlay_modes_plates_probe.cfg"
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
	var reds := values.filter(func(value: float) -> bool: return value >= 0.9)
	return not values.is_empty() and reds.size() >= RED_CELLS and values.min() <= 0.05


func _plates() -> void:
	var started := Time.get_ticks_msec()
	while not _queue_shows_both_ends():
		if Time.get_ticks_msec() - started > WAIT_LIMIT_MS or _clock.tick > _doors_tick:
			_invalid("no queue with a green and a red end by tick %d" % _clock.tick)
			return
		await process_frame
	_hud.press_speed(0)
	await _frames(5)
	_spread_needs()
	var cells := MoodTint.cells_for(_sim)
	var centre := Vector3.ZERO
	for cell: Vector2i in cells:
		centre += _sim.grid.cell_to_world(cell)
	centre /= cells.size()
	_rig.stop_follow()
	_rig.position = Vector3(centre.x, 0.0, centre.z)
	_rig.yaw = 0.0
	_rig.distance = DISTANCE
	await _frames(20)
	_overlay.set_shown(true)
	await _frames(10)
	var rect := _screen_rect(cells)
	if not _framed(cells, rect) or not _clear_of_hud(rect):
		return
	var mood_plate: Image
	for mode in MoodTint.Mode.values():
		var button := _overlay.find_child("Mode" + MoodOverlay.MODE_NAMES[mode], true, false)
		(button as Button).button_pressed = true
		await _frames(10)
		if _overlay.mode() != mode:
			_invalid("the %s button did not switch the mode" % MoodOverlay.MODE_NAMES[mode])
			return
		var shown := _overlay.tinted_cells()
		var warm := shown.values().filter(func(v: float) -> bool: return v >= 0.5).size()
		var red := shown.values().filter(func(v: float) -> bool: return v >= 0.9).size()
		print(
			(
				"PROBE mode=%s tinted_cells=%d orange_or_red=%d red=%d icons_visible=%d"
				% [MoodOverlay.MODE_NAMES[mode], shown.size(), warm, red, _icons_visible()]
			)
		)
		paused = true
		var plate := await PlateSight.grab(self)
		paused = false
		if mode == MoodTint.Mode.MOOD:
			mood_plate = plate
		else:
			var per_screen := root.get_visible_rect().size.y / float(plate.get_height())
			var patch := PlateSight.to_screen(rect, per_screen, plate.get_size())
			var changed := PlateSight.differing(plate, mood_plate, patch, 1)
			print("PROBE vs mood plate: changed_px=%d" % changed)
			if changed < MIN_CHANGED_PX:
				_invalid(
					(
						"%s mode changed only %d px over the patch"
						% [MoodOverlay.MODE_NAMES[mode], changed]
					)
				)
		_save(plate, "%02d_%s" % [mode + 1, MoodOverlay.MODE_NAMES[mode].to_lower()])


## Gives each passenger on the floor its own hunger, toilet need and boredom,
## spread over green, orange and red for its mode, and prints the lot.
func _spread_needs() -> void:
	var i := 0
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.hunger = (i * 37) % 101
		p.toilet_need = (i * 53 + 20) % 101
		p.boredom = (i * 29 + 60) % 101
		print(
			(
				"PROBE need id=%d hunger=%d toilet=%d boredom=%d"
				% [id, p.hunger, p.toilet_need, p.boredom]
			)
		)
		i += 1


func _icons_visible() -> int:
	var views := _main.get_node("PassengerViews") as PassengerViews
	var count := 0
	for id in _sim.passenger_ids():
		var node := views.node_for(id)
		if node == null:
			continue
		for sprite_name in NeedIcons.SPRITES:
			if (node.get_node(sprite_name) as Sprite3D).visible:
				count += 1
	return count


## The patch must not sit under the legend card or the toggle (a ray test sees
## only meshes, so the HUD is tested by its rects).
func _clear_of_hud(rect: Rect2) -> bool:
	for control_name in ["MoodOverlayControls", "MoodLegendCard"]:
		var control := _overlay.find_child(control_name, true, false) as Control
		var hud_rect := control.get_global_rect()
		print("INFRAME hud %s=%s patch=%s" % [control_name, hud_rect, rect])
		if hud_rect.intersects(rect):
			_invalid("the tinted patch is under %s" % control_name)
			return false
	return true


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
