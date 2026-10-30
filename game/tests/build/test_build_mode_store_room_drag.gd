class_name TestBuildModeStoreRoomDrag
extends GdUnitTestSuite
## The store room tools (F4-5, the exchange and ATM rooms of F4-5b and the food
## rooms of F4-6) drag
## out a rectangle through the real mouse path, as the kiosk room tool does: a
## press starts BuildMode's area drag
## (AREA_TOOLS), a motion sizes it and the release marks the room, one undo
## step. A room tool missing from AREA_TOOLS would take the press as a click
## (apply_at) and mark nothing. The kiosk room is the control.

const PORT_SIZE := Vector2i(1280, 720)
const FROM := Vector2i(3, 3)
## A 3x4 rectangle: large enough for every store's minimum size.
const TO := Vector2i(5, 6)
## BuildGrid.room_at() answers 0 for a cell in no room.
const NO_ROOM := 0
## Room tool -> RoomTypes id.
const ROOM_TOOLS := {
	BuildMode.Tool.KIOSK_ROOM: "kiosk",
	BuildMode.Tool.PHARMACY_ROOM: "pharmacy",
	BuildMode.Tool.DUTY_FREE_ROOM: "duty_free",
	BuildMode.Tool.FASHION_ROOM: "fashion",
	BuildMode.Tool.EXCHANGE_ROOM: "exchange",
	BuildMode.Tool.ATM_ROOM: "atm",
	BuildMode.Tool.BAR_ROOM: "bar",
	BuildMode.Tool.RESTAURANT_ROOM: "restaurant",
	BuildMode.Tool.STALL_ROOM: "stall",
	BuildMode.Tool.PLAY_AREA_ROOM: "play_area",
	BuildMode.Tool.LOUNGE_ROOM: "lounge",
	BuildMode.Tool.SHOWER_ROOM: "shower",
	BuildMode.Tool.NAP_POD_ROOM: "nap_pod",
}

var _port: SubViewport
var _camera: Camera3D
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	_camera.position = Vector3(6.0, 20.0, 6.0)
	_camera.look_at(Vector3(6.0, 0.0, 6.0), Vector3.FORWARD)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.grid_centred = false
	_port.add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(1, 10):
		for x in range(1, 10):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _point_at(cell: Vector2i) -> void:
	_mode.pointer_override = _camera.unproject_position(_mode.grid.cell_to_world(cell))


func _click(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _mode.pointer_override
	return event


func _motion() -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = _mode.pointer_override
	return event


func _drag_with_the_mouse(tool: BuildMode.Tool) -> void:
	_mode.set_tool(tool)
	_point_at(FROM)
	_mode._unhandled_input(_click(true))
	_point_at(TO)
	_mode._unhandled_input(_motion())
	_mode._unhandled_input(_click(false))


func test_every_store_room_tool_is_an_area_tool() -> void:
	for tool in ROOM_TOOLS:
		var area := BuildMode.AREA_TOOLS.has(tool)
		assert_bool(area).override_failure_message("tool %d" % tool).is_true()


func test_a_mouse_drag_marks_the_rectangle_as_the_tool_s_room_in_one_undo_step() -> void:
	for tool in ROOM_TOOLS:
		assert_int(_mode.grid.room_at(FROM)).is_equal(NO_ROOM)
		_drag_with_the_mouse(tool)
		var room_id := _mode.grid.room_at(FROM)
		var room := _mode.grid.get_room(room_id)
		print(
			"tool %d -> room %d %s; history %d" % [tool, room_id, room, _mode.undo_history().size()]
		)
		assert_int(room_id).override_failure_message("tool %d marked nothing" % tool).is_not_equal(
			NO_ROOM
		)
		if room_id == NO_ROOM:
			continue
		assert_str(str(room["type"])).is_equal(ROOM_TOOLS[tool])
		assert_object(room["rect"]).is_equal(Rect2i(FROM, TO - FROM + Vector2i.ONE))
		assert_int(_mode.undo_history().size()).is_equal(1)
		assert_bool(_mode.undo().ok).is_true()
		assert_int(_mode.grid.room_at(FROM)).is_equal(NO_ROOM)
		assert_int(_mode.undo_history().size()).is_equal(0)
