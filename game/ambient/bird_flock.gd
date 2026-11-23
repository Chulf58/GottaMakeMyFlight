class_name BirdFlock
extends Node3D
## Ambient crows (decisions ambient-birds-the-toon-farm-pack-crow-small-silent-
## flocks-th and ambient-birds-ground-life-elevated-perches-and-scatter-polish):
## small flocks of the Toon Farm Pack crow perch on landside curbs, sidewalks,
## grass verges, benches, streetlights and tree crowns, stroll within ground
## patches, and scatter cleanly (with subtle takeoff puff and cooldown-gated
## audio) when a car or passenger comes near.
##
## View-local: the flock has its own RandomNumberGenerator, keeps no sim tick
## and is not saved. A load throws every bird away and perches new groups
## (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-start-over-on-l).
##
## Time: the flock runs on SimClock's time, freezing poses, strolling, flight
## banking and takeoff puffs when paused, and scaling playback at 3x.

const CROW := preload("res://assets/birds/tfp_crow_01.glb")
const VARIANTS: Array[String] = ["TFP_Crow_01A", "TFP_Crow_01B", "TFP_Crow_01C"]
## Ground groups per zone (BirdPerches.Zone) and extra elevated lookout groups.
const ZONE_GROUPS: Array[int] = [3, 2, 3]
const ELEVATED_GROUPS := 4
const GROUP_MIN := 1
const GROUND_GROUP_MIN := 2
## The most birds per group by zone on ground patches.
const ZONE_GROUP_MAX: Array[int] = [3, 3, 3]
## Preferred minimum flat distance between active groups' perches.
const MIN_GROUP_GAP := 9.0
## The idle/walk clips' lowest vertex sits near -0.007..-0.010 m; lifting by
## FOOT_LIFT keeps feet cleanly on the surface top (convert_crow.py CONTACT).
const FOOT_LIFT := 0.007
const TAKEOFF_S := 0.8333
const LAND_S := 1.3333
const FLIGHT_SPEED := 6.0
const MIN_FLIGHT_S := 3.0
## Natural flight arch lifts (m) for ground-to-ground flights by zone.
const ZONE_LIFTS: Array[Vector2] = [Vector2(4.5, 6.5), Vector2(6.0, 8.5), Vector2(6.0, 8.5)]
## Control points stay slightly south (+z) to clear the terminal facade.
const AWAY := 1.5
const MAX_DELAY := 0.4
const SETTLE_S := 0.6
const MAX_PITCH := deg_to_rad(20.0)
const MAX_BANK := deg_to_rad(24.0)
const BANK_GAIN := 0.55
const BANK_RATE := 8.0
## idle_03 is left out: its peck takes the beak below the feet.
const PERCHED_CLIPS: Array[String] = ["idle_01", "idle_02", "eat", "hop"]
const CLIP_HOLD_MIN := 1.8
const CLIP_HOLD_MAX := 4.8
const BLEND_S := 0.15
const FLIGHT_BLEND_S := 0.22
const WALK_SPEED := 0.55
const TURN_SPEED := 5.0
const WALK_CHANCE := 0.5
const WALK_MIN_DIST := 0.35
const WALK_MAX_DIST := 1.4
const RELOCATE_MIN_S := 12.0
const RELOCATE_MAX_S := 24.0
const MAX_PUFFS := 6
const PUFF_MOTES := 4
const PUFF_LIFE_S := 0.75
const SCAN_S := 0.15

@export var clock: SimClock
@export var passenger_views: PassengerViews
@export var landside_views: LandsideViews
@export var save_game: SaveGame
## 1.0 is the vendor model (~0.66 m long). Drawn at 1.2x for natural proportion
## beside cars and passengers while staying legible at landside zooms.
@export var bird_scale := 1.2

