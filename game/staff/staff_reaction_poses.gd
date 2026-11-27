class_name StaffReactionPoses
extends RefCounted
## Procedural Break Room seated/chat poses, expressive work/idle micro-reactions,
## and rising-edge sound cues for StaffStationPose and StaffCharacters.
## Keeps all character .glb skeletons unmodified (e7517650) and all pose/prop
## state strictly view-only so saves and forecasts remain deterministic.

const GATE_WAVE_MAX_M := 14.0
const RUSH_PEAK_MIN := 2
const CHEER_DURATION_TICKS := 36.0
const BUSY_GAP_MAX_TICKS := 24.0


static func lull_pose_for(m: StaffMember, tick_now: float, has_served: bool = false) -> Array:
	if m == null:
		return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.NONE]
	if m.is_tired():
		return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.LULL_STRETCH]
	if m.role == StaffMember.Role.RAMP:
		return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.NONE]
	var bucket := int(floor(maxf(tick_now, 0.0) / float(StaffStationPose.FIDGET_PERIOD_TICKS)))
	if m.role == StaffMember.Role.SECURITY:
		if not has_served:
			return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.LULL_WATCH]
		var pick := posmod(m.id + bucket, 2)
		var sub := (
			StaffStationPose.SubMode.LULL_CLIPBOARD
			if pick == 0
			else StaffStationPose.SubMode.LULL_WATCH
		)
		return [StaffStationPose.Mode.IDLE_FIDGET, sub]
	if (
		m.role == StaffMember.Role.CHECKIN
		or m.role == StaffMember.Role.SHOP
		or m.role == StaffMember.Role.GATE
	):
		match posmod(m.id + bucket, 3):
			0:
				return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.LULL_WIPE]
			1:
				return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.LULL_CLIPBOARD]
			_:
				return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.LULL_WATCH]
	return [StaffStationPose.Mode.IDLE_FIDGET, StaffStationPose.SubMode.NONE]


## Evaluates desired [mode, target_pos, has_target, sub_mode, can_fidget,
## lull_mode, lull_sub] combining station activity, Break Room rest/chat,
## tired walk yawns, queue beckoning, and celebratory cheers.
static func evaluate_member(
	m: StaffMember,
	staff_pos: Vector3,
	pose_ctx: Dictionary,
	base_eval: Array,
	extra: Dictionary,
) -> Array:
	var tick_now := float(extra.get("tick_now", 0.0))
	var cheer_until := float(extra.get("cheer_until", -1.0))
	if (
		cheer_until > tick_now
		and not m.in_pool()
		and not m.is_walking_to_exit()
		and m.state != StaffMember.State.ON_BREAK
	):
		return [
			StaffStationPose.Mode.REACTION_CHEER,
			Vector3.ZERO,
			false,
			StaffStationPose.SubMode.NONE,
			false,
			StaffStationPose.Mode.IDLE_FIDGET,
			StaffStationPose.SubMode.NONE,
		]
	if m.state == StaffMember.State.ON_BREAK:
		return _eval_break_member(m, extra)
	if m.is_moving() and m.is_tired() and m.state == StaffMember.State.TO_BREAK:
		return [
			StaffStationPose.Mode.REACTION_STRETCH,
			Vector3.ZERO,
			false,
			StaffStationPose.SubMode.REACT_WALK_YAWN,
			false,
			StaffStationPose.Mode.IDLE_FIDGET,
			StaffStationPose.SubMode.NONE,
		]
	if base_eval[0] != StaffStationPose.Mode.NONE:
		return [
			base_eval[0],
			base_eval[1],
			base_eval[2],
			base_eval[3],
			false,
			StaffStationPose.Mode.IDLE_FIDGET,
			StaffStationPose.SubMode.NONE,
		]
	if m.state == StaffMember.State.ON_DUTY and m.station != 0:
		var wave := _wave_target(m, staff_pos, pose_ctx)
		if bool(wave[1]):
			return [
				StaffStationPose.Mode.REACTION_WAVE,
				wave[0],
				true,
				StaffStationPose.SubMode.NONE,
				false,
				StaffStationPose.Mode.IDLE_FIDGET,
				StaffStationPose.SubMode.NONE,
			]
	var can_fidget := bool(extra.get("can_fidget", false))
	var has_served := bool(extra.get("has_served", false))
	var lull := lull_pose_for(m, tick_now, has_served)
	return [
		StaffStationPose.Mode.NONE,
		base_eval[1],
		base_eval[2],
		StaffStationPose.SubMode.NONE,
		can_fidget,
		lull[0],
		lull[1],
	]


