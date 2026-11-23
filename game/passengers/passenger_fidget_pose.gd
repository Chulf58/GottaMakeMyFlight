class_name PassengerFidgetPose
extends SkeletonModifier3D
## View-only procedural passenger reaction and fidget modifier (Package B 2/3,
## ruling staff-and-passenger-interaction-variety-package-b-procedural):
## layers subtle security alarm/liquids reactions, queue impatience/watch-check
## beats, seated phone/stretch/drowsy variants, and close-call boarding relief
## onto Toon skeletons without modifying .glb rigs, sim state, RNG, or saves.
##
## Placed on Skeleton3D after ClipCrossfade (and any PodRecline/DiningPose/
## RepackPose) and strictly BEFORE CarryStoop and CarryArm0/CarryArm1, while
## yielding cleanly whenever CarryArm, CarryStoop, DiningPose, RepackPose,
## PodRecline, or SHOWER controls arms or torso.

enum Mode { NONE, ALARM, LIQUIDS, QUEUE, SEATED, CLOSE_CALL }

const QUEUE_SETTLE_TICKS := 12.0
const SEATED_SETTLE_TICKS := 10.0
const EASE_TICKS := 6.0
const FADE_OUT_TICKS := 3.0
const SCAN_REACTION_TICKS := 18.0
const REPACK_REACTION_END := RepackPose.EASE_IN_START
const CLOSE_CALL_TICKS := 24.0
const BASE_BEAT_SEC := 4.0
const BEAT_STEP_SEC := 0.45
const QUEUE_STAGES := [
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.CAFE_QUEUE,
]

var mode: Mode = Mode.NONE
var weight := 0.0
var phase_t := 0.0
var sub_variant := 0
var variant_seed := 0
var free_right := true
var free_left := true


## Resets any PassengerFidgetPose modifier on `node` back to inactive Mode.NONE.
static func reset(node: Node3D) -> void:
	apply(node, Mode.NONE, 0.0, 0.0, 0, 0, true, true)


## Applies or disables the PassengerFidgetPose modifier on `node`'s Skeleton3D,
## keeping it ordered after ClipCrossfade and strictly before CarryStoop/CarryArm.
static func apply(
	node: Node3D,
	new_mode: Mode,
	new_weight: float,
	new_phase_t: float,
	new_sub: int,
	seed_id: int,
	right_free: bool,
	left_free: bool,
) -> void:
	var on := new_mode != Mode.NONE and new_weight > 0.0
	if not on and not node.has_meta(&"fidget_pose"):
		return
	var mod := _of(node)
	if mod == null:
		return
	if on:
		var skeleton := mod.get_skeleton()
		if skeleton != null:
			_ensure_order(skeleton, mod)
	mod.active = on
	mod.mode = new_mode if on else Mode.NONE
	mod.weight = clampf(new_weight, 0.0, 1.0) if on else 0.0
	mod.phase_t = maxf(new_phase_t, 0.0) if on else 0.0
	mod.sub_variant = new_sub
	mod.variant_seed = seed_id
	mod.free_right = right_free
	mod.free_left = left_free


## Evaluates desired fidget state on a sync tick and updates `record` (which
## holds sim-tick timestamps cleared on PassengerViews.snap() / _release()).
static func sync_passenger(
	sim: PassengerSim,
	props: CarryOnProps,
	node: Node3D,
	p: Passenger,
	record: Dictionary,
	now: float,
	moving: bool,
	clip: String,
	seat_pose: StageKinds.Pose,
	activity: ActivityPoses.Kind,
	at_cafe: bool,
	at_stall: bool,
	dining_amount: float,
	repack_amount: float,
	snapping: bool,
) -> void:
	if record.has("last_tick") and now < float(record["last_tick"]):
		record.clear()
	record["last_tick"] = now
	var freedom := arm_freedom(sim, props, p, node, now)
	var right_free: bool = freedom["arms"][0]
	var left_free: bool = freedom["arms"][1]
	var blocked: bool = (
		freedom["transferring"]
		or activity == ActivityPoses.Kind.RECLINE
		or activity == ActivityPoses.Kind.SHOWER
		or at_cafe
		or at_stall
		or dining_amount > 0.0
		or repack_amount > 0.0
	)
	record["blocked"] = blocked
	record["moving"] = moving
	record["clip"] = clip
	record["seat_pose"] = seat_pose
	record["activity"] = activity
	_update_tick_state(sim, p, record, now, moving, clip, seat_pose, activity, blocked, snapping)
	var eval := _evaluate(p, record, now, right_free, left_free)
	apply(
		node,
		eval["mode"],
		eval["weight"],
		eval["phase_t"],
		eval["sub"],
		p.id,
		right_free,
		left_free,
	)


