class_name LandsideStreetDressing
extends Node3D
## Mounts the extended through-road segments, east/west highway tunnel portals,
## crosswalks, forecourt bollards, streetlights, benches, trash bins, signs,
## trees, and bushes directly under LandsidePlaces so main.tscn stays untouched.

const PORTAL_MOUTH_EAST_X := 136.0
const PORTAL_MOUTH_WEST_X := -136.0
const PORTAL_BORE_HALF_Z := 5.35
const VEHICLE_HALF_LENGTH := 2.6
const ROAD_CENTER_Z := -46.0
const ROAD_Y := 0.10
const SIDEWALK_Y := 0.20
const GROUND_Y := -0.10

const SCENES := {
	"road_ext": preload("res://assets/landside/landside_road_ext.glb"),
	"portal": preload("res://assets/landside/landside_tunnel_portal.glb"),
	"crosswalk": preload("res://assets/landside/landside_crosswalk.glb"),
	"bollard": preload("res://assets/landside/landside_bollard.glb"),
	"lamp_ped": preload("res://assets/landside/tc_streetlight_1a.glb"),
	"lamp_hwy": preload("res://assets/landside/tc_streetlight_2a.glb"),
	"signpost": preload("res://assets/landside/tp_signpost_01a.glb"),
	"tree_leaf": preload("res://assets/landside/tc_tree_2d.glb"),
	"tree_planter": preload("res://assets/landside/tc_tree_3a.glb"),
	"pine": preload("res://assets/landside/tp_pine_tree_02a.glb"),
	"bush_pot": preload("res://assets/landside/tc_bush_2a.glb"),
	"bush_hedge": preload("res://assets/decor/tc_bush_1a.glb"),
	"bench": preload("res://assets/decor/tc_bench_1a.glb"),
	"trash": preload("res://assets/decor/tc_trash_can_1a.glb"),
}

const HALF_EXTENTS := {
	"bollard": Vector2(0.15, 0.15),
	"lamp_ped": Vector2(0.36, 0.36),
	"lamp_hwy": Vector2(0.42, 0.42),
	"signpost": Vector2(0.80, 0.21),
	"tree_leaf": Vector2(1.65, 1.65),
	"tree_planter": Vector2(1.44, 1.44),
	"pine": Vector2(1.35, 1.35),
	"bush_pot": Vector2(0.56, 0.56),
	"bush_hedge": Vector2(0.90, 0.90),
	"bench": Vector2(0.38, 0.98),
	"trash": Vector2(0.35, 0.35),
}


func _ready() -> void:
	name = "LandsideStreetDressing"
	for spec in road_specs():
		_spawn_entry(spec)
	for spec in prop_specs():
		_spawn_entry(spec)


func _spawn_entry(spec: Dictionary) -> void:
	var kind: String = spec["kind"]
	var packed: PackedScene = SCENES[kind]
	var inst := packed.instantiate() as Node3D
	inst.name = spec["name"]
	inst.position = spec["pos"]
	inst.rotation.y = spec["rot_y"]
	add_child(inst)


## Structural road extensions, portals, and painted crosswalks.
static func road_specs() -> Array[Dictionary]:
	return [
		{
			"name": "RoadExtEast",
			"kind": "road_ext",
			"pos": Vector3(43.0, 0.0, ROAD_CENTER_Z),
			"rot_y": 0.0,
		},
		{
			"name": "RoadExtWest",
			"kind": "road_ext",
			"pos": Vector3(-43.0, 0.0, ROAD_CENTER_Z),
			"rot_y": PI,
		},
		{
			"name": "TunnelPortalEast",
			"kind": "portal",
			"pos": Vector3(PORTAL_MOUTH_EAST_X, 0.0, ROAD_CENTER_Z),
			"rot_y": 0.0,
		},
		{
			"name": "TunnelPortalWest",
			"kind": "portal",
			"pos": Vector3(PORTAL_MOUTH_WEST_X, 0.0, ROAD_CENTER_Z),
			"rot_y": PI,
		},
		{
			"name": "CrosswalkLot2",
			"kind": "crosswalk",
			"pos": Vector3(-2.0, ROAD_Y, 0.0),
			"rot_y": 0.0,
		},
	]


## Street dressing props with world coordinates, yaw, and bounding radius.
static func prop_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_append_forecourt_props(out)
	_append_highway_lamps_and_signs(out)
	_append_greenery(out)
	return out


static func _append_forecourt_props(out: Array[Dictionary]) -> void:
	# Protective bollards along forecourt kerb islands (berths & crosswalks left open).
	var bollard_xs: Array[float] = [
		-36.0,
		-35.0,
		-20.4,
		-19.4,
		-12.5,
		-11.5,
		3.4,
		4.6,
		11.6,
		12.6,
		19.4,
		20.6,
		27.8,
		28.8,
	]
	for i in bollard_xs.size():
		_add_prop(
			out,
			"ForecourtBollard_%d" % i,
			"bollard",
			Vector3(bollard_xs[i], SIDEWALK_Y, -58.72),
			0.0
		)

	# Pedestrian globe streetlights spaced symmetrically behind kerb line.
	var ped_lamp_xs: Array[float] = [-37.0, -18.8, -6.3, 4.0, 20.0, 30.5]
	for i in ped_lamp_xs.size():
		_add_prop(
			out,
			"ForecourtLamp_%d" % i,
			"lamp_ped",
			Vector3(ped_lamp_xs[i], SIDEWALK_Y, -59.08),
			0.0
		)

	# Forecourt sidewalk benches (facing +Z road) & trash cans, plus south pocket.
	_add_prop(out, "ForecourtBench_West", "bench", Vector3(-4.5, SIDEWALK_Y, -58.98), -PI * 0.5)
	_add_prop(out, "ForecourtBench_East", "bench", Vector3(32.6, SIDEWALK_Y, -58.98), -PI * 0.5)
	_add_prop(out, "ForecourtTrash_West", "trash", Vector3(-33.8, SIDEWALK_Y, -59.05), 0.0)
	_add_prop(out, "ForecourtTrash_Mid", "trash", Vector3(-12.0, SIDEWALK_Y, -59.05), 0.0)
	_add_prop(out, "ForecourtTrash_East", "trash", Vector3(34.4, SIDEWALK_Y, -59.05), 0.0)
	_add_prop(out, "ForecourtBush_East", "bush_pot", Vector3(36.0, SIDEWALK_Y, -58.85), 0.0)
	_add_prop(out, "SouthSidewalkBench", "bench", Vector3(-13.05, SIDEWALK_Y, -40.62), PI * 0.5)
	_add_prop(out, "SouthSidewalkTrash", "trash", Vector3(-10.8, SIDEWALK_Y, -40.62), 0.0)


