extends SceneTree
## Windowed Vulkan comparison probe: renders gate_desk and bus_gate_desk side-by-side
## in main.tscn's real terminal lighting, Toon ramp, and outline shaders, proves both
## are framed and unoccluded via PlateSight, saving godot_compare.png.

const PlateSight := preload("res://spike/plate_sight.gd")
const MAIN := "res://main/main.tscn"
const OUT_PATH := "res://../tools/blender/out/bus-gate-desk/godot_compare.png"
const MARGIN_PX := 8.0
const SETTLE_FRAMES := 12

var _main: Node
var _clock: SimClock
var _mode: BuildMode
var _grid: BuildGrid
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _offset := Vector2i.ZERO
var _reg_node: Node3D
var _bus_node: Node3D


func _initialize() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode")
	_grid = _mode.grid
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_mode.require_unlocks = false
	_mode.land_tool.land.gated = false
	(_mode.get_node("Ghost") as Node3D).visible = false
	_hud.dismiss_intro()
	for node_name in ["PassengerHud", "BuildMenu", "RoofView"]:
		var node := _main.get_node_or_null(node_name)
		if node is CanvasLayer or node is Control or node is Node3D:
			node.set("visible", false)
	var apron := _main.get_node_or_null("ApronStand") as ApronStand
	if apron != null and apron.links_view() != null:
		apron.links_view().visible = false
	_clock.set_paused(true)
	_offset = ReferenceTerminal.offset_on(_grid)
	if not _build_compare_hall():
		_fail("could not build comparison hall")
		return
	await _frames(SETTLE_FRAMES)
	if _reg_node == null or _bus_node == null:
		_fail("missing comparison desk nodes (%s, %s)" % [_reg_node, _bus_node])
		return
	var reg_world := _reg_node.global_position
	var bus_world := _bus_node.global_position
	var mid := (reg_world + bus_world) * 0.5 + Vector3(0.0, 0.9, 0.0)
	_rig.set_process(false)
	_rig.set_physics_process(false)
	_cam.position = Vector3.ZERO
	_rig.global_position = mid
	_cam.global_position = mid + Vector3(2.8, 3.6, 5.2)
	_cam.look_at(mid, Vector3.UP)
	await _frames(SETTLE_FRAMES)
	var ok := await _check_and_save(_reg_node, _bus_node)
	quit(0 if ok else 1)


func _build_compare_hall() -> bool:
	var view := _mode.get_node("BuildView") as BuildView
	var existing := GateDesks.desk_ids(_grid)
	var desk_id := existing[0] if not existing.is_empty() else 0
	if desk_id == 0:
		var r1 := _grid.apply(ReferenceTerminal.gate_desk_edit(_offset))
		if not r1.ok:
			print("COMPARE_DESK_FAIL -> %s" % r1.reason_text())
			return false
		desk_id = r1.object_id
		view.refresh(_grid)
	_reg_node = view.object_node(desk_id) as Node3D
	if _reg_node == null:
		return false
	_bus_node = InteriorKit.instantiate(InteriorKit.object_piece(GateDesks.BUS_DESK))
	_bus_node.position = _reg_node.position + Vector3(-3.0, 0.0, 0.0)
	_bus_node.rotation = _reg_node.rotation
	view.add_child(_bus_node)
	return _reg_node != null and _bus_node != null


func _check_and_save(reg_node: Node3D, bus_node: Node3D) -> bool:
	var terminal := _main.get_node("Airside/Terminal")
	var subjects := {reg_node: "gate_desk", bus_node: "bus_gate_desk"}
	var holder := PlateSight.colliders(_main, [terminal, _mode], subjects)
	await physics_frame
	await _frames(2)
	var vp := root.get_visible_rect()
	var frame := Rect2(Vector2(MARGIN_PX, MARGIN_PX), vp.size - Vector2.ONE * (2.0 * MARGIN_PX))
	var space := _cam.get_world_3d().direct_space_state
	var bounds: Dictionary = holder.get_meta("bounds", {})
	var ok := true
	for tag in ["gate_desk", "bus_gate_desk"]:
		var box: AABB = bounds.get(tag, AABB())
		if box.size == Vector3.ZERO:
			print("PROBE_INVALID %s empty bounds" % tag)
			ok = false
			continue
		var pts := _sample_points(box)
		for pt in pts:
			if _cam.is_position_behind(pt):
				print("PROBE_INVALID %s behind camera" % tag)
				ok = false
			var screen := _cam.unproject_position(pt)
			if not frame.has_point(screen):
				print("PROBE_INVALID %s out of frame %s vs %s" % [tag, screen, frame])
				ok = false
		var sight := PlateSight.sight_lines(space, _cam.global_position, pts, tag)
		var hits := (sight["on_subject"] as Array).size()
		var blockers: Array = sight["blockers"]
		print(
			(
				"COMPARE %s unproject_center=%s hits=%d blockers=%s"
				% [tag, _cam.unproject_position(box.get_center()), hits, blockers]
			)
		)
		if hits < 3 or not blockers.is_empty():
			print("PROBE_INVALID %s visibility check failed" % tag)
			ok = false
	holder.queue_free()
	if not ok:
		return false
	var abs_out := ProjectSettings.globalize_path(OUT_PATH).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var img := root.get_texture().get_image()
	var err := img.save_png(abs_out)
	print("PLATE saved %s size=%dx%d err=%d" % [abs_out, img.get_width(), img.get_height(), err])
	return err == OK


func _sample_points(box: AABB) -> Array[Vector3]:
	var c := box.get_center()
	var d := box.size * 0.25
	return [
		c,
		c + Vector3(-d.x, 0.0, 0.0),
		c + Vector3(d.x, 0.0, 0.0),
		c + Vector3(0.0, d.y, 0.0),
		c + Vector3(0.0, -d.y * 0.5, 0.0),
	]


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	quit(1)
