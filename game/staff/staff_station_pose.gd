class_name StaffStationPose
extends SkeletonModifier3D
## Procedural station-interaction and idle-fidget pose modifier for staff
## (rulings staff-station-interaction-poses-and-basic-scanner-scan-repac and
## staff-and-passenger-interaction-variety-package-b-procedural): layers
## head/neck/torso look-at, multi-variant role cycles, security alarm/liquids
## reactions, SHOP sub-mode gestures, ramp shuttle/pushback gestures, and subtle
## time-bucketed idle fidgets onto the clip without altering .glb rigs.

enum Mode {
	NONE,
	CHECKIN,
	SECURITY_SCAN,
	SECURITY_REPACK,
	SHOP,
	GATE,
	CLEANER,
	RAMP_MARSHAL,
	RAMP_SHUTTLE,
	RAMP_PUSHBACK,
	IDLE_FIDGET,
	BREAK_SEATED,
	BREAK_CHAT,
	REACTION_WAVE,
	REACTION_WIPE,
	REACTION_STRETCH,
	REACTION_CLIPBOARD,
	REACTION_CHEER,
}

enum SubMode {
	NONE,
	SEC_CLEAN,
	SEC_ALARM,
	SEC_LIQUIDS,
	SHOP_INFO_DESK,
	SHOP_CAFE,
	SHOP_BAR,
	SHOP_RETAIL,
	CLEANER_SWEEP,
	CLEANER_MOP,
	CLEANER_BIN,
	CLEANER_BAG_CARRY,
	CLEANER_BAG_TOSS,
	RAMP_HOOKUP,
	RAMP_GUIDE,
	BREAK_COFFEE,
	BREAK_PHONE,
	BREAK_MAGAZINE,
	BREAK_STAND,
	REACT_CLIPBOARD,
	REACT_WATCH,
	REACT_WALK_YAWN,
	LULL_WIPE,
	LULL_STRETCH,
	LULL_CLIPBOARD,
	LULL_WATCH,
}

const EASE_TICKS := 6.0
const TRANSITION_TICKS := 6.0
const LOOK_EASE_TICKS := 6.0
const MAX_LOOK_YAW_DEG := 38.0
const MAX_LOOK_PITCH_UP_DEG := 12.0
const MAX_LOOK_PITCH_DOWN_DEG := 18.0
const PASSENGER_EYE_M := 1.45
const STAFF_EYE_M := 1.55
const GATE_INTERACT_M := 7.0
const SHOP_COUNTER_M := 5.0
const AMBIENT_LOOK_M := 8.0

const CHECKIN_CYCLE_SEC := 4.0
const SECURITY_CYCLE_SEC := 3.8
const REPACK_CYCLE_SEC := 4.0
const SHOP_CYCLE_SEC := 4.2
const GATE_CYCLE_SEC := 3.8

const IDLE_SETTLE_TICKS := 24
const FIDGET_PERIOD_TICKS := 120
const FIDGET_ACTIVE_TICKS := 84

var mode: Mode = Mode.NONE
var sub_mode: SubMode = SubMode.NONE
var weight := 0.0
var xfade_mode: Mode = Mode.NONE
var xfade_sub_mode: SubMode = SubMode.NONE
var xfade_weight := 0.0
var sim_time := 0.0
var idle_since := 0.0
var look_yaw_deg := 0.0
var look_pitch_deg := 0.0
var variant_seed := 0
var staff_role := -1


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


## Effective idle-fidget start clock, keeping an interrupted clock until fade-out finishes.
static func idle_since_of(record: Dictionary, now: float) -> float:
	if record.has("xfade_idle_since"):
		return float(record["xfade_idle_since"])
	return float(record.get("idle_since", now))


## Active mode stored on `record` (kept while easing out to 0).
static func mode_of(record: Dictionary) -> Mode:
	return int(record.get("mode", Mode.NONE)) as Mode


## Active sub-mode stored on `record`.
static func sub_mode_of(record: Dictionary) -> SubMode:
	return int(record.get("sub_mode", SubMode.NONE)) as SubMode


## Outgoing pose mode during a mode/sub-mode crossfade.
static func xfade_mode_of(record: Dictionary) -> Mode:
	return int(record.get("xfade_mode", Mode.NONE)) as Mode


## Outgoing pose sub-mode during a mode/sub-mode crossfade.
static func xfade_sub_mode_of(record: Dictionary) -> SubMode:
	return int(record.get("xfade_sub", SubMode.NONE)) as SubMode


## Incoming crossfade factor (0 at switch, 1 once settled or on backward tick).
static func crossfade_in(record: Dictionary, now: float) -> float:
	if not record.has("xfade_since") or now < float(record["xfade_since"]):
		return 1.0
	var k := clampf((now - float(record["xfade_since"])) / TRANSITION_TICKS, 0.0, 1.0)
	return smoothstep(0.0, 1.0, k)


## Outgoing crossfade weight (from previous weight down to 0 over TRANSITION_TICKS).
static func crossfade_out(record: Dictionary, now: float) -> float:
	if not record.has("xfade_since") or now < float(record["xfade_since"]):
		return 0.0
	var k := clampf((now - float(record["xfade_since"])) / TRANSITION_TICKS, 0.0, 1.0)
	var out_w := float(record.get("xfade_from", 0.0)) * (1.0 - smoothstep(0.0, 1.0, k))
	if not record.get("active", false):
		var from_w := float(record.get("from", 1.0))
		var decay := clampf(weight_of(record, now) / maxf(from_w, 1e-4), 0.0, 1.0)
		out_w *= decay
	return out_w


static func _clear_xfade(record: Dictionary) -> void:
	record.erase("xfade_since")
	record.erase("xfade_mode")
	record.erase("xfade_sub")
	record.erase("xfade_from")


## Active check-in cycle variant (0 typing+handoff, 1 squint+stamp, 2 check+wave).
static func checkin_variant(now: float, seed_id: int) -> int:
	return int(_cycle_state(now, seed_id, CHECKIN_CYCLE_SEC, 3)["variant"])


## Whether the check-in agent is currently presenting a boarding pass in Hand.R.
static func checkin_prop_active(now: float, seed_id: int) -> bool:
	var c := _cycle_state(now, seed_id, CHECKIN_CYCLE_SEC, 3)
	var v := int(c["variant"])
	var p := float(c["phase"])
	if v == 0:
		return p > 0.50 and p < 0.96
	if v == 2:
		return p >= 0.10 and p <= 0.88
	return false


## Whether a cafe/bar server is in the pour/cup-slide beat (coffee cup in Hand.R).
static func cafe_cup_active(now: float, seed_id: int) -> bool:
	var c := _cycle_state(now, seed_id, SHOP_CYCLE_SEC, 2)
	return int(c["variant"]) == 0


## Deterministic idle fidget variant (0 watch, 1 look around, 2 stretch, 3 shift).
static func idle_fidget_variant(seed_id: int, elapsed_ticks: float) -> int:
	var shifted := maxf(elapsed_ticks - float(IDLE_SETTLE_TICKS), 0.0)
	shifted += float(posmod(seed_id * 47, 100))
	var bucket := floori(shifted / float(FIDGET_PERIOD_TICKS))
	return posmod(seed_id * 7 + bucket * 3, 4)


