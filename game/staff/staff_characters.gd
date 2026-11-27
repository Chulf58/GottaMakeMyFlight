class_name StaffCharacters
extends Node3D
## Draws hired staff with pooled Toon characters, one model per role, so staff
## never look like passengers: a check-in agent in a navy skirt suit, a security
## officer in a white shirt and tie, a shop server in a warm burgundy suit, a
## gate agent in azure-teal, a ramp agent in hi-vis safety orange, and a
## cleaner in a blue shirt, grey trousers and red apron (CLEANER_BODY) who, at
## work, plays the clean clip forward and back: no pack has a mop or sweep clip,
## and the closest, a bend to the floor and a pull (tools/blender/anim/toon_clips.py,
## CLEAN_SOURCE), reads as picking litter up and wiping. At a bin it stands
## side-on to the can (bin_yaw()), so the clip's forward bend goes along the
## can's side and never into it; at a mess beside its cell it faces the mess,
## and on a mess's own cell it keeps the way it walked in.
## The cleaner view also owns the mess view (MessViews), which draws the
## messes and full bins the cleaners work on. A member is drawn while it is on
## the floor (not in the pool). Each tick it records the position for the tick
## before and the tick now, keyed by member id, and each frame it draws
## between the two with the clock's alpha, as PassengerViews does.
##
## StaffSim walks a member onto its station's staff spot (StaffSpots: behind
## a desk's counter, beside a scanner's landside half) and puts it on duty
## there, so a member is always drawn where it stands: walking onto the spot
## and off it again is an ordinary walk, with no jump. On duty it faces its
## station's front, the passenger side; a security lane's officer faces its
## work instead (post_yaw()). A fired member walking out to the
## entrance is drawn walking until it is gone.
##
## Walking through a security lane's arch, a member tucks its arms in toward
## the body, eased in and out, so its hands stay clear of the narrow posts
## (StaffArchTuck): the passage state is taken each tick, the weight drawn
## each frame. A snapped sync starts each member's tuck over, settled.
##
## Edits, hires, fires and loads between ticks resync at once (snapped) on the
## next frame, so a paused game shows them. It reads the sim and never writes
## to it.

const AGENT_SUIT := preload("res://assets/people/tcp_female_character_07.glb")
const OFFICER := preload("res://assets/people/tcp_male_character_07.glb")
const CLEANER_BODY := preload("res://assets/people/tcp_female_character_10.glb")
## By StaffMember.Role: CHECKIN, SECURITY, SHOP, CLEANER, GATE, RAMP.
const CHARACTERS: Array[PackedScene] = [
	AGENT_SUIT, OFFICER, AGENT_SUIT, CLEANER_BODY, AGENT_SUIT, OFFICER
]
## Walk clip speeds measured by the Toon pipeline (SPEED lines), by role.
const CLIP_WALK_MPS: Array[float] = [1.922, 1.952, 1.922, 1.922, 1.922, 1.952]
const LOOPED := ["idle", "walk"]
## The cleaner's work clip, played forward and back (it does not loop closed).
const CLEAN_CLIP := "clean"
## Cozy warm burgundy jacket/skirt tint for Shop Servers on AGENT_SUIT:
## keeps the white blouse (-1) and contrasts clearly against navy CHECKIN,
## azure-teal GATE, blue SECURITY, and hi-vis orange RAMP.
const SHOP_SUIT_HUE := 0.96
const SHOP_SUIT_SAT := 0.62
const SHOP_SUIT_VALUE_MIN := 0.34
## Crisp airline azure-teal jacket/skirt tint for Gate Agents on AGENT_SUIT:
## keeps the white blouse (-1) and shifts the dark suit to bright sky-teal.
const GATE_SUIT_HUE := 0.54
const GATE_SUIT_SAT := 0.68
const GATE_SUIT_VALUE_MIN := 0.44
## High-visibility safety orange shirt tint for Ramp Agents on OFFICER.
const RAMP_VEST_HUE := 0.06
const RAMP_VEST_SAT := 0.94
const RAMP_VEST_VALUE_MIN := 0.80
## Role -> [hue, sat, value_min, tint_dark_cells].
const UNIFORM_TINTS := {
	StaffMember.Role.SHOP: [SHOP_SUIT_HUE, SHOP_SUIT_SAT, SHOP_SUIT_VALUE_MIN, true],
	StaffMember.Role.GATE: [GATE_SUIT_HUE, GATE_SUIT_SAT, GATE_SUIT_VALUE_MIN, true],
	StaffMember.Role.RAMP: [RAMP_VEST_HUE, RAMP_VEST_SAT, RAMP_VEST_VALUE_MIN, false],
}
const SHUTTLE_OFFSET := Vector3(0.0, 0.0, -1.25)
const PUSHBACK_TUG_OFFSET := Vector3(-2.15, 0.0, 2.6)
const MARSHAL_SIDE_M := 1.8
const MARSHAL_WALL_GAP_M := 1.2
const BELT_LIFT_M := BaggageViews.BELT_TOP

