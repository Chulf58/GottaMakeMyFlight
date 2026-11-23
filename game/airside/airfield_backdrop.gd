class_name AirfieldBackdrop
extends Node3D
## Renders the cohesive Toon airfield environment outside the playable/swept
## airside zones: concrete operations apron north of the runway, control tower,
## radar mast, hangars, parked GSE vehicles, windsock, perimeter fence,
## dynamic runway threshold/edge/aiming markings + touchdown tire wear,
## runway edge/threshold/PAPI lights, and dynamic blue taxiway edge lights.
## Purely visual: nothing in the sim reads it and nothing is saved.

const PROPS_DIR := "res://assets/airside/props/"
const LANDMARKS_DIR := "res://assets/airside/landmarks/"
const WEAR_MATERIAL := preload("res://assets/airside/materials/runway_wear.tres")
const GROUND_MATERIAL := preload("res://assets/airside/materials/airfield_ground_toon.tres")
const GLOW_MATERIAL := preload("res://assets/airside/materials/airfield_light_glow.tres")
const SITE := preload("res://build/terminal_site.tres")

## Spatial safety bounds (all permanent structures keep strictly clear).
const PLAYABLE_EXCLUDE_RECT := Rect2(-225.0, -306.0, 450.0, 246.0)
const RUNWAY_CORRIDOR_Z := Vector2(-375.0, -305.0)
const NORTH_SAFE_Z_MAX := -385.0
const NORTH_FENCE_Z := -380.0
const FLANK_FENCE_X := 235.0
const FLANK_FENCE_Z := Vector2(-295.0, -62.0)
const MAX_EDGE_LIGHT_HEIGHT_M := 0.45

const FENCE_STEP_M := 7.85
const APRON_RECT := Rect2(-142.0, -458.0, 284.0, 74.0)
const APRON_TOP_Y := 0.0
const APRON_SKIRT_Y := -0.12
const APRON_SLAB_M := 14.0
const RUNWAY_MARKING_Y := 0.108
const RUNWAY_WEAR_Y := 0.1075
const LIGHT_GROUND_Y := -0.10
const FENCE_GROUND_Y := -0.15
const RUNWAY_EDGE_STEP_M := 24.0
const TAXI_EDGE_STEP_M := 16.0
const TAXI_LIGHT_OFFSET_M := TaxiPaving.WIDTH_M * 0.5 + 0.65
const TAXI_LIGHT_MIN_SPACING_M := 6.0
const STUB_CLEAR_M := 18.0
const STUB_XS := [-124.0, 124.0]

const CONCRETE_UV := Vector2(2.5 / 32.0, 15.3 / 16.0)
const CONCRETE_ALT_UV := Vector2(12.5 / 32.0, 11.25 / 16.0)
const WHITE_UV := Vector2(11.5 / 32.0, 14.2 / 16.0)
const YELLOW_UV := Vector2(0.6083, 0.0067)

@export var flights: FlightSim
@export var airside: Airside

var _landmarks_root: Node3D
var _runway_root: Node3D
var _taxi_lights_root: Node3D
var _last_runway_size := ""
var _last_paving_id := 0
var _scenes := {}


static func is_outside_playable_bounds(pos: Vector3) -> bool:
	return not PLAYABLE_EXCLUDE_RECT.has_point(Vector2(pos.x, pos.z))


static func clears_runway_corridor(pos: Vector3) -> bool:
	return pos.z < RUNWAY_CORRIDOR_Z.x or pos.z > RUNWAY_CORRIDOR_Z.y


## Landmark buildings, radar, windsock and parked GSE north of the runway
## (all z <= -385, strictly outside playable terminal/spur/runway zones).
static func landmark_specs() -> Array[Dictionary]:
	return [
		{
			"stem": "tp_control_tower_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-92.0, 0.0, -422.0),
			"yaw_deg": 0.0,
			"scale": 0.68,
		},
		{
			"stem": "tp_radar_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-126.0, 0.0, -415.0),
			"yaw_deg": 20.0,
		},
		{
			"stem": "tp_hangar_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(12.0, 0.0, -422.0),
			"yaw_deg": 0.0,
		},
		{
			"stem": "tp_hangar_02a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(96.0, 0.0, -428.0),
			"yaw_deg": 0.0,
		},
		{
			"stem": "windsock",
			"dir": PROPS_DIR,
			"pos": Vector3(-56.0, 0.0, -390.0),
			"yaw_deg": 90.0,
		},
		{
			"stem": "tp_cistern_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-52.0, 0.0, -412.0),
			"yaw_deg": 15.0,
		},
		{
			"stem": "tp_cistern_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-44.0, 0.0, -412.0),
			"yaw_deg": 15.0,
		},
		{
			"stem": "tp_pick_up_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-65.0, 0.0, -400.0),
			"yaw_deg": -25.0,
		},
		{
			"stem": "tp_bus_01a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(-30.0, 0.0, -398.0),
			"yaw_deg": 90.0,
		},
		{
			"stem": "tp_loading_truck_02a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(62.0, 0.0, -398.0),
			"yaw_deg": -75.0,
		},
		{
			"stem": "tp_loading_truck_02a",
			"dir": LANDMARKS_DIR,
			"pos": Vector3(82.0, 0.0, -396.0),
			"yaw_deg": 0.0,
		},
	]


## Perimeter fence segments along north boundary (z = -380, terminating cleanly
## at +-FLANK_FENCE_X) and east/west flanks (x = +-235, z in [-295, -62]).
static func fence_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	_append_fence_line(
		specs, Vector2(-FLANK_FENCE_X, NORTH_FENCE_Z), Vector2(-145.0, NORTH_FENCE_Z)
	)
	_append_fence_line(specs, Vector2(145.0, NORTH_FENCE_Z), Vector2(FLANK_FENCE_X, NORTH_FENCE_Z))
	_append_fence_line(specs, Vector2(-145.0, NORTH_FENCE_Z), Vector2(-145.0, -462.0))
	_append_fence_line(specs, Vector2(145.0, NORTH_FENCE_Z), Vector2(145.0, -462.0))
	_append_fence_line(specs, Vector2(-145.0, -462.0), Vector2(145.0, -462.0))
	_append_fence_line(
		specs, Vector2(-FLANK_FENCE_X, FLANK_FENCE_Z.x), Vector2(-FLANK_FENCE_X, FLANK_FENCE_Z.y)
	)
	_append_fence_line(
		specs, Vector2(FLANK_FENCE_X, FLANK_FENCE_Z.x), Vector2(FLANK_FENCE_X, FLANK_FENCE_Z.y)
	)
	return specs


static func _append_fence_line(out: Array[Dictionary], from_xz: Vector2, to_xz: Vector2) -> void:
	var delta := to_xz - from_xz
	var length := delta.length()
	var count := maxi(1, int(round(length / FENCE_STEP_M)))
	var yaw := atan2(-delta.y, delta.x)
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var pt := from_xz.lerp(to_xz, t)
		(
			out
			. append(
				{
					"stem": "tp_metal_fence_01a",
					"pos": Vector3(pt.x, FENCE_GROUND_Y, pt.y),
					"yaw": yaw,
				}
			)
		)


## Runway edge lights, threshold wingbars, and PAPI light banks scaled to
## `runway_size` (small 384 m, medium 576 m, large 768 m).
static func runway_edge_light_specs(runway_size: String) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var len_m := Runway.length_m(runway_size)
	if len_m <= 0.0:
		return specs
	var half := len_m * 0.5
	var start_x := -half + 48.0
	var end_x := half - 48.0
	var caution_x := half - 144.0
	var z_north := StandPlacement.RUNWAY_Z - 32.6
	var z_south := StandPlacement.RUNWAY_Z + 32.6

	var x := start_x
	while x <= end_x + 0.1:
		var stem := "runway_edge_light_amber" if absf(x) >= caution_x else "runway_edge_light_white"
		specs.append({"stem": stem, "pos": Vector3(x, LIGHT_GROUND_Y, z_north), "yaw": 0.0})
		var near_stub := false
		for sx: float in STUB_XS:
			if absf(x - sx) < STUB_CLEAR_M:
				near_stub = true
				break
		if not near_stub:
			specs.append({"stem": stem, "pos": Vector3(x, LIGHT_GROUND_Y, z_south), "yaw": 0.0})
		x += RUNWAY_EDGE_STEP_M

	for end_sign: float in [-1.0, 1.0]:
		var tx := end_sign * (half - 48.0)
		var yaw := -PI * 0.5 if end_sign < 0.0 else PI * 0.5
		for k in 3:
			var step := float(k) * 0.85
			var north_pos := Vector3(tx, LIGHT_GROUND_Y, StandPlacement.RUNWAY_Z - 33.2 - step)
			if _clears_taxi_signs(north_pos):
				specs.append({"stem": "runway_threshold_light", "pos": north_pos, "yaw": yaw})
			var south_pos := Vector3(tx, LIGHT_GROUND_Y, StandPlacement.RUNWAY_Z + 33.2 + step)
			if _clears_taxi_signs(south_pos):
				specs.append({"stem": "runway_threshold_light", "pos": south_pos, "yaw": yaw})

	var papi_z := StandPlacement.RUNWAY_Z - 35.2
	(
		specs
		. append(
			{
				"stem": "papi_light_bank",
				"pos": Vector3(-half + 84.0, LIGHT_GROUND_Y, papi_z),
				"yaw": -PI * 0.5,
			}
		)
	)
	(
		specs
		. append(
			{
				"stem": "papi_light_bank",
				"pos": Vector3(half - 84.0, LIGHT_GROUND_Y, papi_z),
				"yaw": PI * 0.5,
			}
		)
	)
	return specs