var rng := RandomNumberGenerator.new()
var groups: Array[Dictionary] = []
var _lots_seen: Array[bool] = []
var _anim_speed := 1.0
var _scan_left := 0.0
var _tick_seen := true
var _threats := PackedVector3Array()
var _no_threats := PackedVector3Array()
var _puffs: Array[Dictionary] = []
var _dust_mesh: QuadMesh
var _feather_mesh: QuadMesh


func _ready() -> void:
	rng.randomize()
	var missing := PackedStringArray()
	for dep in ["clock", "passenger_views", "landside_views", "save_game"]:
		if get(dep) == null:
			missing.append(dep)
	if not missing.is_empty():
		push_error("BirdFlock: missing %s; birds run degraded" % ", ".join(missing))
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	if clock != null:
		clock.ticked.connect(_on_ticked)
	rebuild()


func _on_ticked(_tick: int) -> void:
	_tick_seen = true


func _scan_due(delta: float) -> bool:
	if clock != null:
		var due := _tick_seen
		_tick_seen = false
		return due
	_scan_left -= delta
	if _scan_left > 0.0:
		return false
	_scan_left = SCAN_S
	return true


func _process(delta: float) -> void:
	var paused := clock != null and clock.paused
	var speed := float(clock.speed) if clock != null else 1.0
	var anim := 0.0 if paused else speed
	if anim != _anim_speed:
		_anim_speed = anim
		for g in groups:
			for b in g["birds"]:
				(b["player"] as AnimationPlayer).speed_scale = anim
	if paused:
		return
	if not _scan_due(delta):
		step(delta * speed, _no_threats)
		return
	if _lots_changed():
		rebuild()
	step(delta * speed, threats_now())


## Drops every bird and active puff, then perches ground and elevated groups on
## distinct available perches. Rebuilt on load and when built car parks change.
func rebuild() -> void:
	for g in groups:
		for b in g["birds"]:
			(b["node"] as Node3D).queue_free()
	groups.clear()
	for puff in _puffs:
		(puff["root"] as Node3D).queue_free()
	_puffs.clear()
	_lots_seen = _lots_now()
	var there := BirdPerches.available(_lots_seen)
	var chosen: Array[int] = []
	for zone in ZONE_GROUPS.size():
		var spots: Array[int] = []
		for i in there:
			if not BirdPerches.is_elevated(i) and BirdPerches.spot_zone(i) == zone:
				spots.append(i)
		for _i in mini(ZONE_GROUPS[zone], maxi(spots.size() - 1, 0)):
			var spot := _pick_spaced_spot(spots, chosen)
			spots.erase(spot)
			chosen.append(spot)
			groups.append(_new_group(spot, false))
	_spawn_elevated_groups(there, chosen)


func _spawn_elevated_groups(there: Array[int], chosen: Array[int]) -> void:
	var pool: Array[int] = []
	for i in there:
		if BirdPerches.is_elevated(i):
			pool.append(i)
	var kinds_wanted := ["lamp_ped", "bench", "tree_planter", "lamp_hwy", "pine", "tree_leaf"]
	for want_kind in kinds_wanted:
		if groups.size() >= ZONE_GROUPS[0] + ZONE_GROUPS[1] + ZONE_GROUPS[2] + ELEVATED_GROUPS:
			break
		var matching: Array[int] = []
		for i in pool:
			if BirdPerches.spot_kind(i) == want_kind and not chosen.has(i):
				matching.append(i)
		if matching.is_empty():
			continue
		var spot := _pick_spaced_spot(matching, chosen)
		pool.erase(spot)
		chosen.append(spot)
		groups.append(_new_group(spot, true))
	while (
		groups.size() < ZONE_GROUPS[0] + ZONE_GROUPS[1] + ZONE_GROUPS[2] + ELEVATED_GROUPS
		and not pool.is_empty()
	):
		var spot := _pick_spaced_spot(pool, chosen)
		pool.erase(spot)
		chosen.append(spot)
		groups.append(_new_group(spot, true))


