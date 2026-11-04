extends SceneTree
## Windowed probe of a selected built item in the real main.tscn (decision
## select-placed-items-design-click-order-gold-footprint-highlight-...): the
## gold floor outline and the inspect window's info rows.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/ui/built_selection_plates_probe.gd
##
## The sim seed is random and printed. The starter terminal is built with the
## HUD's debug button and every station staffed at once. Plates, each clicked
## the way a player would (a left click at the item's projected screen point,
## HUD input handler), each proving its subject in frame (every corner of the
## outline projects inside the viewport with a margin) and that the click
## selected the expected item, else PROBE_INVALID:
##   desk      a check-in desk: outline outside its footprint, window with name,
##             status, staff and queue
##   cafe      a cafe room (counter, table): outline inside its floor
##   car_park  a built landside car park: outline inside its footprint
## Plates go to tools/blender/out/select-item/ in the main checkout.

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/select-item"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const GLIDE_FRAMES := 240
const CAFE_SIZE := Vector2i(4, 4)
const MIN_SEEN_TRIANGLES := 4

var _failed := false
var _main: Node3D
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _inspect: PassengerInspect
var _outline: BuiltOutline
var _rig: TycoonCamera
var _cam: Camera3D
var _cafe_room := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("PROBE out_dir=", OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	await _boot()
	await _plate_desk()
	await _plate_cafe()
	await _plate_car_park()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _boot() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var sim_seed := randi()
	clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(_main)
	clock.set_paused(true)
	_sim = _main.get_node("PassengerSim")
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_outline = _hud.find_child("BuiltOutline", true, false) as BuiltOutline
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	(_mode.get_node("Ghost") as Node3D).visible = false
	_mode.set_tool(BuildMode.Tool.NONE)
	_hud.press_starter_terminal()
	_build_cafe()
	var staff: StaffSim = _main.get_node("Staff")
	StaffTestKit.staff_all(staff)
	# Seated without a hire, so say so, as a hire does: the staff panel's
	# banner and the cards read the staff on this signal.
	staff.staff_changed.emit()
	await _frames(10)


## A cafe in free landside-hall floor: the room, a counter and a table.
func _build_cafe() -> void:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	var area := Rect2i()
	for y in range(low.y, high.y - CAFE_SIZE.y + 2):
		for x in range(low.x + 4, high.x - CAFE_SIZE.x + 2):
			if (
				not area.has_area()
				and TestBuiltSelectionClick._is_free(grid, Rect2i(Vector2i(x, y), CAFE_SIZE))
			):
				area = Rect2i(Vector2i(x, y), CAFE_SIZE)
	if not area.has_area():
		_invalid("no free floor for the cafe")
		return
	var placed := grid.apply(BuildEdit.place_room(area, &"cafe"))
	print("CAFE room %s: %s" % [area, placed.reason_text()])
	var pieces := [
		[&"cafe_counter", [Vector2i(0, 1), Vector2i(1, 1)]],
		[&"cafe_table", [Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 2)]],
	]
	for piece in pieces:
		var done := false
		for step: Vector2i in piece[1]:
			for facing in 4:
				if (
					not done
					and (
						grid
						. apply(BuildEdit.place_object(piece[0], area.position + step, facing))
						. ok
					)
				):
					done = true
					print("CAFE %s at %s facing %d" % [piece[0], area.position + step, facing])
		if not done:
			_invalid("could not place %s in the cafe" % piece[0])
	_cafe_room = grid.room_at(area.position)
	var status := RoomRules.status(grid, _cafe_room)
	print("CAFE status ok=%s notes=%s" % [status.ok, status.notes])
	if not status.ok:
		_invalid("the cafe is not ready")


func _plate_desk() -> void:
	var desk: int = _sim.layout.desks[0]
	var record := _mode.grid.get_object(desk)
	var cell: Vector2i = record["anchor"]
	var centre := _mode.grid.cell_to_world(cell)
	await _show(centre, 16.0)
	_click(centre + Vector3(0.0, 0.4, 0.0))
	await _frames(4)
	_expect(BuiltSelection.Kind.OBJECT, desk, "desk")
	await _grab("desk_selected.png", "desk", ["status", "staff", "queue"])


func _plate_cafe() -> void:
	var grid := _mode.grid
	var rect: Rect2i = grid.get_room(_cafe_room)["rect"]
	# Open floor on the near (south) row, in front of every piece from the camera.
	var open_cell := Vector2i(-1, -1)
	for x in range(rect.position.x, rect.end.x):
		var cell := Vector2i(x, rect.end.y - 1)
		if open_cell.x < 0 and grid.object_at(cell) == 0:
			open_cell = cell
	if open_cell.x < 0:
		_invalid("the cafe has no open floor")
		return
	var centre := grid.cell_to_world(rect.position + rect.size / 2)
	await _show(centre, 16.0)
	_click(grid.cell_to_world(open_cell))
	await _frames(4)
	_expect(BuiltSelection.Kind.ROOM, _cafe_room, "cafe")
	await _grab("cafe_selected.png", "cafe", ["status", "staff", "queue"])


