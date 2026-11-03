class_name RoomView
extends Node3D
## Draws each room of a BuildGrid: a see-through floor tint over its cells,
## green when RoomRules says it is ready and amber when it is not, and a label
## above its middle with the type and either "Ready" or the notes saying what
## it still needs. It follows the grid's own signals, so furniture placed by any
## path (BuildMode, a probe, later systems) shows on the next frame. Each frame
## RoomLabelLayout slides a label clear of the HUD, caps its size on screen and
## fades it out when the camera zooms in close.

const TINT_Y := 0.06
## Height of the label's bottom line; the text grows upward from it, so more
## notes never cover the furniture.
const LABEL_Y := 2.9
const LABEL_FONT_SIZE := 40
## The label is a world-size billboard at this pixel size until RoomLabelLayout caps
## it on screen.
const LABEL_PIXEL_SIZE := 0.01
const READY_TINT := Color(0.35, 0.85, 0.45, 0.3)
const NEEDS_TINT := Color(1.0, 0.68, 0.18, 0.34)
const READY_TEXT := Color(0.75, 1.0, 0.8)
const NEEDS_TEXT := Color(1.0, 0.85, 0.45)

var _grid: BuildGrid
var _dirty := false
## Room id -> [MeshInstance3D tint, Label3D].
var _drawn: Dictionary = {}
var _layout := RoomLabelLayout.new()
var _labels: Array[Label3D] = []
var _ready_material := _tint_material(READY_TINT)
var _needs_material := _tint_material(NEEDS_TINT)


static func _tint_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Follows `grid` from now on and draws it at once.
func watch(grid: BuildGrid) -> void:
	_grid = grid
	grid.edit_applied.connect(_on_edit_applied)
	grid.graph_changed.connect(_on_graph_changed)
	redraw()


func _process(_delta: float) -> void:
	if _dirty:
		redraw()
	layout_labels()


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_dirty = true


## A snapshot load emits graph_changed with every cell.
func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = true


## The label over a room, or null when the room is not drawn.
func label_of(room_id: int) -> Label3D:
	return _drawn[room_id][1] if _drawn.has(room_id) else null


## Lays the labels out for the camera and the HUD as they are now (every frame).
func layout_labels() -> void:
	if _drawn.is_empty() or not is_inside_tree():
		return
	var view := get_viewport()
	var camera := view.get_camera_3d()
	var scale := view.get_stretch_transform().get_scale()
	_labels.clear()
	for parts in _drawn.values():
		_labels.append(parts[1])
	var hud: Array[Rect2] = []
	if camera != null:
		hud = HudRects.collect(self, scale.y)
	_layout.layout(_labels, camera, scale.y, view.get_visible_rect().size * scale, hud)


## Rebuilds every room's tint and label from the grid.
func redraw() -> void:
	_dirty = false
	for parts in _drawn.values():
		for node in parts:
			node.queue_free()
	_drawn.clear()
	if _grid == null:
		return
	for room_id in _grid.room_ids():
		_draw_room(room_id)


func _draw_room(room_id: int) -> void:
	var status := RoomRules.status(_grid, room_id)
	var area: Rect2i = _grid.get_room(room_id)["rect"]
	var middle := (
		_grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.0, (area.size.y - 1) / 2.0)
	)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(area.size) - Vector2(0.1, 0.1)
	var tint := MeshInstance3D.new()
	tint.name = "RoomTint%d" % room_id
	tint.mesh = mesh
	tint.material_override = _ready_material if status.ok else _needs_material
	tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tint.position = middle + Vector3(0.0, TINT_Y, 0.0)
	add_child(tint)
	var label := Label3D.new()
	label.name = "RoomLabel%d" % room_id
	var lines := [status.type_name]
	lines.append_array(Array(status.notes) if not status.ok else [RoomRules.READY])
	label.text = "\n".join(lines)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.05, 0.08)
	label.modulate = READY_TEXT if status.ok else NEEDS_TEXT
	label.position = middle + Vector3(0.0, LABEL_Y, 0.0)
	add_child(label)
	_drawn[room_id] = [tint, label]