## Every perch unavailable now (unbuilt lot) plus perches held or flown to by other groups.
func closed_spots(skip: Dictionary) -> Array[int]:
	var out := busy_spots(skip)
	var there := BirdPerches.available(_lots_seen)
	for i in BirdPerches.perch_count():
		if not there.has(i):
			out.append(i)
	return out


func active_puff_count() -> int:
	return _puffs.size()


func _lots_now() -> Array[bool]:
	if landside_views == null or landside_views.landside == null:
		return []
	return landside_views.landside.lots_built.duplicate()


func _lots_changed() -> bool:
	if landside_views == null or landside_views.landside == null:
		return not _lots_seen.is_empty()
	var now := landside_views.landside.lots_built
	if now.size() != _lots_seen.size():
		return true
	for i in now.size():
		if now[i] != _lots_seen[i]:
			return true
	return false


func threats_now() -> PackedVector3Array:
	_threats.resize(0)
	var reach := BirdPerches.reach()
	if landside_views != null and landside_views.landside != null:
		var alpha := clock.alpha if clock != null else 1.0
		for id in landside_views.landside.vehicle_ids():
			var v := landside_views.landside.get_vehicle(id)
			if v == null or v.stage == LandsideVehicle.Stage.PARKED:
				continue
			var at := landside_views.pose_at(id, alpha).origin
			if at != Vector3.ZERO and reach.has_point(Vector2(at.x, at.z)):
				_threats.append(at)
	if passenger_views != null and passenger_views.sim != null:
		for id in passenger_views.sim.passenger_ids():
			var node := passenger_views.node_for(id)
			if node == null or not node.is_visible_in_tree():
				continue
			var at := node.global_position
			if reach.has_point(Vector2(at.x, at.z)):
				_threats.append(at)
	return _threats


## Advances the flock `dt` seconds of sim time with cars and passengers at
## `threats`: startled groups scatter with puff + audio, perched ground birds
## stroll/turn, flying birds bank along smooth arches, and puffs fade out.
func step(dt: float, threats: PackedVector3Array) -> void:
	if dt <= 0.0:
		return
	_step_puffs(dt)
	for g in groups:
		if g["target"] < 0:
			g["settle"] = maxf(g["settle"] - dt, 0.0)
			if g["settle"] <= 0.0 and _scatter_due(g["spot"], threats):
				_scatter(g, threats, true)
			elif g["settle"] <= 0.0 and BirdPerches.is_elevated(g["spot"]):
				g["relocate"] = float(g["relocate"]) - dt
				if g["relocate"] <= 0.0:
					_scatter(g, threats, false)
					g["relocate"] = rng.randf_range(RELOCATE_MIN_S, RELOCATE_MAX_S)
		for b in g["birds"]:
			if b["landed"]:
				_perch_tick(b, g, dt)
			else:
				_fly_tick(b, dt)
		if g["target"] >= 0 and g["birds"].all(func(b: Dictionary) -> bool: return b["landed"]):
			g["spot"] = g["target"]
			g["target"] = -1
			g["settle"] = SETTLE_S
			g["relocate"] = rng.randf_range(RELOCATE_MIN_S, RELOCATE_MAX_S)


func _scatter_due(spot: int, threats: PackedVector3Array) -> bool:
	var centre := BirdPerches.spot_pos(spot)
	if centre.y >= BirdPerches.HIGH_PERCH_Y:
		return BirdPerches.scatter_due_3d(centre, threats, BirdPerches.HIGH_SCATTER_RADIUS)
	return BirdPerches.scatter_due(centre, threats, BirdPerches.SCATTER_RADIUS)


## The perches the groups other than `skip` hold or fly to.
func busy_spots(skip: Dictionary) -> Array[int]:
	var busy: Array[int] = []
	for g in groups:
		if g != skip:
			busy.append(g["spot"])
			if g["target"] >= 0:
				busy.append(g["target"])
	return busy