## Updates continuous animation progress and arm freedom between ticks in draw().
static func tick_frame(
	sim: PassengerSim,
	props: CarryOnProps,
	node: Node3D,
	p: Passenger,
	record: Dictionary,
	now: float,
) -> void:
	if record.has("last_tick") and now < float(record["last_tick"]):
		record.clear()
		reset(node)
		return
	var freedom := arm_freedom(sim, props, p, node, now)
	var right_free: bool = freedom["arms"][0]
	var left_free: bool = freedom["arms"][1]
	var blocked: bool = record.get("blocked", false) or freedom["transferring"]
	if blocked:
		apply(node, Mode.NONE, 0.0, 0.0, 0, p.id, right_free, left_free)
		return
	var eval := _evaluate(p, record, now, right_free, left_free)
	apply(
		node,
		eval["mode"],
		eval["weight"],
		eval["phase_t"],
		eval["sub"],
		p.id,
		right_free,
		left_free,
	)


## Determines free arms [right, left] and active bag transfer state without
## mutating sim or CarryOnProps state.
static func arm_freedom(
	sim: PassengerSim, props: CarryOnProps, p: Passenger, node: Node3D, _now: float
) -> Dictionary:
	var arms := [true, true]
	var transferring := false
	if sim != null:
		if (
			SecurityLooks.in_booth_passage(sim, p)
			or SecurityLooks.in_arch_passage(sim, p)
			or SecurityLooks.carry_front(sim, p)
		):
			arms = [false, false]
		var homes := SecurityLooks.bag_homes(sim, p)
		for i in homes.size():
			if homes[i] != SecurityLooks.Home.HAND:
				continue
			var carry := SecurityLooks.carry_of(p, i)
			if carry == SecurityLooks.Carry.SHOULDER:
				arms[SecurityLooks.worn_side(i)] = false
			elif carry != SecurityLooks.Carry.BACK:
				arms[SecurityLooks.hand_of(sim, p, i)] = false
	if props != null:
		if props.tuck_of(p.id) > 0.0 or props.front_weight_of(p.id) > 0.0:
			arms = [false, false]
		var prop_info := props.props_of(p.id)
		var bag_count := (prop_info.get("bags", []) as Array).size()
		for i in bag_count:
			if props.transfer_progress(p.id, i) < 1.0:
				transferring = true
	if node != null and node.has_meta(&"carry_rig"):
		var rig: Dictionary = node.get_meta(&"carry_rig")
		var stoop := rig.get("stoop") as CarryStoop
		if stoop != null and (not stoop.targets.is_empty() or stoop.drawn > 0.0):
			transferring = true
		for arm: CarryArm in rig.get("arms", []):
			if arm.active and (arm.holds or arm.front_weight > 0.0 or arm.reach_weight > 0.0):
				arms[arm.side] = false
	return {"arms": arms, "transferring": transferring}


static func _update_tick_state(
	sim: PassengerSim,
	p: Passenger,
	record: Dictionary,
	now: float,
	moving: bool,
	clip: String,
	seat_pose: StageKinds.Pose,
	activity: ActivityPoses.Kind,
	blocked: bool,
	snapping: bool,
) -> void:
	var was_stage := int(record.get("stage", -1))
	record["stage"] = p.stage
	if snapping:
		record.erase("fade_since")
		record.erase("react_key")
		record.erase("react_since")
		record.erase("close_call_since")
		record["close_call_done"] = false

	# Close-call boarding relief triggers once as a late passenger transitions
	# into TO_EXIT or APRON (before MADE despawn).
	var entered_boarding := (
		p.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]
		and was_stage != -1
		and was_stage != p.stage
		and (
			was_stage not in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]
			or p.stage == Passenger.Stage.APRON
		)
	)
	if (
		not snapping
		and entered_boarding
		and not record.get("close_call_done", false)
		and _is_close_call(sim, p)
	):
		record["close_call_since"] = now
		record["close_call_done"] = true

	# Security scan/arch stationary reaction timestamp.
	var in_scan_hold := (
		not blocked
		and not moving
		and p.stage == Passenger.Stage.SECURITY
		and not p.incident_resolved
		and (p.alarm or p.liquids)
		and p.security_phase in [SecurityRuntime.Phase.SCAN, SecurityRuntime.Phase.ARCH]
	)
	if in_scan_hold:
		var rkey := &"alarm_scan" if p.alarm else &"liquids_scan"
		if record.get("react_key", &"") != rkey:
			record["react_key"] = rkey
			record["react_since"] = now
	elif (
		p.stage != Passenger.Stage.SECURITY
		or p.security_phase not in [SecurityRuntime.Phase.SCAN, SecurityRuntime.Phase.ARCH]
	):
		record.erase("react_key")
		record.erase("react_since")

	# Wait timer for stationary queue or seated idle fidgets.
	var waiting := (
		_is_queue_waiting(sim, p, moving, clip, blocked)
		or _is_seat_waiting(sim, p, moving, clip, seat_pose, activity, blocked)
	)
	if waiting:
		var prev_since := float(record.get("wait_since", -1.0))
		if prev_since < 0.0 or now < prev_since:
			record["wait_since"] = now
		record["wait_mode"] = (Mode.SEATED if seat_pose == StageKinds.Pose.SEATED else Mode.QUEUE)
		record.erase("fade_since")
	else:
		var had_wait := float(record.get("wait_since", -1.0)) >= 0.0
		if had_wait and not snapping and not blocked:
			record["fade_from"] = float(record.get("last_wait_w", 0.0))
			record["fade_mode"] = int(record.get("wait_mode", Mode.QUEUE))
			record["fade_sub"] = int(record.get("last_wait_sub", 0))
			record["fade_t"] = float(record.get("last_wait_t", 0.0))
			record["fade_since"] = now
		record.erase("wait_since")


static func _evaluate(
	p: Passenger, record: Dictionary, now: float, right_free: bool, left_free: bool
) -> Dictionary:
	var out := {"mode": Mode.NONE, "weight": 0.0, "phase_t": 0.0, "sub": 0}
	if record.get("blocked", false):
		return out

	# 1. Close-call relief (visible across TO_EXIT / APRON before MADE despawn).
	if record.has("close_call_since"):
		var since := float(record["close_call_since"])
		if now < since:
			record.erase("close_call_since")
			record["close_call_done"] = false
		elif not (p.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]):
			record.erase("close_call_since")
		elif now - since < CLOSE_CALL_TICKS:
			var elapsed := now - since
			out["mode"] = Mode.CLOSE_CALL
			out["weight"] = _window_weight(elapsed, 0.0, CLOSE_CALL_TICKS, 4.0, 6.0)
			out["phase_t"] = elapsed / float(SimClock.TICK_RATE)
			out["sub"] = posmod(p.id, 2)
			return out
		else:
			record.erase("close_call_since")

	# 2. Security alarm / liquids reactions (REPACK start or stationary SCAN/ARCH).
	var sec_eval := _evaluate_security(p, record, now)
	if not sec_eval.is_empty():
		return sec_eval

	# 3. Stationary queue or seated idle fidgets.
	var wait_since := float(record.get("wait_since", -1.0))
	if wait_since >= 0.0:
		if now < wait_since:
			record.erase("wait_since")
			return out
		var wait_mode := int(record.get("wait_mode", Mode.QUEUE)) as Mode
		var settle := SEATED_SETTLE_TICKS if wait_mode == Mode.SEATED else QUEUE_SETTLE_TICKS
		var elapsed := now - wait_since
		if elapsed >= settle:
			var active_ticks := elapsed - settle
			var ramp := smoothstep(0.0, 1.0, clampf(active_ticks / EASE_TICKS, 0.0, 1.0))
			var t_local := active_ticks / float(SimClock.TICK_RATE)
			var beat_len := BASE_BEAT_SEC + float(posmod(p.id, 5)) * BEAT_STEP_SEC
			var bucket := int(floor(t_local / beat_len))
			var u := fposmod(t_local / beat_len, 1.0)
			var bell := smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.84, 1.0, u))
			var sub := _pick_sub(wait_mode, p.id, bucket, right_free, left_free)
			var w := ramp * bell
			record["last_wait_w"] = w
			record["last_wait_sub"] = sub
			record["last_wait_t"] = t_local
			out = {"mode": wait_mode, "weight": w, "phase_t": t_local, "sub": sub}
		else:
			record["last_wait_w"] = 0.0
		return out

	# 4. Short fade-out if interrupted while standing/sitting.
	if record.has("fade_since"):
		var f_since := float(record["fade_since"])
		var f_from := float(record.get("fade_from", 0.0))
		if now < f_since or f_from <= 0.0 or now - f_since >= FADE_OUT_TICKS:
			record.erase("fade_since")
		else:
			var k := 1.0 - smoothstep(0.0, 1.0, (now - f_since) / FADE_OUT_TICKS)
			out = {
				"mode": int(record.get("fade_mode", Mode.NONE)) as Mode,
				"weight": f_from * k,
				"phase_t":
				float(record.get("fade_t", 0.0)) + (now - f_since) / float(SimClock.TICK_RATE),
				"sub": int(record.get("fade_sub", 0)),
			}

	return out


