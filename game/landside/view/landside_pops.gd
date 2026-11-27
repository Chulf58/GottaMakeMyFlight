class_name LandsidePops
extends Node3D
## Floating '+$' popups over a car park when LandsideSim.parked credits a
## parking fee (decision parking-and-landside-gameplay-popups-2-berth-curb-
## shortest-walk-routing). Each popup rises and fades smoothly above the lot
## and frees itself with queue_free() when done, leaving zero orphans.

const POP_SECONDS := 1.6
const RISE_M := 2.0
const SIDE_STEP_M := 2.2
const SURFACE_Y := 3.5
const MULTI_Y := 29.5
const FONT_SIZE := 64
const COLOR := Color(1.0, 0.84, 0.3)

var landside: LandsideSim
## Optional: used to place popups cleanly above the drawn lot mesh when present.
var places: LandsidePlaces

var _live: Array[Label3D] = []


func _ready() -> void:
	_connect_sim()


func _process(delta: float) -> void:
	advance(delta)


func live_count() -> int:
	return _live.size()


func live_labels() -> Array[Label3D]:
	return _live.duplicate()


## Ages every live popup by `seconds`, freeing finished ones cleanly.
func advance(seconds: float) -> void:
	for label in _live.duplicate():
		if not is_instance_valid(label):
			_live.erase(label)
			continue
		var age: float = float(label.get_meta(&"age")) + seconds
		label.set_meta(&"age", age)
		var t := clampf(age / POP_SECONDS, 0.0, 1.0)
		label.position.y = float(label.get_meta(&"start_y")) + RISE_M * t
		label.modulate.a = 1.0 - t
		if t >= 1.0:
			_live.erase(label)
			label.queue_free()


## Removes all live popups immediately (for save loads).
func clear() -> void:
	for label in _live:
		if is_instance_valid(label):
			label.queue_free()
	_live.clear()


func _connect_sim() -> void:
	if landside != null and not landside.parked.is_connected(_on_parked):
		landside.parked.connect(_on_parked)


func _on_parked(_vehicle_id: int, lot: int) -> void:
	if landside == null or landside.definition == null:
		return
	if lot < 0 or lot >= landside.definition.lots.size():
		return
	var fee := landside.parking_fee(lot)
	if fee <= 0:
		return
	var taken := {}
	for existing in _live:
		if is_instance_valid(existing) and existing.get_meta(&"lot") == lot:
			taken[existing.get_meta(&"slot")] = true
	var n := 0
	while taken.has(CafePops.slot_at(n)):
		n += 1
	var slot := CafePops.slot_at(n)
	var label := _make_label()
	label.set_meta(&"lot", lot)
	label.set_meta(&"slot", slot)
	label.text = tr("+${amount}", "money pop").format({"amount": fee})
	label.position = _anchor(lot)
	label.offset = Vector2(slot * SIDE_STEP_M / label.pixel_size, 0.0)
	label.modulate = COLOR
	label.set_meta(&"age", 0.0)
	label.set_meta(&"start_y", label.position.y)
	add_child(label)
	_live.append(label)


func _anchor(lot: int) -> Vector3:
	var spot := landside.lot_spot(lot)
	var top_y := (
		MULTI_Y if landside.lot_kind(lot) == LandsideLotSpot.Kind.MULTI_STOREY else SURFACE_Y
	)
	if places != null:
		top_y = maxf(top_y, places.lot_top_y(lot) + 2.4)
	return Vector3(spot.centre.x, top_y, spot.centre.z)


func _make_label() -> Label3D:
	var label := CaptionFont.apply(Label3D.new())
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.font_size = FONT_SIZE
	label.outline_size = 16
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.pixel_size = 0.012
	label.render_priority = 12
	label.outline_render_priority = 11
	return label