func _new_group(spot: int, elevated: bool) -> Dictionary:
	var cap := BirdPerches.spot_capacity(spot)
	var min_size := 1 if elevated else mini(GROUND_GROUP_MIN, cap)
	var max_size := cap if elevated else mini(ZONE_GROUP_MAX[BirdPerches.spot_zone(spot)], cap)
	var size := rng.randi_range(min_size, max_size)
	var g := {
		"spot": spot,
		"target": -1,
		"settle": 0.0,
		"relocate": rng.randf_range(RELOCATE_MIN_S, RELOCATE_MAX_S),
		"birds": [],
	}
	var centre := BirdPerches.spot_pos(spot)
	var yaw := rng.randf_range(-PI, PI)
	for off in BirdPerches.offsets(rng, size, spot, bird_scale):
		var node: Node3D = CROW.instantiate()
		var variant := VARIANTS[rng.randi_range(0, VARIANTS.size() - 1)]
		for v in VARIANTS:
			(node.find_child(v, true, false) as Node3D).visible = v == variant
		add_child(node)
		var at := centre + off + Vector3(0.0, FOOT_LIFT * bird_scale, 0.0)
		var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw + rng.randf_range(-0.6, 0.6))
		var b := {
			"node": node,
			"player": node.find_child("AnimationPlayer", true, false),
			"at": at,
			"from": at,
			"to": at,
			"forward": fwd,
			"yaw_target": fwd,
			"walking": false,
			"walk_to": at,
			"walk_time": 0.0,
			"lift": 0.0,
			"t": 0.0,
			"dur": 0.0,
			"roll": 0.0,
			"clip": "",
			"hold": 0.0,
			"landed": true,
		}
		(b["player"] as AnimationPlayer).speed_scale = _anim_speed
		_place(node, at, fwd, 0.0, 0.0)
		_play(b, PERCHED_CLIPS[rng.randi_range(0, PERCHED_CLIPS.size() - 1)], rng.randf())
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)
		g["birds"].append(b)
	return g


func _scatter(g: Dictionary, threats: PackedVector3Array, startled: bool) -> void:
	var count := (g["birds"] as Array).size()
	var target := BirdPerches.pick(rng, g["spot"], _spaced_closed_spots(g), threats, count)
	if target < 0:
		return
	var offs := BirdPerches.offsets(rng, count, target, bird_scale)
	if offs.size() < count:
		return
	var from_spot: int = g["spot"]
	g["target"] = target
	var centre := BirdPerches.spot_pos(target)
	var lifts := lift_bounds(BirdPerches.spot_pos(from_spot), centre, BirdPerches.spot_zone(target))
	for i in count:
		var b: Dictionary = g["birds"][i]
		b["from"] = b["at"]
		b["to"] = centre + offs[i] + Vector3(0.0, FOOT_LIFT * bird_scale, 0.0)
		b["lift"] = rng.randf_range(lifts.x, lifts.y)
		b["dur"] = maxf(MIN_FLIGHT_S, flight_length(b["from"], b["to"], b["lift"]) / FLIGHT_SPEED)
		b["t"] = -rng.randf_range(0.0, MAX_DELAY)
		b["roll"] = 0.0
		b["walking"] = false
		b["walk_to"] = b["to"]
		b["landed"] = false
	if startled:
		_spawn_puff(BirdPerches.spot_pos(from_spot))
		_play_scatter_audio()


func _play_scatter_audio() -> void:
	if not is_inside_tree():
		return
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_bird_scatter"):
		audio.play_bird_scatter()


func _perch_tick(b: Dictionary, g: Dictionary, dt: float) -> void:
	b["forward"] = _turn_toward(b["forward"], b["yaw_target"], TURN_SPEED * dt)
	if b["walking"]:
		_step_walk(b, dt)
		return
	_place(b["node"], b["at"], b["forward"], 0.0, 0.0)
	b["hold"] -= dt
	if b["hold"] > 0.0:
		return
	if BirdPerches.can_stroll(g["spot"]) and rng.randf() < WALK_CHANCE:
		var tgt := _pick_walk_target(b, g)
		if tgt != b["at"]:
			b["walking"] = true
			b["walk_to"] = tgt
			b["yaw_target"] = _flat(tgt - b["at"], b["node"])
			b["walk_time"] = (
				(b["at"] as Vector3).distance_to(tgt) / maxf(WALK_SPEED * bird_scale, 0.1) + 1.5
			)
			_play(b, "walk", 0.0)
			return
	_play(b, PERCHED_CLIPS[rng.randi_range(0, PERCHED_CLIPS.size() - 1)], 0.0)
	b["yaw_target"] = (b["forward"] as Vector3).rotated(Vector3.UP, rng.randf_range(-0.7, 0.7))
	b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)


