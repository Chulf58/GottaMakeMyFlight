extends SceneTree
## Windowed plate probe for the build HUD (BuildMenu and PassengerHud) on the
## real main.tscn with the starter terminal built:
##   a_no_tray_1920   no tool, tray closed
##   b_floor_drag_1920  Structure tray, Floor picked, a rectangle mid-drag
##   c_checkin_refusal_1920  Check-in tray, a desk hovered off the floor
##   d_layout_1280    1280x720, Structure tray, Debug open, a long follow text
## Before each save it proves every HUD panel lies inside the window, that no
## two panels overlap, and that the 3D subject projects inside the frame clear
## of every panel; otherwise it prints PROBE_INVALID and exits 1. A guard
## thread prints PROBE_INVALID and calls OS.crash() if the run passes
## LIMIT_MS, since a frozen main thread never reaches a check in _process.
##
## Run (one windowed Godot run project-wide; hold game/.godot/windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://tests/ui/build_hud_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/hud-followups"
const MARGIN_PX := 8.0
const LIMIT_MS := 120000
const OCCLUSION_STOP_M := 0.1
const FOCUS_CELL := Vector2i(20, 10)
const DRAG_FROM := Vector2i(24, 6)
const DRAG_TO := Vector2i(29, 11)
const REFUSED_CELL := Vector2i(27, 9)
const LONG_FOLLOW := (
	"Passenger 12345   Going through security   mood 100   "
	+ '"If this queue does not move soon I am going to miss my flight"'
)

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _main: Node3D
var _mode: BuildMode
var _menu: BuildMenu
var _hud: PassengerHud
var _cam: Camera3D


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE seed=", probe_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: the probe ran past %d ms" % LIMIT_MS)
			OS.crash("build_hud_plates_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_mode = _main.get_node("BuildMode") as BuildMode
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_hud = _main.get_node("PassengerHud") as PassengerHud
	await _frames(3)
	_hud.press_starter_terminal()
	print("PROBE starter: %s" % _hud.status_text())
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	_cam = rig.get_node("Camera3D") as Camera3D
	rig.position = _mode.grid.cell_to_world(FOCUS_CELL)
	rig.distance = 42.0
	rig.zoom(1.0)
	await _frames(20)
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	if root.size != Vector2i(1920, 1080):
		_invalid("the window is %s, not 1920x1080" % root.size)

	# Control: a point one metre under the ground must report an occluder, or
	# the occlusion check below could not tell anything.
	var under := _mode.grid.cell_to_world(DRAG_FROM) + Vector3(0.0, -1.0, 0.0)
	var control := _occluder(under)
	print("PROBE occlusion control under %s: %s" % [under, control if control != "" else "clear"])
	if control == "":
		_invalid(
			"the occlusion check found nothing between the camera and a point under the ground"
		)

	_mode.set_tool(BuildMode.Tool.NONE)
	_warp(_mode.grid.cell_to_world(FOCUS_CELL))
	await _frames(6)
	await _plate("a_no_tray_1920", [])

	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(DRAG_FROM))
	_mode.move_area(_mode.grid.cell_to_world(DRAG_TO))
	_warp(_mode.grid.cell_to_world(DRAG_TO))
	await _frames(6)
	if not _mode._area.active:
		_invalid("b: the rectangle was dropped before the plate")
	await _plate(
		"b_floor_drag_1920",
		[_mode.grid.cell_to_world(DRAG_FROM), _mode.grid.cell_to_world(DRAG_TO)]
	)
	_mode.cancel_area()

	_mode.set_tool(BuildMode.Tool.DESK)
	_warp(_mode.grid.cell_to_world(REFUSED_CELL))
	await _frames(6)
	if (
		_mode.status_text().find("Facing") < 0
		or _mode.status_text().length() <= "Facing auto".length()
	):
		_invalid("c: no refusal on the status line: '%s'" % _mode.status_text())
	await _plate("c_checkin_refusal_1920", [_mode.grid.cell_to_world(REFUSED_CELL)])

	await _ghost_over_hud()

	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(10)
	# The content scale (project.godot) keeps the layout size the same at every
	# window size, so the window is checked by its pixels, not the visible rect.
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	if root.size != Vector2i(1280, 720):
		_invalid("d: the window is %s, not 1280x720" % root.size)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_hud.set_debug_open(true)
	_hud.press_debug_spawn()
	_hud.press_starter_terminal()
	_hud.refresh()
	_hud.set_process(false)
	(_hud.find_child("FollowText", true, false) as Label).text = LONG_FOLLOW
	_warp(_mode.grid.cell_to_world(DRAG_TO))
	await _frames(8)
	await _plate("d_layout_1280", [])

	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