static func _evaluate_security(p: Passenger, record: Dictionary, now: float) -> Dictionary:
	if p.stage != Passenger.Stage.SECURITY or p.incident_resolved or not (p.alarm or p.liquids):
		return {}
	var react_mode := Mode.ALARM if p.alarm else Mode.LIQUIDS
	if p.security_phase == SecurityRuntime.Phase.REPACK:
		var total := float(SecurityRuntime.work_for(SecurityRuntime.Phase.REPACK, p))
		var done := clampf(total - float(p.security_work) + fposmod(now, 1.0), 0.0, total)
		var start_done := 6.0 if p.carry_on > 0 else 0.0
		if done >= start_done and done < REPACK_REACTION_END:
			var span := REPACK_REACTION_END - start_done
			return {
				"mode": react_mode,
				"weight": _window_weight(done - start_done, 0.0, span, 3.0, 4.0),
				"phase_t": (done - start_done) / float(SimClock.TICK_RATE),
				"sub": 0,
			}
		return {}
	if (
		p.security_phase in [SecurityRuntime.Phase.SCAN, SecurityRuntime.Phase.ARCH]
		and not record.get("moving", false)
		and record.has("react_since")
	):
		var since := float(record["react_since"])
		if now < since:
			record.erase("react_key")
			record.erase("react_since")
			return {}
		if now - since >= SCAN_REACTION_TICKS:
			record.erase("react_since")
			return {}
		var elapsed := now - since
		return {
			"mode": react_mode,
			"weight": _window_weight(elapsed, 0.0, SCAN_REACTION_TICKS, 3.0, 4.0),
			"phase_t": elapsed / float(SimClock.TICK_RATE),
			"sub": 0,
		}
	return {}


static func _is_close_call(sim: PassengerSim, p: Passenger) -> bool:
	if p.late:
		return true
	if sim == null or sim.flights == null or p.flight_id == "":
		return false
	var close_tick := sim.flights.doors_close_tick(p.flight_id)
	return close_tick >= 0 and close_tick - sim.tick <= PassengerLifecycle.CLOSE_CALL_TICKS


static func _is_queue_waiting(
	sim: PassengerSim, p: Passenger, moving: bool, clip: String, blocked: bool
) -> bool:
	if blocked or moving or clip != "idle":
		return false
	if p.stage in QUEUE_STAGES:
		return true
	if p.stage == Passenger.Stage.SPAWNED and sim != null and sim.entrance.waiting(p.id):
		return true
	if p.stage == Passenger.Stage.STANDING and sim != null:
		return sim.tick - p.stage_tick >= PassengerSim.SHUFFLE_TICKS
	return false


static func _is_seat_waiting(
	_sim: PassengerSim,
	p: Passenger,
	moving: bool,
	clip: String,
	seat_pose: StageKinds.Pose,
	activity: ActivityPoses.Kind,
	blocked: bool,
) -> bool:
	if blocked or moving or clip != "sit_idle" or seat_pose != StageKinds.Pose.SEATED:
		return false
	if activity == ActivityPoses.Kind.SEAT:
		return true
	return StageKinds.location(p.stage) == StageKinds.Location.GATE_SEAT and p.seat_object != 0


