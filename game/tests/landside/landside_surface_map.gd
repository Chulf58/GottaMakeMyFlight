class_name LandsideSurfaceMap
extends RefCounted
## The surfaces of a part of the landside, read from the meshes of the assets
## as main.tscn places them, for checks that a wheel or a walker's feet stand
## on what is drawn under them. Each triangle is kept on a 1 m grid with the
## name of the mesh it came from. Where no mesh is, the lawn (main.tscn's
## Ground plane) is at y -0.1.

const LAWN_Y := -0.1
const LAWN := "lawn"
## A wheel or a walker's feet stand within this of the surface under them.
const ON := 0.03
## Within this distance of a kerb (where the surface jumps), a wheel or a foot
## may be anywhere between the heights on either side: it is going over it.
const KERB_SLACK := 0.3
const CELL := 1.0

## The part of the map read (x and z).
var area: Rect2
## Grid cell -> triangles [a, b, c, mesh name] over it.
var _cells := {}


func _init(read_area: Rect2) -> void:
	area = read_area


## Adds every mesh of `scene`, placed at `at`. A node that is not in the tree
## is enough: each mesh's transform is taken relative to the scene's root.
func add_scene(scene: PackedScene, at: Transform3D) -> void:
	var root: Node3D = scene.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var to_world := at * to_root(root, mi)
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			_add_triangle(
				[to_world * f[i], to_world * f[i + 1], to_world * f[i + 2], String(mi.name)]
			)
	root.free()


## The top of the surface under `at` (the highest face no more than 0.5 m over
## it) and the name of its mesh: [y, name], the lawn when there is none.
func top(at: Vector3) -> Array:
	var from := Vector3(at.x, at.y + 0.5, at.z)
	var best := LAWN_Y
	var name := LAWN
	for tri: Array in _cells.get(_cell_of(at.x, at.z), []):
		var hit: Variant = Geometry3D.ray_intersects_triangle(
			from, Vector3.DOWN, tri[0], tri[1], tri[2]
		)
		if hit != null and (hit as Vector3).y > best:
			best = (hit as Vector3).y
			name = tri[3]
	return [best, name]


## How far `at` is over (+) or under (-) the surface below it; NAN within
## KERB_SLACK of a kerb when `at` is between the heights either side of it
## (going over it), and the gap to the nearer side when it is not.
func gap(at: Vector3) -> float:
	var here: float = top(at)[0]
	var lo := here
	var hi := here
	for dx in [-KERB_SLACK, 0.0, KERB_SLACK]:
		for dz in [-KERB_SLACK, 0.0, KERB_SLACK]:
			var y: float = top(at + Vector3(dx, 0.0, dz))[0]
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo <= ON:
		return at.y - here
	if at.y >= lo - ON and at.y <= hi + ON:
		return NAN
	return at.y - hi if at.y > hi else at.y - lo


func _add_triangle(tri: Array) -> void:
	var a: Vector3 = tri[0]
	var b: Vector3 = tri[1]
	var c: Vector3 = tri[2]
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
	if not area.intersects(Rect2(lo, hi - lo).abs().grow(0.01)):
		return
	for cx in range(
		floori(maxf(lo.x, area.position.x) / CELL), floori(minf(hi.x, area.end.x) / CELL) + 1
	):
		for cz in range(
			floori(maxf(lo.y, area.position.y) / CELL), floori(minf(hi.y, area.end.y) / CELL) + 1
		):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				_cells[key] = []
			(_cells[key] as Array).append(tri)


## `node`'s transform relative to `root` (the chain of local transforms between).
static func to_root(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))
