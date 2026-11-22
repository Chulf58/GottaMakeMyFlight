class_name StaffStationPose
extends SkeletonModifier3D
## Procedural station-interaction pose modifier for on-duty staff and ramp
## marshals (ruling staff-station-interaction-poses-and-basic-scanner-scan-repac):
## layers head/neck/upper-torso look-at toward the served passenger (or taxiing
## aircraft) and role-specific arm/hand motions onto the idle clip without
## altering .glb rigs. Placed on Skeleton3D before StaffArchTuck's CarryArms;
## when inactive (weight 0 or Mode.NONE), it does nothing.

enum Mode { NONE, CHECKIN, SECURITY_SCAN, SECURITY_REPACK, SHOP, GATE, RAMP_MARSHAL }

const EASE_TICKS := 6.0
const LOOK_EASE_TICKS := 6.0
const MAX_LOOK_YAW_DEG := 38.0
const MAX_LOOK_PITCH_UP_DEG := 12.0
const MAX_LOOK_PITCH_DOWN_DEG := 18.0
const PASSENGER_EYE_M := 1.45
const STAFF_EYE_M := 1.55
const GATE_INTERACT_M := 16.0

var mode: Mode = Mode.NONE
var weight := 0.0
var sim_time := 0.0
var look_yaw_deg := 0.0
var look_pitch_deg := 0.0
var variant_seed := 0


## Eased interaction weight (0 idle, 1 active) at sim time `now`. A record whose
## turn started after `now` (e.g. a load that went back in time) reads settled.
static func weight_of(record: Dictionary, now: float) -> float:
	var target := 1.0 if record.get("active", false) else 0.0
	if not record.has("since") or now < float(record["since"]):
		return target
	var k := clampf((now - float(record["since"])) / EASE_TICKS, 0.0, 1.0)
	return lerpf(float(record["from"]), target, 1.0 - (1.0 - k) * (1.0 - k))


## Eased look-at angles (yaw, pitch in degrees) at sim time `now`.
static func look_of(record: Dictionary, now: float) -> Vector2:
	var target: Vector2 = record.get("look_target", Vector2.ZERO)
	if not record.has("look_since") or now < float(record["look_since"]):
		return target
	var k := clampf((now - float(record["look_since"])) / LOOK_EASE_TICKS, 0.0, 1.0)
	var from: Vector2 = record.get("look_from", target)
	return from.lerp(target, smoothstep(0.0, 1.0, k))


## Active mode stored on `record` (kept while easing out to 0).
static func mode_of(record: Dictionary) -> Mode:
	return int(record.get("mode", Mode.NONE)) as Mode


## Updates `record` at sim `tick`. An empty record starts settled so a first
## draw or snapped sync after a load never blends from a stale state.
static func update(record: Dictionary, new_mode: Mode, look_deg: Vector2, tick: float) -> void:
	var active_now := new_mode != Mode.NONE
	var target_look := look_deg if active_now else Vector2.ZERO
	if not record.has("active"):
		record["active"] = active_now
		record["mode"] = new_mode
		record["look_target"] = target_look
		return
	if active_now != bool(record["active"]):
		record["from"] = weight_of(record, tick)
		record["since"] = tick
		record["active"] = active_now
		if active_now:
			record["mode"] = new_mode
	elif active_now:
		record["mode"] = new_mode
	var prev_look: Vector2 = record.get("look_target", Vector2.ZERO)
	if prev_look.distance_to(target_look) > 0.5:
		record["look_from"] = look_of(record, tick)
		record["look_since"] = tick
		record["look_target"] = target_look


## Character-local look-at (yaw_deg, pitch_deg) from `staff_pos` facing
## `staff_yaw` toward `target_pos`, or Vector2.ZERO when `has_target` is false.
static func compute_look_deg(
	staff_pos: Vector3, staff_yaw: float, target_pos: Vector3, has_target: bool
) -> Vector2:
	if not has_target:
		return Vector2.ZERO
	var rel := target_pos - staff_pos
	var local := Basis(Vector3.UP, -staff_yaw) * rel
	var horiz := Vector2(local.x, local.z).length()
	var yaw := clampf(
		rad_to_deg(atan2(local.x, maxf(local.z, 0.25))), -MAX_LOOK_YAW_DEG, MAX_LOOK_YAW_DEG
	)
	var dy := target_pos.y - (staff_pos.y + STAFF_EYE_M)
	var pitch := clampf(
		rad_to_deg(atan2(-dy, maxf(horiz, 0.4))),
		-MAX_LOOK_PITCH_UP_DEG,
		MAX_LOOK_PITCH_DOWN_DEG,
	)
	return Vector2(yaw, pitch)