func _step_walk(b: Dictionary, dt: float) -> void:
	var at: Vector3 = b["at"]
	var walk_to: Vector3 = b["walk_to"]
	var delta_xz := Vector2(walk_to.x - at.x, walk_to.z - at.z)
	var dist := delta_xz.length()
	b["walk_time"] -= dt
	if dist <= 0.04 or b["walk_time"] <= 0.0:
		b["at"] = walk_to
		b["walking"] = false
		_place(b["node"], walk_to, b["forward"], 0.0, 0.0)
		_play(b, PERCHED_CLIPS[rng.randi_range(0, PERCHED_CLIPS.size() - 1)], 0.0)
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)
		return
	var dir := Vector3(delta_xz.x / dist, 0.0, delta_xz.y / dist)
	var align := maxf(0.0, (b["forward"] as Vector3).dot(dir))
	var step_m := minf(dist, WALK_SPEED * bird_scale * align * dt)
	b["at"] = at + dir * step_m
	if b["clip"] != "walk":
		_play(b, "walk", 0.0)
	_place(b["node"], b["at"], b["forward"], 0.0, 0.0)


func _pick_walk_target(b: Dictionary, g: Dictionary) -> Vector3:
	var spot: int = g["spot"]
	var centre := BirdPerches.spot_pos(spot)
	var half := BirdPerches.spot_half(spot)
	var at: Vector3 = b["at"]
	var min_apart := BirdPerches.MIN_SPACING * bird_scale
	for _try in 16:
		var cand := Vector3(
			rng.randf_range(centre.x - half.x, centre.x + half.x),
			at.y,
			rng.randf_range(centre.z - half.y, centre.z + half.y)
		)
		var d := at.distance_to(cand)
		if d < WALK_MIN_DIST or d > WALK_MAX_DIST:
			continue
		var clear := true
		for other in g["birds"]:
			if other == b:
				continue
			if cand.distance_to(other["at"]) < min_apart:
				clear = false
				break
			if bool(other["walking"]) and cand.distance_to(other["walk_to"]) < min_apart:
				clear = false
				break
		if clear:
			return cand
	return at