## Cached tinted meshes/materials by StaffMember.Role without altering .glb rigs.
static var _uniform_meshes: Dictionary = {}
static var _uniform_mats: Dictionary = {}

@export var clock: SimClock
@export var staff: StaffSim
@export var baggage: BaggageSim
@export var flights: FlightSim
@export var plane_fleet: PlaneFleet

var _pool: Array[Array] = [[], [], [], [], [], []]
## Member id -> node.
var _nodes: Dictionary = {}
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _prev_lift: Dictionary = {}
var _cur_lift: Dictionary = {}
var _prev_yaw: Dictionary = {}
var _cur_yaw: Dictionary = {}
## Member id -> its arch tuck record (StaffArchTuck).
var _tucks: Dictionary = {}
## Member id -> its station interaction pose record (StaffStationPose).
var _poses: Dictionary = {}
## Idle Role.RAMP member id -> stable airside staging slot index.
var _ramp_idle_slots: Dictionary = {}
## Role.RAMP member id -> {"was_busy", "returning", "tick"} for smooth job transitions.
var _ramp_state: Dictionary = {}
var _ramp_loop: Dictionary = {}
var _ramp_loop_key := ""
## Something changed between ticks: the next sync snaps instead of interpolating.
var _dirty := false


func _ready() -> void:
	process_priority = 1
	for scene in CHARACTERS:
		var probe := scene.instantiate()
		var player := probe.get_node("AnimationPlayer") as AnimationPlayer
		for clip in LOOPED:
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if player.has_animation(CLEAN_CLIP):
			player.get_animation(CLEAN_CLIP).loop_mode = Animation.LOOP_PINGPONG
		probe.free()
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if staff != null:
		staff.staff_changed.connect(_mark_dirty)
		if staff.sim != null:
			staff.sim.grid.graph_changed.connect(_on_graph_changed)
			var messes := MessViews.new()
			messes.name = "MessViews"
			messes.sim = staff.sim
			add_child(messes)
		sync(true)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		sync(true)
	draw()


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


## A member's recorded position for the tick before (false) or now (true).
func tick_position(id: int, current: bool) -> Vector3:
	return (_cur if current else _prev).get(id, Vector3.ZERO)


## How far member `id` has tucked its arms in for an arch now: 0 swinging, 1
## tucked (StaffArchTuck.weight()).
func tuck_of(id: int) -> float:
	return StaffArchTuck.weight(_tucks.get(id, {}), _now())


## How far member `id`'s station interaction pose is blended in now (0 idle, 1 active).
func station_pose_weight(id: int) -> float:
	var rec: Dictionary = _poses.get(id, {})
	var m := StaffStationPose.mode_of(rec)
	if m == StaffStationPose.Mode.NONE or m == StaffStationPose.Mode.IDLE_FIDGET:
		return 0.0
	var now := _now()
	return StaffStationPose.weight_of(rec, now) * StaffStationPose.crossfade_in(rec, now)


## How far member `id`'s idle fidget beat is blended in now (0 rest, 1 active).
func idle_fidget_weight(id: int) -> float:
	var rec: Dictionary = _poses.get(id, {})
	if StaffStationPose.mode_of(rec) != StaffStationPose.Mode.IDLE_FIDGET:
		return 0.0
	var now := _now()
	return StaffStationPose.weight_of(rec, now) * StaffStationPose.crossfade_in(rec, now)


## Current StaffStationPose.Mode for member `id`.
func station_pose_mode(id: int) -> StaffStationPose.Mode:
	var rec: Dictionary = _poses.get(id, {})
	if not rec.get("active", false) and StaffStationPose.weight_of(rec, _now()) <= 0.0:
		return StaffStationPose.Mode.NONE
	return StaffStationPose.mode_of(rec)


## Current StaffStationPose.SubMode for member `id`.
func station_pose_sub_mode(id: int) -> StaffStationPose.SubMode:
	var rec: Dictionary = _poses.get(id, {})
	if not rec.get("active", false) and StaffStationPose.weight_of(rec, _now()) <= 0.0:
		return StaffStationPose.SubMode.NONE
	return StaffStationPose.sub_mode_of(rec)


## Currently visible hand prop kind on member `id`, or StaffHandProps.PropKind.NONE.
func hand_prop_of(id: int) -> StaffHandProps.PropKind:
	return StaffHandProps.active_prop(node_for(id))