## Shop sub-mode for a ShopCounters station id.
static func shop_sub_mode(grid: BuildGrid, station: int) -> SubMode:
	if grid == null or station == 0:
		return SubMode.SHOP_RETAIL
	var obj := grid.get_object(station)
	var def_id := StringName(obj.get("def", &""))
	match def_id:
		&"info_desk":
			return SubMode.SHOP_INFO_DESK
		&"cafe_counter", &"grab_and_go_stall":
			return SubMode.SHOP_CAFE
		&"bar_counter":
			return SubMode.SHOP_BAR
	return SubMode.SHOP_RETAIL


## Updates `record` at sim `tick`. An empty record starts settled so a first
## draw or snapped sync after a load never blends from a stale state.
static func update(
	record: Dictionary,
	new_mode: Mode,
	look_deg: Vector2,
	tick: float,
	new_sub_mode: SubMode = SubMode.NONE,
	can_fidget: bool = false,
	seed_id: int = 0,
	lull_mode: Mode = Mode.IDLE_FIDGET,
	lull_sub: SubMode = SubMode.NONE,
) -> void:
	var had_idle_since := record.has("idle_since")
	var prev_idle_since := float(record.get("idle_since", tick))
	var fidget_was_drawn := (
		mode_of(record) == Mode.IDLE_FIDGET or xfade_mode_of(record) == Mode.IDLE_FIDGET
	)
	if record.has("xfade_idle_since") and tick < float(record["xfade_idle_since"]):
		record.erase("xfade_idle_since")
	var resolved_mode := new_mode
	var resolved_sub := new_sub_mode
	if new_mode == Mode.NONE:
		resolved_sub = SubMode.NONE
		if not can_fidget:
			if (
				fidget_was_drawn
				and had_idle_since
				and prev_idle_since <= tick
				and not record.has("xfade_idle_since")
			):
				record["xfade_idle_since"] = prev_idle_since
			record["idle_since"] = tick
		else:
			if not record.has("idle_since") or tick < float(record["idle_since"]):
				record["idle_since"] = tick
			var elapsed := tick - float(record["idle_since"])
			if _is_fidget_active(seed_id, elapsed):
				resolved_mode = lull_mode
				resolved_sub = lull_sub
	else:
		if (
			fidget_was_drawn
			and had_idle_since
			and prev_idle_since <= tick
			and not record.has("xfade_idle_since")
		):
			record["xfade_idle_since"] = prev_idle_since
		record.erase("idle_since")
	var active_now := resolved_mode != Mode.NONE
	var target_look := look_deg
	if not record.has("active"):
		record["active"] = active_now
		record["mode"] = resolved_mode
		record["sub_mode"] = resolved_sub
		record["look_target"] = target_look
		return
	var prev_active := bool(record["active"])
	var prev_mode := mode_of(record)
	var prev_sub := sub_mode_of(record)
	if record.has("since") and tick < float(record["since"]):
		record.erase("since")
		record["from"] = 0.0
	if record.has("xfade_since") and tick < float(record["xfade_since"]):
		_clear_xfade(record)
	if record.has("look_since") and tick < float(record["look_since"]):
		record.erase("look_since")
		record.erase("look_from")
	if active_now != prev_active:
		record["from"] = weight_of(record, tick)
		record["since"] = tick
		record["active"] = active_now
		if active_now:
			if prev_mode != Mode.NONE and (resolved_mode != prev_mode or resolved_sub != prev_sub):
				var cur_w := weight_of(record, tick)
				if cur_w > 0.0:
					record["xfade_mode"] = prev_mode
					record["xfade_sub"] = prev_sub
					record["xfade_from"] = cur_w
					record["xfade_since"] = tick
				else:
					_clear_xfade(record)
			else:
				_clear_xfade(record)
			record["mode"] = resolved_mode
			record["sub_mode"] = resolved_sub
		elif weight_of(record, tick) <= 0.0:
			record["mode"] = Mode.NONE
			record["sub_mode"] = SubMode.NONE
			_clear_xfade(record)
	elif active_now:
		if resolved_mode != prev_mode or resolved_sub != prev_sub:
			var cur_in := weight_of(record, tick) * crossfade_in(record, tick)
			record["xfade_mode"] = prev_mode
			record["xfade_sub"] = prev_sub
			record["xfade_from"] = cur_in
			record["xfade_since"] = tick
			record["from"] = 1.0
			record["since"] = tick
		elif crossfade_in(record, tick) >= 1.0:
			_clear_xfade(record)
		record["mode"] = resolved_mode
		record["sub_mode"] = resolved_sub
	elif weight_of(record, tick) <= 0.0:
		record["mode"] = Mode.NONE
		record["sub_mode"] = SubMode.NONE
		_clear_xfade(record)
	if mode_of(record) != Mode.IDLE_FIDGET and xfade_mode_of(record) != Mode.IDLE_FIDGET:
		record.erase("xfade_idle_since")
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
	staff: StaffSim,
	flights: FlightSim,
	plane_fleet: PlaneFleet,
	baggage: BaggageSim = null,
) -> Dictionary:
	var bag_sim := baggage
	if bag_sim == null and staff != null and staff.ramp_dispatch != null:
		bag_sim = staff.ramp_dispatch.baggage
	var ctx := {
		"checkin": {},
		"checkin_queue": {},
		"security_queue": {},
		"station_active_pax": {},
		"info": {},
		"shop_rooms": {},
		"shop_pieces": {},
		"gate_pax": {},
		"gate_desks": {},
		"ambient_pax": [],
		"flights": flights,
		"plane_fleet": plane_fleet,
		"baggage": bag_sim,
	}
	if staff == null or staff.sim == null:
		return ctx
	var sim := staff.sim
	for letter: String in sim.layout.gate_desk_ids:
		ctx["gate_desks"][int(sim.layout.gate_desk_ids[letter])] = letter
	var fl := flights if flights != null else sim.flights
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		_collect_passenger(sim, fl, p, ctx)
	return ctx


