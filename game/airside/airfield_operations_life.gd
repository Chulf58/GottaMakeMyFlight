class_name AirfieldOperationsLife
extends Node3D
## View-local, SimClock-synced Living Operations Apron north of
## AirfieldBackdrop.NORTH_SAFE_Z_MAX (-385 m). Adds a parked maintenance plane
## with safety cones and tug on the hangar lead-in line, pulsing red roof
## obstruction beacons and warm hangar bay doorway lights using
## AirfieldBackdrop.GLOW_MATERIAL, animated radar dish and windsock sock,
## 2 closed-loop service vehicles, and 3 rigged mechanics walking inspection
## routes. Keeps zero sim/save state and freezes cleanly when SimClock pauses.

const PLANE_SCENE := preload("res://assets/planes/tp_plane_03a.glb")
const CONE_SCENE := preload("res://assets/airside/props/works/ti_traffic_cone_1b.glb")
const TUG_SCENE := preload("res://assets/airside/props/pushback_tug.glb")
const PICKUP_SCENE := preload("res://assets/airside/landmarks/tp_pick_up_01a.glb")
const TRUCK_SCENE := preload("res://assets/airside/landmarks/tp_loading_truck_02a.glb")
const MECH_MALE_SCENE := preload("res://assets/people/tcp_male_character_07.glb")
const MECH_TECH_SCENE := preload("res://assets/people/tcp_female_character_10.glb")

const SAFE_Z_LIMIT := -388.0
const WINDSOCK_PIVOT_Y := 6.08
const RADAR_SPIN_RAD_S := 0.85
const BEACON_PERIOD_S := 1.4
const MECH_WALK_MPS := 1.45
const MECH_CLIP_WALK_MALE := 1.952
const MECH_CLIP_WALK_FEMALE := 1.922
const MECH_CLIP_BLEND_S := 0.16
const MECH_TURN_S := 0.38
const VEHICLE_CORNER_RADIUS_M := 4.5
const VEHICLE_RAMP_S := 0.9
const TRUCK_PIVOT_SHIFT_Z := -0.828

const SAFETY_YELLOW_HUE := 0.125
const SAFETY_YELLOW_SAT := 0.92
const SAFETY_YELLOW_VALUE_MIN := 0.82

static var _yellow_mech_mesh: Mesh
static var _yellow_mech_mat: ShaderMaterial

@export var clock: SimClock
@export var radar_node: Node3D
@export var windsock_node: Node3D

var _plane_node: Node3D
var _cones_root: Node3D
var _tug_node: Node3D
var _glows_mesh: MultiMeshInstance3D
var _vehicles_root: Node3D
var _mechanics_root: Node3D

var _radar_dish: Node3D
var _windsock_sock: MeshInstance3D
var _windsock_base_yaw := 0.0
var _glow_specs: Array[Dictionary] = []
var _glow_transforms: Array[Transform3D] = []
var _glow_colors := PackedColorArray()
var _vehicles: Array[Dictionary] = []
var _mechanics: Array[Dictionary] = []
var _degraded_time := 0.0
var _last_sim_t := -1.0


static func maintenance_plane_spec() -> Dictionary:
	return {
		"stem": "tp_plane_03a",
		"pos": Vector3(96.0, 0.0, -397.5),
		"yaw_deg": 0.0,
	}


static func maintenance_cone_specs() -> Array[Dictionary]:
	return [
		{"pos": Vector3(105.4, 0.0, -397.5)},
		{"pos": Vector3(86.6, 0.0, -397.5)},
		{"pos": Vector3(100.8, 0.0, -391.6)},
		{"pos": Vector3(91.2, 0.0, -391.6)},
		{"pos": Vector3(101.2, 0.0, -403.4)},
		{"pos": Vector3(90.8, 0.0, -403.4)},
	]


static func maintenance_tug_spec() -> Dictionary:
	return {
		"stem": "pushback_tug",
		"pos": Vector3(110.8, 0.0, -391.6),
		"yaw_deg": -135.0,
	}