## The build ghost shows over the world and hides while the real mouse is over
## the category bar (control: the same tool a moment earlier, over the world).
func _ghost_over_hud() -> void:
	var ghost := _mode.get_node("Ghost") as Node3D
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_warp(_mode.grid.cell_to_world(FOCUS_CELL))
	await _frames(6)
	var world_hovered := root.gui_get_hovered_control()
	var world_children := ghost.get_child_count()
	print(
		(
			"PROBE ghost over world: hovered=%s visible=%s children=%d"
			% [world_hovered, ghost.visible, world_children]
		)
	)
	if world_hovered != null or not ghost.visible or world_children == 0:
		_invalid("e: the control did not show a ghost over the world")
	var on_bar := _menu.bar().get_global_rect().get_center()
	_warp_screen(on_bar)
	await _frames(6)
	var bar_hovered := root.gui_get_hovered_control()
	print(
		(
			"PROBE ghost over HUD at %s: hovered=%s visible=%s status='%s'"
			% [on_bar, bar_hovered, ghost.visible, _mode.status_text()]
		)
	)
	if bar_hovered == null or ghost.visible:
		_invalid("e: the ghost is not hidden over the bar")
	await _plate("e_ghost_over_bar_1920", [])
	_warp(_mode.grid.cell_to_world(FOCUS_CELL))
	await _frames(4)


func _plate(label: String, subjects: Array) -> void:
	var view := root.get_visible_rect()
	var panels := _panels()
	var ok := true
	print("PLATE %s status='%s' tray_open=%s" % [label, _mode.status_text(), _menu.is_tray_open()])
	for key in panels:
		var rect: Rect2 = panels[key]
		var inside := view.encloses(rect)
		print("  PANEL %s %s inside=%s" % [key, rect, inside])
		ok = ok and inside
	var keys := panels.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (panels[keys[i]] as Rect2).intersects(panels[keys[j]]):
				print("  OVERLAP %s with %s" % [keys[i], keys[j]])
				ok = false
	var status := _menu.status_label()
	print("  STATUS lines=%d visible_max=%d" % [status.get_line_count(), status.max_lines_visible])
	ok = ok and status.get_line_count() <= status.max_lines_visible
	for point in subjects:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		var covered := ""
		for key in panels:
			if (panels[key] as Rect2).has_point(p):
				covered = key
		print("  SUBJECT %s -> %s in_frame=%s covered_by='%s'" % [point, p, in_frame, covered])
		var occluder := _occluder(point)
		print("  OCCLUSION %s: %s" % [point, occluder if occluder != "" else "clear"])
		ok = ok and in_frame and covered == "" and occluder == ""
	if not ok:
		_invalid("%s: a panel or subject check failed" % label)
		return
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate was not saved (error %d)" % [label, err])


## Whether an opaque mesh lies between the camera and a world subject: the
## first mesh triangle the camera-to-subject segment crosses, as a description
## with its path, hit point and distance, or "" for a clear line. The game has
## no colliders, so the test runs on mesh triangles (AABB first). The segment
## stops OCCLUSION_STOP_M short of the subject so the ground it stands on does
## not count; the build ghost's own meshes and transparent materials are skipped.
func _occluder(subject: Vector3) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * OCCLUSION_STOP_M
	var ghost := _mode.get_node("Ghost")
	var best := ""
	var best_distance := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree() or ghost.is_ancestor_of(node):
			continue
		if _is_transparent(instance):
			continue
		var xform := instance.global_transform
		if (xform * instance.get_aabb()).intersects_segment(from, to) == null:
			continue
		var inverse := xform.affine_inverse()
		var hit: Dictionary = instance.mesh.generate_triangle_mesh().intersect_segment(
			inverse * from, inverse * to
		)
		if hit.is_empty():
			continue
		var world_hit: Vector3 = xform * (hit["position"] as Vector3)
		var distance := from.distance_to(world_hit)
		if distance < best_distance:
			best_distance = distance
			best = (
				"%s hit at %s, %.2f m from the camera" % [instance.get_path(), world_hit, distance]
			)
	return best


func _is_transparent(instance: MeshInstance3D) -> bool:
	var material := instance.material_override
	if material == null and instance.mesh.get_surface_count() > 0:
		material = instance.get_active_material(0)
	var base := material as BaseMaterial3D
	return base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## The on-screen rect of every visible HUD panel.
func _panels() -> Dictionary:
	var out := {}
	out["bar"] = _menu.bar().get_global_rect()
	if _menu.is_tray_open():
		out["tray"] = _menu.tray().get_global_rect()
	if _menu.status_label().text != "":
		out["status"] = _menu.status_label().get_global_rect()
	out["money"] = (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect()
	out["flight"] = (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect()
	out["debug"] = (_hud.find_child("DebugCorner", true, false) as Control).get_global_rect()
	var follow := _hud.find_child("FollowText", true, false) as Label
	if follow.text != "":
		out["follow"] = follow.get_global_rect()
	return out


func _warp(point: Vector3) -> void:
	_warp_screen(_cam.unproject_position(point))


## Moves the mouse and sends the motion event a real pointer would, which is
## what updates the hovered Control.
func _warp_screen(screen: Vector2) -> void:
	root.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