static func _clears_taxi_signs(pos: Vector3) -> bool:
	var sign_z := StandPlacement.RUNWAY_Z + 32.0 + AirsideProps.SIGN_PAST_EDGE_M
	if absf(pos.z - sign_z) > 0.70:
		return true
	var sign_x_off := TaxiPaving.WIDTH_M * 0.5 + AirsideProps.SIGN_SETBACK_M
	for sx: float in STUB_XS:
		if absf(pos.x - (sx + sign_x_off)) <= 3.6:
			return false
	return true


## Blue taxiway edge lights placed along outer taxiway pavement shoulders,
## filtered clear of intersections, stand pads, runway, and terminal site.
static func taxi_edge_light_specs(
	strips: Array[Dictionary], pads: Array[Rect2], runway_size: String
) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var site_rect: Rect2 = SITE.grid_rect().grow(1.0)
	var rwy_rect := TaxiwayWorks.runway_rect(runway_size).grow(1.5)
	var accepted: Array[Vector2] = []

	for strip in strips:
		if strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		var across_x: bool = strip["across_x"]
		if across_x:
			var z := rect.position.y + 8.0
			while z <= rect.end.y - 6.0:
				for sx: float in [-1.0, 1.0]:
					var cand := Vector2(rect.get_center().x + sx * TAXI_LIGHT_OFFSET_M, z)
					_try_accept_taxi_light(cand, strips, pads, rwy_rect, site_rect, accepted, specs)
				z += TAXI_EDGE_STEP_M
		else:
			var x := rect.position.x + 8.0
			while x <= rect.end.x - 6.0:
				for sz: float in [-1.0, 1.0]:
					var cand := Vector2(x, rect.get_center().y + sz * TAXI_LIGHT_OFFSET_M)
					_try_accept_taxi_light(cand, strips, pads, rwy_rect, site_rect, accepted, specs)
				x += TAXI_EDGE_STEP_M
	return specs


static func _try_accept_taxi_light(
	cand: Vector2,
	strips: Array[Dictionary],
	pads: Array[Rect2],
	rwy_rect: Rect2,
	site_rect: Rect2,
	accepted: Array[Vector2],
	specs: Array[Dictionary]
) -> void:
	if rwy_rect.has_point(cand) or site_rect.has_point(cand):
		return
	for s in strips:
		if not s.has("quad") and (s["rect"] as Rect2).grow(0.45).has_point(cand):
			return
	for pad in pads:
		if pad.grow(0.5).has_point(cand):
			return
	for prev in accepted:
		if prev.distance_to(cand) < TAXI_LIGHT_MIN_SPACING_M:
			return
	accepted.append(cand)
	specs.append({"stem": "taxi_edge_light", "pos": Vector3(cand.x, LIGHT_GROUND_Y, cand.y)})


