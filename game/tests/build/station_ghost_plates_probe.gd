extends "res://tests/build/build_view_plates_probe.gd"
## Windowed plate probe for the station build ghost's use tiles and arrow
## (decision station-build-ghost-shows-passenger-side-staff-spot-and-arrow).
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <worktree>/game -s res://tests/build/station_ghost_plates_probe.gd
##
## Hovers the real BuildMode ghost (through pointer_override and the real
## TycoonCamera) over a floored 16 x 16 grid for a check-in desk, a scanner,
## an X-ray belt joining a standing arch, a gate desk and an arch, each at two
## facings, plus a desk whose staff spot is blocked and a distance shot. Each
## shot proves the ghost's bounds project inside the frame and that a camera
## ray reaches every use tile (its centre or one of four points near its
## corners) and the arrow before any placed object or the ghost body, or it
## prints PROBE_INVALID and exits 1. Plates go to
## tools/blender/out/ghost-cells/.

const GHOST_OUT := "res://../tools/blender/out/ghost-cells"
const AT := Vector2i(8, 8)
const YAW := 0.7

var _mode: BuildMode
var _view: BuildView


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(GHOST_OUT).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	var site := _studio()
	_mode = BuildMode.new()
	_mode.grid_size = GRID
	site.add_child(_mode)
	_view = _mode.get_node("BuildView")
	for y in GRID.y:
		for x in GRID.x:
			_must(_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)))
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	# name, tool, facing, context, camera distance
	var shots := [
		["desk_f0", BuildMode.Tool.DESK, 0, "", 9.0],
		["desk_f1", BuildMode.Tool.DESK, 1, "", 9.0],
		["scanner_f0", BuildMode.Tool.SCANNER, 0, "", 9.0],
		["scanner_f3", BuildMode.Tool.SCANNER, 3, "", 9.0],
		["xray_belt_f0", BuildMode.Tool.XRAY_BELT, 0, "lane", 9.0],
		["xray_belt_f1", BuildMode.Tool.XRAY_BELT, 1, "lane", 9.0],
		["gate_desk_f0", BuildMode.Tool.GATE_DESK, 0, "", 9.0],
		["gate_desk_f3", BuildMode.Tool.GATE_DESK, 3, "", 9.0],
		["arch_f0", BuildMode.Tool.ARCH, 0, "", 10.0],
		["arch_f1", BuildMode.Tool.ARCH, 1, "", 10.0],
		["desk_f0_staff_blocked", BuildMode.Tool.DESK, 0, "block_staff", 9.0],
		["desk_f0_distance", BuildMode.Tool.DESK, 0, "", 24.0],
	]
	var sheet: Array[Image] = []
	for shot in shots:
		var target := _stage(shot[1], shot[2], shot[3])
		rig.position = _mode.grid.cell_to_world(AT)
		rig.distance = shot[4]
		rig.yaw = YAW
		rig.zoom(1.0)
		await _frames(3)
		_mode.pointer_override = cam.unproject_position(_mode.grid.cell_to_world(target))
		await _frames(6)
		var ghost: Node3D = _mode.get_node("Ghost")
		var tiles := _use_nodes(ghost)
		print("SHOT %s cam=%s tiles=%s" % [shot[0], cam.global_position, _describe(tiles)])
		var ok := not tiles.is_empty() and ghost.visible
		if not ok:
			_invalid("%s: the ghost shows no use tiles" % shot[0])
		ok = _prove_in_frame(cam, shot[0], _corners(_aabb_of(ghost))) and ok
		var occluders := _occluders(site, ghost)
		await physics_frame
		await physics_frame
		ok = _prove_tiles_seen(cam, shot[0], tiles, occluders) and ok
		occluders.free()
		var img := await _grab()
		if ok:
			_save(img, shot[0] + ".png")
			sheet.append(img)
	_save(_sheet(sheet), "contact_sheet.png")
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## Clears the grid's objects, places the shot's context, picks the tool and
## facing, and returns the cell to hover.
func _stage(tool: BuildMode.Tool, facing: int, context: String) -> Vector2i:
	for id in _mode.grid.object_ids():
		_must(_mode.grid.apply(BuildEdit.remove_object(id)))
	var target := AT
	if context == "lane":
		var lane := SecurityLanes.geometry(AT, facing, SecurityLanes.RIGHT)
		_must(_mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, AT, facing)))
		for part in [SecurityLanes.TRAY_TABLE, SecurityLanes.PICKUP_TABLE]:
			_must(_mode.grid.apply(BuildEdit.place_object(part, lane[part], facing)))
		target = lane["xray_belt"]
	elif context == "block_staff":
		var spot := StaffSpots.cell_of(&"checkin_desk", AT, facing)
		_must(_mode.grid.apply(BuildEdit.place_object(&"trash_can", spot, 0)))
	_view.refresh(_mode.grid)
	_mode.set_tool(tool)
	_mode.facing = facing
	return target


