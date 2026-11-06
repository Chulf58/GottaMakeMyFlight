extends "res://spike/pull_swap_strip.gd"
## A strip of plates of a pulled roller going through a one-cell doorway (board
## cd4ff4e0), for door_tuck_probe.gd in a windowed run, in place of
## PullSwapStrip. The first guest seen pulling a roller (settled, in no move)
## with its body within START_M of the middle of a door edge whose two edges
## on along its wall line are walls (a one-cell doorway) is plated every
## EVERY_FRAMES frames, PLATES times, so the roller is plated from before it
## reaches the jambs to after it is through. Each plate uses PullSwapStrip's
## framings and checks (_aim(), _judge(): the bag body's middle, the hand, the
## feet and the head in frame by MARGIN_PX, sight lines to the bag body with
## none blocked, the guest seen), and prints the tuck weight, the axle's side
## offset from the guest's centre line and the bag's distance to the door's
## middle. A plate that fails its checks is a problem; `done` is true once the
## strip is through. Load with preload(); no class_name.

const DOOR_OUT_REL := "res://../tools/blender/out/door-tuck"
const START_M := 0.35
const DOOR_EVERY_FRAMES := 9
const PLATES := 6

var _doors: Array[Vector3] = []
var _door := Vector3.INF
var _taken := 0


func look(
	tree: SceneTree,
	main: Node3D,
	views: PassengerViews,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	state: Dictionary
) -> void:
	if done:
		return
	var props := views.carry_on_props()
	var i: int = props.props_of(p.id)["bags"].find(bag)
	if _id < 0:
		if props.transfer_progress(p.id, i) < 1.0:
			return
		var door := _door_near(main, body.global_position)
		if not door.is_finite():
			return
		_id = p.id
		_door = door
		print("DOOR_STRIP start id=%d cell=%s door=%s" % [p.id, p.at, door])
	if p.id != _id:
		return
	_frame += 1
	if (_frame - 1) % DOOR_EVERY_FRAMES != 0:
		return
	var problem: String = await _door_plate(tree, main, props, p, body, bag, state)
	_taken += 1
	if problem != "":
		problems.append(problem)
	if _taken >= PLATES or problem.contains(BODY):
		done = true
		_sheet()


## Saves the strip's plates side by side, three a row, as door_tuck_sheet.png.
func _sheet() -> void:
	if saved.is_empty():
		return
	var cell := saved[0].get_size() / 2
	var rows := ceili(saved.size() / 3.0)
	var sheet := Image.create_empty(cell.x * 3, cell.y * rows, false, Image.FORMAT_RGBA8)
	for k in saved.size():
		var small := saved[k].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(cell.x, cell.y)
		sheet.blit_rect(
			small, Rect2i(Vector2i.ZERO, cell), Vector2i(k % 3 * cell.x, k / 3 * cell.y)
		)
	var dir := ProjectSettings.globalize_path(DOOR_OUT_REL).simplify_path()
	sheet.save_png(dir.path_join("door_tuck_sheet.png"))
	print("PLATE saved %s" % dir.path_join("door_tuck_sheet.png"))


## The middle of a one-cell doorway within START_M of `at` (level), or INF: an
## edge with a door or no wall at all between two walled edges on its line
## (roller_trail_probe.gd's JAMB counts both, and a door-only test found none).
func _door_near(main: Node3D, at: Vector3) -> Vector3:
	if _doors.is_empty():
		var grid: BuildGrid = (main.get_node("BuildMode") as BuildMode).grid
		var seen := {}
		for edge in WallCutaway.wall_edges(grid):
			var cell := Vector2i(edge.x, edge.y)
			var side: int = edge.z
			if not _solid(grid.wall_kind(cell, side)):
				continue
			var along := Vector2i(BuildGrid.SIDE_STEP[side].y, BuildGrid.SIDE_STEP[side].x)
			for k in [1, -1]:
				var gap: Vector2i = cell + along * k
				if (
					_solid(grid.wall_kind(gap, side))
					or not _solid(grid.wall_kind(gap + along * k, side))
				):
					continue
				var key := Vector3i(gap.x, gap.y, side)
				if not seen.has(key):
					seen[key] = true
					_doors.append(BuildView.wall_transform(grid, gap, side).origin)
		print("DOOR_STRIP doorways found %d" % _doors.size())
		if _doors.is_empty():
			_doors.append(Vector3.INF)
	for door in _doors:
		if Vector2(door.x - at.x, door.z - at.z).length() < START_M:
			return door
	return Vector3.INF


## Whether wall kind `kind` stands in the way (a plain or glass wall).
static func _solid(kind: int) -> bool:
	return kind == BuildGrid.WallKind.PLAIN or kind == BuildGrid.WallKind.GLASS


## One plate of the strip: "" when saved, else what failed.
func _door_plate(
	tree: SceneTree,
	main: Node3D,
	props: CarryOnProps,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	state: Dictionary
) -> String:
	var shell := bag.find_child(BODY, true, false) as MeshInstance3D
	if shell == null:
		return "id %d: no %s mesh on the roller %s" % [p.id, BODY, bag.name]
	var place := int(state.get("place", -1))
	var name := "door_tuck_id%d_%02d" % [p.id, _taken]
	var was_cam := main.get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	var holder := PlateSight.colliders(main, [main] as Array[Node], {shell: TAG, body: GUEST_TAG})
	await tree.physics_frame
	var picked := -1
	var verdict := {}
	for f in FRAMINGS.size():
		_aim(cam, shell, body, place, FRAMINGS[f])
		verdict = _judge(cam, main, props, shell, body, state)
		if (verdict["bad"] as String) == "":
			picked = f
			break
	var img: Image = null
	if picked >= 0:
		for n in 3:
			await tree.process_frame
		await tree.physics_frame
		img = main.get_viewport().get_texture().get_image()
		verdict = _judge(cam, main, props, shell, body, state)
	var axle := bag.global_transform * CarryOnProps.ROLLER_AXLE
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var local := frame.affine_inverse() * axle
	var centre := shell.global_transform * shell.get_aabb().get_center()
	print(
		(
			(
				"DOOR_STRIP %s id=%d framing=%d hand=%d tuck=%.2f axle_side=%.3f behind=%.3f "
				+ "bag_to_door=%.2f %s"
			)
			% [
				name,
				p.id,
				picked,
				CarryLead.hand_of(place),
				RollerPull.tuck_weight(state, float(state.get("drawn_at", 0.0))),
				absf(local.x),
				-local.z,
				Vector2(centre.x - _door.x, centre.z - _door.z).length(),
				verdict["report"],
			]
		)
	)
	holder.queue_free()
	cam.queue_free()
	if was_cam != null:
		was_cam.make_current()
	if picked < 0 or (verdict["bad"] as String) != "":
		return "%s: %s" % [name, verdict["bad"]]
	saved.append(img)
	var dir := ProjectSettings.globalize_path(DOOR_OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		return "%s: not saved to %s" % [name, path]
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	return ""
