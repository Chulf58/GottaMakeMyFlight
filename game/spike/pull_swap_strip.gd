extends RefCounted
## A strip of plates of a pulled roller changing hands at the west wall
## (board 578435a7, PullSide), for roller_trail_probe.gd in a windowed run. The
## first guest seen walking along the west wall (in column WEST_X or the one
## before it, the wall on column 10's west edge; headless, its changes of hand
## start in column 11) with
## its roller in a move from one pull to the other is plated every
## EVERY_FRAMES frames through the move and AFTER_FRAMES
## frames after it. Each plate is taken from the first of FRAMINGS that passes
## (high and steep, so the seat rows do not stand between the camera and the
## guest; the camera is on the side the roller goes to, behind the guest, or
## in front of it for the last one) and is saved only when the bag body's
## middle, the holding hand, the feet and the head project inside the viewport
## by MARGIN_PX, at least MIN_ON of the sight lines to the bag body (PlateSight,
## the bag body mesh tagged on its own, not the rods) land on it with none
## blocked, and at least MIN_ON of the lines to the guest's chest, hip and head
## land on the guest. Otherwise a problem is listed and the caller fails the
## run, as it does when the bag has no BODY mesh (the strip then ends). After
## the strip, one plate of a second hand change by another guest, anywhere, is
## taken under the same checks (SECOND_TRIES looks at most); `done` is true
## when both are in. Each plate prints the framing, the hand the bag is drawn
## in, the hand holding it and the bar's distance to that hand's grip.
## Load with preload(); no class_name.

const PlateSight := preload("res://spike/plate_sight.gd")
const WEST_X := 11
const EVERY_FRAMES := 3
const AFTER_FRAMES := 6
const MARGIN_PX := 8.0
const MIN_ON := 2
const TAG := "bag"
const GUEST_TAG := "guest"
const OUT_REL := "res://../tools/blender/out/pull-side"
## The roller piece's shell (carry_roller.glb), the bag body the plates show.
const BODY := "CarryRoller_Body"
## Camera offsets from the aim point: x toward the side the roller goes to, y up,
## z behind the guest (negative: in front of it).
const FRAMINGS: Array[Vector3] = [
	Vector3(1.0, 3.4, 0.8),
	Vector3(0.3, 4.0, 0.4),
	Vector3(1.6, 2.8, -1.4),
	Vector3(2.2, 1.9, 1.2),
]
## Looks at a second guest's change of hand before the strip gives up on it.
const SECOND_TRIES := 30

var saved: Array[Image] = []
var problems: Array[String] = []
var done := false
var second_saved := false
var _id := -1
var _frame := 0
var _after := -1
var _first_done := false
var _second_tries := 0


## One frame of guest `p` (its drawn `body`, roller node `bag`, record copy
## `state`) of the windowed run of `tree` under `main`: starts the strip on the
## first change of hand at the west wall, then plates its guest; once that is
## done, plates the first change of hand of another guest. `views` draws it.
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
	var place := int(state.get("place", -1))
	var was := int(state.get("was", -1))
	var swapping: bool = (
		props.transfer_progress(p.id, i) < 1.0
		and was >= 0
		and was / 4 == SecurityLooks.Home.HAND
		and place / 4 == SecurityLooks.Home.HAND
		and CarryLead.hand_of(was) != CarryLead.hand_of(place)
	)
	if _first_done:
		if swapping and p.id != _id:
			await _look_second(tree, main, props, p, body, bag, state)
		return
	if _id < 0:
		if not swapping or p.at.x > WEST_X:
			return
		_id = p.id
		print("PULL_STRIP start id=%d cell=%s place %d -> %d" % [p.id, p.at, was, place])
	if p.id != _id:
		return
	if not swapping and _after < 0:
		_after = AFTER_FRAMES
	if _after >= 0:
		_after -= 1
		if _after < 0:
			_first_done = true
			done = second_saved
	_frame += 1
	if (_frame - 1) % EVERY_FRAMES != 0 and not _first_done:
		return
	var k := props.transfer_progress(p.id, i)
	var problem: String = await _plate(
		tree, main, props, p, body, bag, state, k, place, saved.size()
	)
	if problem != "":
		problems.append(problem)
		if problem.contains(BODY):
			_first_done = true
			done = second_saved


## A look at a second guest's change of hand: one plate of it, kept when the
## checks pass; after SECOND_TRIES looks without one, a problem is listed.
func _look_second(
	tree: SceneTree,
	main: Node3D,
	props: CarryOnProps,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	state: Dictionary
) -> void:
	var k := props.transfer_progress(p.id, props.props_of(p.id)["bags"].find(bag))
	if k < 0.25 or k > 0.75:
		return
	print("PULL_STRIP second id=%d cell=%s" % [p.id, p.at])
	var place := int(state.get("place", -1))
	var problem: String = await _plate(tree, main, props, p, body, bag, state, k, place, 90)
	_second_tries += 1
	if problem == "":
		second_saved = true
		done = true
	elif _second_tries >= SECOND_TRIES:
		problems.append("second swap: %d looks, none plated, last: %s" % [_second_tries, problem])
		done = true


