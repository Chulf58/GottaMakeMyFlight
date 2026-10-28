extends SceneTree
## Windowed plate for the station caption declutter: the real main scene with
## the starter terminal built and nobody hired, seen from the start camera (the
## home zoom), so every desk and scanner carries a Closed sign.
## Boots main with a new random sim seed (printed). Before it saves the plate
## it proves its subjects: the terminal has closed stations, each sign's icon
## projects inside the frame, the shown captions clear each other by
## MissMarkers.CAPTION_MARGIN_PX, and no caption is shown on a hidden sign.
## It prints the zoom, the camera pitch and, per station, whether its caption
## shows. Otherwise it prints PROBE_INVALID and exits 1.
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
	(main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	var sim: PassengerSim = main.get_node("PassengerSim")
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
	var shown: Array[Rect2] = []
	for station: int in closed:
		var sign := markers.closed_sign_for(station)
		var caption := sign.get_node("Caption") as Label3D
		var point := cam.unproject_position(sign.global_position)
		var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
		var rect := MissMarkers.caption_rect(point * to_screen, caption.text, lift)
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
	var path := out_dir.path_join("01_home_zoom_closed_captions.png")
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)