static func _window_weight(
	val: float, start_v: float, end_v: float, fade_in: float, fade_out: float
) -> float:
	if val <= start_v or val >= end_v:
		return 0.0
	var enter := smoothstep(start_v, start_v + fade_in, val) if fade_in > 0.0 else 1.0
	var exit := smoothstep(end_v, end_v - fade_out, val) if fade_out > 0.0 else 1.0
	return clampf(minf(enter, exit), 0.0, 1.0)


static func _pick_sub(
	wait_mode: Mode, seed_id: int, bucket: int, right_free: bool, left_free: bool
) -> int:
	var h := posmod((seed_id * 1103515245 + bucket * 2654435761) >> 8, 3)
	if wait_mode == Mode.QUEUE and h == 0 and not right_free and not left_free:
		return 1
	if wait_mode == Mode.SEATED and h == 0 and not right_free and not left_free:
		return 1
	return h


static func _of(node: Node3D) -> PassengerFidgetPose:
	if node.has_meta(&"fidget_pose"):
		return node.get_meta(&"fidget_pose")
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	var mod := PassengerFidgetPose.new()
	mod.name = "PassengerFidgetPose"
	mod.active = false
	skeleton.add_child(mod)
	_ensure_order(skeleton, mod)
	node.set_meta(&"fidget_pose", mod)
	return mod


## Places `mod` after ClipCrossfade (and DiningPose/RepackPose/PodRecline) and
## strictly before CarryStoop and CarryArm modifiers on `skeleton`.
static func _ensure_order(skeleton: Skeleton3D, mod: PassengerFidgetPose) -> void:
	var count := skeleton.get_child_count()
	if count <= 1:
		return
	var min_idx := 1 if skeleton.get_child(0) is ClipCrossfade else 0
	var target := count - 1
	for i in count:
		var child := skeleton.get_child(i)
		if child is CarryStoop or child is CarryArm:
			target = i if mod.get_index() > i else maxi(i - 1, min_idx)
			break
	target = clampi(target, min_idx, count - 1)
	if mod.get_index() != target:
		skeleton.move_child(mod, target)


func _process_modification_with_delta(_delta: float) -> void:
	if mode == Mode.NONE or weight <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null or _sibling_yields(skeleton):
		return
	var free := [free_right, free_left]
	for child in skeleton.get_children():
		if child is CarryArm:
			var arm := child as CarryArm
			if arm.active and (arm.holds or arm.front_weight > 0.0 or arm.reach_weight > 0.0):
				free[arm.side] = false
	var w := clampf(weight, 0.0, 1.0)
	match mode:
		Mode.ALARM:
			_pose_alarm(skeleton, w, phase_t, free)
		Mode.LIQUIDS:
			_pose_liquids(skeleton, w, phase_t, free)
		Mode.QUEUE:
			_pose_queue(skeleton, w, phase_t, sub_variant, free)
		Mode.SEATED:
			_pose_seated(skeleton, w, phase_t, sub_variant, free)
		Mode.CLOSE_CALL:
			_pose_close_call(skeleton, w, phase_t, sub_variant, free)


func _sibling_yields(skeleton: Skeleton3D) -> bool:
	for child in skeleton.get_children():
		if child is PodRecline and child.active and (child as PodRecline).amount > 0.0:
			return true
		if (
			child is DiningPose
			and child.active
			and (child as DiningPose).kind != DiningPose.Kind.NONE
			and (child as DiningPose).amount > 0.0
		):
			return true
		if child is RepackPose and child.active and (child as RepackPose).amount > 0.0:
			return true
		if (
			child is CarryStoop
			and (not (child as CarryStoop).targets.is_empty() or (child as CarryStoop).drawn > 0.0)
		):
			return true
	return false


func _pose_alarm(skeleton: Skeleton3D, w: float, t: float, free: Array) -> void:
	var jitter := sin(t * 11.0) * 2.0
	var both_free := bool(free[0]) and bool(free[1])
	if both_free:
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -7.0 * w)
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -5.0 * w)
		_rotate_char(skeleton, "Neck", Vector3.RIGHT, 4.0 * w)
	_rotate_char(skeleton, "Head", Vector3.RIGHT, (-6.0 + jitter * 0.5) * w)
	_rotate_char(skeleton, "Head", Vector3.UP, jitter * 1.5 * w)
	for side in 2:
		if not free[side]:
			continue
		var suffix := _suffix(side)
		var out_z := _outward_z(side)
		var in_y := _inward_y(side)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -96.0 * w)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, out_z * 26.0 * w)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, in_y * 10.0 * w)
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -48.0 * w)
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.BACK, -out_z * 8.0 * w)


