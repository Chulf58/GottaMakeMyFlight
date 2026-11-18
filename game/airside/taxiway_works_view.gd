class_name TaxiwayWorksView
extends Node3D
## Draws the construction works (TaxiwayWorks) on the airside: over each side
## spur while it is pending to move (FlightSim.spur_pending()) and at the ends of
## the runway while its upgrade works run (RunwayWorks, from start to finish).
## Cosmetic only (user ruling airside-construction-works-are-a-visible-stage-
## props-mark-th): it reads the sim and the paving and changes neither.
##
## It lays the works out again whenever what they are worked out from changes:
## either spur's x or wanted x, whether the runway works run, the runway size
## and the paving mesh (Airside rebuilds it on every change of the stands). The
## ground is a flat earth-coloured mesh in the paving's toon material, laid
## GROUND_LIFT_M over the ground the planes roll on (PlaneView.ground_height_at()),
## so it shows over the site's own paving as well as over the grass.
##
## Hovering a works yard shows what the works are for (HoverTarget sign
## provider): over a side spur SideSpurs.works_text() with the forecast move time
## (FlightSim.spur_release_tick()), over the runway RunwayWorks.schedule_text().
## The text is read again every TEXT_FRAMES frames while works show.

## The atlas texel (tp_atlas_1a_d.png, 560, 330) the ground takes: earth brown.
const GROUND_UV := Vector2(560.5 / 1024.0, 330.5 / 1024.0)
const GROUND_LIFT_M := 0.02
## The ground mesh is cut into squares this size so it follows the site's ramp.
const GROUND_CELL_M := 2.0
const MATERIAL := preload("res://assets/materials/tp_atlas_simple_toon.tres")
const TEXT_FRAMES := 30
## The height of the box a yard's hover rect is projected from.
const YARD_HEIGHT_M := 3.6
const RUNWAY := "runway"

var flights: FlightSim
var airside: Airside
## Works name (StandPlacement.WEST, EAST or RUNWAY) -> its TaxiwayWorks layout,
## for the works shown now.
var layouts: Dictionary = {}
## Works name -> its hover text.
var texts: Dictionary = {}
var _key: Array = []
var _frames := 0
var _scenes: Dictionary = {}


func _init() -> void:
	top_level = true


func _ready() -> void:
	var hover := HoverTarget.find(get_tree())
	if hover != null:
		hover.register_provider(self)


## Follows `on_flights` (the spurs, the runway works) and `on_airside` (its paving).
func bind(on_flights: FlightSim, on_airside: Airside) -> void:
	flights = on_flights
	airside = on_airside
	_key = []


func _process(_delta: float) -> void:
	if flights == null or airside == null:
		return
	var key := state_key()
	if key != _key:
		_key = key
		refresh()
	_frames += 1
	if not layouts.is_empty() and _frames % TEXT_FRAMES == 0:
		_read_texts()


## What the layouts are worked out from, cheap enough to compare every frame.
func state_key() -> Array:
	return [
		flights.spurs(),
		runway_works_running(),
		flights.runway.size,
		flights.runway.works.target,
		airside.paving.mesh.get_instance_id() if airside.paving.mesh != null else 0,
	]


## Whether the runway upgrade works are under way now (start to finish).
func runway_works_running() -> bool:
	var works := flights.runway.works
	return works.scheduled() and works.start <= flights.tick and flights.tick < works.finish


## Lays out and draws the works shown now.
func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	layouts = {}
	var live := TaxiwayWorks.live_rects(
		airside.paving.shown, airside.paving.pads, flights.runway.size
	)
	var spurs := flights.spurs()
	for side in SideSpurs.SIDES:
		if flights.spur_pending(side):
			var span := TaxiwayWorks.spur_span(airside.paving.shown, float(spurs[side]["x"]))
			layouts[side] = TaxiwayWorks.side_layout(side, float(spurs[side]["wanted"]), span, live)
	if runway_works_running():
		layouts[RUNWAY] = TaxiwayWorks.runway_layout(
			flights.runway.size, flights.runway.works.target, live
		)
	for works: String in layouts:
		_build(works, layouts[works])
	_read_texts()


func _read_texts() -> void:
	texts = {}
	for works: String in layouts:
		if works == RUNWAY:
			texts[works] = RunwayWorks.schedule_text(
				flights.runway.works, flights.tick, flights.epoch
			)
		else:
			texts[works] = SideSpurs.works_text(
				works, flights.spur_release_tick(works), flights.tick
			)


func _build(works: String, layout: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Works%s" % works.capitalize()
	add_child(root)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh(layout["ground"])
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	for item: Dictionary in layout["props"]:
		var node: Node3D = _scene(item["kind"]).instantiate()
		var origin: Vector2 = item["origin"]
		var centre: Vector2 = item["centre"]
		var height := PlaneView.ground_height_at(Vector3(centre.x, 0.0, centre.y))
		node.position = Vector3(origin.x, height, origin.y)
		node.rotation.y = item["yaw"]
		root.add_child(node)


func _scene(kind: String) -> PackedScene:
	if not _scenes.has(kind):
		_scenes[kind] = load(TaxiwayWorks.DIR + TaxiwayWorks.KINDS[kind][0] + ".glb")
	return _scenes[kind]


## The flat earth ground over `rects`, in squares of at most GROUND_CELL_M, each
## corner GROUND_LIFT_M over PlaneView.ground_height_at().
static func ground_mesh(rects: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for rect: Rect2 in rects:
		var steps := Vector2i(
			maxi(1, ceili(rect.size.x / GROUND_CELL_M)), maxi(1, ceili(rect.size.y / GROUND_CELL_M))
		)
		var base := verts.size()
		for j in steps.y + 1:
			for i in steps.x + 1:
				var x := rect.position.x + rect.size.x * float(i) / float(steps.x)
				var z := rect.position.y + rect.size.y * float(j) / float(steps.y)
				var at := Vector3(x, 0.0, z)
				verts.append(Vector3(x, PlaneView.ground_height_at(at) + GROUND_LIFT_M, z))
		for j in steps.y:
			for i in steps.x:
				var a := base + j * (steps.x + 1) + i
				var b := a + 1
				var c := a + steps.x + 1
				var d := c + 1
				index.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	uvs.fill(GROUND_UV)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, MATERIAL)
	return mesh


## The HoverTarget provider contract: each shown yard's screen rect this frame
## (its box YARD_HEIGHT_M tall, projected) and the works' words.
func hover_signs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return out
	for works: String in layouts:
		var yard: Rect2 = layouts[works]["yard"]
		if yard.size == Vector2.ZERO:
			continue
		var rect := yard_screen_rect(camera, yard)
		if rect.size != Vector2.ZERO:
			out.append({"key": works, "rect": rect, "text": texts.get(works, "")})
	return out


## The screen rect of the box over `yard` as `camera` sees it, or an empty rect
## when any corner is behind the camera.
static func yard_screen_rect(camera: Camera3D, yard: Rect2) -> Rect2:
	var rect := Rect2()
	var first := true
	for corner: Vector2 in [
		yard.position,
		yard.end,
		Vector2(yard.position.x, yard.end.y),
		Vector2(yard.end.x, yard.position.y)
	]:
		for y: float in [0.0, YARD_HEIGHT_M]:
			var at := Vector3(
				corner.x, PlaneView.ground_height_at(Vector3(corner.x, 0.0, corner.y)) + y, corner.y
			)
			if camera.is_position_behind(at):
				return Rect2()
			var point := camera.unproject_position(at)
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect
