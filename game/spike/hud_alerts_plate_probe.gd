extends SceneTree
## Windowed plates of the alert card stack (HUD 1/7, AlertStack). Boots the real
## main scene with a new random sim seed (printed) and its starter shell off,
## builds ReferenceTerminal through the HUD's starter-terminal button, removes
## the east check-in desk so the one desk left overflows, hires staff, lets the
## airport open and sends a crowd in, then:
##   01_two_alerts: the check-in queue fills (AlertSources, held past its
##      three-minute wait) and DirtyAlert.SHOW_AT spills go down, so two cards
##      stack under the top row
##   02_after_click: a left click pushed at the queue card's middle; the camera
##      glides until its focus is on the full desk, which must then project
##      inside the view
##   03_dirty_cleared: every mess cleaned, the dirty card gone, the queue card
##      still up
##   04_history_tray: a click on the Alerts button opens the tray, which lists
##      both cards, the dirty one cleared and the queue one still up
## Each check prints the values it compared. A failed check prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/hud_alerts_plate_probe.gd
##
## Plates go to tools/blender/out/hud-alerts/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/hud-alerts"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const CROWD := 14
const CROWD_LEAD_TICKS := 600
## Real time the camera gets to glide to a clicked card's place (frames run
## far faster than 60 a second here, so a frame count is no clock).
const GLIDE_LIMIT_MS := 6000
## The focus must end this close to the card's target.
const ARRIVE_M := 0.5

var _out_dir := ""
var _failed := false
var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _hud: PassengerHud
var _stack: AlertStack
var _rig: TycoonCamera
var _desk := 0
var _doors_tick := -1


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	if not _failed:
		await _two_alerts()
	if not _failed:
		await _click_jumps()
	if not _failed:
		await _dirty_cleared()
	if not _failed:
		await _history_tray()
	_main.queue_free()
	await _frames(3)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_sim = _main.get_node("PassengerSim")
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	await _frames(5)
	_hud.press_starter_terminal()
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	var desks: Array = ReferenceTerminal.object_ids(_sim.grid)["desks"]
	if desks.size() != 2:
		_invalid("starter terminal has %d desks, expected 2" % desks.size())
		return
	var removed := _sim.grid.apply(BuildEdit.remove_object(desks[1]))
	if not removed.ok:
		_invalid("could not remove the east desk: %s" % removed.reason_text())
		return
	(_main.get_node("BuildMode/BuildView") as BuildView).refresh(_sim.grid)
	_desk = desks[0]
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	_doors_tick = StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print(
		"PROBE desk=%d hired=%d opened tick=%d doors=%d" % [_desk, hired, _clock.tick, _doors_tick]
	)
	if hired == 0 or _doors_tick < 0:
		_invalid("the staff were not hired and the airport did not open")
		return
	var crowd_at := _doors_tick - CROWD_LEAD_TICKS
	StarterFlight.advance_until(_clock, func() -> bool: return _clock.tick >= crowd_at, _doors_tick)
	for i in CROWD:
		_sim.spawn_now(StarterFlight.first_flight())
	_clock.set_paused(true)
	await _frames(3)
	_hud.refresh()
	print("PROBE crowd tick=%d spawned=%d cards=%s" % [_clock.tick, CROWD, _stack.card_keys()])
	# The control: nothing is wrong yet, so no card is up.
	if not _stack.card_keys().is_empty():
		_invalid("cards up before the queue filled: %s" % [_stack.card_keys()])