static func obstruction_beacon_specs() -> Array[Dictionary]:
	return [
		{"pos": Vector3(-91.73, 51.90, -440.36), "size": 2.6, "phase": 0.0, "name": "Tower"},
		{"pos": Vector3(-126.0, 24.55, -415.0), "size": 2.2, "phase": 0.35, "name": "Radar"},
		{"pos": Vector3(12.0, 18.45, -391.5), "size": 2.2, "phase": 0.70, "name": "Hangar01F"},
		{"pos": Vector3(12.0, 18.45, -452.5), "size": 2.2, "phase": 0.70, "name": "Hangar01R"},
		{"pos": Vector3(64.6, 21.25, -411.8), "size": 2.0, "phase": 0.15, "name": "Hangar02FL"},
		{"pos": Vector3(127.4, 21.25, -411.8), "size": 2.0, "phase": 0.15, "name": "Hangar02FR"},
		{"pos": Vector3(64.6, 21.25, -444.2), "size": 2.0, "phase": 0.15, "name": "Hangar02RL"},
		{"pos": Vector3(127.4, 21.25, -444.2), "size": 2.0, "phase": 0.15, "name": "Hangar02RR"},
	]


static func hangar_bay_glow_specs() -> Array[Dictionary]:
	return [
		{"pos": Vector3(4.0, 13.75, -390.5), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.48)},
		{"pos": Vector3(12.0, 13.75, -390.5), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.50)},
		{"pos": Vector3(20.0, 13.75, -390.5), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.48)},
		{"pos": Vector3(90.0, 13.85, -411.6), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.48)},
		{"pos": Vector3(96.0, 13.85, -411.6), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.50)},
		{"pos": Vector3(102.0, 13.85, -411.6), "size": 2.4, "col": Color(1.0, 0.85, 0.48, 0.48)},
	]


static func patrol_routes() -> Array[Dictionary]:
	return [
		{
			"name": "WestApronPickup",
			"stem": "tp_pick_up_01a",
			"speed_mps": 6.5,
			"offset_s": 13.0,
			"pivot_z": 0.0,
			"waypoints":
			[
				Vector2(-75.5, -444.0),
				Vector2(-30.0, -444.0),
				Vector2(-30.0, -406.5),
				Vector2(-75.5, -406.5),
			],
			"stops":
			[
				{"corner": 1, "pause_s": 2.4},
				{"corner": 3, "pause_s": 2.2},
			],
		},
		{
			"name": "EastApronTruck",
			"stem": "tp_loading_truck_02a",
			"speed_mps": 5.4,
			"offset_s": 0.0,
			"pivot_z": TRUCK_PIVOT_SHIFT_Z,
			"corner_radius": 2.5,
			"waypoints":
			[
				Vector2(50.8, -451.0),
				Vector2(50.8, -406.7),
				Vector2(136.6, -406.7),
				Vector2(136.6, -451.0),
			],
			"stops":
			[
				{"corner": 1, "pause_s": 2.8},
				{"corner": 2, "pause_s": 2.6},
			],
		},
	]


static func mechanic_schedules() -> Array[Dictionary]:
	return [
		{
			"name": "MechanicPortWing",
			"variant": "orange",
			"y": 0.0,
			"offset_s": 0.0,
			"stations":
			[
				{"pos": Vector2(98.6, -392.4), "look": Vector2(96.0, -395.0), "pause_s": 2.6},
				{"pos": Vector2(104.0, -395.2), "look": Vector2(100.5, -397.2), "pause_s": 2.4},
				{"pos": Vector2(104.0, -400.0), "look": Vector2(100.0, -398.2), "pause_s": 2.6},
				{"pos": Vector2(99.4, -402.6), "look": Vector2(96.0, -401.5), "pause_s": 2.2},
				{"pos": Vector2(104.0, -400.0), "look": Vector2(100.5, -398.2), "pause_s": 1.6},
				{"pos": Vector2(104.0, -395.2), "look": Vector2(100.5, -397.2), "pause_s": 1.6},
			],
		},
		{
			"name": "MechanicStarboardWing",
			"variant": "yellow",
			"y": 0.0,
			"offset_s": 5.5,
			"stations":
			[
				{"pos": Vector2(93.4, -392.4), "look": Vector2(96.0, -395.0), "pause_s": 2.4},
				{"pos": Vector2(88.0, -395.2), "look": Vector2(91.5, -397.2), "pause_s": 2.8},
				{"pos": Vector2(88.0, -400.0), "look": Vector2(92.0, -398.2), "pause_s": 2.2},
				{"pos": Vector2(92.6, -402.6), "look": Vector2(96.0, -401.5), "pause_s": 2.6},
				{"pos": Vector2(88.0, -400.0), "look": Vector2(91.5, -398.2), "pause_s": 1.6},
				{"pos": Vector2(88.0, -395.2), "look": Vector2(91.5, -397.2), "pause_s": 1.6},
			],
		},
		{
			"name": "MechanicHangarBay",
			"variant": "tech",
			"y": 0.20,
			"offset_s": 2.0,
			"stations":
			[
				{"pos": Vector2(5.0, -392.2), "look": Vector2(5.0, -402.0), "pause_s": 2.8},
				{"pos": Vector2(12.0, -392.2), "look": Vector2(12.0, -382.0), "pause_s": 2.2},
				{"pos": Vector2(19.0, -392.2), "look": Vector2(19.0, -402.0), "pause_s": 2.8},
				{"pos": Vector2(12.0, -394.8), "look": Vector2(12.0, -404.0), "pause_s": 2.0},
			],
		},
	]