func _fly_tick(b: Dictionary, dt: float) -> void:
	b["t"] += dt
	var t: float = b["t"]
	if t < 0.0:
		return
	var dur: float = b["dur"]
	if t >= dur:
		var last := flight_point(b["from"], b["to"], b["lift"], 1.0)
		last -= flight_point(b["from"], b["to"], b["lift"], 0.98)
		var landed_fwd := _flat(last, b["node"])
		b["at"] = b["to"]
		b["forward"] = landed_fwd
		b["yaw_target"] = landed_fwd
		b["walking"] = false
		b["walk_to"] = b["to"]
		b["roll"] = 0.0
		b["landed"] = true
		_place(b["node"], b["to"], landed_fwd, 0.0, 0.0)
		_play(b, PERCHED_CLIPS[rng.randi_range(0, 1)], 0.0)
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)
		return
	var u := smoothstep(0.0, 1.0, t / dur)
	var at := flight_point(b["from"], b["to"], b["lift"], u)
	var u_prev := maxf(u - 0.02, 0.0)
	var u_next := minf(u + 0.02, 1.0)
	var p_prev := flight_point(b["from"], b["to"], b["lift"], u_prev)
	var p_next := flight_point(b["from"], b["to"], b["lift"], u_next)
	var ahead := (p_next - at) if u < 0.98 else (at - p_prev)
	var clip := "fly"
	if t < TAKEOFF_S:
		clip = "takeoff"
	elif t >= dur - LAND_S:
		clip = "land"
	elif ahead.y < 0.0:
		clip = "soar"
	if clip != b["clip"]:
		_play(b, clip, 0.0, FLIGHT_BLEND_S)
	var env := smoothstep(0.15, TAKEOFF_S, t) * (1.0 - smoothstep(dur - LAND_S, dur - 0.25, t))
	var pitch := atan2(ahead.y, Vector2(ahead.x, ahead.z).length())
	pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH) * env
	var f0 := _flat((at - p_prev) if u > 0.02 else ahead, b["node"])
	var f1 := _flat((p_next - at) if u < 0.98 else ahead, b["node"])
	var seg_dt := maxf((u_next - u_prev) * 0.5 * dur, 0.01)
	var yaw_rate := f0.signed_angle_to(f1, Vector3.UP) / seg_dt
	var target_roll := clampf(-yaw_rate * BANK_GAIN, -MAX_BANK, MAX_BANK) * env
	b["roll"] = lerpf(float(b["roll"]), target_roll, minf(1.0, dt * BANK_RATE))
	var fwd := _flat(ahead, b["node"])
	b["forward"] = fwd
	_place(b["node"], at, fwd, pitch, float(b["roll"]))


func _spawn_puff(origin: Vector3) -> void:
	if _dust_mesh == null:
		_dust_mesh = QuadMesh.new()
		_dust_mesh.size = Vector2(0.18, 0.18)
		_feather_mesh = QuadMesh.new()
		_feather_mesh.size = Vector2(0.07, 0.15)
	while _puffs.size() >= MAX_PUFFS:
		var old: Dictionary = _puffs.pop_front()
		(old["root"] as Node3D).queue_free()
	var puff_root := Node3D.new()
	puff_root.name = "TakeoffPuff"
	puff_root.position = origin + Vector3(0.0, 0.16 * bird_scale, 0.0)
	add_child(puff_root)
	var motes: Array[Dictionary] = []
	for i in PUFF_MOTES:
		var is_feather := i % 2 == 1
		var mi := MeshInstance3D.new()
		mi.mesh = _feather_mesh if is_feather else _dust_mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var base_col := (
			Color(0.15, 0.15, 0.18, 0.85) if is_feather else Color(0.88, 0.85, 0.78, 0.6)
		)
		mat.albedo_color = base_col
		mi.material_override = mat
		var ang := float(i) * (TAU / float(PUFF_MOTES)) + rng.randf_range(-0.35, 0.35)
		var speed := rng.randf_range(0.55, 1.15)
		mi.position = Vector3(cos(ang) * 0.14, rng.randf_range(0.0, 0.08), sin(ang) * 0.14)
		puff_root.add_child(mi)
		(
			motes
			. append(
				{
					"node": mi,
					"mat": mat,
					"base_color": base_col,
					"vel": Vector3(cos(ang) * speed, rng.randf_range(0.65, 1.35), sin(ang) * speed),
				}
			)
		)
	_puffs.append({"root": puff_root, "age": 0.0, "motes": motes})