func _pose_liquids(skeleton: Skeleton3D, w: float, t: float, free: Array) -> void:
	var shake := sin(t * 14.0)
	var shrug := 0.7 + 0.3 * sin(t * 7.0)
	if bool(free[0]) and bool(free[1]):
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * shrug * w)
	_rotate_char(skeleton, "Neck", Vector3.RIGHT, 5.0 * w)
	_rotate_char(skeleton, "Neck", Vector3.UP, 8.0 * shake * w)
	_rotate_char(skeleton, "Head", Vector3.UP, 22.0 * shake * w)
	_rotate_char(skeleton, "Head", Vector3.BACK, 10.0 * w)
	for side in 2:
		if not free[side]:
			continue
		var suffix := _suffix(side)
		var out_z := _outward_z(side)
		var in_y := _inward_y(side)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, out_z * 22.0 * shrug * w)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -26.0 * shrug * w)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, in_y * 8.0 * shrug * w)
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -56.0 * shrug * w)
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.UP, -in_y * 24.0 * shrug * w)
		_rotate_char(skeleton, "Hand" + suffix, Vector3.BACK, out_z * 16.0 * shrug * w)


func _pose_queue(skeleton: Skeleton3D, w: float, t: float, sub: int, free: Array) -> void:
	var both_free := bool(free[0]) and bool(free[1])
	match sub:
		0:
			var side := 1 if free[1] else (0 if free[0] else -1)
			if side >= 0:
				var suffix := _suffix(side)
				var out_z := _outward_z(side)
				var in_y := _inward_y(side)
				_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -32.0 * w)
				_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, in_y * 12.0 * w)
				_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -60.0 * w)
				_rotate_char(skeleton, "Forearm" + suffix, Vector3.UP, in_y * 40.0 * w)
				_rotate_char(skeleton, "Hand" + suffix, Vector3.BACK, -out_z * 18.0 * w)
				_rotate_char(skeleton, "Neck", Vector3.RIGHT, 10.0 * w)
				_rotate_char(skeleton, "Neck", Vector3.UP, -in_y * 8.0 * w)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, 16.0 * w)
				_rotate_char(skeleton, "Head", Vector3.UP, -in_y * 10.0 * w)
		1:
			var dir := 1.0 if posmod(variant_seed, 2) == 0 else -1.0
			var glance := sin(t * 1.9)
			if both_free:
				_rotate_char(skeleton, "Spine_02", Vector3.UP, dir * 7.0 * w)
				_rotate_char(skeleton, "Spine_02", Vector3.BACK, -dir * 3.0 * w)
			_rotate_char(skeleton, "Neck", Vector3.UP, dir * 12.0 * (0.7 + 0.3 * glance) * w)
			_rotate_char(skeleton, "Neck", Vector3.RIGHT, -3.0 * w)
			_rotate_char(skeleton, "Head", Vector3.UP, dir * 16.0 * (0.7 + 0.3 * glance) * w)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, -4.0 * w)
			for side in 2:
				if free[side]:
					var suffix := _suffix(side)
					_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -10.0 * w)
					_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, _outward_z(side) * 6.0 * w)
					_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -16.0 * w)
		_:
			var sway := sin(t * 2.2)
			var sigh := maxf(0.0, sin(t * 1.1))
			if both_free:
				_rotate_char(skeleton, "Spine_01", Vector3.BACK, 4.5 * sway * w)
				_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
				_rotate_char(skeleton, "Spine_02", Vector3.BACK, -2.5 * sway * w)
				_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 2.5 * w)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, (4.0 + 4.0 * sigh) * w)
			_rotate_char(skeleton, "Head", Vector3.BACK, -3.0 * sway * w)
			for side in 2:
				if free[side]:
					var suffix := _suffix(side)
					_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, (-8.0 + 5.0 * sway) * w)
					_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, _outward_z(side) * 5.0 * w)
					_rotate_char(
						skeleton, "Forearm" + suffix, Vector3.RIGHT, (-14.0 - 6.0 * absf(sway)) * w
					)


