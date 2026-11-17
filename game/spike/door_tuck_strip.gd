extends "res://spike/pull_swap_strip.gd"
## A strip of plates of a pulled roller going through a one-cell doorway (board
## cd4ff4e0), for door_tuck_probe.gd in a windowed run, in place of
## PullSwapStrip. The first guest seen pulling a roller in the left hand (settled, in no move)
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
## `-- --strip-hand=0` plates a right-hand pull instead (board ed73cfb1: the
## two hands from the same angle, _aim() framing from the pulling hand's side);
## `--strip-out=<res path>` puts the plates elsewhere.

const DOOR_OUT_REL := "res://../tools/blender/out/door-tuck"
const START_M := 0.35
const DOOR_EVERY_FRAMES := 9
const PLATES := 6
## A plate no framing can show (a door leaf, the wall or the bridge stands in
## every line to the guest or its hand) is printed as skipped, not saved, and is
## not a problem by itself; the strip is, when fewer than STRIP_MIN_SAVED are saved.
const STRIP_MIN_SAVED := 3
const STRIP_UNFRAMED := "unframed: "
const LEFT := 1
## PullSwapStrip's framings, then two farther and higher ones for a guest in a
## doorway, whose roller is pulled behind it so the aim point sits low and the
## head can leave the top of the frame from the near ones, then two along the
## door's axis (behind and ahead of the guest, through the opening, for a guest
## whose sides are walled off) and one from the side away from the hand.
const DOOR_FRAMINGS: Array[Vector3] = [
	Vector3(1.0, 3.4, 0.8),
	Vector3(0.3, 4.0, 0.4),
	Vector3(1.6, 2.8, -1.4),
	Vector3(2.2, 1.9, 1.2),
	Vector3(1.4, 4.8, 1.2),
	Vector3(0.6, 5.6, 0.6),
	Vector3(0.0, 3.0, 2.6),
	Vector3(0.5, 3.0, -2.6),
	Vector3(-1.0, 3.4, 0.8),
]
## The most a sight line to the grip may land from it on the guest: the hand's
## own surface, not the torso or an arm in front of it.
const HAND_NEAR_M := 0.2
const HAND_SPREAD_M := 0.06
const AIM_BODY := 0.7
const AIM_UP_M := 0.9
## The jet bridge's folded box (jet_bridge_pose.gd shows it when the bridge is
## folded). It stands outside the terminal wall and is hidden for a plate, as
## the plate's camera can sit on its side of the wall.
const FOLD_CAP := "Fold_Cap"

var _doors: Array[Vector3] = []
var _door := Vector3.INF
var _taken := 0
var _bag: Node3D = null
var _control_done := false
var _control_bad := ""


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
		# A left-hand pull (the side the rods met the legs on before the tuck
		# was measured from the hips).
		var wanted := CarryLead.hand_of(int(state.get("place", 0))) == _arg("strip-hand", LEFT)
		if props.transfer_progress(p.id, i) < 1.0 or not wanted:
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
	if problem.begins_with(STRIP_UNFRAMED):
		print("DOOR_STRIP skipped %s" % problem.trim_prefix(STRIP_UNFRAMED))
		problem = ""
	if problem != "":
		problems.append(problem)
	if _taken >= PLATES or problem.contains(BODY):
		done = true
		if saved.size() < STRIP_MIN_SAVED:
			problems.append(
				(
					"%d of %d plates saved, at least %d wanted"
					% [saved.size(), _taken, STRIP_MIN_SAVED]
				)
			)
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
	var dir := ProjectSettings.globalize_path(_out_rel()).simplify_path()
	sheet.save_png(dir.path_join("door_tuck_sheet_hand%d.png" % _arg("strip-hand", LEFT)))
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


## PullSwapStrip's _aim() with the aim point nearer the guest's chest than the
## bag (AIM_BODY of the way, not 0.4): the roller is pulled behind a guest in a
## doorway, and the lower aim let the head leave the top of the frame.
func _aim(cam: Camera3D, shell: MeshInstance3D, body: Node3D, place: int, framing: Vector3) -> void:
	var centre := shell.global_transform * shell.get_aabb().get_center()
	var turn := Basis(Vector3.UP, body.rotation.y)
	var side := turn * (Vector3.LEFT if CarryLead.hand_of(place) == 0 else Vector3.RIGHT)
	var behind := turn * Vector3.FORWARD
	var look_at := centre.lerp(body.global_position + Vector3.UP * AIM_UP_M, AIM_BODY)
	cam.look_at_from_position(
		look_at + side * framing.x + Vector3.UP * framing.y + behind * framing.z,
		look_at,
		Vector3.UP
	)
	cam.current = true