static func _collect_passenger(
	sim: PassengerSim, fl: FlightSim, p: Passenger, ctx: Dictionary
) -> void:
	if p.is_done() or p.at.x < 0:
		return
	var eye := sim.world_position(p) + Vector3(0.0, PASSENGER_EYE_M, 0.0)
	if (
		p.is_moving()
		or (
			p.stage
			in [
				Passenger.Stage.CHECKIN_QUEUE,
				Passenger.Stage.SECURITY_QUEUE,
				Passenger.Stage.CAFE_QUEUE,
			]
		)
	):
		(ctx["ambient_pax"] as Array).append(eye)
	if (
		p.station != 0
		and (
			p.stage
			in [
				Passenger.Stage.CHECKIN,
				Passenger.Stage.CHECKIN_QUEUE,
				Passenger.Stage.SECURITY,
				Passenger.Stage.SECURITY_QUEUE,
			]
		)
	):
		ctx["station_active_pax"][p.station] = int(ctx["station_active_pax"].get(p.station, 0)) + 1
	if p.stage == Passenger.Stage.CHECKIN_QUEUE and p.station != 0:
		if not ctx["checkin_queue"].has(p.station):
			ctx["checkin_queue"][p.station] = eye
	if p.stage == Passenger.Stage.SECURITY_QUEUE and p.station != 0:
		if not ctx["security_queue"].has(p.station):
			ctx["security_queue"][p.station] = eye
	if p.stage == Passenger.Stage.CHECKIN and p.station != 0:
		ctx["checkin"][p.station] = eye
	if sim.info_desks.holds(p) and not p.is_moving():
		var desk := sim.info_desks.desk_of(p)
		if desk != 0 and sim.info_desks.helping_at(desk):
			ctx["info"][desk] = eye
	if p.stage == Passenger.Stage.SHOP_BROWSE:
		var visit := sim.shops.visit_of(p.id)
		if visit != null:
			if visit.room != 0:
				(ctx["shop_rooms"].get_or_add(visit.room, []) as Array).append(eye)
			elif visit.display != 0:
				(ctx["shop_pieces"].get_or_add(visit.display, []) as Array).append(eye)
	if p.stage == Passenger.Stage.TO_EXIT and fl != null and p.flight_id != "":
		var gate := fl.flight_gate(p.flight_id)
		if gate != "":
			var list: Array = ctx["gate_pax"].get_or_add(gate, [])
			list.append(eye)


## Desired [Mode, target_pos: Vector3, has_target: bool, SubMode] for `m` at `staff_pos`.
static func evaluate(
	m: StaffMember,
	staff: StaffSim,
	staff_pos: Vector3,
	ctx: Dictionary,
	staff_yaw: float = NAN,
) -> Array:
	var out: Array = [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	if m.role == StaffMember.Role.RAMP:
		out = _ramp_eval(m, staff, ctx)
	elif m.role == StaffMember.Role.CLEANER and staff != null and staff.sim != null:
		out = _cleaner_eval(m, staff)
	elif (
		m.state == StaffMember.State.ON_DUTY
		and m.station != 0
		and staff != null
		and staff.sim != null
	):
		match m.role:
			StaffMember.Role.CHECKIN:
				if ctx["checkin"].has(m.station):
					out = [Mode.CHECKIN, ctx["checkin"][m.station], true, SubMode.NONE]
			StaffMember.Role.SECURITY:
				out = _security_eval(m, staff.sim)
			StaffMember.Role.SHOP:
				out = _shop_eval(m, staff.sim, staff_pos, ctx)
			StaffMember.Role.GATE:
				out = _gate_eval(m, staff.sim, staff_pos, ctx)
	if out[0] == Mode.NONE and not m.is_moving() and not m.is_walking_to_exit():
		var glance := _ambient_look(staff_pos, staff_yaw, ctx)
		if glance[1]:
			return [Mode.NONE, glance[0], true, SubMode.NONE]
	return out


static func _ramp_eval(m: StaffMember, staff: StaffSim, ctx: Dictionary) -> Array:
	if m.ramp_job == StaffMember.RampJob.MARSHAL:
		var target := _marshal_target(m, staff, ctx)
		return [Mode.RAMP_MARSHAL, target[0], target[1], SubMode.NONE]
	if m.ramp_job == StaffMember.RampJob.SHUTTLE:
		var bag_sim: BaggageSim = ctx.get("baggage")
		var shuttle := bag_sim.get_shuttle(m.ramp_shuttle_id) if bag_sim != null else null
		if shuttle != null and shuttle.phase == BaggageShuttle.Phase.UNLOADING:
			var cart_pos := shuttle.pose_at(bag_sim.tick, bag_sim.grid).origin
			return [Mode.RAMP_SHUTTLE, cart_pos + Vector3(0.0, 0.85, 0.0), true, SubMode.NONE]
		return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	if m.ramp_job == StaffMember.RampJob.PUSHBACK:
		var target := _pushback_target(m, staff, ctx)
		var fl: FlightSim = ctx.get("flights")
		if fl == null and staff != null and staff.ramp_dispatch != null:
			fl = staff.ramp_dispatch.flights
		var st := fl.state_of(m.ramp_flight_id) if fl != null else -1
		var sub := SubMode.RAMP_HOOKUP if st == FlightSim.State.DOORS_CLOSED else SubMode.RAMP_GUIDE
		return [Mode.RAMP_PUSHBACK, target[0], target[1], sub]
	return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]


static func _cleaner_eval(m: StaffMember, staff: StaffSim) -> Array:
	var grid := staff.sim.grid
	if m.state == StaffMember.State.ON_DUTY:
		if m.bag_carry != StaffMember.BagCarry.NONE:
			var cell := CleanerJobs.bag_cell(staff, m)
			if cell != StaffMember.NO_CELL:
				var pt := grid.origin + Vector3(cell.x, 0.82, cell.y)
				return [Mode.CLEANER, pt, true, SubMode.CLEANER_BAG_TOSS]
			return [Mode.CLEANER, Vector3.ZERO, false, SubMode.CLEANER_BAG_TOSS]
		if m.job_bin:
			var cell := CleanerJobs.job_cell(staff, m)
			if cell != StaffMember.NO_CELL:
				var pt := grid.origin + Vector3(cell.x, 0.78, cell.y)
				return [Mode.CLEANER, pt, true, SubMode.CLEANER_BIN]
			return [Mode.CLEANER, Vector3.ZERO, false, SubMode.CLEANER_BIN]
		if m.job != 0:
			var mess := staff.sim.messes.get_mess(m.job)
			var kind := int(mess.get("kind", MessSim.Kind.LITTER))
			var sub := (
				SubMode.CLEANER_MOP
				if kind == MessSim.Kind.SPILL or kind == MessSim.Kind.TOILET
				else SubMode.CLEANER_SWEEP
			)
			var cell: Vector2i = mess.get("cell", StaffMember.NO_CELL)
			if cell != StaffMember.NO_CELL:
				var pt := grid.origin + Vector3(cell.x, 0.08, cell.y)
				return [Mode.CLEANER, pt, true, sub]
			return [Mode.CLEANER, Vector3.ZERO, false, sub]
	if m.bag_carry != StaffMember.BagCarry.NONE:
		return [Mode.CLEANER, Vector3.ZERO, false, SubMode.CLEANER_BAG_CARRY]
	return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]


static func _security_eval(m: StaffMember, sim: PassengerSim) -> Array:
	var rec := sim.security.record_of(m.station)
	if rec.is_empty():
		return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	var admitted: Array = rec.get("admitted", [])
	if admitted.is_empty():
		return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	var target_id := _security_target_id(m, sim, rec, admitted)
	if target_id == 0:
		return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	var pax := sim.get_passenger(target_id)
	var eye := Vector3(0.0, PASSENGER_EYE_M, 0.0)
	var pos := sim.world_position(pax) + SecurityLooks.target_offset(sim, pax) + eye
	var sec_sub := SubMode.SEC_CLEAN
	if SecurityRuntime.incident_open(pax):
		if pax.security_phase == SecurityRuntime.Phase.BODY_CHECK:
			sec_sub = SubMode.SEC_ALARM
		elif pax.liquids and pax.carry_on > 0 and not pax.bag_resolved:
			sec_sub = SubMode.SEC_LIQUIDS
		elif pax.alarm and not pax.body_resolved:
			sec_sub = SubMode.SEC_ALARM
	var sec_mode := (
		Mode.SECURITY_REPACK
		if pax.security_phase == SecurityRuntime.Phase.REPACK
		else Mode.SECURITY_SCAN
	)
	return [sec_mode, pos, true, sec_sub]