static func _append_highway_lamps_and_signs(out: Array[Dictionary]) -> void:
	# North sidewalk highway cobra-head lights: +PI/2 overhangs arm +Z onto asphalt.
	for x in [-128.0, -110.0, -90.0, -70.0, -50.0, 50.0, 70.0, 90.0, 110.0, 128.0]:
		var tag := "E" if x > 0.0 else "W"
		_add_prop(
			out,
			"HwyLampN_%s_%d" % [tag, abs(int(x))],
			"lamp_hwy",
			Vector3(x, SIDEWALK_Y, -51.42),
			PI * 0.5
		)
	# South sidewalk highway lights staggered: -PI/2 overhangs arm -Z onto asphalt.
	for x in [-120.0, -100.0, -80.0, -60.0, 60.0, 80.0, 100.0, 120.0]:
		var tag := "E" if x > 0.0 else "W"
		_add_prop(
			out,
			"HwyLampS_%s_%d" % [tag, abs(int(x))],
			"lamp_hwy",
			Vector3(x, SIDEWALK_Y, -40.58),
			-PI * 0.5
		)
	# Airport departure/arrival signposts along north boulevard facing camera (+Z).
	for x in [-124.0, -54.0, 54.0, 124.0]:
		var tag := "E" if x > 0.0 else "W"
		_add_prop(
			out,
			"BoulevardSign_%s_%d" % [tag, abs(int(x))],
			"signpost",
			Vector3(x, SIDEWALK_Y, -51.40),
			PI
		)


static func _append_greenery(out: Array[Dictionary]) -> void:
	# Corner stone-planter pines marking site-to-boulevard transitions & portal approaches.
	_add_prop(out, "PlanterPine_NW", "tree_planter", Vector3(-45.8, GROUND_Y, -54.8), 0.2)
	_add_prop(out, "PlanterPine_NE", "tree_planter", Vector3(45.8, GROUND_Y, -54.8), -0.4)
	_add_prop(out, "PlanterPine_SW", "tree_planter", Vector3(-45.8, GROUND_Y, -37.2), 0.7)
	_add_prop(out, "PlanterPine_SE", "tree_planter", Vector3(45.8, GROUND_Y, -37.2), -0.9)

	# Outer boulevard verge trees & bushes (y = GROUND_Y, strictly z > -59.5).
	var verge_specs := [
		[-130.5, -55.4, "pine", 0.3],
		[-130.5, -36.0, "pine", 1.1],
		[-118.0, -55.8, "tree_leaf", 0.8],
		[-112.0, -35.8, "bush_hedge", 0.4],
		[-102.0, -55.2, "pine", 1.9],
		[-96.0, -36.0, "tree_leaf", 2.3],
		[-84.0, -55.8, "tree_leaf", 0.1],
		[-78.0, -35.8, "pine", 1.4],
		[-66.0, -55.2, "pine", 2.7],
		[-60.0, -36.0, "tree_leaf", 0.9],
		[-52.0, -55.0, "bush_hedge", 1.5],
		[-52.0, -36.2, "bush_hedge", 2.1],
		[52.0, -55.0, "bush_hedge", 0.6],
		[52.0, -36.2, "bush_hedge", 1.8],
		[60.0, -36.0, "tree_leaf", 2.4],
		[66.0, -55.2, "pine", 0.5],
		[78.0, -35.8, "pine", 1.2],
		[84.0, -55.8, "tree_leaf", 2.9],
		[96.0, -36.0, "tree_leaf", 0.7],
		[102.0, -55.2, "pine", 2.0],
		[112.0, -35.8, "bush_hedge", 1.3],
		[118.0, -55.8, "tree_leaf", 2.5],
		[130.5, -55.4, "pine", 0.2],
		[130.5, -36.0, "pine", 1.7],
		# West car-park lawn framing (outside BirdPerches & lot_2).
		[-36.0, -32.0, "tree_leaf", 0.4],
		[-26.0, -31.5, "pine", 1.6],
		[-18.5, -33.0, "bush_hedge", 0.9],
	]
	for i in verge_specs.size():
		var item: Array = verge_specs[i]
		_add_prop(
			out, "BoulevardFlora_%d" % i, item[2], Vector3(item[0], GROUND_Y, item[1]), item[3]
		)


static func _add_prop(
	out: Array[Dictionary],
	prop_name: String,
	kind: String,
	pos: Vector3,
	rot_y: float,
) -> void:
	var base: Vector2 = HALF_EXTENTS[kind]
	var c := absf(cos(rot_y))
	var s := absf(sin(rot_y))
	var half := Vector2(c * base.x + s * base.y, s * base.x + c * base.y)
	out.append({"name": prop_name, "kind": kind, "pos": pos, "rot_y": rot_y, "half": half})