## Vertical step-up height above floor for `m` crossing a baggage belt cell.
static func belt_lift_for(grid: BuildGrid, m: StaffMember) -> float:
	if grid == null or m == null or m.in_pool():
		return 0.0
	if not m.is_moving() or m.seg_mm == 0:
		return BELT_LIFT_M if grid.is_belt_cell(m.at) else 0.0
	var next := m.path[m.path_index + 1]
	var from_belt := grid.is_belt_cell(m.at)
	var to_belt := grid.is_belt_cell(next)
	if from_belt == to_belt:
		return BELT_LIFT_M if from_belt else 0.0
	var t := clampf(float(m.seg_mm) / float(Passenger.segment_mm(m.at, next)), 0.0, 1.0)
	if to_belt:
		return smoothstep(0.1, 0.65, t) * BELT_LIFT_M
	return (1.0 - smoothstep(0.35, 0.9, t)) * BELT_LIFT_M


## Where the member on duty at `station` is drawn, in world space: the
## centre of its staff spot.
func post_position(station: int) -> Vector3:
	return staff.sim.grid.cell_to_world(staff.spot_of(station))


## The yaw a member on duty at `station` in `slot` is drawn with: at a whole
## security lane, looking at its work (the primary officer at the X-ray belt,
## the helper at the repack berth, each beside it); elsewhere facing the
## station's front.
func post_yaw(station: int, slot: StaffMember.Slot = StaffMember.Slot.PRIMARY) -> float:
	var lane := staff.sim.layout.security_lanes.lane(station)
	if not lane.is_empty():
		var work: Vector2i = lane["berth" if slot == StaffMember.Slot.HELPER else "xray_belt"]
		var ahead := work - staff.spot_of(station, slot)
		return atan2(ahead.x, ahead.y)
	var front := TerminalLayout.front_of(staff.sim.grid.get_object(station)["facing"])
	return atan2(front.x, front.y)


## The yaw a cleaner emptying the bin on `bin` from `spot` is drawn with:
## side-on to the can, a quarter turn from facing it, toward the side whose
## next cell is walkable (the clip bends forward over about 0.65 m), the
## clockwise side when both or neither are.
func bin_yaw(spot: Vector2i, bin: Vector2i) -> float:
	var ahead := bin - spot
	var side := Vector2i(-ahead.y, ahead.x)
	if not staff.sim.grid.is_walkable(spot + side) and staff.sim.grid.is_walkable(spot - side):
		side = -side
	return atan2(side.x, side.y)


## Records positions for the members on the floor and updates their poses. With
## `snap` both recorded positions are set to now, so nothing glides.
func sync(snap: bool = false) -> void:
	var seen := {}
	var pose_ctx := StaffStationPose.build_context(staff, _flights(), plane_fleet, _baggage())
	var tick_now := _tick()
	if snap:
		_ramp_idle_slots.clear()
		_ramp_state.clear()
		_ramp_loop.clear()
		_ramp_loop_key = ""
		_prev_yaw.clear()
		_cur_yaw.clear()
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role == StaffMember.Role.RAMP and not (m.is_on_break() and not m.in_pool()):
			if m.state == StaffMember.State.OFF_SHIFT:
				continue
			var ramp_pose := {}
			var job_started := false
			if m.ramp_job == StaffMember.RampJob.NONE:
				var slot_idx := _assign_ramp_idle_slot(id)
				ramp_pose = _idle_ramp_patrol_pose(
					id, slot_idx, _cached_ramp_loop(), tick_now, snap
				)
			else:
				_ramp_idle_slots.erase(id)
				job_started = not bool(_ramp_state.get(id, {}).get("was_busy", false))
				ramp_pose = _ramp_pose(m)
				_ramp_state[id] = {"was_busy": true, "returning": false, "tick": int(tick_now)}
			if ramp_pose.is_empty():
				continue
			seen[id] = true
			var node: Node3D = _nodes.get(id)
			if node != null and node.get_meta(&"role") != m.role:
				_release(id)
				node = null
			var fresh := node == null
			if fresh:
				node = _take(m.role)
				_nodes[id] = node
			var ramp_now: Vector3 = ramp_pose["pos"]
			var ramp_yaw := float(ramp_pose["yaw"])
			if snap or fresh or job_started:
				_prev[id] = ramp_now
				_prev_yaw[id] = ramp_yaw
				node.position = ramp_now
			else:
				_prev[id] = _cur[id]
				_prev_yaw[id] = _cur_yaw.get(id, ramp_yaw)
			_cur[id] = ramp_now
			_cur_yaw[id] = ramp_yaw
			node.rotation.y = ramp_yaw
			_play_clip(node, String(ramp_pose["clip"]), float(ramp_pose["speed"]))
			if job_started:
				_poses.erase(id)
			if snap:
				_tucks.erase(id)
				_poses.erase(id)
				StaffHandProps.hide_all(node)
			var ramp_eval := StaffStationPose.evaluate(
				m, staff, ramp_now, pose_ctx, node.rotation.y
			)
			var ramp_look := StaffStationPose.compute_look_deg(
				ramp_now, node.rotation.y, ramp_eval[1], ramp_eval[2]
			)
			(
				StaffStationPose
				. update(
					_poses.get_or_add(id, {}),
					ramp_eval[0],
					ramp_look,
					tick_now,
					ramp_eval[3],
					bool(ramp_pose.get("can_fidget", false)),
					id,
				)
			)
			continue
		if m.in_pool():
			continue
		seen[id] = true
		var node: Node3D = _nodes.get(id)
		if node != null and node.get_meta(&"role") != m.role:
			_release(id)
			node = null
		var fresh := node == null
		if fresh:
			node = _take(m.role)
			_nodes[id] = node
		var now := staff.world_position(m)
		var lift := belt_lift_for(_grid(), m)
		if snap or fresh:
			_prev[id] = now
			_prev_lift[id] = lift
		else:
			_prev[id] = _cur[id]
			_prev_lift[id] = _cur_lift.get(id, lift)
		_cur[id] = now
		_cur_lift[id] = lift
		_pose(node, m, (_cur[id] as Vector3) - (_prev[id] as Vector3))
		# A snapped sync (a load among them: member ids survive it) starts the
		# tuck, station pose and hand props over, settled where the member stands.
		if snap:
			_tucks.erase(id)
			_poses.erase(id)
			StaffHandProps.hide_all(node)
		var inside := StaffArchTuck.in_arch_passage(staff.sim.grid, m)
		StaffArchTuck.update(_tucks.get_or_add(id, {}), inside, tick_now)
		var eval := StaffStationPose.evaluate(m, staff, now, pose_ctx, node.rotation.y)
		var look := StaffStationPose.compute_look_deg(now, node.rotation.y, eval[1], eval[2])
		var cleaner_busy := (
			m.role == StaffMember.Role.CLEANER
			and (m.state == StaffMember.State.ON_DUTY or m.bag_carry != StaffMember.BagCarry.NONE)
		)
		var can_fidget := (
			not m.in_pool()
			and not m.is_walking_to_exit()
			and not m.is_moving()
			and not cleaner_busy
			and not inside
		)
		(
			StaffStationPose
			. update(
				_poses.get_or_add(id, {}),
				eval[0],
				look,
				tick_now,
				eval[3],
				can_fidget,
				id,
			)
		)
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)