## Collects once per sync which stations currently serve passengers so
## StaffCharacters avoids scanning every passenger per staff member.
static func build_context(
	staff: StaffSim, flights: FlightSim, plane_fleet: PlaneFleet
) -> Dictionary:
	var ctx := {
		"checkin": {},
		"info": {},
		"shop_rooms": {},
		"gate_pax": {},
		"gate_boarding": {},
		"flights": flights,
		"plane_fleet": plane_fleet,
	}
	if staff == null or staff.sim == null:
		return ctx
	var sim := staff.sim
	var fl := flights if flights != null else sim.flights
	if fl != null:
		for fid in fl.flight_ids():
			if fl.state_of(fid) == FlightSim.State.BOARDING:
				var gate := fl.flight_gate(fid)
				if gate != "":
					ctx["gate_boarding"][gate] = true
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		_collect_passenger(sim, fl, p, ctx)
	return ctx


static func _collect_passenger(
	sim: PassengerSim, fl: FlightSim, p: Passenger, ctx: Dictionary
) -> void:
	if p.stage == Passenger.Stage.CHECKIN and p.station != 0:
		ctx["checkin"][p.station] = sim.world_position(p) + Vector3(0.0, PASSENGER_EYE_M, 0.0)
	if sim.info_desks.holds(p) and not p.is_moving():
		var desk := sim.info_desks.desk_of(p)
		if desk != 0 and sim.info_desks.helping_at(desk):
			ctx["info"][desk] = sim.world_position(p) + Vector3(0.0, PASSENGER_EYE_M, 0.0)
	if p.stage == Passenger.Stage.SHOP_BROWSE:
		var visit := sim.shops.visit_of(p.id)
		if visit != null and visit.room != 0:
			var list: Array = ctx["shop_rooms"].get_or_add(visit.room, [])
			list.append(sim.world_position(p) + Vector3(0.0, PASSENGER_EYE_M, 0.0))
	if p.stage == Passenger.Stage.TO_EXIT and fl != null and p.flight_id != "":
		var gate := fl.flight_gate(p.flight_id)
		if gate != "":
			var list: Array = ctx["gate_pax"].get_or_add(gate, [])
			list.append(sim.world_position(p) + Vector3(0.0, PASSENGER_EYE_M, 0.0))


## Desired [Mode, target_pos: Vector3, has_target: bool] for `m` at `staff_pos`.
static func evaluate(m: StaffMember, staff: StaffSim, staff_pos: Vector3, ctx: Dictionary) -> Array:
	if m.role == StaffMember.Role.RAMP:
		if m.ramp_job == StaffMember.RampJob.MARSHAL:
			var target := _marshal_target(m, staff, ctx)
			return [Mode.RAMP_MARSHAL, target[0], target[1]]
		return [Mode.NONE, Vector3.ZERO, false]
	if m.state != StaffMember.State.ON_DUTY or m.station == 0 or staff == null or staff.sim == null:
		return [Mode.NONE, Vector3.ZERO, false]
	match m.role:
		StaffMember.Role.CHECKIN:
			if ctx["checkin"].has(m.station):
				return [Mode.CHECKIN, ctx["checkin"][m.station], true]
		StaffMember.Role.SECURITY:
			return _security_eval(m, staff.sim)
		StaffMember.Role.SHOP:
			return _shop_eval(m, staff.sim, staff_pos, ctx)
		StaffMember.Role.GATE:
			return _gate_eval(m, staff.sim, staff_pos, ctx)
	return [Mode.NONE, Vector3.ZERO, false]


static func _security_eval(m: StaffMember, sim: PassengerSim) -> Array:
	var rec := sim.security.record_of(m.station)
	if rec.is_empty():
		return [Mode.NONE, Vector3.ZERO, false]
	var admitted: Array = rec.get("admitted", [])
	if admitted.is_empty():
		return [Mode.NONE, Vector3.ZERO, false]
	var is_lane := sim.security.is_lane(m.station)
	var target_id := 0
	if m.slot == StaffMember.Slot.HELPER:
		target_id = int(rec.get("berth", 0))
		if target_id == 0:
			for id: int in admitted:
				var q := sim.get_passenger(id)
				if (
					q.security_phase
					in [
						SecurityRuntime.Phase.TO_BERTH,
						SecurityRuntime.Phase.REPACK,
						SecurityRuntime.Phase.RETURN,
					]
				):
					target_id = id
					break
	elif is_lane:
		target_id = int(rec.get("main", 0))
		if target_id == 0:
			for id: int in admitted:
				var q := sim.get_passenger(id)
				if (
					q.security_phase
					in [
						SecurityRuntime.Phase.UNPACK,
						SecurityRuntime.Phase.ARCH,
						SecurityRuntime.Phase.PICKUP,
					]
				):
					target_id = id
					break
	else:
		target_id = int(admitted[0])
	if target_id == 0:
		return [Mode.NONE, Vector3.ZERO, false]
	var pax := sim.get_passenger(target_id)
	var eye := Vector3(0.0, PASSENGER_EYE_M, 0.0)
	var pos := sim.world_position(pax) + SecurityLooks.target_offset(sim, pax) + eye
	var sec_mode := (
		Mode.SECURITY_REPACK
		if pax.security_phase == SecurityRuntime.Phase.REPACK
		else Mode.SECURITY_SCAN
	)
	return [sec_mode, pos, true]