## PullSwapStrip's checks, then the pulling hand's: a sight line from the camera
## to the grip must meet no mesh but the roller's own (the bar the hand holds)
## and, when it lands on the guest, land within HAND_NEAR_M of the grip (a line
## that lands on the torso first has the hand behind the body). The plate that
## passed with the hand behind a door lintel (board e4be6104) failed neither
## the bag's nor the guest's lines. Control, once per run, on the first view
## that passes the rest: the same check on a point 0.4 m behind the guest's
## chest (the torso is in front of it) must fail, or the check is not engaged;
## the plates' own hand_gap (within HAND_NEAR_M) is the positive.
func _judge(
	cam: Camera3D,
	main: Node3D,
	props: CarryOnProps,
	shell: MeshInstance3D,
	body: Node3D,
	state: Dictionary
) -> Dictionary:
	var verdict := super._judge(cam, main, props, shell, body, state)
	var grip := props.grip_of(body, maxi(int(state.get("held_by", -1)), 0))
	var space := main.get_world_3d().direct_space_state
	var hand := _hand_seen(space, cam.global_position, grip)
	verdict["report"] += " hand_gap=%.2f hand_blocked=%s" % [hand["gap"], hand["blockers"]]
	if _control_bad != "":
		verdict["bad"] = _control_bad
	elif (verdict["bad"] as String) == "" and not hand["ok"]:
		verdict["bad"] = (
			"hand not seen: first hit %.2f m from the grip, blocked %s"
			% [hand["gap"], hand["blockers"]]
		)
	if (verdict["bad"] as String) == "" and not _control_done:
		_control_done = true
		var away := (body.global_position - cam.global_position) * Vector3(1.0, 0.0, 1.0)
		var hidden := body.global_position + Vector3.UP * 1.3 + away.normalized() * 0.4
		var control := _hand_seen(space, cam.global_position, hidden)
		print(
			(
				"DOOR_STRIP hand control ok=%s gap=%.2f %s"
				% [control["ok"], control["gap"], control["blockers"]]
			)
		)
		if control["ok"]:
			_control_bad = "hand control: the check passed a point 0.4 m behind the guest's chest"
			verdict["bad"] = _control_bad
	return verdict


## {ok, gap, blockers} of five sight lines from `from`, to the grip and to four
## points HAND_SPREAD_M around it across the view (the grip point can sit just
## outside the hand's mesh, so a line to it alone passes the hand): the roller's
## own meshes are not blockers, `gap` is how near the grip any line lands on the
## guest (INF when none does), and a hand is seen when one lands within
## HAND_NEAR_M with no other mesh in front of any line.
func _hand_seen(space: PhysicsDirectSpaceState3D, from: Vector3, grip: Vector3) -> Dictionary:
	var dir := (grip - from).normalized()
	var right := dir.cross(Vector3.UP).normalized() * HAND_SPREAD_M
	var up := right.cross(dir).normalized() * HAND_SPREAD_M
	var targets: Array[Vector3] = [grip, grip + right, grip - right, grip + up, grip - up]
	var lines := PlateSight.sight_lines(space, from, targets, GUEST_TAG)
	var own := {}
	if _bag != null:
		for mi in _bag.find_children("*", "MeshInstance3D", true, false):
			own[String(mi.name)] = true
	var blockers: Array[String] = []
	for name: String in lines["blockers"]:
		if not own.has(name):
			blockers.append(name)
	var landed: Array[Vector3] = lines["on_subject"]
	var gap := INF
	for at in landed:
		gap = minf(gap, at.distance_to(grip))
	return {"ok": blockers.is_empty() and gap <= HAND_NEAR_M, "gap": gap, "blockers": blockers}


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
	_bag = bag
	var place := int(state.get("place", -1))
	var name := "door_tuck_hand%d_id%d_%02d" % [CarryLead.hand_of(place), p.id, _taken]
	var was_cam := main.get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	var caps: Array[Node3D] = []
	for cap in main.find_children(FOLD_CAP, "Node3D", true, false):
		if (cap as Node3D).visible:
			(cap as Node3D).visible = false
			caps.append(cap as Node3D)
	var holder := PlateSight.colliders(main, [main] as Array[Node], {shell: TAG, body: GUEST_TAG})
	await tree.physics_frame
	var picked := -1
	var verdict := {}
	var why: Array[String] = []
	for f in DOOR_FRAMINGS.size():
		_aim(cam, shell, body, place, DOOR_FRAMINGS[f])
		verdict = _judge(cam, main, props, shell, body, state)
		if (verdict["bad"] as String) == "":
			picked = f
			break
		why.append("f%d %s" % [f, verdict["bad"]])
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
	for cap in caps:
		cap.visible = true
	holder.queue_free()
	cam.queue_free()
	if was_cam != null:
		was_cam.make_current()
	if picked < 0:
		return "%s%s: %s" % [STRIP_UNFRAMED, name, " | ".join(why)]
	if (verdict["bad"] as String) != "":
		return "%s: %s" % [name, verdict["bad"]]
	saved.append(img)
	var dir := ProjectSettings.globalize_path(_out_rel()).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		return "%s: not saved to %s" % [name, path]
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	return ""


## The integer user argument `--<key>=N`, or `fallback`.
static func _arg(key: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return int(arg.get_slice("=", 1))
	return fallback


## Where the plates go: `--strip-out=<res path>`, or DOOR_OUT_REL.
static func _out_rel() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--strip-out="):
			return arg.get_slice("=", 1)
	return DOOR_OUT_REL
