class_name CafePops
extends Node3D
## The '+$' pop over a cafe counter when a visit is paid (ruling
## shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos): a gold
## "+$<amount>" that rises a metre and fades out over POP_SECONDS. It listens
## to CafeSim.paid, which fires only after the money is in the wallet.
## PassengerViews creates it as a child. It reads the sim and never writes
## to it; labels are pooled.

const POP_SECONDS := 1.6
const RISE_M := 1.0
## Starts just above the counter's 1.98 m chalkboard.
const LIFT_M := 2.3
const FONT_SIZE := 64
const COLOR := Color(1.0, 0.84, 0.3)

var sim: PassengerSim

## Labels on screen, oldest first; each carries its age and start height.
var _live: Array[Label3D] = []
var _free: Array[Label3D] = []


func _ready() -> void:
	if sim != null and not sim.cafes.paid.is_connected(_on_paid):
		sim.cafes.paid.connect(_on_paid)


func _process(delta: float) -> void:
	advance(delta)


func live_count() -> int:
	return _live.size()


func live_labels() -> Array[Label3D]:
	return _live.duplicate()


## Ages every pop by `seconds`: it rises and fades, and is put away at the end.
func advance(seconds: float) -> void:
	for label in _live.duplicate():
		var age: float = label.get_meta(&"age") + seconds
		label.set_meta(&"age", age)
		var t := clampf(age / POP_SECONDS, 0.0, 1.0)
		label.position.y = float(label.get_meta(&"start_y")) + RISE_M * t
		label.modulate.a = 1.0 - t
		if t >= 1.0:
			label.visible = false
			_live.erase(label)
			_free.append(label)


func _on_paid(passenger_id: int, room_id: int, amount: int) -> void:
	var label := _take()
	label.text = "+$%d" % amount
	label.position = _point(passenger_id, room_id)
	label.modulate = COLOR
	label.set_meta(&"age", 0.0)
	label.set_meta(&"start_y", label.position.y)
	_live.append(label)


## Above the guest's counter (the visit is still there when `paid` fires), or
## above the room's middle when the counter is gone.
func _point(passenger_id: int, room_id: int) -> Vector3:
	var grid := sim.grid
	var visit := sim.cafes.visit_of(passenger_id)
	var counter := grid.get_object(visit.counter) if visit != null else {}
	if not counter.is_empty():
		var def := BuildCatalog.get_def(counter["def"])
		var cells := def.footprint(counter["anchor"], counter["facing"])
		var centre := BuildView.object_transform(grid, cells, counter["facing"]).origin
		return centre + Vector3(0.0, LIFT_M, 0.0)
	var room := grid.get_room(room_id)
	if room.is_empty():
		return grid.origin + Vector3(0.0, LIFT_M, 0.0)
	var rect: Rect2i = room["rect"]
	var middle := Vector2(rect.position) + Vector2(rect.size) * 0.5
	return grid.origin + Vector3(middle.x, LIFT_M, middle.y)


func _take() -> Label3D:
	if not _free.is_empty():
		var reused: Label3D = _free.pop_back()
		reused.visible = true
		return reused
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = FONT_SIZE
	label.outline_size = 16
	label.pixel_size = 0.006
	add_child(label)
	return label