static func _security_target_id(
	m: StaffMember, sim: PassengerSim, rec: Dictionary, admitted: Array
) -> int:
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
					]
				):
					target_id = id
					break
	elif sim.security.is_lane(m.station):
		target_id = int(rec.get("main", 0))
		if target_id == 0:
			for id: int in admitted:
				var q := sim.get_passenger(id)
				if (
					q.security_phase
					in [
						SecurityRuntime.Phase.UNPACK,
						SecurityRuntime.Phase.ARCH,
						SecurityRuntime.Phase.BODY_CHECK,
						SecurityRuntime.Phase.PICKUP,
					]
				):
					target_id = id
					break
		if target_id == 0:
			target_id = int(rec.get("berth", 0))
	else:
		target_id = int(admitted[0])
	return target_id


static func _shop_eval(
	m: StaffMember, sim: PassengerSim, staff_pos: Vector3, ctx: Dictionary
) -> Array:
	var sub := shop_sub_mode(sim.grid, m.station)
	var cid := sim.cafes.serving_at(m.station)
	if cid != 0:
		var pax := sim.get_passenger(cid)
		return [Mode.SHOP, sim.world_position(pax) + Vector3(0.0, PASSENGER_EYE_M, 0.0), true, sub]
	if ctx["info"].has(m.station):
		return [Mode.SHOP, ctx["info"][m.station], true, SubMode.SHOP_INFO_DESK]
	if sub == SubMode.SHOP_RETAIL:
		var pieces: Dictionary = ctx.get("shop_pieces", {})
		if pieces.has(m.station):
			var best_piece := _nearest(staff_pos, pieces[m.station], SHOP_COUNTER_M)
			if best_piece[1]:
				return [Mode.SHOP, best_piece[0], true, sub]
		var room := ShopCounters.room_of(sim.grid, m.station)
		if room != 0 and ctx["shop_rooms"].has(room):
			var best := _nearest(staff_pos, ctx["shop_rooms"][room], SHOP_COUNTER_M)
			if best[1]:
				return [Mode.SHOP, best[0], true, sub]
	return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]


static func _gate_eval(
	m: StaffMember, sim: PassengerSim, staff_pos: Vector3, ctx: Dictionary
) -> Array:
	var gate := ""
	for letter: String in sim.layout.gate_desk_ids:
		if int(sim.layout.gate_desk_ids[letter]) == m.station:
			gate = letter
			break
	if gate == "":
		return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]
	var walkers: Array = ctx["gate_pax"].get(gate, [])
	var nearest := _nearest(staff_pos, walkers, GATE_INTERACT_M)
	if nearest[1]:
		return [Mode.GATE, nearest[0], true, SubMode.NONE]
	return [Mode.NONE, Vector3.ZERO, false, SubMode.NONE]


static func _ambient_look(staff_pos: Vector3, staff_yaw: float, ctx: Dictionary) -> Array:
	var pts: Array = ctx.get("ambient_pax", [])
	if pts.is_empty():
		return [Vector3.ZERO, false]
	var best_pt := Vector3.ZERO
	var best_d := AMBIENT_LOOK_M
	var found := false
	var check_front := not is_nan(staff_yaw)
	var inv_yaw := Basis(Vector3.UP, -staff_yaw) if check_front else Basis.IDENTITY
	for pt: Vector3 in pts:
		var d := staff_pos.distance_to(pt)
		if d > best_d:
			continue
		if check_front and (inv_yaw * (pt - staff_pos)).z < -0.25:
			continue
		best_d = d
		best_pt = pt
		found = true
	return [best_pt, found]


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


static func _pushback_target(m: StaffMember, staff: StaffSim, ctx: Dictionary) -> Array:
	var fleet: PlaneFleet = ctx.get("plane_fleet")
	if fleet != null and m.ramp_flight_id != "":
		for view in fleet.views:
			if view.flight_id == m.ramp_flight_id and view.tug_visible():
				return [view.tug_global_transform().origin + Vector3(0.0, 0.6, 0.0), true]
	return _marshal_target(m, staff, ctx)


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


static func _is_fidget_active(seed_id: int, elapsed_ticks: float) -> bool:
	if elapsed_ticks < float(IDLE_SETTLE_TICKS):
		return false
	var shifted := elapsed_ticks - float(IDLE_SETTLE_TICKS) + float(posmod(seed_id * 47, 100))
	var pos := fposmod(shifted, float(FIDGET_PERIOD_TICKS))
	return pos < float(FIDGET_ACTIVE_TICKS)


static func _cycle_state(now: float, seed_id: int, cycle_sec: float, count: int) -> Dictionary:
	var t := now / float(SimClock.TICK_RATE) + float(posmod(seed_id, 13)) * 0.43
	var cycle_idx := floori(t / cycle_sec)
	var phase := fposmod(t, cycle_sec) / cycle_sec
	var variant := posmod(seed_id * 5 + cycle_idx, count)
	var env := smoothstep(0.0, 0.14, phase) * (1.0 - smoothstep(0.86, 1.0, phase))
	return {"t": t, "phase": phase, "variant": variant, "env": env}


## Applies or disables the StaffStationPose modifier on `node`'s Skeleton3D.
static func pose(
	node: Node3D,
	new_mode: Mode,
	new_weight: float,
	now: float,
	look_deg: Vector2,
	seed_id: int,
	new_sub_mode: SubMode = SubMode.NONE,
	new_idle_since: float = 0.0,
	new_xfade_mode: Mode = Mode.NONE,
	new_xfade_sub_mode: SubMode = SubMode.NONE,
	new_xfade_weight: float = 0.0,
	new_role: int = -1,
) -> void:
	var main_on := new_mode != Mode.NONE and new_weight > 0.0
	var xfade_on := new_xfade_mode != Mode.NONE and new_xfade_weight > 0.0
	var look_on := look_deg.length_squared() > 0.0025
	var on := main_on or xfade_on or look_on
	if not on and not node.has_meta(&"station_pose"):
		return
	var mod := _of(node)
	if mod == null:
		return
	mod.active = on
	mod.mode = new_mode if main_on else Mode.NONE
	mod.sub_mode = new_sub_mode if main_on else SubMode.NONE
	mod.weight = clampf(new_weight, 0.0, 1.0) if main_on else 0.0
	mod.xfade_mode = new_xfade_mode if xfade_on else Mode.NONE
	mod.xfade_sub_mode = new_xfade_sub_mode if xfade_on else SubMode.NONE
	mod.xfade_weight = clampf(new_xfade_weight, 0.0, 1.0) if xfade_on else 0.0
	mod.sim_time = now
	mod.idle_since = new_idle_since
	mod.look_yaw_deg = look_deg.x if on else 0.0
	mod.look_pitch_deg = look_deg.y if on else 0.0
	mod.variant_seed = seed_id
	mod.staff_role = new_role


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
	var w := clampf(weight, 0.0, 1.0)
	var xw := clampf(xfade_weight, 0.0, 1.0)
	var has_main := mode != Mode.NONE and w > 0.0
	var has_xfade := xfade_mode != Mode.NONE and xw > 0.0
	var has_look := absf(look_yaw_deg) >= 0.05 or absf(look_pitch_deg) >= 0.05
	if not has_main and not has_xfade and not has_look:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if has_xfade:
		_apply_role_pose_for(skeleton, xfade_mode, xfade_sub_mode, xw)
	if has_main:
		_apply_role_pose_for(skeleton, mode, sub_mode, w)
	var main_w := w if has_main else 0.0
	var xfade_w := xw if has_xfade else 0.0
	var idle_w := maxf(0.0, 1.0 - main_w - xfade_w)
	var look_w := (
		main_w * (0.35 if mode == Mode.IDLE_FIDGET else 1.0)
		+ xfade_w * (0.35 if xfade_mode == Mode.IDLE_FIDGET else 1.0)
		+ 0.75 * idle_w
	)
	if look_w > 0.0 and has_look:
		_apply_look_at(skeleton, minf(look_w, 1.0))


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


func rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	_rotate_char(skeleton, bone_name, axis_char, deg)


func _apply_role_pose_for(
	skeleton: Skeleton3D, p_mode: Mode, p_sub_mode: SubMode, w: float
) -> void:
	var t := sim_time / float(SimClock.TICK_RATE) + float(posmod(variant_seed, 13)) * 0.43
	var skip_body_life := (
		p_mode == Mode.IDLE_FIDGET
		or p_mode == Mode.BREAK_SEATED
		or p_mode == Mode.BREAK_CHAT
		or (p_mode == Mode.REACTION_STRETCH and p_sub_mode == SubMode.REACT_WALK_YAWN)
		or (p_mode == Mode.CLEANER and p_sub_mode == SubMode.CLEANER_BAG_CARRY)
	)
	if not skip_body_life:
		var deep_legs := (
			p_mode == Mode.RAMP_SHUTTLE
			or (p_mode == Mode.RAMP_PUSHBACK and p_sub_mode == SubMode.RAMP_HOOKUP)
		)
		var knee_scale := 0.25 if deep_legs else (0.35 if p_mode == Mode.CLEANER else 1.0)
		var sway_scale := 0.45 if p_mode == Mode.CLEANER else 1.0
		_apply_body_life(skeleton, t, w, sway_scale, knee_scale)
	match p_mode:
		Mode.CHECKIN:
			_pose_checkin(skeleton, w)
		Mode.SECURITY_SCAN:
			_pose_security_scan(skeleton, p_sub_mode, w)
		Mode.SECURITY_REPACK:
			_pose_security_repack(skeleton, w)
		Mode.SHOP:
			_pose_shop(skeleton, p_sub_mode, w)
		Mode.GATE:
			_pose_gate(skeleton, w)
		Mode.CLEANER:
			_pose_cleaner(skeleton, p_sub_mode, w)
		Mode.RAMP_MARSHAL:
			_pose_marshal(skeleton, w)
		Mode.RAMP_SHUTTLE:
			_pose_ramp_shuttle(skeleton, w)
		Mode.RAMP_PUSHBACK:
			_pose_ramp_pushback(skeleton, p_sub_mode, w)
		Mode.IDLE_FIDGET:
			_pose_idle_fidget(skeleton, p_sub_mode, w)
		_:
			StaffReactionPoses.apply_pose(self, skeleton, p_mode, p_sub_mode, w)


func _apply_body_life(
	skeleton: Skeleton3D, t: float, w: float, sway_scale: float, knee_scale: float
) -> void:
	if w <= 0.0:
		return
	var sway := sin(t * 1.15)
	var breath := 0.5 + 0.5 * sin(t * 2.15)
	var twist := sin(t * 0.85 + 0.7)
	var hips_idx := skeleton.find_bone("Hips")
	if hips_idx >= 0:
		var hips_pose := skeleton.get_bone_global_pose(hips_idx)
		hips_pose.origin.y += (0.006 * sin(t * 2.15) - 0.004 * absf(sway)) * w
		hips_pose.origin.x += 0.012 * sway * sway_scale * w
		hips_pose.basis = (
			Basis(Vector3.UP, deg_to_rad(2.2 * twist * sway_scale * w))
			* Basis(Vector3.BACK, deg_to_rad(2.4 * sway * sway_scale * w))
			* hips_pose.basis
		)
		skeleton.set_bone_global_pose(hips_idx, hips_pose)
	var knee_l := (2.2 + 1.8 * sway) * knee_scale * w
	var knee_r := (2.2 - 1.8 * sway) * knee_scale * w
	_rotate_char(skeleton, "Quad.L", Vector3.RIGHT, -knee_l)
	_rotate_char(skeleton, "Shin.L", Vector3.RIGHT, knee_l * 1.6)
	_rotate_char(skeleton, "Quad.R", Vector3.RIGHT, -knee_r)
	_rotate_char(skeleton, "Shin.R", Vector3.RIGHT, knee_r * 1.6)
	_rotate_char(skeleton, "Spine_01", Vector3.BACK, -1.5 * sway * sway_scale * w)
	_rotate_char(skeleton, "Spine_02", Vector3.UP, 2.0 * cos(t * 1.15) * sway_scale * w)
	_rotate_char(skeleton, "Spine_03", Vector3.RIGHT, 1.8 * breath * w)
	_rotate_char(skeleton, "Spine_03", Vector3.UP, -1.6 * twist * sway_scale * w)
	_rotate_char(skeleton, "Clavicle.L", Vector3.BACK, (1.4 * breath + 0.8 * sway) * w)
	_rotate_char(skeleton, "Clavicle.R", Vector3.BACK, -(1.4 * breath - 0.8 * sway) * w)


