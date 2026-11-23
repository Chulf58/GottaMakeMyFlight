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
## Member id -> its arch tuck record (StaffArchTuck).
var _tucks: Dictionary = {}
## Member id -> its station interaction pose record (StaffStationPose).
var _poses: Dictionary = {}
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
	return StaffStationPose.weight_of(rec, _now())


## How far member `id`'s idle fidget beat is blended in now (0 rest, 1 active).
func idle_fidget_weight(id: int) -> float:
	var rec: Dictionary = _poses.get(id, {})
	if StaffStationPose.mode_of(rec) != StaffStationPose.Mode.IDLE_FIDGET:
		return 0.0
	return StaffStationPose.weight_of(rec, _now())


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
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.role == StaffMember.Role.RAMP:
			if m.ramp_job == StaffMember.RampJob.NONE:
				continue
			var ramp_pose := _ramp_pose(m)
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
			if snap or fresh:
				_prev[id] = ramp_now
			else:
				_prev[id] = _cur[id]
			_cur[id] = ramp_now
			node.rotation.y = float(ramp_pose["yaw"])
			_play_clip(node, String(ramp_pose["clip"]), float(ramp_pose["speed"]))
			if snap:
				_tucks.erase(id)
				_poses.erase(id)
				StaffHandProps.hide_all(node)
			var ramp_eval := StaffStationPose.evaluate(m, staff, ramp_now, pose_ctx)
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
					false,
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
		if snap or fresh:
			_prev[id] = now
		else:
			_prev[id] = _cur[id]
		_cur[id] = now
		_pose(node, m, (_cur[id] as Vector3) - (_prev[id] as Vector3))
		# A snapped sync (a load among them: member ids survive it) starts the
		# tuck, station pose and hand props over, settled where the member stands.
		if snap:
			_tucks.erase(id)
			_poses.erase(id)
			StaffHandProps.hide_all(node)
		var inside := StaffArchTuck.in_arch_passage(staff.sim.grid, m)
		StaffArchTuck.update(_tucks.get_or_add(id, {}), inside, tick_now)
		var eval := StaffStationPose.evaluate(m, staff, now, pose_ctx)
		var look := StaffStationPose.compute_look_deg(now, node.rotation.y, eval[1], eval[2])
		var cleaner_busy := (
			m.role == StaffMember.Role.CLEANER and m.state == StaffMember.State.ON_DUTY
		)
		var can_fidget := (
			not m.in_pool()
			and m.state != StaffMember.State.WALKING_OUT
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
		else:
			node.position = (_prev[id] as Vector3).lerp(_cur[id], alpha)
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
			)
		)
		var tuck_w := StaffArchTuck.weight(_tucks.get(id, {}), now)
		StaffArchTuck.pose(node, tuck_w)
		var walking := m != null and (m.is_moving() or String(node.get_meta(&"clip", "")) == "walk")
		StaffHandProps.update(
			node, draw_mode, draw_sub, draw_w * xfade_in, now, id, walking, tuck_w > 0.0
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
	_tucks.erase(id)
	_poses.erase(id)


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
		clip = CLEAN_CLIP
		var job := CleanerJobs.job_cell(staff, m)
		var ahead := job - m.at
		if ahead != Vector2i.ZERO and job != StaffMember.NO_CELL:
			node.rotation.y = bin_yaw(m.at, job) if m.job_bin else atan2(ahead.x, ahead.y)
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