func _two_alerts() -> void:
	# Step tick by tick with the HUD read each tick, as frames would.
	var queue_up := func() -> bool:
		_hud.refresh()
		return _stack.card_keys().has(AlertSources.QUEUE_CHECKIN)
	if not StarterFlight.advance_until(_clock, queue_up, _doors_tick - 50 - _clock.tick):
		_invalid("no check-in queue card by tick %d" % _clock.tick)
		return
	var full_since := int(_stack.board().alert(AlertSources.QUEUE_CHECKIN)["raised_tick"])
	var cells := _indoor_cells(DirtyAlert.SHOW_AT)
	if cells.size() < DirtyAlert.SHOW_AT:
		_invalid("only %d spaced indoor cells" % cells.size())
		return
	for cell in cells:
		if _sim.messes.add(MessSim.Kind.SPILL, cell) == 0:
			_invalid("a spill at %s was refused" % cell)
			return
	_hud.refresh()
	await _frames(4)
	print(
		(
			"TWO tick=%d full=%s raised=%d dirt=%d cards=%s"
			% [
				_clock.tick,
				MissSignals.full_stations(_sim),
				full_since,
				_sim.messes.total_dirt(),
				_stack.card_keys()
			]
		)
	)
	var want: Array[StringName] = [AlertSources.QUEUE_CHECKIN, DirtyAlert.KEY]
	if _stack.card_keys() != want:
		_invalid("expected cards %s, got %s" % [want, _stack.card_keys()])
		return
	var queue_rect := _card_in_frame(AlertSources.QUEUE_CHECKIN, "01_two_alerts")
	var dirty_rect := _card_in_frame(DirtyAlert.KEY, "01_two_alerts")
	if _failed:
		return
	print("STACK queue=%s dirty=%s" % [queue_rect, dirty_rect])
	if queue_rect.intersects(dirty_rect) or dirty_rect.position.y <= queue_rect.position.y:
		_invalid("the two cards do not stack")
		return
	await _save_plate("01_two_alerts")


func _click_jumps() -> void:
	var target: Vector3 = (_stack.board().alert(AlertSources.QUEUE_CHECKIN)["targets"] as Array)[0]
	var before := _rig.position
	var desk_point := AlertSources.object_point(_sim.grid, _desk)
	print(
		(
			"CLICK target=%s desk=%s focus_before=%s away=%.2f"
			% [target, desk_point, before, before.distance_to(target)]
		)
	)
	if target.distance_to(desk_point) > 0.01:
		_invalid("the queue card does not point at the full desk")
		return
	if before.distance_to(target) < 2.0:
		_invalid("the camera already looks at the desk; the click would prove nothing")
		return
	var jumps: Array[Vector3] = []
	_stack.jumped.connect(func(at: Vector3) -> void: jumps.append(at))
	_click(_stack.card_node(AlertSources.QUEUE_CHECKIN).get_global_rect().get_center())
	var started := Time.get_ticks_msec()
	await _frames(2)
	while _rig.is_gliding() and Time.get_ticks_msec() - started < GLIDE_LIMIT_MS:
		await process_frame
	await _frames(4)
	print("GLIDE gliding=%s ms=%d" % [_rig.is_gliding(), Time.get_ticks_msec() - started])
	var after := _rig.position
	var eye := _rig.get_node("Camera3D") as Camera3D
	var on_screen := eye.unproject_position(target + Vector3(0.0, 1.0, 0.0))
	var view := root.get_visible_rect()
	var inside := view.grow(-MARGIN_PX).has_point(on_screen)
	# The camera makes room for the drawn cards: the desk lands below them.
	var cards := _stack.room_rect()
	var clear := on_screen.y > cards.end.y + MARGIN_PX
	var line := "JUMPED jumps=%d focus_after=%s off=%.3f dist=%.1f screen=%s"
	line += " view=%s inside=%s cards=%s clear=%s"
	print(
		(
			line
			% [
				jumps.size(),
				after,
				after.distance_to(target),
				_rig.distance,
				on_screen,
				view,
				inside,
				cards,
				clear,
			]
		)
	)
	if jumps.size() != 1 or after.distance_to(target) > ARRIVE_M or not inside or not clear:
		_invalid("the click did not bring the full desk into view")
		return
	_occlusion(eye, target + Vector3(0.0, 1.0, 0.0))
	await _save_plate("02_after_click")


func _dirty_cleared() -> void:
	for id in _sim.messes.mess_ids():
		_sim.messes.clean(id)
	_hud.refresh()
	await _frames(4)
	print("CLEARED dirt=%d cards=%s" % [_sim.messes.total_dirt(), _stack.card_keys()])
	var keys := _stack.card_keys()
	var alone := keys.size() == 1 and keys[0] == AlertSources.QUEUE_CHECKIN
	if not alone or _stack.card_node(DirtyAlert.KEY) != null:
		_invalid("the dirty card did not clear alone")
		return
	_card_in_frame(AlertSources.QUEUE_CHECKIN, "03_dirty_cleared")
	if not _failed:
		await _save_plate("03_dirty_cleared")


func _history_tray() -> void:
	var button := _stack.find_child("AlertHistoryButton", true, false) as Button
	_click(button.get_global_rect().get_center())
	await _frames(4)
	var tray := _stack.find_child("AlertHistory", true, false) as Control
	var lines := _stack.history_lines()
	var rect := tray.get_global_rect()
	var view := root.get_visible_rect()
	print(
		(
			"TRAY open=%s rect=%s inside=%s lines=%s"
			% [tray.is_visible_in_tree(), rect, view.grow(-MARGIN_PX).encloses(rect), lines]
		)
	)
	if not tray.is_visible_in_tree() or not view.grow(-MARGIN_PX).encloses(rect):
		_invalid("the history tray is not open in frame")
		return
	if lines.size() != 2:
		_invalid("expected 2 history lines")
		return
	var dirty_cleared := lines[0].contains(DirtyAlert.TITLE) and lines[0].contains("cleared")
	var queue_up := lines[1].contains("Check-in queue full") and lines[1].contains("still up")
	if not (dirty_cleared and queue_up):
		_invalid("the history lines do not say what happened")
		return
	await _save_plate("04_history_tray")


## The card's rect, checked inside the viewport and drawn; prints it.
func _card_in_frame(key: StringName, plate: String) -> Rect2:
	var card := _stack.card_node(key)
	if card == null:
		_invalid("%s: no card %s" % [plate, key])
		return Rect2()
	var rect := card.get_global_rect()
	var view := root.get_visible_rect()
	var inside := view.grow(-MARGIN_PX).encloses(rect)
	print(
		(
			"IN_FRAME %s %s rect=%s view=%s drawn=%s inside=%s"
			% [plate, key, rect, view, card.is_visible_in_tree(), inside]
		)
	)
	if not inside or not card.is_visible_in_tree() or rect.size.x < 100.0:
		_invalid("%s: card %s is not in frame" % [plate, key])
	return rect


## A left press and release at `at` (canvas pixels), through the GUI.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event, true)


## A ray from the eye to `point`: a first hit well before it means something
## stands in front of the desk.
func _occlusion(eye: Camera3D, point: Vector3) -> void:
	var space := eye.get_world_3d().direct_space_state
	var from := eye.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, point))
	var short := 0.0
	if not hit.is_empty():
		short = (hit["position"] as Vector3).distance_to(point)
	print("OCCLUSION from=%s to=%s hit=%s short=%.2f" % [from, point, not hit.is_empty(), short])
	if short > 1.5:
		_invalid("something stands between the camera and the desk")


func _save_plate(name: String) -> void:
	var img: Image = await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## `count` indoor walkable object-free cells, three apart so no two spills
## merge, nearest the first entrance door first.
func _indoor_cells(count: int) -> Array[Vector2i]:
	var grid := _sim.grid
	var door := _sim.layout.door_cell(grid, _sim.layout.entrances[0])
	var found: Array[Vector2i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if grid.is_indoor(c) and grid.is_walkable(c) and grid.object_at(c) == 0:
				found.append(c)
	found.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return absi(a.x - door.x) + absi(a.y - door.y) < absi(b.x - door.x) + absi(b.y - door.y)
	)
	var picked: Array[Vector2i] = []
	for c in found:
		var apart := true
		for p in picked:
			apart = apart and maxi(absi(p.x - c.x), absi(p.y - c.y)) >= 3
		if apart:
			picked.append(c)
		if picked.size() == count:
			break
	return picked