func _plate_car_park() -> void:
	var land: LandsideSim = _main.get_node("LandsideSim")
	var lot := land.definition.lots[0]
	if not land.build_lot(0):
		_invalid("lot 0 did not build")
		return
	await _show(lot.centre, 55.0)
	_click(lot.centre)
	await _frames(4)
	var selection := _inspect.built_card.selection
	print("HIT car park: kind %d spot %d" % [selection.kind, selection.spot])
	if selection.kind != BuiltSelection.Kind.LANDSIDE or selection.spot != 0:
		_invalid("the click did not select the car park")
	await _grab("car_park_selected.png", "car_park", ["status", "queue"])


func _show(point: Vector3, distance: float) -> void:
	_rig.glide_to(point, distance)
	await _frames(GLIDE_FRAMES)


func _click(at: Vector3) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _cam.unproject_position(at)
	print("CLICK world %s screen %s" % [at, click.position])
	_hud._unhandled_input(click)
	_hud.refresh()


func _expect(kind: BuiltSelection.Kind, id: int, label: String) -> void:
	var selection := _inspect.built_card.selection
	print(
		(
			"HIT %s: kind %d id %d (wanted kind %d id %d)"
			% [label, selection.kind, selection.id, kind, id]
		)
	)
	if selection.kind != kind or selection.id != id:
		_invalid("%s: the click selected the wrong thing" % label)


func _grab(file: String, label: String, fields: Array[String]) -> void:
	_outline.refresh()
	_prove_outline(label)
	await _prove_outline_seen(label)
	_prove_fields(label, fields)
	var card := _inspect.built_card
	print(
		(
			"WINDOW %s: %s | %s | %s | %s | %s | %s"
			% [
				label,
				card.name_text(),
				card.field_text("where"),
				card.field_text("status"),
				card.field_text("staff"),
				card.field_text("queue"),
				card.field_text("upkeep")
			]
		)
	)
	await _frames(4)
	var img := root.get_texture().get_image()
	var path := OUT_DIR.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## Every corner of the drawn outline projects inside the viewport with a margin,
## and the window is inside it too.
func _prove_outline(label: String) -> void:
	if not _outline.is_showing():
		_invalid("%s: the outline is not showing" % label)
		return
	var frame := _outline.frame_aabb()
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for x in [frame.position.x, frame.end.x]:
		for z in [frame.position.z, frame.end.z]:
			var corner := Vector3(x, frame.position.y, z)
			var s := _cam.unproject_position(corner)
			var ok := not _cam.is_position_behind(corner) and view.has_point(s)
			print("INFRAME %s corner screen=(%.0f, %.0f) ok=%s" % [label, s.x, s.y, ok])
			if not ok:
				_invalid("%s: an outline corner leaves the viewport" % label)
	if not (_inspect.visible and view.encloses(_inspect.get_global_rect())):
		_invalid("%s: the window is not fully on screen" % label)


## The window's name and each of `fields` hold text.
func _prove_fields(label: String, fields: Array[String]) -> void:
	var card := _inspect.built_card
	if card.name_text() == "":
		_invalid("%s: the window has no name" % label)
	for field in fields:
		if card.field_text(field) == "":
			_invalid("%s: the window's %s line is empty" % [label, field])


## Occlusion: a ray from the camera to each triangle of the outline's mesh
## meets the outline first for at least MIN_SEEN_TRIANGLES of its 8 (a tall
## piece may cover the far side of a room's frame, so not all). Every visible
## mesh gets a collider for the check, which is removed afterwards.
func _prove_outline_seen(label: String) -> void:
	var bodies: Array[Node] = []
	for mi: MeshInstance3D in _main.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree():
			continue
		var faces := mi.mesh.get_faces()
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.add_child(shape_node)
		mi.add_child(body)
		bodies.append(body)
	await physics_frame
	await physics_frame
	var mesh_node := _outline.get_child(0) as MeshInstance3D
	var faces := mesh_node.mesh.get_faces()
	var from := _cam.global_position
	var space := _cam.get_world_3d().direct_space_state
	var seen := 0
	var blockers := {}
	for i in range(0, faces.size(), 3):
		var centre := mesh_node.global_transform * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
		var query := PhysicsRayQueryParameters3D.create(
			from, centre + (centre - from).normalized() * 0.05
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and mesh_node.is_ancestor_of(hit["collider"]):
			seen += 1
		elif not hit.is_empty():
			var by := str((hit["collider"] as Node).get_parent().name)
			blockers[by] = int(blockers.get(by, 0)) + 1
	for body in bodies:
		body.free()
	print("OCCLUSION %s outline triangles seen=%d/8 blocked_by=%s" % [label, seen, blockers])
	if seen < MIN_SEEN_TRIANGLES:
		_invalid("%s: the outline is hidden behind %s" % [label, blockers])