static func beacon_pulse(sim_t: float, phase_s: float) -> float:
	var wave := 0.5 + 0.5 * sin(((sim_t + phase_s) / BEACON_PERIOD_S) * TAU)
	return 0.15 + 0.85 * (wave * wave * wave)


static func build_patrol_track(spec: Dictionary) -> Dictionary:
	var wps: Array = spec["waypoints"]
	var n := wps.size()
	var poly := PackedVector2Array()
	var corner_mid_s: Array[float] = []
	var cum := 0.0
	var corner_r := float(spec.get("corner_radius", VEHICLE_CORNER_RADIUS_M))
	for i in n:
		var p0: Vector2 = wps[(i - 1 + n) % n]
		var p1: Vector2 = wps[i]
		var p2: Vector2 = wps[(i + 1) % n]
		var in_vec := p1 - p0
		var out_vec := p2 - p1
		var d := minf(corner_r, minf(in_vec.length() * 0.35, out_vec.length() * 0.35))
		var a := p1 - in_vec.normalized() * d
		var b := p1 + out_vec.normalized() * d
		for step in 11:
			var t := float(step) / 10.0
			var u := 1.0 - t
			var pt := a * (u * u) + p1 * (2.0 * u * t) + b * (t * t)
			if not poly.is_empty():
				cum += poly[poly.size() - 1].distance_to(pt)
			if step == 5:
				corner_mid_s.append(cum)
			poly.append(pt)
	var total_len := cum + poly[poly.size() - 1].distance_to(poly[0])
	var cum_dists := PackedFloat32Array()
	cum_dists.resize(poly.size() + 1)
	cum_dists[0] = 0.0
	for i in range(1, poly.size()):
		cum_dists[i] = cum_dists[i - 1] + poly[i - 1].distance_to(poly[i])
	cum_dists[poly.size()] = total_len

	var speed := float(spec["speed_mps"])
	var stop_list: Array = spec.get("stops", [])
	var stop_entries: Array[Dictionary] = []
	for st: Dictionary in stop_list:
		var c_idx: int = st["corner"]
		var mid_prev := corner_mid_s[c_idx]
		var next_s := total_len if c_idx + 1 >= n else corner_mid_s[c_idx + 1]
		var s_stop := fposmod(0.5 * (mid_prev + next_s), total_len)
		stop_entries.append({"s": s_stop, "pause": float(st["pause_s"])})
	stop_entries.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["s"] < q["s"])

	var timeline: Array[Dictionary] = []
	var t_cur := 0.0
	if stop_entries.is_empty():
		var move_dur := total_len / speed
		(
			timeline
			. append(
				{
					"kind": "move",
					"t0": 0.0,
					"t1": move_dur,
					"s0": 0.0,
					"s1": total_len,
					"r0": 0.0,
					"r1": 0.0,
				}
			)
		)
		t_cur = move_dur
	else:
		for k in stop_entries.size():
			var cur_stop: Dictionary = stop_entries[k]
			var next_stop: Dictionary = stop_entries[(k + 1) % stop_entries.size()]
			var s_start: float = cur_stop["s"]
			var s_end: float = next_stop["s"]
			if s_end <= s_start:
				s_end += total_len
			var pause_s: float = cur_stop["pause"]
			timeline.append({"kind": "pause", "t0": t_cur, "t1": t_cur + pause_s, "s": s_start})
			t_cur += pause_s
			var span := s_end - s_start
			var move_dur := span / speed
			var r := minf(0.45, VEHICLE_RAMP_S / maxf(move_dur, 0.01))
			(
				timeline
				. append(
					{
						"kind": "move",
						"t0": t_cur,
						"t1": t_cur + move_dur,
						"s0": s_start,
						"s1": s_end,
						"r0": r,
						"r1": r,
					}
				)
			)
			t_cur += move_dur
	return {
		"poly": poly,
		"cum_dists": cum_dists,
		"total_len": total_len,
		"timeline": timeline,
		"cycle_s": t_cur,
		"offset_s": float(spec.get("offset_s", 0.0)),
	}