func _pose_checkin(skeleton: Skeleton3D, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, CHECKIN_CYCLE_SEC, 3)
	var t := float(c["t"])
	var p := float(c["phase"])
	var env := float(c["env"])
	var variant := int(c["variant"])
	if variant == 1:
		var squint := sin(PI * clampf(p / 0.55, 0.0, 1.0)) * env
		var stamp := pow(maxf(0.0, sin(PI * 2.0 * clampf((p - 0.48) / 0.40, 0.0, 1.0))), 2.0) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.5 + 3.0 * squint) * w)
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, (3.0 + 4.0 * squint) * w)
		_rotate_char(skeleton, "Head", Vector3.BACK, 8.0 * squint * w)
		_rotate_char(skeleton, "Head", Vector3.UP, -10.0 * squint * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-26.0 - 2.0 * env) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.UP, -10.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -46.0 * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 - 8.0 * env + 14.0 * stamp) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, (10.0 - 2.0 * env) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-48.0 - 10.0 * env + 32.0 * stamp) * w)
		return
	if variant == 2:
		var inspect := sin(PI * clampf((p - 0.08) / 0.42, 0.0, 1.0)) * env
		var wave := sin(PI * clampf((p - 0.52) / 0.40, 0.0, 1.0)) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.5 + 2.5 * wave) * w)
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 3.0 * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 10.0 * inspect * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-26.0 + 2.0 * env) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.UP, -10.0 * (1.0 - env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-46.0 + 4.0 * env) * w)
		_rotate_char(
			skeleton,
			"Arm.R",
			Vector3.RIGHT,
			(-30.0 + 2.0 * env - 20.0 * inspect - 16.0 * wave) * w,
		)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, (10.0 + 14.0 * inspect - 30.0 * wave) * w)
		_rotate_char(
			skeleton,
			"Forearm.R",
			Vector3.RIGHT,
			(-48.0 + 2.0 * env - 22.0 * inspect + 24.0 * wave) * w,
		)
		return
	var handoff := 0.0
	if p > 0.56:
		handoff = sin(PI * clampf((p - 0.56) / 0.38, 0.0, 1.0))
		handoff = handoff * handoff * env
	var tap := sin(t * 15.0) * (1.0 - handoff) * env
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.5 + 3.0 * handoff) * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, (3.0 + 0.5 * env) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-26.0 - 2.0 * env) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, (-10.0 - 2.0 * env) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.BACK, 6.0 * env * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-46.0 - 2.0 * env + 6.0 * tap) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 + 2.0 * env - 26.0 * handoff) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, (10.0 + 2.0 * env - 8.0 * handoff) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -6.0 * env * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-48.0 + 30.0 * handoff - 6.0 * tap) * w)
	_rotate_char(skeleton, "Hand.R", Vector3.RIGHT, 12.0 * handoff * w)


func _pose_security_scan(skeleton: Skeleton3D, p_sub_mode: SubMode, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, SECURITY_CYCLE_SEC, 2)
	var t := float(c["t"])
	if p_sub_mode == SubMode.SEC_ALARM:
		var sweep := sin(t * 2.9)
		var arc := cos(t * 2.9)
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 4.0 * w)
		_rotate_char(skeleton, "Spine_02", Vector3.UP, -8.0 * arc * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-48.0 + 14.0 * sweep) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, 20.0 * arc * w)
		_rotate_char(skeleton, "Arm.R", Vector3.BACK, -14.0 * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-46.0 + 12.0 * sweep) * w)
		_rotate_char(skeleton, "Hand.R", Vector3.UP, 16.0 * arc * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -58.0 * w)
		_rotate_char(skeleton, "Arm.L", Vector3.BACK, 14.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -68.0 * w)
		_rotate_char(skeleton, "Hand.L", Vector3.RIGHT, -18.0 * w)
		return
	if p_sub_mode == SubMode.SEC_LIQUIDS:
		var point := 0.5 + 0.5 * sin(t * 2.4)
		var shake := sin(t * 4.8)
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 4.0 * w)
		_rotate_char(skeleton, "Head", Vector3.UP, 15.0 * shake * w)
		_rotate_char(skeleton, "Head", Vector3.BACK, 5.0 * cos(t * 2.4) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-46.0 - 8.0 * point) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.UP, -24.0 * w)
		_rotate_char(skeleton, "Arm.L", Vector3.BACK, 18.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-22.0 + 8.0 * point) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -32.0 * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-44.0 + 6.0 * sin(t * 2.4)) * w)
		return
	var env := float(c["env"])
	var p := float(c["phase"])
	if int(c["variant"]) == 1:
		var scan := sin(PI * p) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 6.0 * scan * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-38.0 + 4.0 * env - 16.0 * scan) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, 12.0 * sin(t * 2.8) * env * w)
		_rotate_char(skeleton, "Arm.R", Vector3.BACK, (-11.0 + env) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-42.0 - 4.0 * env + 14.0 * scan) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-19.0 + 3.0 * env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-26.0 + 2.0 * env) * w)
		return
	var sweep := sin(t * 3.2) * env
	var nod := cos(t * 3.2) * env
	var beckon := sin(t * 2.1) * env
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-38.0 - 4.0 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, 18.0 * sweep * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, (-11.0 - env) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-42.0 + 4.0 * env + 10.0 * nod) * w)
	_rotate_char(skeleton, "Hand.R", Vector3.UP, 12.0 * sweep * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-19.0 - 3.0 * env + 6.0 * beckon) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-26.0 - 2.0 * env + 8.0 * beckon) * w)


func _pose_security_repack(skeleton: Skeleton3D, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, REPACK_CYCLE_SEC, 2)
	var t := float(c["t"])
	var env := float(c["env"])
	if int(c["variant"]) == 1:
		var nod := sin(t * 2.6) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (4.5 - 0.5 * env) * w)
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 1.5 * (1.0 - env) * w)
		_rotate_char(skeleton, "Head", Vector3.BACK, 5.0 * env * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-19.0 - 3.0 * env) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.UP, (-6.0 - 6.0 * env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-36.0 - 12.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 + 6.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, (6.0 + 6.0 * env) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-42.0 - 6.0 * env + 8.0 * nod) * w)
		return
	var gesture := sin(t * 2.4) * env
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (4.5 + 0.5 * env) * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, (1.5 + 1.5 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 - 6.0 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, (6.0 * (1.0 - env) + 10.0 * gesture) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -8.0 * env * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-42.0 + 6.0 * env + 10.0 * gesture) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-19.0 + 3.0 * env) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -6.0 * (1.0 - env) * w)
	_rotate_char(
		skeleton, "Forearm.L", Vector3.RIGHT, (-36.0 + 12.0 * env + 5.0 * cos(t * 2.4) * env) * w
	)


func _pose_shop(skeleton: Skeleton3D, p_sub_mode: SubMode, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, SHOP_CYCLE_SEC, 2)
	var t := float(c["t"])
	var p := float(c["phase"])
	var env := float(c["env"])
	var variant := int(c["variant"])
	if p_sub_mode == SubMode.SHOP_INFO_DESK:
		_pose_info_desk(skeleton, w, t, env, variant)
		return
	if p_sub_mode == SubMode.SHOP_CAFE or p_sub_mode == SubMode.SHOP_BAR:
		_pose_cafe_bar(skeleton, w, t, p, env, variant, p_sub_mode == SubMode.SHOP_BAR)
		return
	_pose_retail(skeleton, w, t, p, env, variant)


func _pose_info_desk(skeleton: Skeleton3D, w: float, t: float, env: float, variant: int) -> void:
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -28.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -14.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -62.0 * w)
	_rotate_char(skeleton, "Hand.L", Vector3.BACK, 10.0 * w)
	if variant == 1:
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 14.0 * env * w)
		_rotate_char(skeleton, "Head", Vector3.UP, 16.0 * env * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-34.0 - 2.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, 22.0 * env * w)
		_rotate_char(
			skeleton, "Forearm.R", Vector3.RIGHT, (-45.0 - 9.0 * env + 8.0 * sin(t * 6.0) * env) * w
		)
		return
	_rotate_char(skeleton, "Spine_02", Vector3.UP, -8.0 * env * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-34.0 - 20.0 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, (-18.0 + 8.0 * sin(t * 2.8)) * env * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -10.0 * env * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-45.0 + 27.0 * env) * w)


