class_name CafePops
extends Node3D
## The '+$' pop over a cafe or kiosk when a visit is paid (ruling
## shops-and-food-stalls-earn-per-visit-toilets-and-screens-cos: "a small '+$'
## pop over the shop"): a gold "+$<amount>" that rises and fades out over
## POP_SECONDS. It hangs in the same column as the room's label (RoomView), top
## aligned under the label's bottom line, so for any camera turn it stays below
## the label and never covers it. It listens to CafeSim.paid and ShopSim.paid,
## which fire only after the money is in the wallet. PassengerViews creates it as a child. It
## reads the sim and never writes to it; labels are pooled.
##
## Under a camera, each pop also stays clear of the passengers drawn around it
## (board a48bca8d: at the top-down step a pop covered a need icon and a
## seated guest's head). lay_out() keeps a pop in its side slot while that slot
## covers no need icon, wish bubble, speech bubble or passenger head on screen,
## and otherwise moves it to the first clear slot in the ruled order 0, +1, -1,
## +2, -2; with no clear slot it takes the one covering fewest. It runs when a
## pop is paid and when the view changes, not every frame, so a passenger
## walking past does not make a pop jump. With no camera the slots keep the
## ruled order only.

const POP_SECONDS := 1.6
const RISE_M := 0.4
## Space between the pop's top line at the end of its rise and the bottom line
## of the room label (RoomView.LABEL_Y), which grows upward from there.
const GAP_M := 0.6
## How far the pop also hangs below the label, in the label's own plane (so it is
## the same on screen at every camera pitch): the world gap above shrinks on
## screen as the camera looks steeper down, and the top-down step (70 degrees)
## would put the pop on the room label.
const DROP_M := 0.4
## How far a pop paid while another of its room is up steps aside, wider
## than a "+$<amount>" pop.
const SIDE_STEP_M := 1.3
const FONT_SIZE := 64
const COLOR := Color(1.0, 0.84, 0.3)
## Side slots a pop tries to stay clear of passengers: 0, +1, -1, +2, -2.
const SLOT_TRIES := 5
## Screen pixels a pop keeps from anything it must not cover.
const CLEAR_PX := 4.0
## A passenger's head on screen: the band from a seated head's chin to a
## standing head's top, over the node, and its half width, in metres.
const HEAD_LOW_M := 0.9
const HEAD_TOP_M := 1.85
const HEAD_HALF_M := 0.3
## The sprites and label over a passenger node that a pop must not cover.
const OVERHEAD := [&"NeedIcon0", &"NeedIcon1", &"NeedIcon2", &"WishIcon", &"Bubble"]

var sim: PassengerSim

## Labels on screen, oldest first; each carries its age and start height.
var _live: Array[Label3D] = []
var _free: Array[Label3D] = []
## The view the pops were last laid out for; emptied when a pop is paid.
var _view_key: Array = []


func _ready() -> void:
	if sim != null and not sim.cafes.paid.is_connected(_on_paid):
		sim.cafes.paid.connect(_on_paid)
	if sim != null and not sim.shops.paid.is_connected(_on_paid):
		sim.shops.paid.connect(_on_paid)


func _process(delta: float) -> void:
	advance(delta)
	if _live.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and _key_of(camera) != _view_key:
		lay_out(camera)


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
	# room are still up steps aside in the label's plane to the first free
	# slot in the order 0, +1, -1, +2, -2, ... Sideways steps keep it under
	# the room label.
	var taken := {}
	for live in _live:
		if live.get_meta(&"room") == room_id:
			taken[live.get_meta(&"slot")] = true
	var n := 0
	while taken.has(slot_at(n)):
		n += 1
	var label := _take()
	label.set_meta(&"room", room_id)
	_set_slot(label, slot_at(n))
	label.text = "+$%d" % amount
	label.position = _point(passenger_id, room_id)
	label.modulate = COLOR
	label.set_meta(&"age", 0.0)
	label.set_meta(&"start_y", label.position.y)
	_live.append(label)
	_view_key = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		lay_out(camera)


## The side slot tried `n`-th: 0, +1, -1, +2, -2, ...
static func slot_at(n: int) -> int:
	return ceili(n / 2.0) * (1 if n % 2 == 1 else -1)


## Puts every live pop in a side slot no other pop of its room holds. A pop
## whose own slot covers nothing drawn over a passenger (OVERHEAD) and no
## passenger's head keeps it; the others, oldest first, take the first clear
## slot of the first SLOT_TRIES free ones in the order 0, +1, -1, +2, -2, or
## else the one of those covering fewest. Does nothing with no camera.
func lay_out(camera: Camera3D) -> void:
	var unit := _unit(camera)
	if unit <= 0.0:
		return
	_view_key = _key_of(camera)
	var blockers := blocker_rects(camera)
	var held := {}
	var moving: Array[Label3D] = []
	for label in _live:
		var used: Dictionary = held.get_or_add(label.get_meta(&"room"), {})
		var own: int = label.get_meta(&"slot")
		if not used.has(own) and _covered(screen_rect(label, camera, own), blockers) == 0:
			used[own] = true
		else:
			moving.append(label)
	for label in moving:
		var used: Dictionary = held.get_or_add(label.get_meta(&"room"), {})
		var best := 0
		var fewest := -1
		var n := 0
		var tried := 0
		while fewest != 0 and tried < SLOT_TRIES:
			var side := slot_at(n)
			n += 1
			if used.has(side):
				continue
			tried += 1
			var count := _covered(screen_rect(label, camera, side), blockers)
			if fewest < 0 or count < fewest:
				best = side
				fewest = count
		used[best] = true
		_set_slot(label, best)


