extends SceneTree
## Windowed plates of the calm station signs (decision calm-cozy-default-view-
## quiet-world-detail-on-ask-soft-statio, part 2; calm-view-technical-design-
## shared-hover-target-reusing-click, parts 2-4): the real main scene with the
## reference terminal and its gate, staff hired, one scanner closed by the
## player and a crowd that fills the check-in queues.
## 01 home zoom, 02 close zoom, 03 far zoom, 04 home zoom at UI scale 1.5: the
## queue-full and Closed signs, no captions. 05: a queue-full sign hovered, with
## its tooltip. 06: build mode with a wall gap opened in the outer wall, its
## build-hint sign hovered, with its tooltip.
## Boots main with a new random sim seed (printed). Before each plate it proves
## each subject sign: shown, projected inside the frame by MARGIN_PX, drawn
## SIGN_PX tall on screen (from its pixel size), and not under a HUD control
## (HudRects; the signs draw over the world, so the HUD is what can hide them).
## The hover plates also prove the hover target is that sign and the tooltip
## shows its words beside it. It prints what it compared; otherwise it prints
## PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 400 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/calm_signs_plates_probe.gd
##
## The plates go to tools/blender/out/calm_signs_20261114/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/calm_signs_20261114"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const CROWD := 40
const CROWD_LEAD_TICKS := 240