## One plate: returns "" when saved, else what failed.
func _plate(
	tree: SceneTree,
	main: Node3D,
	props: CarryOnProps,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	state: Dictionary,
	k: float,
	place: int,
	number: int
) -> String:
	var shell := bag.find_child(BODY, true, false) as MeshInstance3D
	if shell == null:
		return "id %d: no %s mesh on the roller %s" % [p.id, BODY, bag.name]
	var name := "pull_swap_id%d_%02d" % [p.id, number]
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
	var bar := _bar(bag)
	var grip := props.grip_of(body, maxi(int(state.get("held_by", -1)), 0))
	print(
		(
			"PULL_STRIP %s id=%d k=%.2f framing=%d drawn_hand=%d held_by=%d bar_gap_m=%.3f %s"
			% [
				name,
				p.id,
				k,
				picked,
				CarryLead.hand_of(place),
				int(state.get("held_by", -1)),
				bar.distance_to(grip),
				verdict["report"]
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
	var dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		return "%s: not saved to %s" % [name, path]
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	return ""


## The roller's top bar, where the hand grips it.
func _bar(bag: Node3D) -> Vector3:
	var top := bag.find_child("Pull_Top", true, false) as Node3D
	return top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)


## Put `cam` at `framing` (see FRAMINGS) around the guest and its roller, and
## make it the current camera.
func _aim(cam: Camera3D, shell: MeshInstance3D, body: Node3D, place: int, framing: Vector3) -> void:
	var centre := shell.global_transform * shell.get_aabb().get_center()
	var turn := Basis(Vector3.UP, body.rotation.y)
	var side := turn * (Vector3.LEFT if CarryLead.hand_of(place) == 0 else Vector3.RIGHT)
	var behind := turn * Vector3.FORWARD
	var look_at := centre.lerp(body.global_position + Vector3.UP * 0.8, 0.4)
	cam.look_at_from_position(
		look_at + side * framing.x + Vector3.UP * framing.y + behind * framing.z,
		look_at,
		Vector3.UP
	)
	cam.current = true


## The checks on `cam`'s view now: {bad: what failed ("" when none), report:
## the numbers to print}. Points are checked in the viewport's own size.
func _judge(
	cam: Camera3D,
	main: Node3D,
	props: CarryOnProps,
	shell: MeshInstance3D,
	body: Node3D,
	state: Dictionary
) -> Dictionary:
	var size := main.get_viewport().get_visible_rect().size
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var centre := shell.global_transform * shell.get_aabb().get_center()
	var grip := props.grip_of(body, maxi(int(state.get("held_by", -1)), 0))
	var points := {
		"bag": centre,
		"hand": grip,
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
	}
	var flat := {}
	var missing: Array[String] = []
	for name: String in points:
		var at := cam.unproject_position(points[name])
		flat[name] = at.round()
		if cam.is_position_behind(points[name]) or not inside.has_point(at):
			missing.append(name)
	var half := shell.get_aabb().size * 0.3
	var targets: Array[Vector3] = [centre]
	for offset in [Vector3(half.x, 0, 0), Vector3(-half.x, 0, 0), Vector3(0, half.y, 0)]:
		targets.append(shell.global_transform * (shell.get_aabb().get_center() + offset))
	var space := main.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, cam.global_position, targets, TAG)
	var on: int = (lines["on_subject"] as Array).size()
	var guest_at: Array[Vector3] = []
	for up in [1.3, 0.9, 1.65]:
		guest_at.append(body.global_position + Vector3.UP * up)
	var guest := PlateSight.sight_lines(space, cam.global_position, guest_at, GUEST_TAG)
	var guest_on: int = (guest["on_subject"] as Array).size()
	var bad := ""
	if not missing.is_empty() or on < MIN_ON or not (lines["blockers"] as Array).is_empty():
		bad = "out of frame %s, sight_on %d, blocked %s" % [missing, on, lines["blockers"]]
	elif guest_on < MIN_ON:
		bad = (
			"guest seen by %d of %d lines, blocked %s"
			% [guest_on, guest_at.size(), guest["blockers"]]
		)
	var report := (
		"px=%s sight_on=%d of %d blocked=%s guest_on=%d of %d"
		% [flat, on, targets.size(), lines["blockers"], guest_on, guest_at.size()]
	)
	return {"bad": bad, "report": report}