static func sample_patrol_track(track: Dictionary, sim_t: float) -> Dictionary:
	var cycle_s: float = track["cycle_s"]
	var t := fposmod(sim_t + float(track["offset_s"]), cycle_s)
	var timeline: Array = track["timeline"]
	var s := 0.0
	var moving := false
	for seg: Dictionary in timeline:
		if t <= float(seg["t1"]) or seg == timeline[timeline.size() - 1]:
			if seg["kind"] == "pause":
				s = float(seg["s"])
				moving = false
			else:
				var dur := maxf(float(seg["t1"]) - float(seg["t0"]), 1e-4)
				var u := clampf((t - float(seg["t0"])) / dur, 0.0, 1.0)
				var frac := _trapezoid_integral(u, float(seg["r0"]), float(seg["r1"]))
				s = lerpf(float(seg["s0"]), float(seg["s1"]), frac)
				moving = true
			break
	var total_len: float = track["total_len"]
	var s_wrap := fposmod(s, total_len)
	var pos := _poly_point_at(track["poly"], track["cum_dists"], s_wrap)
	var ahead := _poly_point_at(track["poly"], track["cum_dists"], fposmod(s_wrap + 0.5, total_len))
	var dir := ahead - pos
	var yaw := atan2(dir.x, dir.y) if dir.length_squared() > 1e-6 else 0.0
	return {"pos": Vector3(pos.x, 0.0, pos.y), "yaw": yaw, "moving": moving}


static func build_mechanic_timeline(spec: Dictionary) -> Dictionary:
	var stations: Array = spec["stations"]
	var n := stations.size()
	var segs: Array[Dictionary] = []
	var t_cur := 0.0
	for i in n:
		var st: Dictionary = stations[i]
		var nxt: Dictionary = stations[(i + 1) % n]
		var p0: Vector2 = st["pos"]
		var p1: Vector2 = nxt["pos"]
		var look_dir: Vector2 = st["look"] - p0
		var look_yaw := atan2(look_dir.x, look_dir.y) if look_dir.length_squared() > 1e-6 else 0.0
		var prev_p: Vector2 = stations[(i - 1 + n) % n]["pos"]
		var in_dir := p0 - prev_p
		var in_yaw := atan2(in_dir.x, in_dir.y) if in_dir.length_squared() > 1e-6 else look_yaw
		var out_dir := p1 - p0
		var out_yaw := atan2(out_dir.x, out_dir.y) if out_dir.length_squared() > 1e-6 else look_yaw
		var pause_s: float = float(st["pause_s"])
		(
			segs
			. append(
				{
					"kind": "idle",
					"t0": t_cur,
					"t1": t_cur + pause_s,
					"pos": p0,
					"in_yaw": in_yaw,
					"look_yaw": look_yaw,
					"out_yaw": out_yaw,
				}
			)
		)
		t_cur += pause_s
		var walk_dur := maxf(out_dir.length() / MECH_WALK_MPS, 0.1)
		(
			segs
			. append(
				{
					"kind": "walk",
					"t0": t_cur,
					"t1": t_cur + walk_dur,
					"p0": p0,
					"p1": p1,
					"yaw": out_yaw,
				}
			)
		)
		t_cur += walk_dur
	return {
		"segs": segs,
		"cycle_s": t_cur,
		"y": float(spec["y"]),
		"offset_s": float(spec.get("offset_s", 0.0)),
	}