static func apply_pose(
	mod: StaffStationPose,
	skeleton: Skeleton3D,
	p_mode: StaffStationPose.Mode,
	p_sub_mode: StaffStationPose.SubMode,
	w: float,
) -> void:
	var t := mod.sim_time / float(SimClock.TICK_RATE) + float(posmod(mod.variant_seed, 13)) * 0.43
	match p_mode:
		StaffStationPose.Mode.BREAK_SEATED:
			_pose_break(mod, skeleton, p_sub_mode, w, t, false)
		StaffStationPose.Mode.BREAK_CHAT:
			_pose_break(mod, skeleton, p_sub_mode, w, t, true)
		StaffStationPose.Mode.REACTION_WAVE:
			_pose_wave(mod, skeleton, w, t)
		StaffStationPose.Mode.REACTION_WIPE:
			_pose_wipe(mod, skeleton, w, t)
		StaffStationPose.Mode.REACTION_STRETCH:
			if p_sub_mode == StaffStationPose.SubMode.REACT_WALK_YAWN:
				_pose_walk_yawn(mod, skeleton, w, t)
			else:
				_pose_stretch(mod, skeleton, w)
		StaffStationPose.Mode.REACTION_CLIPBOARD:
			if p_sub_mode == StaffStationPose.SubMode.REACT_WATCH:
				_pose_watch(mod, skeleton, w)
			else:
				_pose_clipboard(mod, skeleton, w, t)
		StaffStationPose.Mode.REACTION_CHEER:
			_pose_cheer(mod, skeleton, w, t)


static func apply_lull_pose(
	mod: StaffStationPose,
	skeleton: Skeleton3D,
	p_sub_mode: StaffStationPose.SubMode,
	env: float,
	t: float,
) -> bool:
	match p_sub_mode:
		StaffStationPose.SubMode.LULL_WIPE:
			_pose_wipe(mod, skeleton, env, t)
			return true
		StaffStationPose.SubMode.LULL_STRETCH:
			_pose_stretch(mod, skeleton, env)
			return true
		StaffStationPose.SubMode.LULL_CLIPBOARD:
			_pose_clipboard(mod, skeleton, env, t)
			return true
		StaffStationPose.SubMode.LULL_WATCH:
			_pose_watch(mod, skeleton, env)
			return true
	return false


static func reaction_sound_for(
	prev_mode: StaffStationPose.Mode,
	prev_sub: StaffStationPose.SubMode,
	new_mode: StaffStationPose.Mode,
	new_sub: StaffStationPose.SubMode,
) -> StringName:
	if new_mode == prev_mode and new_sub == prev_sub:
		return &""
	match new_mode:
		StaffStationPose.Mode.REACTION_CHEER:
			return &"staff_cheer"
		StaffStationPose.Mode.REACTION_WIPE:
			return &"staff_wipe"
		StaffStationPose.Mode.REACTION_STRETCH:
			return &"staff_yawn"
		StaffStationPose.Mode.BREAK_CHAT:
			return &"staff_mumble"
		StaffStationPose.Mode.BREAK_SEATED:
			if new_sub == StaffStationPose.SubMode.BREAK_COFFEE:
				return &"staff_sip"
		StaffStationPose.Mode.IDLE_FIDGET:
			if new_sub == StaffStationPose.SubMode.LULL_WIPE:
				return &"staff_wipe"
			if new_sub == StaffStationPose.SubMode.LULL_STRETCH:
				return &"staff_yawn"
	return &""


static func _eval_break_member(m: StaffMember, extra: Dictionary) -> Array:
	var seated := bool(extra.get("seated", false))
	var standing_rest := bool(extra.get("standing_rest", false))
	var chat_info: Dictionary = extra.get("chat_info", {})
	if not seated and not standing_rest:
		return [
			StaffStationPose.Mode.NONE,
			Vector3.ZERO,
			false,
			StaffStationPose.SubMode.NONE,
			false,
			StaffStationPose.Mode.IDLE_FIDGET,
			StaffStationPose.SubMode.NONE,
		]
	var prop_sub := StaffHandProps.break_sub_mode_for(StaffHandProps.break_prop_for(m.id))
	if not chat_info.is_empty():
		return [
			StaffStationPose.Mode.BREAK_CHAT,
			chat_info.get("coworker_eye", Vector3.ZERO),
			true,
			prop_sub,
			false,
			StaffStationPose.Mode.IDLE_FIDGET,
			StaffStationPose.SubMode.NONE,
		]
	return [
		StaffStationPose.Mode.BREAK_SEATED,
		Vector3.ZERO,
		false,
		prop_sub,
		false,
		StaffStationPose.Mode.IDLE_FIDGET,
		StaffStationPose.SubMode.NONE,
	]


