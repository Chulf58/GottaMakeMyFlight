class_name PutinSweep
extends RefCounted
## A first-pass lane passenger's unpack and put-in, swept finely for the booth
## crossing probe (basic_scanner_crossing_probe.gd --lane calls scan() first on
## each sim tick). With `--sweep=<passenger id>` the probe holds the clock on the
## tick that passenger is first at UNPACK, then steps it STEP_TICKS at a time, a
## frame drawn after each, to the end of its last move into the tray, printing
## each step's gap from each bag to the arch's left and right side parts
## (side_gaps()) and its points inside the arch's meshes (SWEEP lines), then
## each bag's smallest left gap (SWEEP_MIN). Board item H (c2bb3bc0): a roller
## put into the tray swept through the arch's left post.
##
## At each of SHOT_K of a put-in, and on the first step a bag is inside the
## arch, the bag is plated from a camera fixed in the arch's frame (CAM_LOCAL,
## looking at AIM_LOCAL), the other passengers hidden: a frame strip. A plate
## is kept only when the bag's drawn bounds and the lower part of the post on
## its side project inside the frame, at least two sight lines land on the bag
## (probe._bag_seen) and a sight line reaches the post's front face; otherwise
## PROBE_INVALID. `--sweep-tag=<name>` names the plates
## (sweep_<tag>_p<id>_b<bag>_<n>_k<k>.png under tools/blender/out/h/).

enum State { IDLE, HELD, DONE }