## The pop's screen box (viewport pixels) in side slot `side`, over its whole
## rise and grown by CLEAR_PX; empty when it is behind the camera.
func screen_rect(label: Label3D, camera: Camera3D, side: int) -> Rect2:
	var unit := _unit(camera)
	var font := label.font if label.font != null else ThemeDB.fallback_font
	var size := (
		font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size)
		+ Vector2.ONE * 2.0 * label.outline_size
	)
	size *= label.pixel_size
	var start := Vector3(label.position.x, float(label.get_meta(&"start_y")), label.position.z)
	var box := Rect2()
	for rise in [0.0, RISE_M]:
		var at := to_global(start + Vector3(0.0, rise, 0.0))
		var depth := (at - camera.global_position).dot(-camera.global_basis.z)
		if depth <= 0.0 or unit <= 0.0:
			return Rect2()
		var scale := 1.0 / (depth * unit)
		var top := camera.unproject_position(at) + Vector2(side * SIDE_STEP_M, DROP_M) * scale
		var part := Rect2(top - Vector2(size.x / 2.0, 0.0) * scale, size * scale)
		box = part if not box.has_area() else box.merge(part)
	return box.grow(CLEAR_PX)


## Screen boxes (viewport pixels) of every passenger head and every need icon,
## wish bubble and speech bubble drawn over a passenger, as the passenger nodes
## (PassengerViews' children with a body) are now.
func blocker_rects(camera: Camera3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var unit := _unit(camera)
	var views := get_parent()
	if views == null or unit <= 0.0:
		return rects
	for child in views.get_children():
		var node := child as Node3D
		if node == null or not node.has_meta(&"body") or not node.visible:
			continue
		var low := node.global_position + Vector3(0.0, HEAD_LOW_M, 0.0)
		var high := node.global_position + Vector3(0.0, HEAD_TOP_M, 0.0)
		var depth := (low - camera.global_position).dot(-camera.global_basis.z)
		if depth <= 0.0:
			continue
		var half := HEAD_HALF_M / (depth * unit)
		var head := Rect2(camera.unproject_position(high), Vector2.ZERO)
		rects.append(head.expand(camera.unproject_position(low)).grow(half))
		for part_name in OVERHEAD:
			var part := node.get_node_or_null(NodePath(part_name)) as Node3D
			if part != null and part.visible:
				var rect := _overhead_rect(part, camera, unit)
				if rect.has_area():
					rects.append(rect)
	return rects


## The screen box of a billboard Sprite3D or Label3D over a passenger, or an
## empty one when it draws nothing or is behind the camera.
func _overhead_rect(part: Node3D, camera: Camera3D, unit: float) -> Rect2:
	var at := part.global_position
	var depth := (at - camera.global_position).dot(-camera.global_basis.z)
	if depth <= 0.0:
		return Rect2()
	var point := camera.unproject_position(at)
	var sprite := part as Sprite3D
	if sprite != null:
		if sprite.texture == null or sprite.modulate.a <= 0.0:
			return Rect2()
		var scale := sprite.pixel_size / ((1.0 if sprite.fixed_size else depth) * unit)
		var size := sprite.texture.get_size() * scale
		var centre := point + Vector2(sprite.offset.x, -sprite.offset.y) * scale
		return Rect2(centre - size / 2.0, size)
	var bubble := part as Label3D
	if bubble == null or bubble.text == "":
		return Rect2()
	return BubbleDeclutter.rect_of(
		point,
		bubble.text,
		bubble.font_size,
		bubble.outline_size,
		bubble.pixel_size / (depth * unit)
	)


## How many of `blockers` the box `rect` overlaps.
static func _covered(rect: Rect2, blockers: Array[Rect2]) -> int:
	var count := 0
	for blocker in blockers:
		if rect.intersects(blocker):
			count += 1
	return count


func _set_slot(label: Label3D, side: int) -> void:
	label.set_meta(&"slot", side)
	label.offset = Vector2(side * SIDE_STEP_M, -DROP_M) / label.pixel_size


## World units per viewport pixel at one metre from `camera` (the space
## Camera3D.unproject_position() answers in), or 0 with no camera.
func _unit(camera: Camera3D) -> float:
	if camera == null or not is_inside_tree():
		return 0.0
	return 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / get_viewport().get_visible_rect().size.y


func _key_of(camera: Camera3D) -> Array:
	return [camera.global_transform, camera.fov, get_viewport().get_visible_rect().size]


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