func _pose_cafe_bar(
	skeleton: Skeleton3D, w: float, t: float, p: float, env: float, variant: int, is_bar: bool
) -> void:
	if variant == 1:
		var wx := sin(t * 4.5) * env
		var wy := cos(t * 4.5) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (4.5 + 1.5 * env) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-22.0 + 2.0 * env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-41.0 + 5.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-34.0 - 4.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, (3.0 * (1.0 - env) + 20.0 * wx) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-39.0 + 11.0 * env) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.UP, 12.0 * wy * w)
		return
	var pour := sin(PI * clampf(p / 0.45, 0.0, 1.0)) * env
	var slide := sin(PI * clampf((p - 0.45) / 0.50, 0.0, 1.0)) * env
	var shake := sin(t * 9.0) * pour * (8.0 if is_bar else 0.0)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (4.5 - 1.5 * env + 4.0 * slide) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-22.0 - 2.0 * env - 18.0 * pour) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -14.0 * pour * w)
	_rotate_char(
		skeleton, "Forearm.L", Vector3.RIGHT, (-41.0 - 5.0 * env - 14.0 * pour + shake) * w
	)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-34.0 + 4.0 * env - 24.0 * slide) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, (3.0 + 3.0 * env - 6.0 * slide) * w)
	_rotate_char(
		skeleton, "Forearm.R", Vector3.RIGHT, (-39.0 - 11.0 * env + 28.0 * slide - shake) * w
	)


func _pose_retail(
	skeleton: Skeleton3D, w: float, t: float, p: float, env: float, variant: int
) -> void:
	if variant == 1:
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.5 + 3.5 * env) * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 6.0 * env * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-29.0 - 15.0 * env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-50.0 + 22.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 - 16.0 * env) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-46.0 + 20.0 * env) * w)
		return
	var sweep := sin(PI * p) * env
	var tap := sin(t * 12.0) * (1.0 - sweep) * env
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.5 + 0.5 * env) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-29.0 - 3.0 * env) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-50.0 - 2.0 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-30.0 - 4.0 * env) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, -18.0 * sweep * w)
	_rotate_char(
		skeleton, "Forearm.R", Vector3.RIGHT, (-46.0 + 2.0 * env + 8.0 * tap + 12.0 * sweep) * w
	)


func _pose_gate(skeleton: Skeleton3D, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, GATE_CYCLE_SEC, 3)
	var t := float(c["t"])
	var p := float(c["phase"])
	var env := float(c["env"])
	var variant := int(c["variant"])
	if variant == 0:
		var tap := pow(maxf(0.0, sin(PI * clampf((p - 0.15) / 0.40, 0.0, 1.0))), 2.0) * env
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 8.0 * tap * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -24.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -42.0 * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-32.0 - 10.0 * tap) * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-48.0 - 6.0 * env + 24.0 * tap) * w)
		return
	if variant == 2:
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (3.0 + env) * w)
		_rotate_char(skeleton, "Head", Vector3.RIGHT, 12.0 * env * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-24.0 - 6.0 * env) * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-42.0 - 12.0 * env) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-32.0 + 2.0 * env) * w)
		_rotate_char(
			skeleton, "Forearm.R", Vector3.RIGHT, (-48.0 - 2.0 * env + 6.0 * sin(t * 7.0) * env) * w
		)
		return
	var wave := sin(PI * p) * env
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-32.0 - 2.0 * env - 20.0 * wave) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, -16.0 * wave * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, (-6.4 * env - 9.6 * wave) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-48.0 + 6.0 * env + 18.0 * wave) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-24.0 + 6.0 * env) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-42.0 + 12.0 * env) * w)


func _pose_marshal(skeleton: Skeleton3D, w: float) -> void:
	var c := _cycle_state(sim_time, variant_seed, 3.6, 2)
	var t := float(c["t"])
	var env := float(c["env"])
	var phase_shift := 0.0 if int(c["variant"]) == 0 else PI * 0.5 * env
	var beckon_l := sin(t * 5.2)
	var beckon_r := sin(t * 5.2 + phase_shift)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -3.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.BACK, 132.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, 28.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.BACK, (32.0 + 24.0 * beckon_l) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, 18.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, -132.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, 28.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.BACK, (-32.0 - 24.0 * beckon_r) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, 18.0 * w)


func _pose_ramp_shuttle(skeleton: Skeleton3D, w: float) -> void:
	var t := sim_time / float(SimClock.TICK_RATE) + float(posmod(variant_seed, 11)) * 0.37
	var lift := 0.5 - 0.5 * cos(t * 2.8)
	var crouch := 1.0 - 0.5 * lift
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 16.0 * crouch * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 10.0 * crouch * w)
	_rotate_char(skeleton, "Quad.L", Vector3.RIGHT, -14.0 * crouch * w)
	_rotate_char(skeleton, "Shin.L", Vector3.RIGHT, 24.0 * crouch * w)
	_rotate_char(skeleton, "Quad.R", Vector3.RIGHT, -14.0 * crouch * w)
	_rotate_char(skeleton, "Shin.R", Vector3.RIGHT, 24.0 * crouch * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, lerpf(-52.0, -34.0, lift) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -10.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, lerpf(-34.0, -64.0, lift) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, lerpf(-52.0, -34.0, lift) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, 10.0 * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, lerpf(-34.0, -64.0, lift) * w)


func _pose_ramp_pushback(skeleton: Skeleton3D, p_sub_mode: SubMode, w: float) -> void:
	var t := sim_time / float(SimClock.TICK_RATE) + float(posmod(variant_seed, 11)) * 0.37
	if p_sub_mode == SubMode.RAMP_HOOKUP:
		var check := 0.5 - 0.5 * cos(t * 2.4)
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 15.0 * w)
		_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 9.0 * w)
		_rotate_char(skeleton, "Quad.L", Vector3.RIGHT, -12.0 * w)
		_rotate_char(skeleton, "Shin.L", Vector3.RIGHT, 20.0 * w)
		_rotate_char(skeleton, "Quad.R", Vector3.RIGHT, -12.0 * w)
		_rotate_char(skeleton, "Shin.R", Vector3.RIGHT, 20.0 * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -46.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-44.0 - 12.0 * check) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -46.0 * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-44.0 + 12.0 * check) * w)
		return
	var guide := sin(t * 2.2)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -44.0 * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -20.0 * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -82.0 * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-18.0 + 8.0 * guide) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-24.0 + 8.0 * guide) * w)


