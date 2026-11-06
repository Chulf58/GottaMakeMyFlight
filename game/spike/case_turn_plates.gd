class_name CaseTurnPlates
extends RefCounted
## Close plates of a hard case in the hand part way through its turn from the
## side carry to the front carry (CaseTurn, board a82c613f), for the booth
## crossing probe (basic_scanner_crossing_probe.gd calls scan() first on each
## sim tick). With `--case-turn-plate=<passenger id>` the probe plates that
## passenger's first turn to the front, when the case has turned TURN_LO to
## TURN_HI of the way, from each side of the body at SIDE_M, the sim clock
## paused. The turn lasts a few ticks, so once that passenger walks to security
## with a case in hand and no other plate runs, the plate task is held for it
## (no other plate starts) until the turn. `--case-turn-tag=<name>` names the
## plates (case_turn_<tag>_<side>), so a run with the fix switched off can be
## told apart. Each plate is kept only when the body's and the case's drawn
## bounds project inside the frame, the body is shown (PlateSight.person_shown:
## sight lines land on it, none blocked) and the case is seen (probe._bag_seen);
## a side tries SIDE_TURNS about the side before it gives up. A side with no
## plate, or a target passenger past security never plated, prints PROBE_INVALID.

enum State { IDLE, HELD, DONE }

const PlateSight := preload("res://spike/plate_sight.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const TURN_LO := 0.3
const TURN_HI := 0.6
const SIDE_M := 3.0
const HEIGHT_M := 1.2
const AIM_M := 1.0
const MIN_PX := 300.0
const SIDE_TURNS := [0.0, -PI / 8.0, PI / 8.0, -PI / 4.0, PI / 4.0]

static var _target := -2
static var _tag := ""
static var _state := State.IDLE


## Called first on each sim tick. Holds the plate task for the target passenger
## once it walks to security with a case in hand and no other plate runs; when its
## case is part way through its turn to the front, pauses the clock and starts
## the plates. Returns whether it holds the plate task (the tick's other plate
## checks are then skipped).
static func scan(probe) -> bool:
	if _target == -2:
		_target = -1
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--case-turn-plate="):
				_target = int(arg.get_slice("=", 1))
			elif arg.begins_with("--case-turn-tag="):
				_tag = arg.get_slice("=", 1)
		print("CASE_TURN_PLATE target=%d tag=%s" % [_target, _tag])
	if _target < 0 or _state == State.DONE:
		return false
	var sim: PassengerSim = probe._sim
	var p := sim.get_passenger(_target)
	if p == null:
		return false
	if p.stage > Passenger.Stage.SECURITY:
		_state = State.DONE
		probe._plate_task = false
		probe._invalid("passenger %d left security with no case turn plate" % _target)
		return false
	var props: CarryOnProps = probe._views.carry_on_props()
	var kinds: Array = props.props_of(_target)["kinds"]
	var homes := SecurityLooks.bag_homes(sim, p)
	var case := -1
	for i in kinds.size():
		if kinds[i] == SecurityLooks.Kind.CASE and homes[i] == SecurityLooks.Home.HAND:
			case = i
	if _state == State.IDLE:
		if p.stage < Passenger.Stage.TO_SECURITY or case < 0:
			return false
		if probe._plate_task or probe._hold_frame >= 0:
			return false
		_state = State.HELD
		probe._plate_task = true
		print("CASE_TURN_PLATE held for passenger %d at tick %d" % [_target, probe._clock.tick])
	var turn := props.bag_turn_of(_target)
	if case >= 0 and turn >= TURN_LO and turn <= TURN_HI and SecurityLooks.carry_front(sim, p):
		_state = State.DONE
		probe._clock.set_paused(true)
		probe._clock._accumulator = 0.0
		_plate(probe, case)
	return true


## The two side plates of bag `i` of the target passenger, the clock paused.
static func _plate(probe, i: int) -> void:
	await probe._frames(1)
	var props: CarryOnProps = probe._views.carry_on_props()
	var body: Node3D = probe._views.node_for(_target)
	var bag: Node3D = props.props_of(_target)["bags"][i]
	var turn := props.bag_turn_of(_target)
	var to_body := body.global_transform.affine_inverse()
	print(
		(
			"CASE_TURN_PLATE passenger=%d bag=%d turn=%.2f tick=%d body_at=%s bag_at=%s"
			% [
				_target,
				i,
				turn,
				probe._clock.tick,
				body.global_position,
				to_body * bag.global_position
			]
		)
	)
	if turn < TURN_LO or turn > TURN_HI:
		probe._invalid("case turn plate drawn at turn %.2f, outside the window" % turn)
	else:
		for side in [["left", PI / 2.0], ["right", -PI / 2.0]]:
			if not await _side(probe, body, bag, side[0], side[1]):
				probe._invalid("no case turn plate from the %s" % side[0])
	probe._clock.set_paused(false)
	probe._plate_task = false


## One plate of `body` and `bag` from the body's side `yaw_off` (PI / 2 its
## left), the HUD hidden; tries SIDE_TURNS about that side. Returns whether
## one was saved.
static func _side(probe, body: Node3D, bag: Node3D, side: String, yaw_off: float) -> bool:
	var root: Window = probe.root
	var main: Node3D = probe._main
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
	var owners: Array[Node] = [probe._views]
	for path in ["Airside/Terminal", "BuildMode", "StaffCharacters", "BaggageViews"]:
		owners.append(main.get_node(path))
	var margin := Vector2.ONE * 8.0
	var frame := Rect2(margin, root.get_visible_rect().size - margin * 2.0)
	var saved := false
	for turn_off: float in SIDE_TURNS:
		var yaw := body.global_rotation.y + yaw_off + turn_off
		var out := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, SIDE_M)
		cam.global_position = body.global_position + out + Vector3.UP * HEIGHT_M
		cam.look_at(body.global_position + Vector3.UP * AIM_M)
		await probe._frames(2)
		var img := root.get_texture().get_image()
		var holder := PlateSight.colliders(root, owners, {body: "subject", bag: "bag"})
		PlateSteps.see_both_sides(holder)
		await probe.physics_frame
		await probe.physics_frame
		var bounds: Dictionary = holder.get_meta("bounds")
		var tag := "case_turn %s %s off=%.2f" % [_tag, side, turn_off]
		var ok := (holder.get_meta("unbaked") as Array).is_empty()
		ok = ok and bounds.has("subject") and bounds.has("bag")
		if ok:
			ok = probe._box_in_frame(cam, bounds["subject"], frame, tag + " body")
			ok = probe._box_in_frame(cam, bounds["bag"], frame, tag + " bag") and ok
			var shown := PlateSight.person_shown(
				cam, bounds["subject"], "subject", frame, img, img, MIN_PX
			)
			print("INFRAME %s person=%s" % [tag, shown])
			ok = ok and shown["ok"] and probe._bag_seen(cam, bounds["bag"], tag)
		else:
			print("INFRAME %s no bounds or unbaked: %s" % [tag, holder.get_meta("unbaked")])
		holder.free()
		if ok:
			var path: String = probe._close_dir.path_join("case_turn_%s_%s.png" % [_tag, side])
			saved = img.save_png(path) == OK
			print("PLATE saved=%s %s size=%s" % [saved, path, img.get_size()])
			break
	probe._cam.make_current()
	cam.queue_free()
	for layer in layers:
		layer.visible = true
	await probe._frames(1)
	return saved
