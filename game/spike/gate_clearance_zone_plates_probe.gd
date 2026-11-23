extends SceneTree
## Windowed plate probe for the shifted starter shell and build-mode gate
## plane-stand clearance zone (board a23ec884, decision
## starter-shell-shifted-south-with-build-mode-gate-clearance-zone):
##   starter_shifted_overview  starter terminal shifted south near the road with
##                             open north expansion room inside owned plots
##   clearance_near            build mode hovering within 6 cells of Gate A's
##                             stand envelope (CLEARANCE_NEAR_TINT)
##   clearance_overlap         build mode hovering inside Gate A's stand
##                             envelope (CLEARANCE_OVERLAP_TINT)
##
## Run (one windowed Godot run project-wide):
##   tools/godot.sh --display-driver windows --rendering-driver vulkan \
##     --audio-driver Dummy --path game -s res://spike/gate_clearance_zone_plates_probe.gd
##
## Plates go to tools/blender/out/starter_shell_clearance/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/starter_shell_clearance"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 16.0
const SETTLE_FRAMES := 30
const FIT_DISTANCES: Array[float] = [55.0, 75.0, 95.0, 120.0, 150.0, 185.0, 225.0]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: Node3D
var _build: BuildMode
var _menu: BuildMenu
var _staff: StaffPanel
var _gates: GateDesks
var _apron: ApronStand
var _links: GateLinksView


func _initialize() -> void:
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=", world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_invalid(msg)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(randi())
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_rig = _main.get_node("TycoonCamera")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_staff = _main.get_node("StaffPanel")
	_gates = _main.get_node("GateDesks")
	_apron = _main.get_node("ApronStand")
	_links = _apron.links_view()
	await _frames(20)

	_expect(StarterFlight.add_gate_desk(_build.grid), "failed to place starter gate desk")
	await _frames(6)
	_expect(_gates.stands.has("A"), "gate A stand missing")

	_build.set_tool(BuildMode.Tool.FLOOR)
	await _frames(4)
	_expect(_links.is_visible_in_tree(), "GateLinksView hidden in build mode")

	var env_rects := StandEnvelope.rects(_gates.stands["A"], _gates.max_class("A"))
	_expect(not env_rects.is_empty(), "gate A envelope rects empty")
	var env_bounds: Rect2 = env_rects[0]
	for i in range(1, env_rects.size()):
		env_bounds = env_bounds.merge(env_rects[i])

	var offset := _build.site.starter_offset
	var road_pt := _build.grid.cell_to_world(
		offset + ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, 7)
	)
	var west_pt := _build.grid.cell_to_world(offset + Vector2i(7, 10))
	var east_pt := _build.grid.cell_to_world(offset + Vector2i(24, 10))
	var north_pt := _build.grid.cell_to_world(offset + Vector2i(15, -24))
	var overview_pts := [road_pt, west_pt, east_pt, north_pt]
	var far_south := _build.grid.cell_to_world(
		offset + ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, 6)
	)
	var overview_focus := _centre(overview_pts) + Vector3(0.0, 0.0, 12.0)
	var overview_dist := await _fit(overview_focus, overview_pts)
	await _point_to_world(far_south, overview_focus, overview_dist)
	var zone := _links.clearance_node("A")
	_expect(zone != null, "clearance node A missing")
	_expect(
		zone != null and not zone.visible, "overview: clearance zone should be hidden far south"
	)
	print(
		"OVERVIEW starter_offset=%s clearance_visible=%s" % [offset, zone != null and zone.visible]
	)
	await _plate("starter_shifted_overview", overview_focus, overview_dist, overview_pts)

	var env_points := _rect_corners(env_rects[0], _build.grid.origin.y)
	var near_world := Vector3(
		_build.grid.origin.x + float(offset.x + 5) + 0.5,
		_build.grid.origin.y,
		env_bounds.end.y + 3.0
	)
	var near_pts := env_points + [near_world]
	var near_focus := _centre(near_pts) + Vector3(0.0, 0.0, 18.0)
	var near_dist := await _fit(near_focus, near_pts)
	await _point_to_world(near_world, near_focus, near_dist)
	var near_mat := zone.material_override as StandardMaterial3D if zone != null else null
	_expect(zone != null and zone.visible, "clearance_near: zone should be visible within 6 cells")
	_expect(
		(
			near_mat != null
			and near_mat.albedo_color.is_equal_approx(GateLinksView.CLEARANCE_NEAR_TINT)
		),
		"clearance_near: expected CLEARANCE_NEAR_TINT"
	)
	print(
		(
			"CLEARANCE_NEAR visible=%s color=%s"
			% [
				zone != null and zone.visible,
				near_mat.albedo_color if near_mat != null else Color.BLACK
			]
		)
	)
	await _plate("clearance_near", near_focus, near_dist, near_pts)

	var r0: Rect2 = env_rects[0]
	var overlap_world := Vector3(r0.get_center().x, _build.grid.origin.y, r0.end.y - 3.0)
	var overlap_pts := env_points + [overlap_world]
	var overlap_focus := _centre(overlap_pts) + Vector3(0.0, 0.0, 18.0)
	var overlap_dist := await _fit(overlap_focus, overlap_pts)
	await _point_to_world(overlap_world, overlap_focus, overlap_dist)
	var overlap_mat := zone.material_override as StandardMaterial3D if zone != null else null
	_expect(zone != null and zone.visible, "clearance_overlap: zone should be visible on overlap")
	_expect(
		(
			overlap_mat != null
			and overlap_mat.albedo_color.is_equal_approx(GateLinksView.CLEARANCE_OVERLAP_TINT)
		),
		"clearance_overlap: expected CLEARANCE_OVERLAP_TINT"
	)
	print(
		(
			"CLEARANCE_OVERLAP visible=%s color=%s"
			% [
				zone != null and zone.visible,
				overlap_mat.albedo_color if overlap_mat != null else Color.BLACK,
			]
		)
	)
	await _plate("clearance_overlap", overlap_focus, overlap_dist, overlap_pts)

	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _rect_corners(rect: Rect2, y: float) -> Array:
	var out: Array = []
	var center := rect.get_center()
	for corner: Vector2 in [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]:
		var inward := (center - corner).normalized() * 0.5
		out.append(Vector3(corner.x + inward.x, y, corner.y + inward.y))
	return out