func _pose_cleaner(skeleton: Skeleton3D, p_sub_mode: SubMode, w: float) -> void:
	var t := sim_time / float(SimClock.TICK_RATE) + float(posmod(variant_seed, 13)) * 0.43
	if p_sub_mode == SubMode.CLEANER_BAG_CARRY:
		_rotate_char(skeleton, "Spine_01", Vector3.BACK, 2.5 * w)
		_rotate_char(skeleton, "Clavicle.R", Vector3.BACK, -3.0 * w)
		return
	if p_sub_mode == SubMode.CLEANER_BAG_TOSS:
		var toss := 0.5 + 0.5 * sin(t * 5.2)
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (8.0 + 4.0 * toss) * w)
		_rotate_char(skeleton, "Spine_02", Vector3.UP, (6.0 * toss) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-52.0 - 18.0 * toss) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, 10.0 * w)
		_rotate_char(skeleton, "Arm.R", Vector3.BACK, -12.0 * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-34.0 - 14.0 * toss) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -14.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -22.0 * w)
		return
	if p_sub_mode == SubMode.CLEANER_BIN:
		var pull := 0.5 + 0.5 * sin(t * 3.8)
		_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (12.0 - 3.0 * pull) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-40.0 - 14.0 * pull) * w)
		_rotate_char(skeleton, "Arm.R", Vector3.UP, 14.0 * w)
		_rotate_char(skeleton, "Arm.R", Vector3.BACK, -8.0 * w)
		_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-44.0 - 10.0 * pull) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-42.0 - 14.0 * pull) * w)
		_rotate_char(skeleton, "Arm.L", Vector3.UP, -14.0 * w)
		_rotate_char(skeleton, "Arm.L", Vector3.BACK, 8.0 * w)
		_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-46.0 - 10.0 * pull) * w)
		return
	var is_mop := p_sub_mode == SubMode.CLEANER_MOP
	var freq := 3.6 if is_mop else 4.6
	var sweep := sin(t * freq)
	var push := cos(t * freq)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, (26.0 if is_mop else 24.0) * w)
	_rotate_char(skeleton, "Spine_02", Vector3.UP, 10.0 * sweep * w)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, (6.0 + 2.0 * push) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-52.0 + 6.0 * push) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, (24.0 + 18.0 * sweep) * w)
	_rotate_char(skeleton, "Arm.R", Vector3.BACK, (20.0 + 4.0 * sweep) * w)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (96.0 + 6.0 * push) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (28.0 - 4.0 * push) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, (-16.0 + 14.0 * sweep) * w)
	_rotate_char(skeleton, "Arm.L", Vector3.BACK, (-28.0 + 4.0 * sweep) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-74.0 + 5.0 * push) * w)
	_rotate_char(skeleton, "Forearm.L", Vector3.BACK, -46.0 * w)
	var hr_idx := skeleton.find_bone("Hand.R")
	var hl_idx := skeleton.find_bone("Hand.L")
	if hr_idx >= 0 and hl_idx >= 0:
		var hr_pose := skeleton.get_bone_global_pose(hr_idx)
		var hl_pose := skeleton.get_bone_global_pose(hl_idx)
		var to_top := hl_pose.origin - hr_pose.origin
		if to_top.length() > 0.05:
			var align := Quaternion(hr_pose.basis.z.normalized(), to_top.normalized())
			hr_pose.basis = Basis(Quaternion.IDENTITY.slerp(align, w)) * hr_pose.basis
			skeleton.set_bone_global_pose(hr_idx, hr_pose)


func _pose_idle_fidget(skeleton: Skeleton3D, p_sub_mode: SubMode, w: float) -> void:
	var elapsed := maxf(sim_time - idle_since, 0.0)
	if elapsed < float(IDLE_SETTLE_TICKS):
		return
	var shifted := elapsed - float(IDLE_SETTLE_TICKS) + float(posmod(variant_seed * 47, 100))
	var pos := fposmod(shifted, float(FIDGET_PERIOD_TICKS))
	if pos >= float(FIDGET_ACTIVE_TICKS):
		return
	var u := clampf(pos / float(FIDGET_ACTIVE_TICKS), 0.0, 1.0)
	var env := sin(PI * u) * w
	var t_idle := sim_time / float(SimClock.TICK_RATE) + float(posmod(variant_seed, 13)) * 0.43
	_apply_body_life(skeleton, t_idle, env, 1.15, 1.15)
	if StaffReactionPoses.apply_lull_pose(self, skeleton, p_sub_mode, env, t_idle):
		return
	var variant := idle_fidget_variant(variant_seed, elapsed)
	match variant:
		0:
			_rotate_char(skeleton, "Neck", Vector3.UP, 14.0 * env)
			_rotate_char(skeleton, "Head", Vector3.UP, 16.0 * env)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, 14.0 * env)
			_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -30.0 * env)
			_rotate_char(skeleton, "Arm.L", Vector3.UP, -22.0 * env)
			_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -68.0 * env)
		1:
			var scan := sin(PI * 2.0 * u) * w
			_rotate_char(skeleton, "Spine_02", Vector3.UP, 6.0 * scan)
			_rotate_char(skeleton, "Spine_03", Vector3.UP, 5.0 * scan)
			_rotate_char(skeleton, "Neck", Vector3.UP, 12.0 * scan)
			_rotate_char(skeleton, "Head", Vector3.UP, 16.0 * scan)
		2:
			if staff_role == StaffMember.Role.SHOP:
				var sip := sin(PI * clampf((u - 0.15) / 0.70, 0.0, 1.0)) * env
				_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -2.5 * env)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, -6.0 * sip)
				_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -38.0 * sip)
				_rotate_char(skeleton, "Arm.R", Vector3.UP, -12.0 * sip)
				_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -64.0 * sip)
				_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -12.0 * env)
				_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -24.0 * env)
			else:
				_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, -4.0 * env)
				_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, -4.0 * env)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, -4.0 * env)
				_rotate_char(skeleton, "Arm.L", Vector3.BACK, 10.0 * env)
				_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, 6.0 * env)
				_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -14.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.BACK, -10.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, 6.0 * env)
				_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -14.0 * env)
		3:
			if staff_role == StaffMember.Role.SHOP:
				var wipe := sin(PI * 4.0 * u) * env
				_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 6.0 * env)
				_rotate_char(skeleton, "Spine_02", Vector3.UP, 8.0 * wipe)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, 10.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -36.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.UP, 18.0 * wipe)
				_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -34.0 * env)
				_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -18.0 * env)
				_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -32.0 * env)
			elif (
				staff_role
				in [StaffMember.Role.CHECKIN, StaffMember.Role.GATE, StaffMember.Role.SECURITY]
			):
				var tap := sin(PI * 3.0 * u) * env
				_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * env)
				_rotate_char(skeleton, "Head", Vector3.RIGHT, 10.0 * env)
				_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -26.0 * env)
				_rotate_char(skeleton, "Arm.L", Vector3.UP, -14.0 * env)
				_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -58.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -28.0 * env)
				_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-46.0 + 10.0 * tap) * env)
			else:
				var dir := 1.0 if posmod(variant_seed, 2) == 0 else -1.0
				_rotate_char(skeleton, "Spine_01", Vector3.BACK, 5.5 * dir * env)
				_rotate_char(skeleton, "Spine_02", Vector3.BACK, -3.5 * dir * env)
				_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, -12.0 * env)
				_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, -22.0 * env)
				_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, -12.0 * env)
				_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, -22.0 * env)


func _rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0 or absf(deg) < 1e-4:
		return
	var bone_pose := skeleton.get_bone_global_pose(idx)
	bone_pose.basis = Basis(axis_char.normalized(), deg_to_rad(deg)) * bone_pose.basis
	skeleton.set_bone_global_pose(idx, bone_pose)