## Places every node between its last two tick positions.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var paused := clock == null or clock.paused
	var now := _now()
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var m := staff.get_member(id) if staff != null else null
		if (
			m != null
			and m.role == StaffMember.Role.RAMP
			and m.ramp_job == StaffMember.RampJob.PUSHBACK
		):
			var tug_xform := _live_tug_transform(m.ramp_flight_id)
			if tug_xform != Transform3D.IDENTITY:
				var pos := tug_xform * PUSHBACK_TUG_OFFSET
				pos.y = BaggageShuttle.ground_y(_grid(), pos)
				node.position = pos
				var fwd := tug_xform.basis.z.slide(Vector3.UP)
				if fwd.length() > 0.001:
					node.rotation.y = atan2(fwd.x, fwd.z)
			else:
				node.position = (_prev[id] as Vector3).lerp(_cur[id], alpha)
				if _prev_yaw.has(id) and _cur_yaw.has(id):
					node.rotation.y = lerp_angle(float(_prev_yaw[id]), float(_cur_yaw[id]), alpha)
		else:
			var pos := (_prev[id] as Vector3).lerp(_cur[id], alpha)
			pos.y += lerpf(float(_prev_lift.get(id, 0.0)), float(_cur_lift.get(id, 0.0)), alpha)
			node.position = pos
			if _prev_yaw.has(id) and _cur_yaw.has(id):
				node.rotation.y = lerp_angle(float(_prev_yaw[id]), float(_cur_yaw[id]), alpha)
		var pose_rec: Dictionary = _poses.get(id, {})
		var draw_mode := StaffStationPose.mode_of(pose_rec)
		var draw_sub := StaffStationPose.sub_mode_of(pose_rec)
		var draw_w := StaffStationPose.weight_of(pose_rec, now)
		var xfade_in := StaffStationPose.crossfade_in(pose_rec, now)
		var xfade_out := StaffStationPose.crossfade_out(pose_rec, now)
		var xfade_m := StaffStationPose.xfade_mode_of(pose_rec)
		var xfade_s := StaffStationPose.xfade_sub_mode_of(pose_rec)
		var draw_look := StaffStationPose.look_of(pose_rec, now)
		var idle_since := StaffStationPose.idle_since_of(pose_rec, now)
		(
			StaffStationPose
			. pose(
				node,
				draw_mode,
				draw_w * xfade_in,
				now,
				draw_look,
				id,
				draw_sub,
				idle_since,
				xfade_m,
				xfade_s,
				xfade_out,
				m.role if m != null else -1,
			)
		)
		var tuck_w := StaffArchTuck.weight(_tucks.get(id, {}), now)
		StaffArchTuck.pose(node, tuck_w)
		var walking := m != null and (m.is_moving() or String(node.get_meta(&"clip", "")) == "walk")
		var is_cleaner := m != null and m.role == StaffMember.Role.CLEANER
		var cleaner_working := is_cleaner and m.state == StaffMember.State.ON_DUTY
		var cleaner_bag := (
			is_cleaner
			and m.bag_carry != StaffMember.BagCarry.NONE
			and (m.state == StaffMember.State.TO_STATION or m.state == StaffMember.State.ON_DUTY)
		)
		var cleaner_walking_to_mess := (
			is_cleaner
			and m.is_moving()
			and m.state == StaffMember.State.TO_STATION
			and m.job != 0
			and not m.job_bin
			and m.bag_carry == StaffMember.BagCarry.NONE
		)
		var cleaner_patrolling := (
			is_cleaner
			and m.is_moving()
			and (m.state == StaffMember.State.IDLE or cleaner_walking_to_mess)
		)
		(
			StaffHandProps
			. update(
				node,
				draw_mode,
				draw_sub,
				draw_w * xfade_in,
				now,
				id,
				walking,
				tuck_w > 0.0,
				m.role if m != null else -1,
				m.job_bin if m != null else false,
				cleaner_working,
				cleaner_patrolling,
				cleaner_bag,
			)
		)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		player.speed_scale = 0.0 if paused else base * clock.speed