static func sample_mechanic_timeline(timeline_data: Dictionary, sim_t: float) -> Dictionary:
	var cycle_s: float = timeline_data["cycle_s"]
	var t := fposmod(sim_t + float(timeline_data["offset_s"]), cycle_s)
	var y: float = timeline_data["y"]
	var segs: Array = timeline_data["segs"]
	for seg: Dictionary in segs:
		if t <= float(seg["t1"]) or seg == segs[segs.size() - 1]:
			var phase_t := maxf(t - float(seg["t0"]), 0.0)
			if seg["kind"] == "walk":
				var dur := maxf(float(seg["t1"]) - float(seg["t0"]), 1e-4)
				var u := clampf(phase_t / dur, 0.0, 1.0)
				var pt: Vector2 = (seg["p0"] as Vector2).lerp(seg["p1"], u)
				return {
					"pos": Vector3(pt.x, y, pt.y),
					"yaw": float(seg["yaw"]),
					"clip": "walk",
					"phase_t": phase_t,
				}
			var t_left := float(seg["t1"]) - t
			var yaw := float(seg["look_yaw"])
			if phase_t < MECH_TURN_S:
				var k := smoothstep(0.0, 1.0, phase_t / MECH_TURN_S)
				yaw = lerp_angle(float(seg["in_yaw"]), float(seg["look_yaw"]), k)
			elif t_left < MECH_TURN_S * 0.65:
				var k := smoothstep(0.0, 1.0, t_left / (MECH_TURN_S * 0.65))
				yaw = lerp_angle(float(seg["out_yaw"]), float(seg["look_yaw"]), k)
			var p: Vector2 = seg["pos"]
			return {"pos": Vector3(p.x, y, p.y), "yaw": yaw, "clip": "idle", "phase_t": phase_t}
	return {"pos": Vector3.ZERO, "yaw": 0.0, "clip": "idle", "phase_t": 0.0}


func _ready() -> void:
	if clock == null:
		push_error("AirfieldOperationsLife: missing clock; operations apron runs degraded")
	_build_static_maintenance_bay()
	_build_glows()
	_bind_landmarks()
	_build_vehicles()
	_build_mechanics()
	sync_to_clock()


func _process(delta: float) -> void:
	var paused := clock != null and clock.paused
	if clock == null:
		_degraded_time += delta
	_sync_mechanic_anim_speeds(paused)
	if not paused:
		sync_to_clock()


func glow_transform(index: int) -> Transform3D:
	return _glow_transforms[index]


func glow_color(index: int) -> Color:
	return _glow_colors[index]


func sync_to_clock() -> void:
	var sim_t := _sim_seconds()
	var jumped := _last_sim_t < 0.0 or sim_t < _last_sim_t or absf(sim_t - _last_sim_t) > 2.0
	_last_sim_t = sim_t
	_update_glows(sim_t)
	_update_landmarks(sim_t)
	_update_vehicles(sim_t)
	_update_mechanics(sim_t, jumped)
	_sync_mechanic_anim_speeds(clock != null and clock.paused)


func _sim_seconds() -> float:
	if clock == null:
		return _degraded_time
	return (float(clock.tick) + clock.alpha) * SimClock.STEP


func _build_static_maintenance_bay() -> void:
	var pspec := maintenance_plane_spec()
	_plane_node = PLANE_SCENE.instantiate() as Node3D
	_plane_node.name = "MaintenancePlane"
	_plane_node.position = pspec["pos"]
	_plane_node.rotation.y = deg_to_rad(float(pspec["yaw_deg"]))
	PlaneView._apply_tinted_glass(_plane_node)
	add_child(_plane_node)

	_cones_root = Node3D.new()
	_cones_root.name = "MaintenanceCones"
	add_child(_cones_root)
	var cone_specs := maintenance_cone_specs()
	for i in cone_specs.size():
		var cone := CONE_SCENE.instantiate() as Node3D
		cone.name = "SafetyCone_%d" % i
		cone.position = cone_specs[i]["pos"]
		_cones_root.add_child(cone)

	var tspec := maintenance_tug_spec()
	_tug_node = TUG_SCENE.instantiate() as Node3D
	_tug_node.name = "MaintenanceTug"
	_tug_node.position = tspec["pos"]
	_tug_node.rotation.y = deg_to_rad(float(tspec["yaw_deg"]))
	add_child(_tug_node)


func _build_glows() -> void:
	_glow_specs.clear()
	for bspec in obstruction_beacon_specs():
		var item := bspec.duplicate()
		item["kind"] = "beacon"
		_glow_specs.append(item)
	for hspec in hangar_bay_glow_specs():
		var item := hspec.duplicate()
		item["kind"] = "bay"
		_glow_specs.append(item)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _glow_specs.size()
	_glow_transforms.resize(_glow_specs.size())
	_glow_colors.resize(_glow_specs.size())
	for i in _glow_specs.size():
		var item := _glow_specs[i]
		var s := float(item["size"])
		var xf := Transform3D(Basis.from_scale(Vector3(s, s, 1.0)), item["pos"])
		_glow_transforms[i] = xf
		mm.set_instance_transform(i, xf)
	_glows_mesh = MultiMeshInstance3D.new()
	_glows_mesh.name = "ApronGlows"
	_glows_mesh.multimesh = mm
	_glows_mesh.material_override = AirfieldBackdrop.GLOW_MATERIAL
	_glows_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glows_mesh)