func _ready() -> void:
	_landmarks_root = Node3D.new()
	_landmarks_root.name = "Landmarks"
	add_child(_landmarks_root)
	_runway_root = Node3D.new()
	_runway_root.name = "RunwayDressing"
	add_child(_runway_root)
	_taxi_lights_root = Node3D.new()
	_taxi_lights_root.name = "TaxiEdgeLights"
	add_child(_taxi_lights_root)

	_build_landmarks()
	if flights != null:
		flights.runway.size_changed.connect(rebuild_for_runway)
		rebuild_for_runway(flights.runway.size)
	else:
		rebuild_for_runway(Runway.SMALL)
	refresh_taxi_lights()


func _exit_tree() -> void:
	GROUND_MATERIAL.set_shader_parameter("runway_half_length", Runway.length_m(Runway.SMALL) * 0.5)


func _process(_delta: float) -> void:
	if airside != null and airside.paving.mesh != null:
		var mesh_id := airside.paving.mesh.get_instance_id()
		if mesh_id != _last_paving_id:
			refresh_taxi_lights()


func rebuild_for_runway(runway_size: String) -> void:
	if runway_size == _last_runway_size and _runway_root.get_child_count() > 0:
		return
	_last_runway_size = runway_size
	var half_len := Runway.length_m(runway_size) * 0.5
	if half_len > 0.0:
		GROUND_MATERIAL.set_shader_parameter("runway_half_length", half_len)
	_clear_children(_runway_root)

	var markings := MeshInstance3D.new()
	markings.name = "RunwayMarkings"
	markings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markings.mesh = _build_runway_markings_mesh(runway_size)
	_runway_root.add_child(markings)

	var wear := MeshInstance3D.new()
	wear.name = "RunwayWear"
	wear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wear.mesh = _build_runway_wear_mesh(runway_size)
	_runway_root.add_child(wear)

	var rwy_specs := runway_edge_light_specs(runway_size)
	var glows: Array[Dictionary] = []
	for spec in rwy_specs:
		var node := (_scene(PROPS_DIR + spec["stem"] + ".glb").instantiate()) as Node3D
		node.position = spec["pos"]
		node.rotation.y = spec["yaw"]
		_runway_root.add_child(node)
		_append_glow_for_spec(glows, spec)
	var glow_mesh := _build_glow_multimesh("RunwayLightGlows", glows)
	if glow_mesh != null:
		_runway_root.add_child(glow_mesh)


func refresh_taxi_lights() -> void:
	if airside == null:
		return
	_last_paving_id = (airside.paving.mesh.get_instance_id() if airside.paving.mesh != null else 0)
	_clear_children(_taxi_lights_root)
	var rwy_size := flights.runway.size if flights != null else Runway.SMALL
	var taxi_specs := taxi_edge_light_specs(airside.paving.shown, airside.paving.pads, rwy_size)
	var glows: Array[Dictionary] = []
	for spec in taxi_specs:
		var node := (_scene(PROPS_DIR + spec["stem"] + ".glb").instantiate()) as Node3D
		node.position = spec["pos"]
		_taxi_lights_root.add_child(node)
		_append_glow_for_spec(glows, spec)
	var glow_mesh := _build_glow_multimesh("TaxiLightGlows", glows)
	if glow_mesh != null:
		_taxi_lights_root.add_child(glow_mesh)


func _build_landmarks() -> void:
	var apron := MeshInstance3D.new()
	apron.name = "OperationsApron"
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apron.mesh = _build_service_apron_mesh()
	_landmarks_root.add_child(apron)

	var apron_marks := MeshInstance3D.new()
	apron_marks.name = "OperationsApronMarkings"
	apron_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apron_marks.mesh = _build_service_apron_markings_mesh()
	_landmarks_root.add_child(apron_marks)

	for spec in landmark_specs():
		var path: String = spec["dir"] + spec["stem"] + ".glb"
		var node := (_scene(path).instantiate()) as Node3D
		node.position = spec["pos"]
		node.rotation.y = deg_to_rad(float(spec["yaw_deg"]))
		var s := float(spec.get("scale", 1.0))
		if not is_equal_approx(s, 1.0):
			node.scale = Vector3.ONE * s
		_landmarks_root.add_child(node)

	for fspec in fence_specs():
		var fnode := (_scene(LANDMARKS_DIR + fspec["stem"] + ".glb").instantiate()) as Node3D
		fnode.position = fspec["pos"]
		fnode.rotation.y = fspec["yaw"]
		_landmarks_root.add_child(fnode)