func _step_puffs(dt: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var puff := _puffs[i]
		var age := float(puff["age"]) + dt
		puff["age"] = age
		if age >= PUFF_LIFE_S:
			(puff["root"] as Node3D).queue_free()
			_puffs.remove_at(i)
			continue
		var frac := age / PUFF_LIFE_S
		var fade := 1.0 - smoothstep(0.15, 1.0, frac)
		var drag := maxf(0.0, 1.0 - dt * 2.4)
		var scl := 1.0 + 0.55 * frac
		for m: Dictionary in puff["motes"]:
			var vel: Vector3 = (m["vel"] as Vector3) * drag
			m["vel"] = vel
			var mi: MeshInstance3D = m["node"]
			mi.position += vel * dt
			mi.scale = Vector3.ONE * scl
			var mat: StandardMaterial3D = m["mat"]
			var col: Color = m["base_color"]
			mat.albedo_color = Color(col.r, col.g, col.b, col.a * fade)


## Lift range (m) scaled smoothly when endpoints stand on elevated perches.
static func lift_bounds(from: Vector3, to: Vector3, zone: int) -> Vector2:
	var base: Vector2 = ZONE_LIFTS[zone]
	var top := maxf(from.y, to.y)
	if top <= 2.0:
		return base
	var drop := 0.35 * (top - 2.0)
	return Vector2(maxf(3.2, base.x - drop), maxf(4.6, base.y - drop))


## The point `u` (0 to 1) along a flight from `from` to `to`.
static func flight_point(from: Vector3, to: Vector3, lift: float, u: float) -> Vector3:
	var p1 := from + Vector3(0.0, lift, AWAY)
	var p2 := to + Vector3(0.0, lift, AWAY)
	var v := 1.0 - u
	return from * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + to * (u * u * u)


## The length of a flight, summed over 32 straight pieces.
static func flight_length(from: Vector3, to: Vector3, lift: float) -> float:
	var total := 0.0
	var prev := from
	for i in range(1, 33):
		var p := flight_point(from, to, lift, i / 32.0)
		total += prev.distance_to(p)
		prev = p
	return total


static func _flat(dir: Vector3, node: Node3D) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 1e-4:
		return node.basis.z.normalized()
	return flat.normalized()


static func _turn_toward(from_dir: Vector3, to_dir: Vector3, max_angle: float) -> Vector3:
	var diff := from_dir.signed_angle_to(to_dir, Vector3.UP)
	var step_ang := clampf(diff, -max_angle, max_angle)
	return from_dir.rotated(Vector3.UP, step_ang).normalized()


## Puts the crow (head +Z) at `at`, heading `forward`, nose tilted up `pitch`,
## banked by `roll` radians around its forward axis.
func _place(node: Node3D, at: Vector3, forward: Vector3, pitch: float, roll: float) -> void:
	var basis := Basis.looking_at(forward, Vector3.UP, true)
	basis = basis * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)
	node.transform = Transform3D(basis.scaled(Vector3.ONE * bird_scale), at)


func _play(b: Dictionary, clip: String, start_frac: float, blend := BLEND_S) -> void:
	var player: AnimationPlayer = b["player"]
	b["clip"] = clip
	player.play(clip, blend)
	if start_frac > 0.0:
		player.seek(player.current_animation_length * start_frac, true)


func _on_loaded(ok: bool) -> void:
	if ok:
		rebuild()


func _pick_spaced_spot(spots: Array[int], taken: Array[int]) -> int:
	var clear: Array[int] = []
	for s in spots:
		if _far_from_all(s, taken):
			clear.append(s)
	var pool := clear if not clear.is_empty() else spots
	return pool[rng.randi_range(0, pool.size() - 1)]


func _spaced_closed_spots(skip: Dictionary) -> Array[int]:
	var base := closed_spots(skip)
	var from_spot: int = skip["spot"]
	var count := (skip["birds"] as Array).size()
	var busy := busy_spots(skip)
	var spaced: Array[int] = base.duplicate()
	var open_far := 0
	for i in BirdPerches.perch_count():
		if (
			i == from_spot
			or base.has(i)
			or BirdPerches.spot_capacity(i) < count
			or not BirdPerches.can_fly(from_spot, i)
		):
			continue
		if _far_from_all(i, busy):
			open_far += 1
		else:
			spaced.append(i)
	return spaced if open_far > 0 else base


static func _far_from_all(spot: int, others: Array[int]) -> bool:
	var p := BirdPerches.spot_pos(spot)
	for other in others:
		var q := BirdPerches.spot_pos(other)
		if Vector2(p.x - q.x, p.z - q.z).length() < MIN_GROUP_GAP:
			return false
	return true