func _bind_landmarks() -> void:
	if radar_node != null:
		var dish := radar_node.find_child("TP_Radar_01A_Dish", true, false) as MeshInstance3D
		if dish != null and dish.mesh != null:
			var dish_in_radar := Transform3D.IDENTITY
			var cur: Node = dish
			while cur != null and cur != radar_node:
				if cur is Node3D:
					dish_in_radar = (cur as Node3D).transform * dish_in_radar
				cur = cur.get_parent()
			var hub := dish_in_radar * dish.mesh.get_aabb().get_center()
			var pivot := Node3D.new()
			pivot.name = "RadarDishPivot"
			pivot.position = hub
			radar_node.add_child(pivot)
			dish.get_parent().remove_child(dish)
			pivot.add_child(dish)
			dish.transform = Transform3D(dish_in_radar.basis, dish_in_radar.origin - hub)
			_radar_dish = pivot
		else:
			_radar_dish = radar_node
	if windsock_node != null:
		_windsock_base_yaw = windsock_node.rotation.y
		_windsock_sock = _split_windsock_swivel(windsock_node)


func _build_vehicles() -> void:
	_vehicles_root = Node3D.new()
	_vehicles_root.name = "PatrolVehicles"
	add_child(_vehicles_root)
	for spec in patrol_routes():
		var pivot := Node3D.new()
		pivot.name = String(spec["name"])
		var scene: PackedScene = (
			PICKUP_SCENE if String(spec["stem"]) == "tp_pick_up_01a" else TRUCK_SCENE
		)
		var mesh_node := scene.instantiate() as Node3D
		mesh_node.position = Vector3(0.0, 0.0, float(spec["pivot_z"]))
		pivot.add_child(mesh_node)
		_vehicles_root.add_child(pivot)
		_vehicles.append({"node": pivot, "track": build_patrol_track(spec), "spec": spec})