func _build_service_apron_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()

	var cols := ceili(APRON_RECT.size.x / APRON_SLAB_M)
	var rows := ceili(APRON_RECT.size.y / APRON_SLAB_M)
	for r in rows:
		for c in cols:
			var x0 := APRON_RECT.position.x + c * APRON_SLAB_M
			var x1 := minf(x0 + APRON_SLAB_M, APRON_RECT.end.x)
			var z0 := APRON_RECT.position.y + r * APRON_SLAB_M
			var z1 := minf(z0 + APRON_SLAB_M, APRON_RECT.end.y)
			var uv := CONCRETE_UV if (r + c) % 2 == 0 else CONCRETE_ALT_UV
			_add_flat_quad(
				Rect2(x0, z0, x1 - x0, z1 - z0), APRON_TOP_Y, uv, verts, normals, uvs, index
			)

	var skirt_verts := PackedVector3Array()
	var skirt_normals := PackedVector3Array()
	var skirt_uvs := PackedVector2Array()
	var skirt_index := PackedInt32Array()
	var corners := [
		Vector3(APRON_RECT.position.x, APRON_TOP_Y, APRON_RECT.position.y),
		Vector3(APRON_RECT.end.x, APRON_TOP_Y, APRON_RECT.position.y),
		Vector3(APRON_RECT.end.x, APRON_TOP_Y, APRON_RECT.end.y),
		Vector3(APRON_RECT.position.x, APRON_TOP_Y, APRON_RECT.end.y),
	]
	var out_norms := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var base := skirt_verts.size()
		(
			skirt_verts
			. append_array(
				[
					a,
					b,
					Vector3(b.x, APRON_SKIRT_Y, b.z),
					Vector3(a.x, APRON_SKIRT_Y, a.z),
				]
			)
		)
		for _k in 4:
			skirt_normals.append(out_norms[i])
			skirt_uvs.append(CONCRETE_UV)
		skirt_index.append_array(
			PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2])
		)

	var out := ArrayMesh.new()
	_commit_surface(out, verts, normals, uvs, index, TaxiMarkings.material())
	_commit_surface(
		out, skirt_verts, skirt_normals, skirt_uvs, skirt_index, TaxiMarkings.material()
	)
	return out


func _build_service_apron_markings_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var y := APRON_TOP_Y + 0.01

	var inset := 1.4
	var w := 0.45
	_add_flat_quad(
		Rect2(
			APRON_RECT.position.x + inset,
			APRON_RECT.end.y - inset - w,
			APRON_RECT.size.x - 2.0 * inset,
			w
		),
		y,
		YELLOW_UV,
		verts,
		normals,
		uvs,
		index
	)
	for sx: float in [APRON_RECT.position.x + inset, APRON_RECT.end.x - inset - w]:
		_add_flat_quad(
			Rect2(sx, APRON_RECT.position.y + inset, w, APRON_RECT.size.y - 2.0 * inset),
			y,
			YELLOW_UV,
			verts,
			normals,
			uvs,
			index
		)
	# Hangar lead-in centrelines and GSE stall bays.
	for hx: float in [12.0, 96.0]:
		_add_flat_quad(Rect2(hx - 0.25, -395.0, 0.5, 9.5), y, YELLOW_UV, verts, normals, uvs, index)
	for bx: float in [-56.0, -48.0, -40.0]:
		_add_flat_quad(Rect2(bx, -418.0, 0.25, 13.0), y, WHITE_UV, verts, normals, uvs, index)
	var out := ArrayMesh.new()
	_commit_surface(out, verts, normals, uvs, index, TaxiMarkings.material())
	return out


func _build_runway_markings_mesh(runway_size: String) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var half := Runway.length_m(runway_size) * 0.5
	var rz := StandPlacement.RUNWAY_Z
	var y := RUNWAY_MARKING_Y

	# White threshold bars & piano keys cleanly framing where 01A end chevron pads meet 03A.
	# Centerline dashes, side lines and TDZ dots belong to the underlying tp_runway_03a mesh.
	for end_sign: float in [-1.0, 1.0]:
		var tx := end_sign * (half - 48.0)
		var bar_x := tx if end_sign < 0.0 else tx - 2.2
		_add_flat_quad(Rect2(bar_x, rz - 25.0, 2.2, 50.0), y, WHITE_UV, verts, normals, uvs, index)
		var key_x0 := (-half + 52.0) if end_sign < 0.0 else (half - 68.0)
		for k in 8:
			var kz := rz - 21.0 + float(k) * 6.0 - 0.9
			_add_flat_quad(Rect2(key_x0, kz, 16.0, 1.8), y, WHITE_UV, verts, normals, uvs, index)

	var out := ArrayMesh.new()
	_commit_surface(out, verts, normals, uvs, index, TaxiMarkings.material())
	return out


