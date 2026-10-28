extends SceneTree
## Windowed plate for the station caption declutter: the real main scene with
## the starter terminal built and nobody hired, seen from the start camera (the
## home zoom), so every desk and scanner carries a Closed sign. The terminal's
## two adjacent desks then get a seat row over each staff spot (as an old save
## could leave them), so both carry the mandatory "Closed: staff spot blocked"
## caption and the moved-caption path runs for real.
## Boots main with a new random sim seed (printed). Before it saves the plate
## it proves its subjects: the terminal has closed stations, both desks say
## their staff spot is blocked, each sign's icon projects inside the frame, the
## shown captions clear each other by MissMarkers.CAPTION_MARGIN_PX, no caption
## is shown on a hidden sign, and every staff-spot caption shows with its whole
## (lifted or shifted) rectangle inside the frame and clear of every other
## shown caption and every icon. It prints the zoom, the camera pitch, the
## rectangles and, per station, whether its caption shows. Otherwise it prints
## PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first). The window is
## 1536x864 and the UI scale is the project's own 1.25:
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/caption_declutter_plate_probe.gd
##
## The plate goes to tools/blender/out/caption-declutter/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/caption-declutter"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Puts a seat row over the staff spot of each desk by editing a snapshot of the
## grid, the way an old save could have left them, and loads it back.
func _block_staff_spots(build_mode: BuildMode, sim: PassengerSim, desks: Array[int]) -> void:
	var grid := build_mode.grid
	var data := grid.to_snapshot()
	var next: int = data["next_object_id"]
	for desk in desks:
		var spot := sim.staff.spot_of(desk)
		(data["objects"] as Array).append(
			{"id": next, "def": "seat_row", "anchor": [spot.x - 1, spot.y], "facing": 0}
		)
		next += 1
	data["next_object_id"] = next
	if not grid.from_snapshot(JSON.parse_string(JSON.stringify(data))):
		_invalid("the grid refused the seat rows over the staff spots")
	(build_mode.get_node("BuildView") as BuildView).refresh(grid)


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node3D = load(MAIN_SCENE).instantiate()
	var clock: SimClock = main.get_node("SimClock")
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed, " window=", root.size, " ui_scale=", root.content_scale_factor)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	(main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var build_mode := main.get_node("BuildMode") as BuildMode
	build_mode.set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	var sim: PassengerSim = main.get_node("PassengerSim")
	var desks: Array[int] = []
	desks.assign(sim.layout.desks)
	if desks.size() != 2:
		_invalid("expected the two desks of the starter terminal, got %d" % desks.size())
	_block_staff_spots(build_mode, sim, desks)
	await _frames(20)
	for desk in desks:
		var reason := MissSignals.closed_reason(sim, desk)
		print("PROBE desk=%d staff_spot=%s reason=%s" % [desk, sim.staff.spot_of(desk), reason])
		if reason != MissSignals.SPOT_BLOCKED_REASON:
			_invalid("desk %d is not closed for a blocked staff spot" % desk)
	var markers: MissMarkers = (main.get_node("PassengerViews") as PassengerViews).get_node(
		"MissMarkers"
	)
	var rig: TycoonCamera = main.get_node("TycoonCamera")
	var cam: Camera3D = rig.get_node("Camera3D")
	print("PROBE zoom=%.2f pitch=%.1f" % [rig.distance, rig.pitch_for_distance(rig.distance)])
	var closed := MissSignals.closed_stations(sim)
	print("PROBE closed_stations=", closed.size())
	if closed.size() < 4:
		_invalid("the starter terminal has fewer than 4 closed stations")
	var img := await PlateSight.grab(self)
	var to_screen := float(img.get_height()) / root.get_visible_rect().size.y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2.0
	)
	var full := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	var shown: Array[Rect2] = []
	var staff_rects: Array[Rect2] = []
	var icons: Array[Rect2] = []
	for station: int in closed:
		var sign := markers.closed_sign_for(station)
		var caption := sign.get_node("Caption") as Label3D
		var point := cam.unproject_position(sign.global_position)
		var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
		var at := point * to_screen
		var rect := MissMarkers.caption_rect(at, caption.text, lift, caption.offset.x)
		var side := MissMarkers.SIGN_PX
		icons.append(Rect2(at.x - side / 2.0, at.y - side, side, side))
		print(
			(
				"SIGN station=%d icon_visible=%s caption_visible=%s lift=%.1f text=%s point=%s"
				% [station, sign.visible, caption.visible, lift, caption.text, point]
			)
		)
		if not sign.visible or not frame.has_point(point):
			_invalid("station %d: sign not visible inside the frame" % station)
		if caption.visible:
			shown.append(rect)
		if MissMarkers.is_staff_spot_caption(caption.text):
			if not caption.visible:
				_invalid("station %d: a staff-spot caption is hidden" % station)
			staff_rects.append(rect)
	print("PROBE captions_shown=%d of %d" % [shown.size(), closed.size()])
	if shown.is_empty():
		_invalid("no caption shows, so nothing was checked")
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			var gap_ok := not shown[i].grow(MissMarkers.CAPTION_MARGIN_PX - 0.01).intersects(
				shown[j]
			)
			print("PAIR %d,%d clear=%s" % [i, j, gap_ok])
			if not gap_ok:
				_invalid("captions %d and %d overlap" % [i, j])
	print("PROBE staff_spot_captions=%d frame=%s" % [staff_rects.size(), full])
	if staff_rects.size() < 2:
		_invalid("fewer than 2 staff-spot captions, so the moved path was not engaged")
	for rect in staff_rects:
		var inside := full.encloses(rect)
		var on_icon := false
		for icon in icons:
			on_icon = on_icon or rect.intersects(icon)
		var on_caption := false
		var margin := MissMarkers.CAPTION_MARGIN_PX - 0.01
		for other in shown:
			if not other.is_equal_approx(rect):
				on_caption = on_caption or rect.grow(margin).intersects(other)
		print(
			"STAFF rect=%s inside=%s on_icon=%s on_caption=%s" % [rect, inside, on_icon, on_caption]
		)
		if not inside or on_icon or on_caption:
			_invalid("staff-spot caption %s is outside the frame or on an icon or caption" % rect)
	var path := out_dir.path_join("01_home_zoom_closed_captions.png")
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)