func _build_mechanics() -> void:
	_mechanics_root = Node3D.new()
	_mechanics_root.name = "Mechanics"
	add_child(_mechanics_root)
	for spec in mechanic_schedules():
		var variant := String(spec["variant"])
		var is_tech := variant == "tech"
		var scene := MECH_TECH_SCENE if is_tech else MECH_MALE_SCENE
		var node := scene.instantiate() as Node3D
		node.name = String(spec["name"])
		if variant == "orange":
			StaffCharacters._apply_role_uniform(node, StaffMember.Role.RAMP)
		elif variant == "yellow":
			_apply_yellow_mechanic_uniform(node)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		for clip in ["idle", "walk"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_mechanics_root.add_child(node)
		(
			_mechanics
			. append(
				{
					"node": node,
					"player": player,
					"timeline": build_mechanic_timeline(spec),
					"clip_walk_mps": MECH_CLIP_WALK_FEMALE if is_tech else MECH_CLIP_WALK_MALE,
					"clip": "",
					"base_speed": 1.0,
				}
			)
		)


func _update_glows(sim_t: float) -> void:
	if _glows_mesh == null:
		return
	var mm := _glows_mesh.multimesh
	for i in _glow_specs.size():
		var spec := _glow_specs[i]
		var c: Color
		if spec["kind"] == "beacon":
			var pulse := beacon_pulse(sim_t, float(spec["phase"]))
			c = Color(1.0, 0.16, 0.12, pulse)
		else:
			var col: Color = spec["col"]
			var shimmer := 0.95 + 0.05 * sin(sim_t * 1.4 + float(i) * 0.7)
			c = Color(col.r, col.g, col.b, col.a * shimmer)
		_glow_colors[i] = c
		mm.set_instance_color(i, c)


func _update_landmarks(sim_t: float) -> void:
	if is_instance_valid(_radar_dish):
		_radar_dish.rotation.y = wrapf(sim_t * RADAR_SPIN_RAD_S, 0.0, TAU)
	if is_instance_valid(_windsock_sock):
		_windsock_sock.rotation.y = 0.22 * sin(sim_t * 1.15) + 0.07 * sin(sim_t * 2.65)
		_windsock_sock.rotation.x = -0.04 + 0.045 * sin(sim_t * 1.85)
	elif is_instance_valid(windsock_node):
		windsock_node.rotation.y = _windsock_base_yaw + 0.14 * sin(sim_t * 1.15)


func _update_vehicles(sim_t: float) -> void:
	for v in _vehicles:
		var pose := sample_patrol_track(v["track"], sim_t)
		var node := v["node"] as Node3D
		node.position = pose["pos"]
		node.rotation.y = float(pose["yaw"])


func _update_mechanics(sim_t: float, snap: bool) -> void:
	for m in _mechanics:
		var pose := sample_mechanic_timeline(m["timeline"], sim_t)
		var node := m["node"] as Node3D
		node.position = pose["pos"]
		node.rotation.y = float(pose["yaw"])
		var clip := String(pose["clip"])
		var walk_scale := MECH_WALK_MPS / float(m["clip_walk_mps"])
		m["base_speed"] = walk_scale if clip == "walk" else 1.0
		var player := m["player"] as AnimationPlayer
		if String(m["clip"]) != clip or snap:
			m["clip"] = clip
			player.play(clip, 0.0 if snap else MECH_CLIP_BLEND_S)
		if snap:
			var clip_len := player.current_animation_length
			if clip_len > 0.0:
				var anim_t := float(pose["phase_t"]) * float(m["base_speed"])
				player.seek(fposmod(anim_t, clip_len), true)


func _sync_mechanic_anim_speeds(paused: bool) -> void:
	var clk_speed := 1.0
	if clock != null:
		clk_speed = float(
			SimClock.FAST_FORWARD_SPEED if clock.is_fast_forwarding() else clock.speed
		)
	for m in _mechanics:
		var player := m["player"] as AnimationPlayer
		player.speed_scale = 0.0 if paused else float(m["base_speed"]) * clk_speed


static func _split_windsock_swivel(root: Node3D) -> MeshInstance3D:
	var body := root.find_child("Windsock_Body", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		return null
	var src := body.mesh as ArrayMesh
	if src == null:
		return null
	var mast_mesh := ArrayMesh.new()
	var sock_mesh := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var mat := src.surface_get_material(s)
		var fmt: int = src.surface_get_format(s)
		var preserve: int = (
			fmt & (Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES | (0x1F << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
		)
		var mast_idx := PackedInt32Array()
		var sock_idx := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var v0 := verts[idx[t]]
			var v1 := verts[idx[t + 1]]
			var v2 := verts[idx[t + 2]]
			var min_y := minf(v0.y, minf(v1.y, v2.y))
			var max_z := maxf(v0.z, maxf(v1.z, v2.z))
			var dst := sock_idx if (min_y > 4.9 and max_z > 0.14) else mast_idx
			dst.append(idx[t])
			dst.append(idx[t + 1])
			dst.append(idx[t + 2])
		_append_filtered_surface(mast_mesh, arrays, mast_idx, mat, preserve, Vector3.ZERO)
		_append_filtered_surface(
			sock_mesh, arrays, sock_idx, mat, preserve, Vector3(0.0, -WINDSOCK_PIVOT_Y, 0.0)
		)
	if sock_mesh.get_surface_count() == 0:
		return null
	body.mesh = mast_mesh
	var sock_mi := MeshInstance3D.new()
	sock_mi.name = "Windsock_Swivel"
	sock_mi.mesh = sock_mesh
	sock_mi.position = Vector3(0.0, WINDSOCK_PIVOT_Y, 0.0)
	body.get_parent().add_child(sock_mi)
	return sock_mi


static func _append_filtered_surface(
	dst: ArrayMesh,
	src_arrays: Array,
	tris: PackedInt32Array,
	mat: Material,
	preserve_flags: int,
	shift: Vector3
) -> void:
	if tris.is_empty():
		return
	var remap := PackedInt32Array()
	var old_verts: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
	remap.resize(old_verts.size())
	remap.fill(-1)
	var old_to_new: Array[int] = []
	for vi in tris:
		if remap[vi] < 0:
			remap[vi] = old_to_new.size()
			old_to_new.append(vi)
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	var new_count := old_to_new.size()

	var new_verts := PackedVector3Array()
	new_verts.resize(new_count)
	for i in new_count:
		new_verts[i] = old_verts[old_to_new[i]] + shift
	out_arrays[Mesh.ARRAY_VERTEX] = new_verts

	if src_arrays[Mesh.ARRAY_NORMAL] != null:
		var old_n: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
		var new_n := PackedVector3Array()
		new_n.resize(new_count)
		for i in new_count:
			new_n[i] = old_n[old_to_new[i]]
		out_arrays[Mesh.ARRAY_NORMAL] = new_n

	if src_arrays[Mesh.ARRAY_TANGENT] != null:
		var old_t: PackedFloat32Array = src_arrays[Mesh.ARRAY_TANGENT]
		var new_t := PackedFloat32Array()
		new_t.resize(new_count * 4)
		for i in new_count:
			var oi := old_to_new[i] * 4
			var ni := i * 4
			for k in 4:
				new_t[ni + k] = old_t[oi + k]
		out_arrays[Mesh.ARRAY_TANGENT] = new_t

	if src_arrays[Mesh.ARRAY_TEX_UV] != null:
		var old_uv: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
		var new_uv := PackedVector2Array()
		new_uv.resize(new_count)
		for i in new_count:
			new_uv[i] = old_uv[old_to_new[i]]
		out_arrays[Mesh.ARRAY_TEX_UV] = new_uv

	if src_arrays[Mesh.ARRAY_CUSTOM0] != null:
		var old_c0: PackedByteArray = src_arrays[Mesh.ARRAY_CUSTOM0]
		var new_c0 := PackedByteArray()
		new_c0.resize(new_count * 4)
		for i in new_count:
			var oi := old_to_new[i] * 4
			var ni := i * 4
			for k in 4:
				new_c0[ni + k] = old_c0[oi + k]
		out_arrays[Mesh.ARRAY_CUSTOM0] = new_c0

	var new_idx := PackedInt32Array()
	new_idx.resize(tris.size())
	for k in tris.size():
		new_idx[k] = remap[tris[k]]
	out_arrays[Mesh.ARRAY_INDEX] = new_idx

	dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays, [], {}, preserve_flags)
	if mat != null:
		dst.surface_set_material(dst.get_surface_count() - 1, mat)


static func _apply_yellow_mechanic_uniform(node: Node3D) -> void:
	var mi := PassengerLooks.body_mesh(node)
	if mi == null:
		return
	if _yellow_mech_mesh == null:
		var plain := mi.mesh
		var arrays := plain.surface_get_arrays(0)
		var parts := PassengerLooks.cloth_split(arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_COLOR])
		if parts[1].is_empty():
			_yellow_mech_mesh = plain
		else:
			var mat := _build_yellow_mat(plain, parts[1])
			_yellow_mech_mesh = StaffCharacters._split_cloth_mesh(plain, arrays, parts, mat)
	mi.mesh = _yellow_mech_mesh


static func _build_yellow_mat(plain: Mesh, cloth_index: PackedInt32Array) -> ShaderMaterial:
	if _yellow_mech_mat != null:
		return _yellow_mech_mat
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
		var texels := StaffCharacters._cloth_texels(uvs, cloth_index, width, height)
		var dark := PassengerLooks.dark_cells(atlas, texels)
		var cols := width / PassengerLooks.SWATCH_PX.x
		for t in texels:
			var x := t % width
			var y := t / width
			var is_dark: bool = dark.get(
				(y / PassengerLooks.SWATCH_PX.y) * cols + x / PassengerLooks.SWATCH_PX.x, false
			)
			if not is_dark:
				var c := atlas.get_pixel(x, y)
				var v := SAFETY_YELLOW_VALUE_MIN + (1.0 - SAFETY_YELLOW_VALUE_MIN) * c.v
				atlas.set_pixel(x, y, Color.from_hsv(SAFETY_YELLOW_HUE, SAFETY_YELLOW_SAT, v, c.a))
		atlas.generate_mipmaps()
		made.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(atlas))
	_yellow_mech_mat = made
	return made


static func _trapezoid_integral(u: float, r0: float, r1: float) -> float:
	if r0 + r1 <= 1e-4:
		return u
	var area := maxf(1.0 - 0.5 * r0 - 0.5 * r1, 1e-4)
	if r0 > 1e-4 and u < r0:
		return 0.5 * u * u / (r0 * area)
	if r1 > 1e-4 and u > 1.0 - r1:
		var rem := 1.0 - u
		return 1.0 - 0.5 * rem * rem / (r1 * area)
	return (0.5 * r0 + (u - r0)) / area


static func _poly_point_at(poly: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var n := poly.size()
	for i in n:
		if s <= cum[i + 1] or i == n - 1:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var seg_len := maxf(cum[i + 1] - cum[i], 1e-5)
			var u := clampf((s - cum[i]) / seg_len, 0.0, 1.0)
			return a.lerp(b, u)
	return poly[0]