func _pose_seated(skeleton: Skeleton3D, w: float, t: float, sub: int, free: Array) -> void:
	match sub:
		0:
			var pref := posmod(variant_seed, 2)
			var side := pref if free[pref] else (1 - pref if free[1 - pref] else -1)
			if side >= 0:
				var suffix := _suffix(side)
				var out_z := _outward_z(side)
				var in_y := _inward_y(side)
				var scroll := sin(t * 5.0)
				_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -26.0 * w)
				_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, in_y * 14.0 * w)
				_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -68.0 * w)
				_rotate_char(skeleton, "Forearm" + suffix, Vector3.UP, in_y * 24.0 * w)
				_rotate_char(skeleton, "Hand" + suffix, Vector3.RIGHT, -14.0 * w)
				_rotate_char(skeleton, "Hand" + suffix, Vector3.BACK, -out_z * 14.0 * w)
				_rotate_char(skeleton, "Neck", Vector3.RIGHT, 12.0 * w)
				_rotate_char(skeleton, "Neck", Vector3.UP, -in_y * 4.0 * w)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, (18.0 + 2.0 * scroll) * w)
				_rotate_char(skeleton, "Head", Vector3.UP, -in_y * 6.0 * w)
		1:
			var look := sin(t * 1.4)
			_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -4.0 * w)
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -4.0 * w)
			_rotate_char(skeleton, "Spine_02", Vector3.UP, 8.0 * look * w)
			_rotate_char(skeleton, "Neck", Vector3.UP, 14.0 * look * w)
			_rotate_char(skeleton, "Head", Vector3.UP, 18.0 * look * w)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, -5.0 * w)
			for side in 2:
				if free[side]:
					var suffix := _suffix(side)
					_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -20.0 * w)
					_rotate_char(
						skeleton, "Arm" + suffix, Vector3.BACK, _outward_z(side) * 14.0 * w
					)
					_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -26.0 * w)
		_:
			var bob := pow(0.5 - 0.5 * cos(t * 1.8), 1.6)
			var tilt_sign := 1.0 if posmod(variant_seed, 2) == 0 else -1.0
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * bob * w)
			_rotate_char(skeleton, "Neck", Vector3.RIGHT, 10.0 * bob * w)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, (-2.0 + 20.0 * bob) * w)
			_rotate_char(skeleton, "Head", Vector3.BACK, 6.0 * tilt_sign * bob * w)


func _pose_close_call(skeleton: Skeleton3D, w: float, t: float, sub: int, free: Array) -> void:
	var both_free := bool(free[0]) and bool(free[1])
	var side := 0 if free[0] else (1 if free[1] else -1)
	if sub == 0:
		var pump := 0.5 + 0.5 * sin(t * 9.0)
		if both_free:
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -4.0 * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, -8.0 * w)
		if side >= 0:
			var suffix := _suffix(side)
			var out_z := _outward_z(side)
			_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, (-68.0 - 22.0 * pump) * w)
			_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, out_z * 20.0 * w)
			_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, (-74.0 + 24.0 * pump) * w)
	else:
		var wipe := sin(t * 8.0)
		if both_free:
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, (8.0 - 5.0 * wipe) * w)
		if side >= 0:
			var suffix := _suffix(side)
			var out_z := _outward_z(side)
			var in_y := _inward_y(side)
			_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, -80.0 * w)
			_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, in_y * 16.0 * w)
			_rotate_char(skeleton, "Arm" + suffix, Vector3.BACK, out_z * 8.0 * w)
			_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, -104.0 * w)
			_rotate_char(skeleton, "Forearm" + suffix, Vector3.UP, in_y * (34.0 + 14.0 * wipe) * w)


func _rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0 or absf(deg) < 1e-4:
		return
	var bone_pose := skeleton.get_bone_global_pose(idx)
	bone_pose.basis = Basis(axis_char.normalized(), deg_to_rad(deg)) * bone_pose.basis
	skeleton.set_bone_global_pose(idx, bone_pose)


static func _suffix(side: int) -> String:
	return ".R" if side == 0 else ".L"


static func _outward_z(side: int) -> float:
	return -1.0 if side == 0 else 1.0


static func _inward_y(side: int) -> float:
	return 1.0 if side == 0 else -1.0
