extends "res://spike/roller_trail_probe.gd"
## Which RollerPark moves draw a pulled roller in a wall, and why (board
## a40fdbaf). Runs roller_trail_probe.gd as it is (same worlds, spawns, seed and
## wall boxes) and, for every wall hit frame of its PARK class, also prints the
## move's stage, where the bag is against the wall, and where the move starts
## and parks against that wall, so a hit can be told apart: the start or the
## park spot in the wall, or the bag carried with the body past it.
##
## Stages: queue (a queue stand), stand, park, lay, let_go (pull>floor), reach,
## lift, park_up, roll (carried upright with the body, RollerPark._rolling()),
## tip (floor>pull, into the pull), and after: the move is over (k 1) and the
## bag is drawn in the settled pull, but its record keeps "park" until the next
## move is stamped (CarryLead.stamp_move()), so the trail probe books it PARK.
##
## Each line PARK_HIT gives the guest's cell, the move's tick and k, the stage,
## the hit's depth, and against the wall's own frame (x along, z across, the
## wall's face at |z| = WALL_THICKNESS / 2, its ends at |x| = 0.57): the drawn
## axle, the least and most x and z of the drawn bag's box (CarryOnProps.
## bag_box()), the body, the parked axle (RollerPark.park() in the move's park
## frame) and the start's axle; then the bag's axle in the body's frame. Every
## SAMPLE_EVERY-th frame of an episode is printed. PARK_STAGES then totals hit
## frames by stage and wall, and PARK_EPISODE lists each (guest, wall) episode
## with the stages it ran through. The control: the PARK frames counted here
## equal the trail probe's PARK class frames, above 0.
##
## Run (headless; plates are the trail probe's own and need a window):
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path game -s res://spike/roller_park_walls_probe.gd -- --seed=N

const SAMPLE_EVERY := 6

var _park_frames := 0
var _by_stage := {}
var _episodes := {}


func _classify(
	world: String, p: Passenger, body: Node3D, bag: Node3D, state: Dictionary, found: Dictionary
) -> void:
	super._classify(world, p, body, bag, state, found)
	if not state.get("park", false):
		return
	_park_frames += 1
	var mesh: Dictionary = found["mesh"]
	var inv: Transform3D = mesh["inv"]
	var props := _views.carry_on_props()
	var k := props.transfer_progress(p.id, 0)
	var ticks := CarryLead.ticks_of(state)
	var stage := _move_stage(state, k)
	var key := "%s %s %s" % [world, mesh["name"], stage]
	_by_stage[key] = int(_by_stage.get(key, 0)) + 1
	var axle: Vector3 = bag.global_transform * CarryOnProps.ROLLER_AXLE
	var yawed := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var parked := _parked_axle(state, body)
	var start := _start_axle(state, body)
	var ep_key := "%s p%d %s" % [world, p.id, mesh["name"]]
	var ep: Dictionary = _episodes.get_or_add(
		ep_key, {"first": _clock.tick, "frames": 0, "stages": {}, "deep": 0.0, "cells": {}}
	)
	ep["last"] = _clock.tick
	ep["frames"] += 1
	ep["stages"][stage] = int(ep["stages"].get(stage, 0)) + 1
	ep["deep"] = maxf(float(ep["deep"]), float(found["depth"]))
	ep["cells"]["(%d,%d)" % [p.at.x, p.at.y]] = true
	if (int(ep["frames"]) - 1) % SAMPLE_EVERY != 0:
		return
	print(
		(
			(
				"PARK_HIT %s p%d tick %d cell (%d,%d) %s stage %s k %.2f of %.1f ticks depth %.3f"
				+ " | wall frame: axle %s box x %s z %s body %s parked %s start %s"
				+ " | body frame axle %s | flags %s"
			)
			% [
				world,
				p.id,
				_clock.tick,
				p.at.x,
				p.at.y,
				mesh["name"],
				stage,
				k,
				ticks,
				found["depth"],
				_v(inv * axle),
				_span(inv * bag.global_transform, 0),
				_span(inv * bag.global_transform, 2),
				_v(inv * body.global_position),
				_v(inv * parked),
				_v(inv * start),
				_v(yawed.affine_inverse() * axle),
				_flags(state),
			]
		)
	)


