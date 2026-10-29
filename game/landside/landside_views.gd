class_name LandsideViews
extends Node3D
## Placeholder views of the landside's cars and taxis (Landside 1/4): one
## coloured box per vehicle, yellow for a taxi and blue for a car, placed
## where LandsideSim says it stands and turned along its lane. Cars waiting
## off the map (below 0 on road_in) are not drawn. Reads the sim every frame
## and never writes back. Real vehicle models replace the boxes in Landside
## 2/4.

const BOX_SIZE := Vector3(1.8, 1.4, 4.5)
const TAXI_COLOR := Color(0.95, 0.78, 0.15)
const CAR_COLOR := Color(0.25, 0.45, 0.85)

@export var landside: LandsideSim

## Vehicle id -> its box.
var _boxes := {}
var _mesh := BoxMesh.new()
var _materials := {}


func _ready() -> void:
	_mesh.size = BOX_SIZE
	for kind in [LandsideVehicle.Kind.TAXI, LandsideVehicle.Kind.CAR]:
		var material := StandardMaterial3D.new()
		material.albedo_color = TAXI_COLOR if kind == LandsideVehicle.Kind.TAXI else CAR_COLOR
		_materials[kind] = material


func _process(_delta: float) -> void:
	update_views()


## Adds, places and removes boxes to match the sim's vehicles.
func update_views() -> void:
	if landside == null or landside.definition == null:
		return
	var seen := {}
	for id in landside.vehicle_ids():
		var v := landside.get_vehicle(id)
		if v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm < 0:
			continue
		seen[id] = true
		var box: MeshInstance3D = _boxes.get(id)
		if box == null:
			box = MeshInstance3D.new()
			box.name = "Vehicle%d" % id
			box.mesh = _mesh
			box.material_override = _materials[v.kind]
			add_child(box)
			_boxes[id] = box
		var at := landside.world_position(v) + Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
		box.transform = Transform3D(Basis.looking_at(landside.heading(v), Vector3.UP), at)
	for id in _boxes.keys():
		if not seen.has(id):
			(_boxes[id] as Node).queue_free()
			_boxes.erase(id)


## The number of vehicles drawn.
func box_count() -> int:
	return _boxes.size()
