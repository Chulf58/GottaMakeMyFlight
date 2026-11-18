extends SceneTree
## Windowed 1280x720 plate of Gotta Air's opening phone call (board D3e,
## decisions opening-phone-call-right-after-the-airport-opens-the-airline,
## day-clock-stops-until-the-airport-opens-the-opening-call-pau and
## the-airline-s-opening-phone-call-shows-a-new-gotta-air-stati).
##
## Boots the real main.tscn with a random world seed, turns UnlockGuide on,
## fills the starter terminal and hires a check-in agent and security officer,
## then runs the clock until AirportGate opens the airport. Asserts the clock
## paused synchronously on the exact opening tick, the Gotta Air station
## manager portrait and GOTTA AIR nameplate are shown, the 4 draft lines with
## the starter flight's departure time fit without scrolling inside the 1280x720
## window, and Space closes the call and resumes the clock.
##
## Windowed, from the repo root (hold the one windowed slot):
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy -s res://spike/opening_call_plate_probe.gd
## Plates go to tools/blender/out/gotta-air-portrait/. PROBE_INVALID and exit 1
## on any failed check.

const MAIN := "res://main/main.tscn"
const OUT_DIR := "res://../tools/blender/out/gotta-air-portrait"
const SCREEN := Vector2i(1280, 720)
const MARGIN := 8.0
const MAX_OPEN_FRAMES := 600
const SETTLE_FRAMES := 15
const AFTER_FRAMES := 20


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_size(SCREEN)
	await _frames(10)
	if root.size != SCREEN:
		_invalid("the window is %s, not %s" % [root.size, SCREEN])
		return
	var main: Node3D = (load(MAIN) as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	var hud := main.get_node("PassengerHud") as PassengerHud
	hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	root.add_child(main)
	await _frames(4)
	hud.press_starter_terminal()
	var staff := main.get_node("Staff") as StaffSim
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	var flights := main.get_node("FlightSim") as FlightSim
	var guide := hud.unlock_guide()
	clock.set_speed(3)
	clock.set_paused(false)
	for _i in MAX_OPEN_FRAMES:
		if flights.opened_tick >= 0:
			break
		await process_frame
	if flights.opened_tick < 0:
		_invalid("the airport never opened within %d frames" % MAX_OPEN_FRAMES)
		return
	await _verify_and_capture(main, guide, flights, clock)


func _verify_and_capture(
	main: Node, guide: UnlockGuide, flights: FlightSim, clock: SimClock
) -> void:
	var opened_tick := flights.opened_tick
	print(
		(
			"PROBE at_open opened_tick=%d clock_tick=%d paused=%s guide_open=%s"
			% [opened_tick, clock.tick, clock.paused, guide.is_open()]
		)
	)
	if not guide.is_open() or not clock.paused or clock.tick != opened_tick:
		_invalid("the opening call did not pause the clock synchronously on the opening tick")
		return
	await _frames(SETTLE_FRAMES)
	if clock.tick != opened_tick or not clock.paused:
		_invalid("ticks ran while the opening call was open (%d -> %d)" % [opened_tick, clock.tick])
		return
	var problem := _dialog_problem(main, guide, flights, clock)
	if problem != "":
		_invalid(problem)
		return
	if not _save_open_plates(guide):
		return
	_press_space()
	await _frames(AFTER_FRAMES)
	print(
		(
			"PROBE after guide_open=%s paused=%s tick=%d (opened %d)"
			% [guide.is_open(), clock.paused, clock.tick, opened_tick]
		)
	)
	if guide.is_open() or clock.paused or clock.tick <= opened_tick:
		_invalid("Space did not close the opening call and resume the clock")
		return
	if not _save(root.get_texture().get_image(), "opening_call_after_720p.png"):
		_invalid("opening_call_after_720p.png did not save")
		return
	print("PROBE done")
	quit(0)


func _save_open_plates(guide: UnlockGuide) -> bool:
	var image := root.get_texture().get_image()
	var rects := guide.dialog().part_rects()
	var crop: Rect2 = (
		(rects["box"] as Rect2).merge(rects["portrait"]).merge(rects["nameplate"]).grow(12.0)
	)
	var factor := Vector2(image.get_size()) / root.get_visible_rect().size
	var crop_px := Rect2(crop.position * factor, crop.size * factor).intersection(
		Rect2(Vector2.ZERO, Vector2(image.get_size()))
	)
	print("PROBE crop layout=%s factor=%s pixels=%s" % [crop, factor, crop_px])
	if not _save(image, "opening_call_720p.png"):
		_invalid("opening_call_720p.png did not save")
		return false
	if not _save(image.get_region(Rect2i(crop_px)), "opening_call_crop.png"):
		_invalid("opening_call_crop.png did not save")
		return false
	return true


func _dialog_problem(main: Node, guide: UnlockGuide, flights: FlightSim, clock: SimClock) -> String:
	var dlg := guide.dialog()
	var portrait := dlg.find_child("Portrait", true, false) as TextureRect
	var speaker_label := dlg.find_child("Name", true, false) as Label
	var role_label := dlg.find_child("Title", true, false) as Label
	var dep_tick := flights.state_start(UnlockGuide.STARTER_OCCURRENCE, FlightSim.State.PUSHBACK)
	var dep_text := GameCalendar.clock_text(dep_tick, clock.epoch)
	print(
		(
			"PROBE speaker=%d name='%s' role='%s' departure='%s' scrolls=%s"
			% [dlg.speaker(), speaker_label.text, role_label.text, dep_text, dlg.scrolls()]
		)
	)
	if dlg.speaker() != IntroDialogue.Speaker.GOTTA_AIR:
		return "expected GOTTA_AIR speaker"
	if portrait.texture != IntroDialogue.GOTTA_AIR_PORTRAIT:
		return "expected station_manager_portrait.png"
	if speaker_label.text != "GOTTA AIR" or role_label.text != "Station manager":
		return "unexpected nameplate '%s' / '%s'" % [speaker_label.text, role_label.text]
	if dlg.scrolls():
		return "the opening call body scrolled instead of fitting the box"
	if not dlg.body_text().contains(dep_text):
		return "the opening call body is missing departure time '%s'" % dep_text
	return _layout_problem(main, dlg)


func _layout_problem(main: Node, dlg: IntroDialogue) -> String:
	var layout_size := root.get_visible_rect().size
	var screen := Rect2(Vector2.ONE * MARGIN, layout_size - Vector2.ONE * 2.0 * MARGIN)
	var rects := dlg.part_rects()
	for part in rects:
		var rect: Rect2 = rects[part]
		print("PROBE in_frame %s rect=%s inside=%s" % [part, rect, screen.encloses(rect)])
		if not rect.has_area() or not screen.encloses(rect):
			return "%s is outside the 1280x720 layout margin" % part
	var menu := main.get_node("BuildMenu") as BuildMenu
	var bar_top := menu.bar().get_global_rect().position.y
	if (rects["box"] as Rect2).end.y > bar_top:
		return "the dialog box covers the build bar"
	var own := dlg.get_parent() as CanvasLayer
	var top_other := -1000
	for node in root.find_children("*", "CanvasLayer", true, false):
		if node != own:
			top_other = maxi(top_other, (node as CanvasLayer).layer)
	if not dlg.is_visible_in_tree() or own == null or top_other >= own.layer:
		return "the opening call is hidden or occluded by another CanvasLayer"
	return ""


func _press_space() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		Input.parse_input_event(event)


func _save(image: Image, file: String) -> bool:
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(file))
	var err := image.save_png(path)
	print("PROBE plate %s err=%d size=%s" % [path, err, image.get_size()])
	return err == OK


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	quit(1)