func _build_runway_wear_mesh(runway_size: String) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var rz := StandPlacement.RUNWAY_Z
	var half := Runway.length_m(runway_size) * 0.5
	var zones: Array[float] = [-40.0, half - 100.0]
	if runway_size == Runway.MEDIUM or runway_size == Runway.LARGE:
		zones.append(-110.0)
	if runway_size == Runway.LARGE:
		zones.append(-170.0)
	for zx in zones:
		var base := verts.size()
		verts.append(Vector3(zx - 20.0, RUNWAY_WEAR_Y, rz - 9.5))
		verts.append(Vector3(zx + 20.0, RUNWAY_WEAR_Y, rz - 9.5))
		verts.append(Vector3(zx + 20.0, RUNWAY_WEAR_Y, rz + 9.5))
		verts.append(Vector3(zx - 20.0, RUNWAY_WEAR_Y, rz + 9.5))
		for _i in 4:
			normals.append(Vector3.UP)
		uvs.append_array(
			[Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
		)
		index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var out := ArrayMesh.new()
	_commit_surface(out, verts, normals, uvs, index, WEAR_MATERIAL)
	return out


static func _append_glow_for_spec(out: Array[Dictionary], spec: Dictionary) -> void:
	var stem: String = spec["stem"]
	var pos: Vector3 = spec["pos"]
	if stem == "taxi_edge_light":
		out.append(
			{
				"pos": pos + Vector3(0.0, 0.28, 0.0),
				"size": 1.35,
				"col": Color(0.24, 0.68, 1.0, 0.92)
			}
		)
	elif stem == "runway_edge_light_white":
		out.append(
			{
				"pos": pos + Vector3(0.0, 0.30, 0.0),
				"size": 1.50,
				"col": Color(1.0, 0.96, 0.88, 0.92)
			}
		)
	elif stem == "runway_edge_light_amber":
		out.append(
			{
				"pos": pos + Vector3(0.0, 0.30, 0.0),
				"size": 1.50,
				"col": Color(1.0, 0.65, 0.14, 0.95)
			}
		)
	elif stem == "runway_threshold_light":
		out.append(
			{
				"pos": pos + Vector3(0.0, 0.22, 0.0),
				"size": 1.35,
				"col": Color(0.24, 1.0, 0.44, 0.85)
			}
		)
	elif stem == "papi_light_bank":
		var yaw := float(spec.get("yaw", 0.0))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var xs: Array[float] = [-2.4, -0.8, 0.8, 2.4]
		for i in 4:
			var col := Color(1.0, 0.22, 0.18, 0.95) if i < 2 else Color(1.0, 0.98, 0.90, 0.95)
			out.append(
				{"pos": pos + right * xs[i] + Vector3(0.0, 0.22, 0.0), "size": 1.35, "col": col}
			)


static func _build_glow_multimesh(
	node_name: String, items: Array[Dictionary]
) -> MultiMeshInstance3D:
	if items.is_empty():
		return null
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = items.size()
	for i in items.size():
		var item := items[i]
		var s: float = item["size"]
		var xform := Transform3D(Basis.from_scale(Vector3(s, s, 1.0)), item["pos"])
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, item["col"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = GLOW_MATERIAL
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


static func _add_flat_quad(
	rect: Rect2,
	y: float,
	uv: Vector2,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var base := verts.size()
	verts.append(Vector3(rect.position.x, y, rect.position.y))
	verts.append(Vector3(rect.end.x, y, rect.position.y))
	verts.append(Vector3(rect.end.x, y, rect.end.y))
	verts.append(Vector3(rect.position.x, y, rect.end.y))
	for _i in 4:
		normals.append(Vector3.UP)
		uvs.append(uv)
	index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


static func _commit_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array,
	mat: Material
) -> void:
	if index.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
