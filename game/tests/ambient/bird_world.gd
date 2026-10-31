extends RefCounted
## The outdoor surfaces the bird tests measure against, placed as main.tscn
## and LandsidePlaces place them: the terminal shell (Airside/Terminal at
## z -80), the starter curb bays and both car parks of the starter landside,
## built. Each entry: {"name", "mesh": TriangleMesh, "inv": world to mesh
## Transform3D, "xform": mesh to world, "box": world AABB}.

const SHELL := "res://assets/buildings/tp_airport_shell.glb"
const SHELL_AT := Vector3(0, 0, -80)
const LANDSIDE := "res://landside/starter_landside.tres"


static func build(parent: Node) -> Array[Dictionary]:
	var definition: LandsideDefinition = load(LANDSIDE)
	var holder := Node3D.new()
	parent.add_child(holder)
	var shell: Node3D = (load(SHELL) as PackedScene).instantiate()
	shell.position = SHELL_AT
	holder.add_child(shell)
	var places := LandsidePlaces.new()
	var road_top := places.road_top
	places.free()
	for origin in LandsidePlaces.bay_origins(definition, road_top):
		var bay: Node3D = LandsidePlaces.BAY.instantiate()
		bay.position = origin
		holder.add_child(bay)
	for spot in definition.lots.size():
		var lot_spot := definition.lots[spot]
		var multi := lot_spot.kind == LandsideLotSpot.Kind.MULTI_STOREY
		var lot: Node3D = (LandsidePlaces.MULTI if multi else LandsidePlaces.SURFACE).instantiate()
		lot.transform = LandsidePlaces.lot_transform(lot_spot)
		holder.add_child(lot)
	var out: Array[Dictionary] = []
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		(
			out
			. append(
				{
					"name": str(mi.name),
					"mesh": mi.mesh.generate_triangle_mesh(),
					"inv": mi.global_transform.affine_inverse(),
					"xform": mi.global_transform,
					"box": mi.global_transform * mi.mesh.get_aabb(),
				}
			)
		)
	holder.free()
	return out


## The first surface of `world` on the segment from `a` to `b`, skipping
## names in `skip`: {"y", "name"} or {}.
static func first_hit(
	world: Array[Dictionary], a: Vector3, b: Vector3, skip: Array[String] = []
) -> Dictionary:
	var best := {}
	var best_d := INF
	for e in world:
		if skip.has(e["name"]):
			continue
		var inv: Transform3D = e["inv"]
		var hit: Dictionary = (e["mesh"] as TriangleMesh).intersect_segment(inv * a, inv * b)
		if hit.is_empty():
			continue
		var p: Vector3 = (e["xform"] as Transform3D) * (hit["position"] as Vector3)
		if a.distance_to(p) < best_d:
			best_d = a.distance_to(p)
			best = {"y": p.y, "name": e["name"]}
	return best