static func _wave_target(m: StaffMember, staff_pos: Vector3, pose_ctx: Dictionary) -> Array:
	if m.role == StaffMember.Role.CHECKIN:
		var q: Dictionary = pose_ctx.get("checkin_queue", {})
		if q.has(m.station):
			return [q[m.station], true]
	elif m.role == StaffMember.Role.SECURITY:
		var q: Dictionary = pose_ctx.get("security_queue", {})
		if q.has(m.station):
			return [q[m.station], true]
	elif m.role == StaffMember.Role.GATE:
		var gate_desks: Dictionary = pose_ctx.get("gate_desks", {})
		var gate := String(gate_desks.get(m.station, ""))
		if gate != "":
			var walkers: Array = pose_ctx.get("gate_pax", {}).get(gate, [])
			var best_pt := Vector3.ZERO
			var best_d := GATE_WAVE_MAX_M
			var found := false
			for pt: Vector3 in walkers:
				var d := staff_pos.distance_to(pt)
				if d > StaffStationPose.GATE_INTERACT_M and d <= best_d:
					best_d = d
					best_pt = pt
					found = true
			return [best_pt, found]
	return [Vector3.ZERO, false]


static func _pose_break(
	mod: StaffStationPose,
	skeleton: Skeleton3D,
	p_sub_mode: StaffStationPose.SubMode,
	w: float,
	t: float,
	chatting: bool,
) -> void:
	var breath := 0.5 + 0.5 * sin(t * 1.9)
	mod.rotate_char(skeleton, "Spine_03", Vector3.RIGHT, 1.8 * breath * w)
	match p_sub_mode:
		StaffStationPose.SubMode.BREAK_COFFEE:
			var sip_phase := fposmod(t * 0.22, 1.0)
			var sip := sin(PI * clampf((sip_phase - 0.58) / 0.34, 0.0, 1.0)) * w
			mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, lerpf(-6.0, -18.0, sip) * w)
			mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 8.0 * w)
			mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, lerpf(-28.0, -48.0, sip) * w)
			mod.rotate_char(skeleton, "Hand.R", Vector3.BACK, 6.0 * w)
			mod.rotate_char(skeleton, "Head", Vector3.RIGHT, -3.0 * sip)
		StaffStationPose.SubMode.BREAK_PHONE:
			var thumb := sin(t * 3.8)
			mod.rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 2.5 * w)
			mod.rotate_char(skeleton, "Neck", Vector3.RIGHT, 5.0 * w)
			mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 9.0 * w)
			mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -10.0 * w)
			mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 10.0 * w)
			mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -34.0 * w)
			mod.rotate_char(skeleton, "Hand.R", Vector3.RIGHT, (8.0 + 4.0 * thumb) * w)
		StaffStationPose.SubMode.BREAK_MAGAZINE:
			var glance := sin(t * 1.3)
			mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 8.0 * w)
			mod.rotate_char(skeleton, "Head", Vector3.UP, 5.0 * glance * w)
			mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -8.0 * w)
			mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 4.0 * w)
			mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -22.0 * w)
		_:
			mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -6.0 * w)
			mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -14.0 * w)
	if chatting:
		var chat_wave := sin(t * 2.6)
		var nod := sin(t * 3.4)
		mod.rotate_char(skeleton, "Spine_02", Vector3.UP, 5.0 * sin(t * 1.4) * w)
		mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 4.0 * nod * w)
		mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-10.0 - 8.0 * chat_wave) * w)
		mod.rotate_char(skeleton, "Arm.L", Vector3.BACK, (6.0 + 6.0 * absf(chat_wave)) * w)
		mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-24.0 - 14.0 * chat_wave) * w)
	elif p_sub_mode == StaffStationPose.SubMode.BREAK_MAGAZINE:
		mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -8.0 * w)
		mod.rotate_char(skeleton, "Arm.L", Vector3.UP, -12.0 * w)
		mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -24.0 * w)
	else:
		mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -6.0 * w)
		mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -16.0 * w)