const PlateSight := preload("res://spike/plate_sight.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const OUT_REL := "res://../tools/blender/out/h"
const STEP_TICKS := 0.1
const SHOT_K := [0.1, 0.3, 0.5, 0.7, 0.9]
## The camera and its aim in the arch's frame (x across, the tray table at -x;
## z along, the entry at +z): high over the entry side and the tray table's
## side, looking at the left post's front and the tray.
const CAM_LOCAL := Vector3(-1.5, 2.4, 2.3)
const AIM_LOCAL := Vector3(-0.55, 0.55, 0.4)
## The left post's lower part and points on its front and outer faces (arch
## frame), framed and sighted on each plate; mirrored for a bag at x > 0, the
## camera too (the right post).
const POST_LOW := AABB(Vector3(-0.42, 0.0, -0.30), Vector3(0.04, 1.2, 0.60))
const POST_FACE := [
	Vector3(-0.405, 0.2, 0.301),
	Vector3(-0.405, 0.5, 0.301),
	Vector3(-0.405, 0.8, 0.301),
	Vector3(-0.405, 1.1, 0.301),
	Vector3(-0.421, 0.4, 0.15),
	Vector3(-0.421, 0.9, 0.15),
]

static var _target := -2
static var _tag := "run"
static var _state := State.IDLE


## The smallest gap of `points` (world) to the arch's side parts' bounds:
## [left (x < 0), right (x > 0)], negative when that deep inside the bounds.
## `booth` is the probe's booth record ([node, to_booth, parts, ...]).
static func side_gaps(points: PackedVector3Array, booth: Array) -> Array:
	var gaps := [INF, INF]
	var to_arch: Transform3D = booth[1]
	for pt in points:
		var lp := to_arch * pt
		for part in booth[2]:
			var box: AABB = part[1]
			if box.position.x <= 0.0 and box.end.x >= 0.0:
				continue
			var d := (box.position - lp).max(lp - box.end)
			var gap := d.max(Vector3.ZERO).length()
			if d.x <= 0.0 and d.y <= 0.0 and d.z <= 0.0:
				gap = maxf(d.x, maxf(d.y, d.z))
			var side := 0 if box.end.x < 0.0 else 1
			gaps[side] = minf(gaps[side], gap)
	return gaps


## Called first on each sim tick. Once the target, on its first pass, is at
## UNPACK and no other plate runs, holds the plate task and sweeps it (_sweep).
## Returns whether it holds the plate task.
static func scan(probe) -> bool:
	if _target == -2:
		_target = -1
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--sweep="):
				_target = int(arg.get_slice("=", 1))
			elif arg.begins_with("--sweep-tag="):
				_tag = arg.get_slice("=", 1)
		print("SWEEP target=%d tag=%s" % [_target, _tag])
	if _target < 0 or _state == State.DONE:
		return false
	if _state == State.HELD:
		return true
	var p: Passenger = probe._sim.get_passenger(_target)
	if p == null or p.incident_resolved or probe._plate_task or probe._hold_frame >= 0:
		return false
	if p.stage != Passenger.Stage.SECURITY or p.security_phase != SecurityRuntime.Phase.UNPACK:
		return false
	_state = State.HELD
	probe._plate_task = true
	probe._clock.set_paused(true)
	probe._clock._accumulator = 0.0
	print("SWEEP held passenger=%d tick=%d" % [_target, probe._clock.tick])
	_sweep.call_deferred(probe)
	return true


## Steps the target from the start of its UNPACK to the end of its last move
## into the tray, printing each bag's step and plating each put-in at SHOT_K
## (and the first step any bag is inside the arch); lets the clock and the
## plate task go.
static func _sweep(probe) -> void:
	var clock: SimClock = probe._clock
	var props: CarryOnProps = probe._views.carry_on_props()
	var booth: Array = probe._booths[0]
	var to_arch: Transform3D = booth[1]
	var hidden: Array[Node3D] = probe._hide_others(_target)
	var lows := {}
	var shots := {}
	var steps := 0
	var clip_plated := false
	await probe._frames(1)
	for _step in 400:
		var body: Node3D = probe._views.node_for(_target)
		var p: Passenger = probe._sim.get_passenger(_target)
		if body == null or p == null:
			probe._invalid("swept passenger %d is not drawn" % _target)
			break
		var bags: Array = props.props_of(_target)["bags"]
		var drawn: float = clock.tick + clock._accumulator / SimClock.STEP
		var yaw := (to_arch.basis * body.global_basis).get_euler().y
		var moving := false
		steps += 1
		for i in bags.size():
			var bag: Node3D = bags[i]
			if not bag.is_visible_in_tree():
				continue
			var k := props.transfer_progress(_target, i)
			var move := FloatCheck.move_of(props, _target, i)
			moving = moving or move.ends_with(">tray")
			var surface := CarryChecks.surface(bag)
			var gaps := side_gaps(surface, booth)
			var hits: int = probe._contacts(surface, booth)
			var low: Array = lows.get(i, [INF, -1.0, 0.0, ""])
			if gaps[0] < low[0]:
				low = [gaps[0], k, drawn, move]
			lows[i] = low
			print(
				(
					(
						"SWEEP passenger=%d bag=%d move=%s k=%.3f sim=%.2f phase=%d contacts=%d"
						+ " left_gap=%+.3f right_gap=%+.3f bag_at=%s body_at=%s yaw=%+.3f"
					)
					% [
						_target,
						i,
						move if move != "" else "none",
						k,
						drawn,
						p.security_phase,
						hits,
						gaps[0],
						gaps[1],
						(to_arch * bag.global_position).snapped(Vector3.ONE * 0.01),
						(to_arch * body.global_position).snapped(Vector3.ONE * 0.01),
						yaw
					]
				)
			)
			if hits > 0 and not clip_plated:
				clip_plated = true
				if not await _plate(probe, body, bag, i, "clip", k):
					probe._invalid("sweep clip plate of passenger %d not framed" % _target)
			var shot: int = shots.get(i, 0)
			while shot < SHOT_K.size() and k >= SHOT_K[shot] and move.ends_with(">tray"):
				if not await _plate(probe, body, bag, i, str(shot), k):
					probe._invalid("sweep plate %d of passenger %d not framed" % [shot, _target])
				shot += 1
			shots[i] = shot
		var unpacking := p.security_phase == SecurityRuntime.Phase.UNPACK
		if not unpacking and not moving:
			break
		PlateSteps.step_clock(clock, STEP_TICKS)
		await probe._frames(1)
	for i: int in lows:
		print(
			(
				"SWEEP_MIN passenger=%d bag=%d left_gap=%+.3f at k=%.3f sim=%.2f move=%s plates=%d"
				% [_target, i, lows[i][0], lows[i][1], lows[i][2], lows[i][3], shots.get(i, 0)]
			)
		)
	print("SWEEP_DONE passenger=%d steps=%d clip_plate=%s" % [_target, steps, clip_plated])
	if steps < 10 or shots.values().max() == 0:
		probe._invalid("sweep of passenger %d: %d steps, no put-in plated" % [_target, steps])
	for node in hidden:
		node.visible = true
	_state = State.DONE
	clock.set_paused(false)
	probe._plate_task = false


## One plate of the put-in from the camera fixed in the arch's frame, the HUD
## hidden. Returns whether it was saved.
static func _plate(probe, body: Node3D, bag: Node3D, i: int, n: String, k: float) -> bool:
	var root: Window = probe.root
	var main: Node3D = probe._main
	var to_arch: Transform3D = probe._booths[0][1]
	# The camera and the post on the bag's side of the arch (mirrored for x > 0).
	var mirror := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	var right := (to_arch * bag.global_position).x > 0.0
	var to_world := (
		to_arch.affine_inverse() * Transform3D(mirror if right else Basis(), Vector3.ZERO)
	)
	var layers: Array[CanvasLayer] = []
	for node in main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			layers.append(layer)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.make_current()
	cam.global_position = to_world * CAM_LOCAL
	cam.look_at(to_world * AIM_LOCAL)
	await probe._frames(2)
	var img := root.get_texture().get_image()
	var owners: Array[Node] = [probe._views]
	for path in ["Airside/Terminal", "BuildMode", "StaffCharacters", "BaggageViews"]:
		owners.append(main.get_node(path))
	var holder := PlateSight.colliders(root, owners, {body: "subject", bag: "bag"})
	PlateSteps.see_both_sides(holder)
	await probe.physics_frame
	await probe.physics_frame
	var margin := Vector2.ONE * 8.0
	var frame := Rect2(margin, root.get_visible_rect().size - margin * 2.0)
	var bounds: Dictionary = holder.get_meta("bounds")
	var tag := "sweep %s p%d b%d n%s k%.2f" % [_tag, _target, i, n, k]
	var ok := (holder.get_meta("unbaked") as Array).is_empty() and bounds.has("bag")
	if ok:
		ok = probe._box_in_frame(cam, bounds["bag"], frame, tag + " bag")
		ok = probe._box_in_frame(cam, to_world * POST_LOW, frame, tag + " post") and ok
		ok = probe._bag_seen(cam, bag, tag) and ok
		ok = _post_seen(cam, to_world, tag) and ok
	else:
		print("INFRAME %s no bag bounds or unbaked: %s" % [tag, holder.get_meta("unbaked")])
	holder.free()
	var saved := false
	if ok:
		var dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
		DirAccess.make_dir_recursive_absolute(dir)
		var name := "sweep_%s_p%d_b%d_%s_k%03d.png" % [_tag, _target, i, n, roundi(k * 100.0)]
		saved = img.save_png(dir.path_join(name)) == OK
		print("PLATE saved=%s %s size=%s" % [saved, dir.path_join(name), img.get_size()])
	probe._cam.make_current()
	cam.queue_free()
	for layer in layers:
		layer.visible = true
	await probe._frames(1)
	return saved


## Whether a sight line from `cam` reaches one of the left post's front-face
## points (POST_FACE) with nothing hit more than 3 cm before it.
static func _post_seen(cam: Camera3D, to_world: Transform3D, tag: String) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var reached := 0
	for local: Vector3 in POST_FACE:
		var at := to_world * local
		var to := at + (at - cam.global_position).normalized() * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, to))
		var short := INF
		if not hit.is_empty():
			short = (
				cam.global_position.distance_to(at) - cam.global_position.distance_to(hit.position)
			)
		if absf(short) < 0.03:
			reached += 1
		print("INFRAME %s post_point=%s hit_short_m=%.3f" % [tag, local, short])
	return reached >= 1