func _centre(points: Array) -> Vector3:
	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for p: Vector3 in points:
		low = low.min(p)
		high = high.max(p)
	return (low + high) / 2.0


func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [_menu.bar().get_global_rect()]
	if _menu.tray().is_visible_in_tree():
		out.append(_menu.tray().get_global_rect())
	if _menu.preview_label().is_visible_in_tree():
		out.append(_menu.preview_label().get_global_rect())
	var card := _staff.hint_card()
	if card.is_visible_in_tree():
		out.append(card.get_global_rect())
	var top := _menu.get_node_or_null("TopBar")
	if top is Control and (top as Control).is_visible_in_tree():
		out.append((top as Control).get_global_rect())
	return out


func _fit(focus: Vector3, points: Array) -> float:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for distance in FIT_DISTANCES:
		_rig.position = focus
		_rig.target_distance = distance
		_rig.distance = distance
		await _frames(SETTLE_FRAMES)
		var fits := true
		for p: Vector3 in points:
			var s := _cam.unproject_position(p)
			var under := _hud_rects().any(func(r: Rect2) -> bool: return r.has_point(s))
			fits = fits and not _cam.is_position_behind(p) and frame.has_point(s) and not under
		if fits:
			return distance
	return FIT_DISTANCES[-1]


func _point_to_world(hover_world: Vector3, focus: Vector3, distance: float) -> void:
	_rig.position = focus
	_rig.target_distance = distance
	_rig.distance = distance
	await _frames(SETTLE_FRAMES)
	_build.pointer_override = _cam.unproject_position(hover_world)
	await _frames(8)


func _plate(label: String, focus: Vector3, distance: float, points: Array) -> void:
	_rig.position = focus
	_rig.target_distance = distance
	_rig.distance = distance
	await _frames(SETTLE_FRAMES)
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := _cam.get_world_3d().direct_space_state
	for p: Vector3 in points:
		var s := _cam.unproject_position(p)
		var under_hud := _hud_rects().any(func(r: Rect2) -> bool: return r.has_point(s))
		var query := PhysicsRayQueryParameters3D.create(_cam.global_position, p + Vector3.UP * 0.05)
		var hit := space.intersect_ray(query)
		print(
			(
				"INFRAME %s point=%s screen=(%.0f,%.0f) in=%s under_hud=%s ray_hit=%s"
				% [label, p, s.x, s.y, frame.has_point(s), under_hud, hit.get("collider", "none")]
			)
		)
		if _cam.is_position_behind(p) or not frame.has_point(s) or under_hud:
			_invalid("%s: %s is out of frame or under the HUD" % [label, p])
			return
		if not hit.is_empty():
			_invalid("%s: %s is hidden behind %s" % [label, p, hit["collider"]])
			return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s camera=%s distance=%.1f" % [path, _cam.global_position, distance])