func _on_ticked(_tick: int) -> void:
	var snap := _dirty
	_dirty = false
	sync(snap)


## Inside a tick the tick's own sync shows the change; between ticks the next
## frame resyncs.
func _mark_dirty() -> void:
	if clock == null or not clock.is_in_tick():
		_dirty = true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_ramp_loop.clear()
	_ramp_loop_key = ""
	_mark_dirty()


func _take(role: StaffMember.Role) -> Node3D:
	var free: Array = _pool[role]
	var node: Node3D
	if not free.is_empty():
		node = free.pop_back()
		node.visible = true
		StaffHandProps.hide_all(node)
	else:
		node = CHARACTERS[role].instantiate() as Node3D
		if UNIFORM_TINTS.has(role):
			_apply_role_uniform(node, role)
		node.set_meta(&"role", role)
		add_child(node)
	node.rotation.y = 0.0
	return node


## Splits the character's clothes surface and applies the role's UNIFORM_TINTS
## colour on a cached ArrayMesh without altering .glb rigs or adding per-instance
## surface overrides (Dummy renderer logs null material errors on override free).
static func _apply_role_uniform(node: Node3D, role: StaffMember.Role) -> void:
	var mi := PassengerLooks.body_mesh(node)
	if mi == null:
		return
	if not _uniform_meshes.has(role):
		_uniform_meshes[role] = _build_tinted_mesh(mi.mesh, role)
	mi.mesh = _uniform_meshes[role]


static func _build_tinted_mesh(plain: Mesh, role: StaffMember.Role) -> Mesh:
	var arrays := plain.surface_get_arrays(0)
	var parts := PassengerLooks.cloth_split(arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR])
	if parts[1].is_empty():
		return plain
	return _split_cloth_mesh(plain, arrays, parts, _tinted_material(plain, parts[1], role))