static func _pose_wave(mod: StaffStationPose, skeleton: Skeleton3D, w: float, t: float) -> void:
	var cycle := sin(t * 5.2)
	var sweep := smoothstep(-0.3, 0.9, sin(t * 2.6))
	mod.rotate_char(skeleton, "Spine_02", Vector3.UP, 6.0 * w)
	mod.rotate_char(skeleton, "Spine_03", Vector3.RIGHT, -3.0 * w)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, (-3.0 + 4.0 * sin(t * 2.6)) * w)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-116.0 - 10.0 * sweep) * w)
	mod.rotate_char(skeleton, "Arm.R", Vector3.BACK, (24.0 + 8.0 * sweep) * w)
	mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 8.0 * sweep * w)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-22.0 - 24.0 * (0.5 + 0.5 * cycle)) * w)
	mod.rotate_char(skeleton, "Hand.R", Vector3.RIGHT, 14.0 * cycle * w)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -14.0 * w)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -26.0 * w)


static func _pose_wipe(mod: StaffStationPose, skeleton: Skeleton3D, env: float, t: float) -> void:
	var wipe_x := sin(t * 4.2)
	var wipe_z := cos(t * 4.2)
	mod.rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 8.0 * env)
	mod.rotate_char(skeleton, "Spine_02", Vector3.UP, 10.0 * wipe_x * env)
	mod.rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 14.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.UP, 6.0 * wipe_x * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-38.0 + 8.0 * wipe_z) * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.UP, (-6.0 + 18.0 * wipe_x) * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.BACK, (-10.0 - 8.0 * wipe_x) * env)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-16.0 + 10.0 * wipe_z) * env)
	mod.rotate_char(skeleton, "Hand.R", Vector3.RIGHT, 16.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -18.0 * env)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -32.0 * env)


static func _pose_stretch(mod: StaffStationPose, skeleton: Skeleton3D, env: float) -> void:
	mod.rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -4.0 * env)
	mod.rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -4.0 * env)
	mod.rotate_char(skeleton, "Spine_03", Vector3.RIGHT, -3.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, -15.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -140.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.BACK, -28.0 * env)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -10.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -140.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.BACK, 28.0 * env)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -10.0 * env)


static func _pose_walk_yawn(
	mod: StaffStationPose, skeleton: Skeleton3D, w: float, t: float
) -> void:
	var phase := smoothstep(-0.1, 0.75, sin(t * 1.45))
	var env := w * (0.45 + 0.55 * phase)
	mod.rotate_char(skeleton, "Spine_03", Vector3.RIGHT, -3.5 * env)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, -10.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -68.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 24.0 * env)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -92.0 * env)


static func _pose_clipboard(
	mod: StaffStationPose, skeleton: Skeleton3D, env: float, t: float
) -> void:
	var tap := sin(t * 5.0)
	mod.rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 14.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.UP, -8.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -34.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.UP, -18.0 * env)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -68.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -36.0 * env)
	mod.rotate_char(skeleton, "Arm.R", Vector3.UP, 32.0 * env)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-74.0 + 10.0 * tap) * env)


static func _pose_watch(mod: StaffStationPose, skeleton: Skeleton3D, env: float) -> void:
	mod.rotate_char(skeleton, "Neck", Vector3.UP, 14.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.UP, 14.0 * env)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, 16.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -40.0 * env)
	mod.rotate_char(skeleton, "Arm.L", Vector3.UP, -28.0 * env)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -88.0 * env)
	mod.rotate_char(skeleton, "Hand.L", Vector3.UP, -25.0 * env)


static func _pose_cheer(mod: StaffStationPose, skeleton: Skeleton3D, w: float, t: float) -> void:
	var pump := absf(sin(t * 7.5))
	mod.rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -2.5 * pump * w)
	mod.rotate_char(skeleton, "Spine_03", Vector3.UP, 4.0 * sin(t * 3.8) * w)
	mod.rotate_char(skeleton, "Head", Vector3.RIGHT, -10.0 * pump * w)
	mod.rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-130.0 - 14.0 * pump) * w)
	mod.rotate_char(skeleton, "Arm.R", Vector3.BACK, 22.0 * w)
	mod.rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-42.0 + 16.0 * pump) * w)
	mod.rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-24.0 - 8.0 * pump) * w)
	mod.rotate_char(skeleton, "Arm.L", Vector3.BACK, 14.0 * w)
	mod.rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -54.0 * w)
