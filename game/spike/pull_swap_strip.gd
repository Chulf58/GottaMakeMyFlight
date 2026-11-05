extends RefCounted
## A strip of plates of a pulled roller changing hands at the west wall
## (board 578435a7, PullSide), for roller_trail_probe.gd in a windowed run. The
## first guest seen walking along the west wall (in column WEST_X or the one
## before it, the wall on column 10's west edge; headless, its changes of hand
## start in column 11) with
## its roller in a move from one pull to the other is plated every
## EVERY_FRAMES frames through the move and AFTER_FRAMES
## frames after it, from the side the roller goes to, above and behind. Each
## plate is saved only when the bag body's middle, the holding hand, the feet
## and the head project inside the viewport by MARGIN_PX, and at least MIN_ON
## of the sight lines to the bag body (PlateSight, the bag body mesh tagged on
## its own, not the rods) land on it with none blocked. Otherwise a problem is
## listed and the caller fails the run, as it does when the bag has no BODY
## mesh (the strip then ends). Each plate prints the hand the bag is
## drawn in, the hand holding it and the bar's distance to that hand's grip.
## Load with preload(); no class_name.

const PlateSight := preload("res://spike/plate_sight.gd")
const WEST_X := 11
const EVERY_FRAMES := 3
const AFTER_FRAMES := 6
const MARGIN_PX := 8.0
const MIN_ON := 2
const TAG := "bag"
const OUT_REL := "res://../tools/blender/out/pull-side"
## The roller piece's shell (carry_roller.glb), the bag body the plates show.
const BODY := "CarryRoller_Body"

var saved: Array[Image] = []
var problems: Array[String] = []
var done := false
var _id := -1
var _frame := 0
var _after := -1


## One frame of guest `p` (its drawn `body`, roller node `bag`, record copy
## `state`) of the windowed run of `tree` under `main`: starts the strip on the
## first change of hand at the west wall, then plates its guest. `views` draws it.
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
			done = true
	_frame += 1
	if (_frame - 1) % EVERY_FRAMES != 0 and not done:
		return
	var k := props.transfer_progress(p.id, i)
	await _plate(tree, main, props, p, body, bag, state, k, place)


func _plate(
	tree: SceneTree,
	main: Node3D,
	props: CarryOnProps,
	p: Passenger,
	body: Node3D,
	bag: Node3D,
	state: Dictionary,
	k: float,
	place: int
) -> void:
	var shell := bag.find_child(BODY, true, false) as MeshInstance3D
	if shell == null:
		problems.append("id %d: no %s mesh on the roller %s" % [p.id, BODY, bag.name])
		done = true
		return
	var centre := shell.global_transform * shell.get_aabb().get_center()
	var out := CarryLead.hand_of(place)
	var turn := Basis(Vector3.UP, body.rotation.y)
	var side := turn * (Vector3.LEFT if out == 0 else Vector3.RIGHT)
	var behind := turn * Vector3.FORWARD
	var was_cam := main.get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	var look_at := centre.lerp(body.global_position + Vector3.UP * 0.8, 0.4)
	cam.look_at_from_position(
		look_at + side * 2.2 + behind * 1.2 + Vector3.UP * 1.9, look_at, Vector3.UP
	)
	cam.current = true
	var holder := PlateSight.colliders(main, [main] as Array[Node], {shell: TAG})
	for n in 3:
		await tree.process_frame
	await tree.physics_frame
	var img := main.get_viewport().get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var holding := int(state.get("held_by", -1))
	var grip := props.grip_of(body, maxi(holding, 0))
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
	var top := bag.find_child("Pull_Top", true, false) as Node3D
	var bar := top.global_transform * Vector3(0.0, 0.0, CarryOnProps.ROLLER_GRIP_PAST_TOP_M)
	var name := "pull_swap_id%d_%02d" % [p.id, saved.size()]
	print(
		(
			(
				"PULL_STRIP %s id=%d k=%.2f drawn_hand=%d held_by=%d bar_gap_m=%.3f px=%s"
				+ " sight_on=%d of %d blocked=%s"
			)
			% [
				name,
				p.id,
				k,
				out,
				holding,
				bar.distance_to(grip),
				flat,
				on,
				targets.size(),
				lines["blockers"]
			]
		)
	)
	holder.queue_free()
	cam.queue_free()
	if was_cam != null:
		was_cam.make_current()
	if not missing.is_empty() or on < MIN_ON or not (lines["blockers"] as Array).is_empty():
		problems.append(
			"%s: out of frame %s, sight_on %d, blocked %s" % [name, missing, on, lines["blockers"]]
		)
		return
	saved.append(img)
	var dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		problems.append("%s: not saved to %s" % [name, path])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