func _use_nodes(ghost: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in ghost.get_children():
		if not child.is_queued_for_deletion() and child.has_meta("role"):
			out.append(child)
	return out


func _describe(tiles: Array[Node3D]) -> String:
	var parts := []
	for node in tiles:
		var role: String = node.get_meta("role")
		if role == StationUseCells.ARROW:
			parts.append("arrow flow %s" % node.get_meta("flow"))
		else:
			var state := " BLOCKED" if node.get_meta("blocked") else ""
			parts.append("%s %s%s" % [role, node.get_meta("cell"), state])
	return ", ".join(parts)


## Colliders for every placed object and the ghost's body (not its tiles).
func _occluders(site: Node3D, ghost: Node3D) -> Node3D:
	var holder := Node3D.new()
	site.add_child(holder)
	var bodies: Array[Node] = []
	for child in _view.get_children():
		if child.has_meta("record"):
			bodies.append(child)
	for child in ghost.get_children():
		if not child.has_meta("role") and not child.is_queued_for_deletion():
			bodies.append(child)
	for node in bodies:
		for mi in _meshes(node):
			var faces := PackedVector3Array()
			for p in _opaque_faces(mi.mesh):
				faces.append(mi.global_transform * p)
			if not faces.is_empty():
				holder.add_child(_body(faces))
	return holder


## Every use tile's top (its centre or a point near a corner) and the arrow's
## centre is reached by a camera ray before any collider.
func _prove_tiles_seen(
	cam: Camera3D, label: String, tiles: Array[Node3D], occluders: Node3D
) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var seen := 0
	for node in tiles:
		var top := node.global_position + Vector3(0.0, 0.05, 0.0)
		var points: Array[Vector3] = [top]
		if node.get_meta("role") != StationUseCells.ARROW:
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				points.append(top + Vector3(corner.x, 0.0, corner.y) * 0.35)
		var reached := 0
		for point in points:
			var ray := PhysicsRayQueryParameters3D.create(cam.global_position, point)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or not occluders.is_ancestor_of(hit.collider):
				reached += 1
		var clear := reached > 0
		print(
			(
				"SEEN %s %s %s rays_clear=%d/%d"
				% [label, node.get_meta("role"), top, reached, points.size()]
			)
		)
		if clear:
			seen += 1
	var ok := seen == tiles.size() and seen > 0
	if not ok:
		_invalid("%s: %d of %d use marks hidden" % [label, tiles.size() - seen, tiles.size()])
	return ok


func _sheet(images: Array[Image]) -> Image:
	var tile := Vector2i(640, 360)
	var rows := ceili(images.size() / 4.0)
	var sheet := Image.create(tile.x * 4, tile.y * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for i in images.size():
		var small := images[i].duplicate() as Image
		small.resize(tile.x, tile.y)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, tile), Vector2i(i % 4, i / 4) * tile)
	return sheet