var _failed := false
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _markers: MissMarkers
var _gaps: GapMarkers
var _hover: HoverTarget
var _rig: TycoonCamera
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	var out := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	if await _boot():
		await _plates(out)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed, " window=", root.size)
	root.add_child(_main)
	_sim = _main.get_node("PassengerSim")
	_markers = _main.get_node("PassengerViews/MissMarkers")
	_gaps = _main.get_node("GapMarkers")
	_hover = _main.get_node("HoverTarget")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	await _frames(5)
	var hud := _main.get_node("PassengerHud") as PassengerHud
	hud.press_starter_terminal()
	# The starter terminal may come with its gate desk already; a refusal then
	# only means the exit is taken. Opening the airport below is the real check.
	print("PROBE gate desk added=%s" % StarterFlight.add_gate_desk(_sim.grid))
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print("PROBE hired=%d opened tick=%d doors=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		return false
	var scanner: int = _sim.layout.scanners[0]
	if not staff.closures.set_closed(scanner, true):
		_invalid("scanner %d could not be closed" % scanner)
		return false
	var crowd_at := doors - CROWD_LEAD_TICKS
	StarterFlight.advance_until(_clock, func() -> bool: return _clock.tick >= crowd_at, doors)
	for i in CROWD:
		_sim.spawn_now(StarterFlight.first_flight())
	var full := func() -> bool: return MissSignals.full_stations(_sim).size() >= 2
	StarterFlight.advance_until(_clock, full, doors - 20)
	_clock.set_paused(true)
	await _frames(5)
	print(
		(
			"PROBE paused tick=%d full=%s closed=%s"
			% [_clock.tick, MissSignals.full_stations(_sim), MissSignals.closed_stations(_sim)]
		)
	)
	return true


func _plates(out: String) -> void:
	var full: Array = MissSignals.full_stations(_sim).keys()
	var scanner: int = _sim.layout.scanners[0]
	if full.is_empty():
		_invalid("no full queue to plate")
		return
	var subjects: Array[Node3D] = [_markers.sign_for(full[0]), _markers.closed_sign_for(scanner)]
	var middle := (subjects[0].global_position + subjects[1].global_position) / 2.0
	await _aim(middle, 45.0)
	await _plate(out, "01_home_zoom", subjects)
	await _aim(subjects[0].global_position, 14.0)
	await _plate(out, "02_close_zoom", [subjects[0]])
	await _aim(middle, 150.0)
	await _plate(out, "03_far_zoom", subjects)
	await _aim(middle, 45.0)
	var scale := root.content_scale_factor
	root.content_scale_factor = 1.5
	await _frames(4)
	await _plate(out, "04_home_zoom_ui_scale_1_5", subjects)
	root.content_scale_factor = scale
	await _aim(subjects[0].global_position, 22.0)
	await _hover_plate(out, "05_hovered_queue_sign", _markers, "queue:%d" % full[0])
	await _build_plate(out)


## Glides the camera to look at `point` from `distance` metres and waits it out.
func _aim(point: Vector3, distance: float) -> void:
	_rig.glide_to(Vector3(point.x, 0.0, point.z), distance)
	for i in 240:
		if not _rig.is_gliding():
			break
		await process_frame
	await _frames(6)


func _plate(out: String, name: String, subjects: Array[Node3D]) -> void:
	for sign in subjects:
		_check_sign(sign, name)
	await _save(out.path_join(name + ".png"))


## The sign is shown, inside the frame by MARGIN_PX, SIGN_PX tall on screen and
## clear of the HUD.
func _check_sign(sign: Node3D, what: String) -> void:
	var sprite := sign as Sprite3D
	if sprite == null or not sprite.is_visible_in_tree():
		_invalid("%s: a subject sign is not shown" % what)
		return
	var view := root.get_visible_rect()
	var to_output := root.get_stretch_transform().get_scale().y
	var foot := _cam.unproject_position(sprite.global_position)
	var unit := 2.0 * tan(deg_to_rad(_cam.fov) / 2.0) / (view.size.y * to_output)
	var px := sprite.pixel_size * MarkerIcons.SIZE / unit
	var side := px / to_output
	var rect := Rect2(foot.x - side / 2.0, foot.y - side, side, side)
	var hud := HudRects.collect(_main, to_output)
	var under := hud.filter(
		func(r: Rect2) -> bool:
			return r.intersects(Rect2(rect.position * to_output, rect.size * to_output))
	)
	print(
		(
			"SIGN %s %s glyph=%d rect=%s frame=%s on_screen_px=%.1f behind=%s under_hud=%d"
			% [
				what,
				sprite.name,
				MissMarkers.glyph_of(sprite),
				rect,
				view.grow(-MARGIN_PX),
				px,
				_cam.is_position_behind(sprite.global_position),
				under.size()
			]
		)
	)
	if _cam.is_position_behind(sprite.global_position) or not view.grow(-MARGIN_PX).encloses(rect):
		_invalid("%s: %s is not inside the frame" % [what, sprite.name])
	if absf(px - MissMarkers.SIGN_PX) > 0.5:
		_invalid("%s: %s is %.1f px, not %.0f" % [what, sprite.name, px, MissMarkers.SIGN_PX])
	if not under.is_empty():
		_invalid("%s: %s is under the HUD at %s" % [what, sprite.name, under])


func _hover_plate(out: String, name: String, provider: Object, key: Variant) -> void:
	var entry := {}
	for e: Dictionary in provider.hover_signs():
		if e["key"] == key:
			entry = e
	if entry.is_empty():
		_invalid("%s: the provider reports no sign %s" % [name, key])
		return
	var rect: Rect2 = entry["rect"]
	_hover.pointer_override = rect.get_center()
	await _frames(4)
	var target := _hover.hovered_target()
	var tip := _hover.tooltip()
	var tip_rect := tip.get_global_rect()
	print(
		(
			"HOVER %s key=%s rect=%s target=%s tip_visible=%s tip=%s text='%s'"
			% [
				name,
				key,
				rect,
				target.key if target != null else null,
				tip.visible,
				tip_rect,
				tip.text()
			]
		)
	)
	if target == null or target.provider != provider or target.key != key:
		_invalid("%s: the hovered target is not sign %s" % [name, key])
	if not tip.visible or tip.text() != entry["text"]:
		_invalid("%s: the tooltip does not show '%s'" % [name, entry["text"]])
	if tip_rect.intersects(rect):
		_invalid("%s: the tooltip covers its sign" % name)
	if not root.get_visible_rect().encloses(tip_rect):
		_invalid("%s: the tooltip leaves the view" % name)
	await _save(out.path_join(name + ".png"))
	_hover.pointer_override = null
	await _frames(2)


## Build mode with one outer wall removed, so a wall-gap sign shows.
func _build_plate(out: String) -> void:
	var session := MissMarkers.find_session(self)
	session.set_building(true)
	var grid := _sim.grid
	var opened := false
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if opened or not grid.is_indoor(cell) or not grid.has_wall(cell, BuildGrid.Side.SOUTH):
				continue
			if grid.object_at(cell) != 0:
				continue
			var result := grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.SOUTH))
			opened = result.ok and _gaps.sign_count() > 0
			if result.ok and not opened:
				grid.apply(BuildEdit.place_wall(cell, BuildGrid.Side.SOUTH))
	await _frames(4)
	print("BUILD building=%s gap_signs=%d" % [session.active, _gaps.sign_count()])
	if not opened:
		_invalid("no outer wall could be opened for a wall gap")
		return
	var gap: Sprite3D = _gaps.signs()[0]
	await _aim(gap.global_position, 30.0)
	_check_sign(gap, "06_build_mode_wall_gap")
	await _hover_plate(out, "06_build_mode_wall_gap_hovered", _gaps, 0)
	session.set_building(false)


func _save(path: String) -> void:
	var img := await PlateSight.grab(self)
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())
