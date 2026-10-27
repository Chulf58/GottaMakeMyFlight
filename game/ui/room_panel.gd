class_name RoomPanel
extends PanelContainer
## The room info panel: type, status ("Ready" or what the room still needs),
## seats and base spend of the room under the pointer (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces). BuildMenu
## creates it top-left under the money slot; it is hidden while no room is
## followed. It reads RoomRules and follows the grid's own signals, so
## furniture placed while it is open shows on the next frame.

const POSITION := Vector2(16.0, 64.0)
const WIDTH := 280.0
const READY_COLOR := Color(0.6, 0.95, 0.65)
const NOTE_COLOR := Color(1.0, 0.78, 0.4)
const TEXT_COLOR := Color(0.85, 0.88, 0.94)

var _build_mode: BuildMode
var _room_id := 0
var _dirty := false
var _lines := VBoxContainer.new()


func _ready() -> void:
	name = "RoomPanel"
	position = POSITION
	custom_minimum_size = Vector2(WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", BuildMenu.panel_style())
	_lines.add_theme_constant_override("separation", 2)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)
	visible = false


## Follows `mode`'s focused room and its grid's edits.
func watch(mode: BuildMode) -> void:
	_build_mode = mode
	mode.room_focus_changed.connect(show_room)
	mode.grid.edit_applied.connect(_on_edit_applied)
	mode.grid.graph_changed.connect(_on_graph_changed)
	show_room(mode.focused_room())


## The room shown, 0 for none.
func room_id() -> int:
	return _room_id


## Shows a room's status, or hides the panel for 0 or an unknown room.
func show_room(id: int) -> void:
	_room_id = id
	_dirty = false
	for child in _lines.get_children():
		child.free()
	var status := RoomRules.status(_build_mode.grid, id) if id != 0 else null
	visible = status != null
	if status == null:
		return
	_line(status.type_name, 22, Color.WHITE)
	if status.ok:
		_line(RoomRules.READY, 17, READY_COLOR)
	for note in status.notes:
		_line(note, 17, NOTE_COLOR)
	_line("Seats %d" % status.seats, 17, TEXT_COLOR)
	_line("Base spend $%d per visit" % status.base_spend, 17, TEXT_COLOR)
	reset_size()


func _process(_delta: float) -> void:
	if _dirty:
		show_room(_room_id)


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_dirty = _room_id != 0


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = _room_id != 0


func _line(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs a width, or the label measures one word per line.
	label.custom_minimum_size = Vector2(WIDTH - 8.0, 0.0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(label)