static func _split_cloth_mesh(
	plain: Mesh, arrays: Array, parts: Array, cloth_mat: ShaderMaterial
) -> Mesh:
	var flags: int = (plain as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	for i in 2:
		arrays[Mesh.ARRAY_INDEX] = parts[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, plain.surface_get_material(0))
	mesh.surface_set_material(1, cloth_mat)
	return mesh


static func _tinted_material(
	plain: Mesh, cloth_index: PackedInt32Array, role: StaffMember.Role
) -> ShaderMaterial:
	if _uniform_mats.has(role):
		return _uniform_mats[role]
	var spec: Array = UNIFORM_TINTS[role]
	var hue := float(spec[0])
	var sat := float(spec[1])
	var value_min := float(spec[2])
	var tint_dark := bool(spec[3])
	var base := plain.surface_get_material(0) as ShaderMaterial
	var made := base.duplicate() as ShaderMaterial
	var atlas := (base.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	if atlas != null:
		atlas = atlas.duplicate() as Image
		if atlas.is_compressed():
			atlas.decompress()
		if atlas.has_mipmaps():
			atlas.clear_mipmaps()
		var width := atlas.get_width()
		var height := atlas.get_height()
		var uvs: PackedVector2Array = plain.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var texels := _cloth_texels(uvs, cloth_index, width, height)
		var dark := PassengerLooks.dark_cells(atlas, texels)
		var cols := width / PassengerLooks.SWATCH_PX.x
		for t in texels:
			var x := t % width
			var y := t / width
			var is_dark: bool = dark.get(
				(y / PassengerLooks.SWATCH_PX.y) * cols + x / PassengerLooks.SWATCH_PX.x, false
			)
			if is_dark == tint_dark:
				var c := atlas.get_pixel(x, y)
				var v := value_min + (1.0 - value_min) * c.v
				atlas.set_pixel(x, y, Color.from_hsv(hue, sat, v, c.a))
		atlas.generate_mipmaps()
		made.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(atlas))
	_uniform_mats[role] = made
	return made


static func _cloth_texels(
	uvs: PackedVector2Array, index: PackedInt32Array, width: int, height: int
) -> PackedInt32Array:
	var mark := {}
	var margin := PassengerLooks.TEXEL_MARGIN
	for t in range(0, index.size(), 3):
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 3:
			var at := uvs[index[t + k]] * Vector2(width, height)
			lo = lo.min(at)
			hi = hi.max(at)
		var x1 := mini(int(hi.x) + margin, width - 1)
		var y1 := mini(int(hi.y) + margin, height - 1)
		for y in range(maxi(int(lo.y) - margin, 0), y1 + 1):
			for x in range(maxi(int(lo.x) - margin, 0), x1 + 1):
				mark[y * width + x] = true
	var out := PackedInt32Array(mark.keys())
	out.sort()
	return out


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	(node.get_node("AnimationPlayer") as AnimationPlayer).stop()
	node.set_meta(&"clip", "")
	StaffStationPose.pose(node, StaffStationPose.Mode.NONE, 0.0, 0.0, Vector2.ZERO, 0)
	StaffArchTuck.pose(node, 0.0)
	StaffHandProps.hide_all(node)
	_pool[node.get_meta(&"role")].append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)
	_prev_lift.erase(id)
	_cur_lift.erase(id)
	_prev_yaw.erase(id)
	_cur_yaw.erase(id)
	_tucks.erase(id)
	_poses.erase(id)
	_ramp_idle_slots.erase(id)
	_ramp_state.erase(id)


func _assign_ramp_idle_slot(id: int) -> int:
	if _ramp_idle_slots.has(id):
		return int(_ramp_idle_slots[id])
	var used := {}
	for existing_slot: int in _ramp_idle_slots.values():
		used[existing_slot] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	_ramp_idle_slots[id] = slot
	return slot


## Sim time now, between ticks: the tick and the clock's alpha.
func _now() -> float:
	return clock.tick + clock.alpha if clock != null else 0.0


func _tick() -> float:
	return float(clock.tick) if clock != null else 0.0


## `moved` is the step drawn between the two recorded positions; a walker faces
## it, or its next path cell when it was just placed (no step to draw yet).
func _pose(node: Node3D, m: StaffMember, moved: Vector3) -> void:
	var clip := "idle"
	var base := 1.0
	if m.state == StaffMember.State.ON_DUTY and m.role == StaffMember.Role.CLEANER:
		clip = "idle"
		var target := (
			CleanerJobs.bag_cell(staff, m)
			if m.bag_carry != StaffMember.BagCarry.NONE
			else CleanerJobs.job_cell(staff, m)
		)
		var ahead := target - m.at
		if ahead != Vector2i.ZERO and target != StaffMember.NO_CELL:
			node.rotation.y = atan2(ahead.x, ahead.y)
		elif moved.length() > 0.001:
			node.rotation.y = atan2(moved.x, moved.z)
	elif m.state == StaffMember.State.ON_DUTY:
		node.rotation.y = post_yaw(m.station, m.slot)
	elif m.is_moving():
		clip = "walk"
		base = (PassengerSim.WALK_MM * SimClock.TICK_RATE / 1000.0) / CLIP_WALK_MPS[m.role]
		if moved.length() > 0.001:
			node.rotation.y = atan2(moved.x, moved.z)
		else:
			var ahead := m.path[m.path_index + 1] - m.at
			node.rotation.y = atan2(ahead.x, ahead.y)
	_play_clip(node, clip, base)


func _play_clip(node: Node3D, clip: String, base: float) -> void:
	node.set_meta(&"base_speed", base)
	if node.get_meta(&"clip", "") != clip:
		node.set_meta(&"clip", clip)
		(node.get_node("AnimationPlayer") as AnimationPlayer).play(clip)


func _baggage() -> BaggageSim:
	if baggage != null:
		return baggage
	if staff != null and staff.ramp_dispatch != null:
		return staff.ramp_dispatch.baggage
	return null


func _flights() -> FlightSim:
	if flights != null:
		return flights
	if staff != null and staff.ramp_dispatch != null:
		return staff.ramp_dispatch.flights
	return null