func _summary(world: String) -> void:
	super._summary(world)
	var keys := _by_stage.keys()
	keys.sort()
	for key: String in keys:
		if key.begins_with(world + " "):
			print("PARK_STAGES %s x%d" % [key, _by_stage[key]])
	var eps := _episodes.keys()
	eps.sort()
	for key: String in eps:
		if not key.begins_with(world + " "):
			continue
		var ep: Dictionary = _episodes[key]
		print(
			(
				"PARK_EPISODE %s ticks %d-%d frames %d deepest %.3f stages %s cells %s"
				% [
					key,
					ep["first"],
					ep["last"],
					ep["frames"],
					ep["deep"],
					ep["stages"],
					ep["cells"].keys()
				]
			)
		)


func _print_classes() -> void:
	super._print_classes()
	var trail: int = _cls["PARK"]["frames"]
	print("PARK_CONTROL counted %d == PARK class %d, above 0" % [_park_frames, trail])
	if _park_frames != trail or _park_frames <= 0:
		_invalid("the PARK frames counted here differ from the trail probe's PARK class")


## The stage of a RollerPark move of `state` (a bag record) at `k` of its length.
static func _move_stage(state: Dictionary, k: float) -> String:
	if k >= 1.0:
		# The move is over: "park" stays on the record until the next stamp.
		return "after"
	if RollerPark.queued(state):
		return "queue"
	if CarryLead.start_of(state)[0] != CarryLead.End.REST:
		if k < RollerPark.STAND_END:
			return "stand"
		if k < RollerPark.PARK_END:
			return "park"
		return "lay" if k <= RollerPark.LAY_END else "let_go"
	var up := RollerPark.up_k(state, k)
	var took: float = state.get("park_took", -1.0)
	if took < 0.0 or up < took:
		return "reach"
	var ends := RollerPark.up_ends(state)
	if up < ends.x:
		return "lift"
	if up < ends.y:
		return "park_up"
	if RollerPark.rolls(state) and (not state.has("roll_tip") or up < float(state["roll_tip"])):
		return "roll"
	return "tip"


## The parked axle (world) of the move of `state`, as RollerPark.plan() places it.
static func _parked_axle(state: Dictionary, body: Node3D) -> Vector3:
	if not state.has("park_frame"):
		return body.global_position
	var off_floor: bool = CarryLead.start_of(state)[0] == CarryLead.End.REST
	var lead: int = CarryLead.hand_of(state["home"]) if off_floor else CarryLead.start_of(state)[1]
	var ahead := (
		RollerPark.UP_PARK_AHEAD_M
		if off_floor and not state.get("up_near", false)
		else RollerPark.PARK_AHEAD_M
	)
	var xf := RollerPark.park(state["park_frame"], lead, 1.0, ahead)
	return xf * CarryOnProps.ROLLER_AXLE


## The start's axle (world) of the move of `state`: fixed in the world for a
## floor>pull ("from_world"), else in the body's frame.
static func _start_axle(state: Dictionary, body: Node3D) -> Vector3:
	if state.has("from_world"):
		return (state["from_world"] as Transform3D) * CarryOnProps.ROLLER_AXLE
	if not state.has("from"):
		return body.global_position
	var yawed := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	return yawed * (state["from"] as Transform3D) * CarryOnProps.ROLLER_AXLE


static func _flags(state: Dictionary) -> String:
	var out: Array[String] = []
	for key in ["up_near", "rolls", "roll_tip", "park_cut", "park_took", "park_tip", "home_held"]:
		if state.has(key):
			out.append("%s=%s" % [key, str(state[key]).replace(" ", "")])
	return ",".join(out)


## The least and most of axis `axis` (0 x, 2 z) over the roller box's corners
## drawn by `xf` (in the wall's frame).
static func _span(xf: Transform3D, axis: int) -> String:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var lo := INF
	var hi := -INF
	for i in 8:
		var at := xf * box.get_endpoint(i)
		lo = minf(lo, at[axis])
		hi = maxf(hi, at[axis])
	return "[%.2f,%.2f]" % [lo, hi]


static func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
