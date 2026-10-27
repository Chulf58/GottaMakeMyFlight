class_name CafePops
extends Node3D
## The '+$' pop over a cafe when a visit is paid (ruling
## shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos: "a small '+$'
## pop over the shop"): a gold "+$<amount>" that rises and fades out over
## POP_SECONDS. It hangs in the same column as the room's label (RoomView), top
## aligned under the label's bottom line, so for any camera turn it stays below
## the label and never covers it. It listens to CafeSim.paid, which fires only
## after the money is in the wallet. PassengerViews creates it as a child. It
## reads the sim and never writes to it; labels are pooled.

const POP_SECONDS := 1.6
const RISE_M := 0.4
## Space between the pop's top line at the end of its rise and the bottom line
## of the room label (RoomView.LABEL_Y), which grows upward from there.
const GAP_M := 0.6
## How far a pop paid while another of its room is up steps aside, wider
## than a "+$<amount>" pop.
const SIDE_STEP_M := 1.3
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
	# Pops of one room share its column, so a pop paid while others of that
	# room are still up steps aside in the label's plane: right, left, then
	# further out. Sideways steps keep it under the room label.
	var others := 0
	for live in _live:
		if live.get_meta(&"room") == room_id:
			others += 1
	var label := _take()
	label.set_meta(&"room", room_id)
	var side := ceili(others / 2.0) * (1 if others % 2 == 1 else -1)
	label.offset = Vector2(side * SIDE_STEP_M / label.pixel_size, 0.0)
	label.text = "+$%d" % amount
	label.position = _point(passenger_id, room_id)
	label.modulate = COLOR
	label.set_meta(&"age", 0.0)
	label.set_meta(&"start_y", label.position.y)
	_live.append(label)


## Where a pop starts: under the room label's column, RISE_M + GAP_M below the
## label's bottom line. Over the guest's counter when the room is gone.
func _point(passenger_id: int, room_id: int) -> Vector3:
	var grid := sim.grid
	var lift := Vector3(0.0, RoomView.LABEL_Y - GAP_M - RISE_M, 0.0)
	var room := grid.get_room(room_id)
	if not room.is_empty():
		var area: Rect2i = room["rect"]
		# RoomView's own formula for the label's position.
		var middle := (
			grid.cell_to_world(area.position)
			+ Vector3((area.size.x - 1) / 2.0, 0.0, (area.size.y - 1) / 2.0)
		)
		return middle + lift
	var visit := sim.cafes.visit_of(passenger_id)
	var counter := grid.get_object(visit.counter) if visit != null else {}
	if not counter.is_empty():
		var def := BuildCatalog.get_def(counter["def"])
		var cells := def.footprint(counter["anchor"], counter["facing"])
		return BuildView.object_transform(grid, cells, counter["facing"]).origin + lift
	return grid.origin + lift


func _take() -> Label3D:
	if not _free.is_empty():
		var reused: Label3D = _free.pop_back()
		reused.visible = true
		return reused
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# The text hangs down from the label's position.
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.font_size = FONT_SIZE
	label.outline_size = 16
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.pixel_size = 0.006
	# Over the room's own label, which also ignores depth.
	label.render_priority = 10
	label.outline_render_priority = 9
	add_child(label)
	return label