func _grid() -> BuildGrid:
	return staff.sim.grid if staff != null and staff.sim != null else null


func _live_tug_transform(flight_id: String) -> Transform3D:
	if plane_fleet == null or flight_id == "":
		return Transform3D.IDENTITY
	for view in plane_fleet.views:
		if view.flight_id == flight_id and view.tug_visible():
			return view.tug_global_transform()
	return Transform3D.IDENTITY


func _ramp_pose(m: StaffMember) -> Dictionary:
	if m.ramp_job == StaffMember.RampJob.SHUTTLE:
		return _shuttle_pose(m)
	if m.ramp_job == StaffMember.RampJob.PUSHBACK:
		return _pushback_pose(m)
	if m.ramp_job == StaffMember.RampJob.MARSHAL:
		return _marshal_pose(m)
	return {}


func _idle_ramp_patrol_pose(
	id: int, slot_idx: int, ramp_loop: Dictionary, tick_now: float, snap: bool
) -> Dictionary:
	var grid := _grid()
	var patrol := RampPatrol.sample(ramp_loop, tick_now, slot_idx, grid)
	var prev_st: Dictionary = _ramp_state.get(id, {})
	var rolled_back := prev_st.is_empty() or int(prev_st.get("tick", int(tick_now))) > int(tick_now)
	var returning_from_job := (
		not snap
		and not rolled_back
		and (bool(prev_st.get("was_busy", false)) or bool(prev_st.get("returning", false)))
		and _cur.has(id)
	)
	if returning_from_job:
		var from_pos := _cur[id] as Vector3
		var step_m := RampPatrol.PATROL_WALK_MPS / float(SimClock.TICK_RATE)
		var path: Array = prev_st.get("path", [])
		var idx := int(prev_st.get("idx", 1))
		if bool(prev_st.get("was_busy", false)):
			var plan := _plan_ramp_return(from_pos, patrol["pos"], ramp_loop, tick_now, slot_idx)
			if not bool(plan["ok"]):
				_ramp_state[id] = {"was_busy": false, "returning": false, "tick": int(tick_now)}
				return patrol
			path = plan["points"]
			idx = 1
		var step := _step_return_path(from_pos, path, idx, step_m, grid)
		if not step.is_empty():
			_ramp_state[id] = {
				"was_busy": false,
				"returning": true,
				"path": path,
				"idx": int(step["idx"]),
				"tick": int(tick_now),
			}
			return step["pose"]
	_ramp_state[id] = {"was_busy": false, "returning": false, "tick": int(tick_now)}
	return patrol


func _plan_ramp_return(
	from_pos: Vector3,
	patrol_pos: Vector3,
	ramp_loop: Dictionary,
	tick_now: float,
	slot_idx: int,
) -> Dictionary:
	var grid := _grid()
	var fl := _flights()
	var plan0 := RampPatrol.plan_return_path(from_pos, patrol_pos, fl, grid)
	if not bool(plan0["ok"]):
		return plan0
	var pts: Array = plan0["points"]
	var dist_m := 0.0
	for i in pts.size() - 1:
		var a := pts[i] as Vector3
		var b := pts[i + 1] as Vector3
		dist_m += Vector2(b.x - a.x, b.z - a.z).length()
	var step_m := RampPatrol.PATROL_WALK_MPS / float(SimClock.TICK_RATE)
	var est_ticks := roundi(dist_m / step_m)
	if est_ticks <= 1:
		return plan0
	var arr_pose := RampPatrol.sample(ramp_loop, tick_now + float(est_ticks), slot_idx, grid)
	var plan_arr := RampPatrol.plan_return_path(from_pos, arr_pose["pos"], fl, grid)
	return plan_arr if bool(plan_arr["ok"]) else plan0


func _step_return_path(
	from_pos: Vector3, path: Array, idx: int, step_m: float, grid: BuildGrid
) -> Dictionary:
	var flat_from := Vector2(from_pos.x, from_pos.z)
	var cur_idx := idx
	while cur_idx < path.size():
		var wp := path[cur_idx] as Vector3
		var wp2 := Vector2(wp.x, wp.z)
		var dist := flat_from.distance_to(wp2)
		if dist <= 1e-4:
			cur_idx += 1
			continue
		var dir := wp2 - flat_from
		var next_2d := wp2 if dist <= step_m else flat_from.move_toward(wp2, step_m)
		var next_idx := cur_idx + 1 if dist <= step_m else cur_idx
		var next_pos := Vector3(
			next_2d.x,
			BaggageShuttle.ground_y(grid, Vector3(next_2d.x, 0.0, next_2d.y)),
			next_2d.y,
		)
		return {
			"idx": next_idx,
			"pose":
			{
				"pos": next_pos,
				"yaw": atan2(dir.x, dir.y),
				"clip": "walk",
				"speed": RampPatrol.PATROL_WALK_MPS / CLIP_WALK_MPS[StaffMember.Role.RAMP],
				"can_fidget": false,
			},
		}
	return {}


func _cached_ramp_loop() -> Dictionary:
	var fl := _flights()
	var key := ""
	if fl != null:
		if fl.stand_source.is_valid() or fl.remote_ground_source.is_valid():
			key = str(fl.stand_grounds())
		else:
			var fids := fl.flight_ids()
			if not fids.is_empty():
				key = str(fl.flight_stand(fids[0]))
	if _ramp_loop.is_empty() or key != _ramp_loop_key:
		_ramp_loop_key = key
		_ramp_loop = RampPatrol.build_loop(fl, _grid(), staff)
	return _ramp_loop


func _shuttle_pose(m: StaffMember) -> Dictionary:
	var bag_sim := _baggage()
	var shuttle := bag_sim.get_shuttle(m.ramp_shuttle_id) if bag_sim != null else null
	if shuttle == null:
		return {}
	var cart_xform := shuttle.pose_at(bag_sim.tick, bag_sim.grid)
	var pos := cart_xform * SHUTTLE_OFFSET
	pos.y = BaggageShuttle.ground_y(bag_sim.grid, pos)
	if shuttle.phase == BaggageShuttle.Phase.UNLOADING:
		var to_cart := cart_xform.origin - pos
		return {"pos": pos, "yaw": atan2(to_cart.x, to_cart.z), "clip": "idle", "speed": 1.0}
	var forward := cart_xform.basis.z.slide(Vector3.UP)
	var yaw := atan2(forward.x, forward.z) if forward.length() > 0.001 else 0.0
	var next_xform := shuttle.pose_at(bag_sim.tick + 1, bag_sim.grid)
	var step_m := (next_xform * SHUTTLE_OFFSET - pos).slide(Vector3.UP).length()
	var speed := clampf((step_m * SimClock.TICK_RATE) / CLIP_WALK_MPS[m.role], 0.5, 2.5)
	return {"pos": pos, "yaw": yaw, "clip": "walk", "speed": speed}


func _pushback_pose(m: StaffMember) -> Dictionary:
	var flight_sim := _flights()
	var state := flight_sim.state_of(m.ramp_flight_id) if flight_sim != null else -1
	var clip := "idle" if state == FlightSim.State.DOORS_CLOSED else "walk"
	var tug_xform := _live_tug_transform(m.ramp_flight_id)
	if tug_xform != Transform3D.IDENTITY:
		var live_pos := tug_xform * PUSHBACK_TUG_OFFSET
		live_pos.y = BaggageShuttle.ground_y(_grid(), live_pos)
		var fwd := tug_xform.basis.z.slide(Vector3.UP)
		var live_yaw := atan2(fwd.x, fwd.z) if fwd.length() > 0.001 else 0.0
		return {"pos": live_pos, "yaw": live_yaw, "clip": clip, "speed": 1.0}
	if flight_sim == null:
		return {}
	var stand := flight_sim.flight_stand(m.ramp_flight_id)
	if stand.is_empty():
		return {}
	var model := PlaneClasses.flight_model(flight_sim, m.ramp_flight_id)
	var twin := StandPlacement.north_twin(stand)
	var stand_pt := StandPlacement.stand_point(twin)
	var nose_z := (
		stand_pt.z + float(PlaneModels.PLANES.get(model, {}).get("nose", StandPlacement.NOSE_M))
	)
	var pos := StandPlacement.to_world(
		stand, Vector3(stand_pt.x, 0.0, nose_z) + PUSHBACK_TUG_OFFSET
	)
	pos.y = BaggageShuttle.ground_y(_grid(), pos)
	return {
		"pos": pos,
		"yaw": StandPlacement.SIDE_YAW[StandPlacement.side_of(stand)],
		"clip": clip,
		"speed": 1.0,
	}


func _marshal_pose(m: StaffMember) -> Dictionary:
	var flight_sim := _flights()
	if flight_sim == null:
		return {}
	var stand := flight_sim.flight_stand(m.ramp_flight_id)
	if stand.is_empty():
		return {}
	var twin := StandPlacement.north_twin(stand)
	var stand_pt := StandPlacement.stand_point(twin)
	var local_pos := Vector3(
		stand_pt.x - MARSHAL_SIDE_M, 0.0, float(twin["wall_z"]) - MARSHAL_WALL_GAP_M
	)
	var pos := StandPlacement.to_world(stand, local_pos)
	pos.y = BaggageShuttle.ground_y(_grid(), pos)
	return {
		"pos": pos,
		"yaw": StandPlacement.SIDE_YAW[StandPlacement.side_of(stand)] + PI,
		"clip": "idle",
		"speed": 1.0,
	}