static func _shop_eval(
	m: StaffMember, sim: PassengerSim, staff_pos: Vector3, ctx: Dictionary
) -> Array:
	var cid := sim.cafes.serving_at(m.station)
	if cid != 0:
		var pax := sim.get_passenger(cid)
		return [Mode.SHOP, sim.world_position(pax) + Vector3(0.0, PASSENGER_EYE_M, 0.0), true]
	if ctx["info"].has(m.station):
		return [Mode.SHOP, ctx["info"][m.station], true]
	var room := ShopCounters.room_of(sim.grid, m.station)
	if room != 0 and ctx["shop_rooms"].has(room):
		var best := _nearest(staff_pos, ctx["shop_rooms"][room], GATE_INTERACT_M)
		if best[1]:
			return [Mode.SHOP, best[0], true]
	return [Mode.NONE, Vector3.ZERO, false]


static func _gate_eval(
	m: StaffMember, sim: PassengerSim, staff_pos: Vector3, ctx: Dictionary
) -> Array:
	var gate := ""
	for letter: String in sim.layout.gate_desk_ids:
		if int(sim.layout.gate_desk_ids[letter]) == m.station:
			gate = letter
			break
	if gate == "":
		return [Mode.NONE, Vector3.ZERO, false]
	var walkers: Array = ctx["gate_pax"].get(gate, [])
	var nearest := _nearest(staff_pos, walkers, GATE_INTERACT_M)
	if nearest[1]:
		return [Mode.GATE, nearest[0], true]
	if ctx["gate_boarding"].get(gate, false):
		return [Mode.GATE, Vector3.ZERO, false]
	return [Mode.NONE, Vector3.ZERO, false]


static func _marshal_target(m: StaffMember, staff: StaffSim, ctx: Dictionary) -> Array:
	var fleet: PlaneFleet = ctx.get("plane_fleet")
	if fleet != null and m.ramp_flight_id != "":
		for view in fleet.views:
			if view.flight_id == m.ramp_flight_id and view.visible:
				return [view.global_position + Vector3(0.0, STAFF_EYE_M, 0.0), true]
	var fl: FlightSim = ctx.get("flights")
	if fl == null and staff != null and staff.ramp_dispatch != null:
		fl = staff.ramp_dispatch.flights
	if fl != null and m.ramp_flight_id != "":
		var stand := fl.flight_stand(m.ramp_flight_id)
		if not stand.is_empty():
			var twin := StandPlacement.north_twin(stand)
			var pt := StandPlacement.stand_point(twin)
			var at := StandPlacement.to_world(stand, pt) + Vector3(0.0, STAFF_EYE_M, 0.0)
			return [at, true]
	return [Vector3.ZERO, false]


static func _nearest(from: Vector3, points: Array, max_dist: float) -> Array:
	var best_pt := Vector3.ZERO
	var best_d := max_dist
	var found := false
	for pt: Vector3 in points:
		var d := from.distance_to(pt)
		if d <= best_d:
			best_d = d
			best_pt = pt
			found = true
	return [best_pt, found]


## Applies or disables the StaffStationPose modifier on `node`'s Skeleton3D.
static func pose(
	node: Node3D,
	new_mode: Mode,
	new_weight: float,
	now: float,
	look_deg: Vector2,
	seed_id: int,
) -> void:
	var on := new_mode != Mode.NONE and new_weight > 0.0
	if not on and not node.has_meta(&"station_pose"):
		return
	var mod := _of(node)
	if mod == null:
		return
	mod.active = on
	mod.mode = new_mode if on else Mode.NONE
	mod.weight = clampf(new_weight, 0.0, 1.0) if on else 0.0
	mod.sim_time = now
	mod.look_yaw_deg = look_deg.x if on else 0.0
	mod.look_pitch_deg = look_deg.y if on else 0.0
	mod.variant_seed = seed_id


## Returns (and lazily adds) the StaffStationPose modifier on `node`'s skeleton.
static func _of(node: Node3D) -> StaffStationPose:
	if node.has_meta(&"station_pose"):
		return node.get_meta(&"station_pose")
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	var mod := StaffStationPose.new()
	mod.name = "StaffStationPose"
	mod.active = false
	skeleton.add_child(mod)
	skeleton.move_child(mod, 0)
	node.set_meta(&"station_pose", mod)
	return mod


func _process_modification_with_delta(_delta: float) -> void:
	if mode == Mode.NONE or weight <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var w := clampf(weight, 0.0, 1.0)
	var t := sim_time / float(SimClock.TICK_RATE) + float(variant_seed % 7) * 0.43
	_apply_role_pose(skeleton, w, t)
	_apply_look_at(skeleton, w)


func _apply_look_at(skeleton: Skeleton3D, w: float) -> void:
	if absf(look_yaw_deg) < 0.01 and absf(look_pitch_deg) < 0.01:
		return
	var yaw := look_yaw_deg * w
	var pitch := look_pitch_deg * w
	_rotate_char(skeleton, "Spine_02", Vector3.UP, yaw * 0.25)
	_rotate_char(skeleton, "Neck", Vector3.UP, yaw * 0.35)
	_rotate_char(skeleton, "Neck", Vector3.RIGHT, pitch * 0.4)
	_rotate_char(skeleton, "Head", Vector3.UP, yaw * 0.40)
	_rotate_char(skeleton, "Head", Vector3.RIGHT, pitch * 0.6)


func _apply_role_pose(skeleton: Skeleton3D, w: float, t: float) -> void:
	match mode:
		Mode.CHECKIN:
			_pose_checkin(skeleton, w, t)
		Mode.SECURITY_SCAN:
			_pose_security_scan(skeleton, w, t)
		Mode.SECURITY_REPACK:
			_pose_security_repack(skeleton, w, t)
		Mode.SHOP:
			_pose_shop(skeleton, w, t)
		Mode.GATE:
			_pose_gate(skeleton, w, t)
		Mode.RAMP_MARSHAL:
			_pose_marshal(skeleton, w, t)


func _pose_checkin(skeleton: Skeleton3D, w: float, t: float) -> void:
	var cycle := fposmod(t, 3.6)
	var handoff := 0.0
	if cycle > 2.4:
		handoff = sin(PI * clampf((cycle - 2.4) / 1.2, 0.0, 1.0))
		handoff = handoff * handoff
	var tap := sin(t * 15.0) * (1.0 - handoff)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (4.0 + 3.0 * handoff) * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -30.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -12.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.BACK, 6.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-52.0 + 6.0 * tap) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, lerpf(-30.0, -52.0, handoff) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, lerpf(12.0, 4.0, handoff) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -6.0 * w)
	_rotate_char(
		skeleton, "Forearm.R", Vector3.RIGHT, (lerpf(-52.0, -20.0, handoff) - 6.0 * tap) * w
	)
	_rotate_char(skeleton, "Hand.R", Vector3.RIGHT, 10.0 * handoff * w)


func _pose_security_scan(skeleton: Skeleton3D, w: float, t: float) -> void:
	var sweep := sin(t * 3.4)
	var nod := cos(t * 3.4)
	var beckon := sin(t * 2.1)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -42.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, 18.0 * sweep * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -12.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-38.0 + 10.0 * nod) * w)
	_rotate_char(skeleton, "Hand.R", Vector3.UP, 12.0 * sweep * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-22.0 + 6.0 * beckon) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-28.0 + 8.0 * beckon) * w)


func _pose_security_repack(skeleton: Skeleton3D, w: float, t: float) -> void:
	var gesture := sin(t * 2.4)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 5.0 * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -34.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, 8.0 * gesture * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -8.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-40.0 + 8.0 * gesture) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -16.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-24.0 + 5.0 * cos(t * 2.4)) * w)


func _pose_shop(skeleton: Skeleton3D, w: float, t: float) -> void:
	var reach := 0.5 - 0.5 * cos(t * 2.2)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.0 + 4.0 * reach) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, lerpf(-24.0, -48.0, reach) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, lerpf(8.0, 0.0, reach) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -8.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, lerpf(-46.0, -22.0, reach) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-22.0 - 8.0 * reach) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-42.0 + 10.0 * sin(t * 3.0)) * w)


func _pose_gate(skeleton: Skeleton3D, w: float, t: float) -> void:
	var wave := maxf(0.0, sin(t * 2.5))
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-32.0 - 16.0 * wave) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, -14.0 * wave * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -14.0 * (0.4 + 0.6 * wave) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-46.0 + 18.0 * wave) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -18.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -30.0 * w)


func _pose_marshal(skeleton: Skeleton3D, w: float, t: float) -> void:
	var beckon := sin(t * 5.2)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -3.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.BACK, 132.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, 28.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.BACK, (32.0 + 24.0 * beckon) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, 18.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -132.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, 28.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.BACK, (-32.0 - 24.0 * beckon) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, 18.0 * w)


func _rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0 or absf(deg) < 1e-4:
		return
	var bone_pose := skeleton.get_bone_global_pose(idx)
	bone_pose.basis = Basis(axis_char.normalized(), deg_to_rad(deg)) * bone_pose.basis
	skeleton.set_bone_global_pose(idx, bone_pose)
