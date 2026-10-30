extends SceneTree
## Windowed probe of the shopping wish icons (WishIconView) in the real main
## scene. The reference terminal stands on the Toon shell's doors with a kiosk
## and a pharmacy east of its airside half (WishTestLayout's rooms, built here
## through the grid's own edits on the shelled terminal). Eight bored
## passengers stand airside, wishing in turn for the kiosk, the pharmacy, duty
## free and fashion. The first four may shop at once, so the kiosk and pharmacy
## wishers are FULFILLED and the duty free and fashion wishers settle for less
## (SUBSTITUTED); the other four are held back by their shop cooldown and stay
## WANTED.
##
## Plates, the scene frozen:
##   overview      every wisher at a gameplay zoom (closer than home), the
##                 three states together
##   wanted, fulfilled, substituted
##                 one wisher of that state, close, with a crop of its icon and
##                 head scaled up CROP_ZOOM times (the icon keeps its screen
##                 size at every zoom, so only a crop shows its mark large)
## Proofs before a save: each subject's head and wish icon anchor project
## inside the frame with a margin (INFRAME lines), and a twin frame with only
## that icon hidden differs inside the icon's predicted screen rect (in frame
## is not drawn). At the home zoom every wish icon must be hidden. Otherwise
## PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/passengers/wish_icon_plates_probe.gd
##
## Plates go to tools/blender/out/wish_icons/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/wish_icons"
const MARGIN_PX := 8.0
const KINDS: Array[StringName] = [&"kiosk", &"pharmacy", &"duty_free", &"fashion"]
const SHOP_TYPES: Array[StringName] = [&"kiosk", &"pharmacy"]
const CELLS: Array[Vector2i] = [
	Vector2i(19, 4),
	Vector2i(19, 5),
	Vector2i(19, 6),
	Vector2i(19, 7),
	Vector2i(17, 4),
	Vector2i(17, 5),
	Vector2i(17, 6),
	Vector2i(17, 7),
]
const LAST_TICKS := 400
const HEAD_M := 1.7
## Twin pixels that must differ inside an icon's rect, of WISH_PX squared.
const DRAWN_SHARE := 0.2
const STATE_NAMES := ["none", "wanted", "fulfilled", "substituted"]
const CROP_PX := 160
const CROP_ZOOM := 3

var _out_dir := ""
var _failed := false
var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _rig: TycoonCamera
var _cam: Camera3D
var _wishers: Array[int] = []
var _wish := {}
var _images: Array[Image] = []
var _crops: Array[Image] = []
## The last proven icon's rect in the plate.
var _icon_rect := Rect2i()


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	if not _build():
		_invalid("the terminal and its shops were not built")
		quit(1)
		return
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.shops.refresh()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	for i in SHOP_TYPES.size():
		hired += int(staff.hire(StaffMember.Role.SHOP) != 0)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE hired=%d tick=%d doors_close=%d" % [hired, _clock.tick, doors])
	if doors < 0:
		_invalid("the airport did not open")
		quit(1)
		return
	_sim.shops.wishes = func(p: Passenger) -> StringName: return _wish.get(p.id, WishTable.NONE)
	for i in CELLS.size():
		_wishers.append(_spawn(i))
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	print(
		"PROBE viewport=%s home_distance=%.1f" % [root.get_visible_rect().size, _rig.home_distance]
	)
	var until := _clock.tick + LAST_TICKS
	var states := {}
	while _clock.tick < until:
		_clock.advance(SimClock.STEP)
		await process_frame
		states = _states()
		if states.has(WishTable.State.WANTED) and states.has(WishTable.State.FULFILLED):
			if states.has(WishTable.State.SUBSTITUTED) and _all_walking():
				break
	print("PROBE tick=%d states=%s" % [_clock.tick, _state_text()])
	for state in [WishTable.State.WANTED, WishTable.State.FULFILLED, WishTable.State.SUBSTITUTED]:
		if not states.has(state):
			_invalid("no wisher is %s by tick %d" % [STATE_NAMES[state], _clock.tick])
	if _failed:
		quit(1)
		return
	await _overview()
	for state in [WishTable.State.WANTED, WishTable.State.FULFILLED, WishTable.State.SUBSTITUTED]:
		await _close(states[state][0], STATE_NAMES[state])
	await _home_zoom()
	if not _images.is_empty():
		_save(_contact_sheet(_images), "contact_sheet.png")
	if not _crops.is_empty():
		_save(_crop_sheet(_crops), "crop_sheet.png")
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## The shelled reference terminal and WishTestLayout's kiosk and pharmacy.
func _build() -> bool:
	var grid := _mode.grid
	if not ReferenceTerminal.build(grid, _mode.shell):
		return false
	var edits: Array[BuildEdit] = []
	var floor_rect := ShopTestLayout.FLOOR
	for y in range(floor_rect.position.y, floor_rect.end.y):
		for x in range(floor_rect.position.x, floor_rect.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(floor_rect.position.x, floor_rect.end.x):
		edits.append(
			BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH)
		)
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y), BuildGrid.Side.EAST))
	var end_x := floor_rect.position.x + WishTestLayout.BLOCK * SHOP_TYPES.size()
	var air := ShopTestLayout.AIRSIDE_ROOM
	for y in range(air.position.y, air.end.y):
		for x in range(floor_rect.end.x, end_x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in grid.apply_batch(edits):
		if not result.ok:
			print("PROBE edit refused: ", result.reason_text())
			return false
	for i in SHOP_TYPES.size():
		var rect := air
		rect.position.x += WishTestLayout.BLOCK * i
		rect.size.y -= 1
		var placed: Array[BuildEdit] = [BuildEdit.place_room(rect, SHOP_TYPES[i])]
		var pieces: Array = WishTestLayout.PIECES[SHOP_TYPES[i]]
		placed.append(BuildEdit.place_object(pieces[0], rect.position, 0))
		for row in 2:
			placed.append(
				BuildEdit.place_object(pieces[1], rect.position + Vector2i(3, 3 * row), 0)
			)
		for edit in placed:
			var result := grid.apply(edit)
			if not result.ok:
				print("PROBE shop edit refused: ", result.reason_text())
				return false
	return true


## Wisher `i`: bored, airside at CELLS[i], wishing for KINDS[i % 4]; the first
## four may shop now, the rest are held back by their cooldown.
func _spawn(i: int) -> int:
	var id := _sim.spawn_now(StarterFlight.first_flight())
	var p := _sim.get_passenger(id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = CELLS[i]
	p.clear_path()
	p.boredom = BoredomSim.MAX
	p.shop_cooldown = 0 if i < 4 else _clock.tick + 100000
	_wish[id] = KINDS[i % KINDS.size()]
	print(
		(
			"PROBE wisher id=%d cell=%s walkable=%s wish=%s"
			% [id, CELLS[i], _mode.grid.is_walkable(CELLS[i]), _wish[id]]
		)
	)
	return id


## State -> wisher ids in it.
func _states() -> Dictionary:
	var out := {}
	for id in _wishers:
		var state := WishIconView.read(_sim.shops, _sim.get_passenger(id))[1] as WishTable.State
		if state != WishTable.State.NONE:
			if not out.has(state):
				out[state] = []
			out[state].append(id)
	return out


## Whether every visiting wisher has left its spot, so the plates show them
## on their way.
func _all_walking() -> bool:
	for id in _wishers:
		var p := _sim.get_passenger(id)
		if _sim.shops.visit_of(id) != null and p.path_index < 2:
			return false
	return true


func _state_text() -> String:
	var parts: Array[String] = []
	for id in _wishers:
		var wish := WishIconView.read(_sim.shops, _sim.get_passenger(id))
		parts.append("%d:%s/%s" % [id, wish[0], STATE_NAMES[wish[1]]])
	return " ".join(parts)


func _overview() -> void:
	var centre := Vector3.ZERO
	for id in _wishers:
		centre += _views.node_for(id).global_position
	centre /= _wishers.size()
	await _aim(centre, _rig.home_distance * 0.5, 0.35)
	var img := _grab()
	var ok := true
	for id in _wishers:
		if _sim.shops.visit_wish_state(id) == WishTable.State.NONE:
			continue
		ok = await _proven(id, img, "overview") and ok
	_keep(img, "overview", ok)


func _close(id: int, label: String) -> void:
	await _aim(_views.node_for(id).global_position, 9.0, 0.35)
	var img := _grab()
	var ok: bool = await _proven(id, img, label)
	_keep(img, label, ok)
	if ok:
		_crops.append(_crop(img, label))


## At the home zoom every wish icon is hidden (decision passenger-need-icons-
## hide-when-the-camera-is-zoomed-out-past, followed by the wish icon).
func _home_zoom() -> void:
	await _aim(_views.node_for(_wishers[0]).global_position, _rig.home_distance, 0.35)
	var shown := 0
	var wishing := 0
	for id in _wishers:
		var node := _views.node_for(id)
		if node.get_meta(&"wish", "") != "":
			wishing += 1
		if (node.get_node(WishIconView.SPRITE) as Sprite3D).visible:
			shown += 1
	print("HOMEZOOM distance=%.1f wishing=%d icons_shown=%d" % [_rig.distance, wishing, shown])
	if wishing == 0 or shown != 0:
		_invalid("at the home zoom wish icons must hide (wishing %d, shown %d)" % [wishing, shown])


## In frame and drawn: the head and the icon anchor project inside the frame,
## and a twin with the icon hidden differs inside its predicted rect.
func _proven(id: int, img: Image, label: String) -> bool:
	var node := _views.node_for(id)
	var sprite := node.get_node(WishIconView.SPRITE) as Sprite3D
	var head := node.global_position + Vector3(0.0, HEAD_M, 0.0)
	var anchor := node.global_transform * sprite.position
	var tag := "%s id=%d %s" % [label, id, _state_text_of(id)]
	var ok := _in_frame(head, tag + " head") and _in_frame(anchor, tag + " icon")
	if not sprite.visible:
		print("PROBE %s: icon not visible" % tag)
		return false
	var k := WishIconView.WISH_PX / WishIconView.SIZE
	var at := _cam.unproject_position(anchor)
	var centre := at + Vector2(sprite.offset.x * k, -sprite.offset.y * k)
	var scale := Vector2(img.get_size()) / root.get_visible_rect().size
	var half := Vector2.ONE * WishIconView.WISH_PX / 2.0
	var rect := Rect2i(Rect2((centre - half) * scale, half * 2.0 * scale))
	_views.set_process(false)
	sprite.visible = false
	await _frames(2)
	var bare := _grab()
	sprite.visible = true
	_views.set_process(true)
	await _frames(2)
	var differ := 0
	var bounds := rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if not img.get_pixel(x, y).is_equal_approx(bare.get_pixel(x, y)):
				differ += 1
	var need := int(DRAWN_SHARE * rect.get_area())
	var drawn := differ >= need and bounds == rect
	_icon_rect = rect
	print("DRAWN %s rect=%s differ=%d need=%d ok=%s" % [tag, rect, differ, need, drawn])
	return ok and drawn


func _state_text_of(id: int) -> String:
	var wish := WishIconView.read(_sim.shops, _sim.get_passenger(id))
	return "%s/%s" % [wish[0], STATE_NAMES[wish[1]]]


func _aim(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus * Vector3(1, 0, 1)
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	await _frames(8)
	print(
		(
			"CAMERA pos=%s distance=%.1f pitch_deg=%.1f"
			% [_cam.global_position, _rig.distance, -_cam.rotation_degrees.x]
		)
	)


func _in_frame(point: Vector3, label: String) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * MARGIN_PX * 2.0)
	var behind := _cam.is_position_behind(point)
	var screen := _cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) behind=%s ok=%s" % [label, screen.x, screen.y, behind, ok])
	return ok


func _grab() -> Image:
	return root.get_texture().get_image()


func _keep(img: Image, shot: String, ok: bool) -> void:
	if ok:
		_save(img, "wish_%s.png" % shot)
		_images.append(img)
	else:
		_invalid("%s: a subject is out of frame or its icon is not drawn" % shot)
		_save(img, "wish_%s_INVALID.png" % shot)


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var rows := ceili(plates.size() / 2.0)
	var sheet := Image.create(w * 2, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
	return sheet


## The last proven icon and the head under it, CROP_PX square, scaled up
## CROP_ZOOM times without smoothing so the badge's mark can be judged.
func _crop(img: Image, label: String) -> Image:
	var centre := _icon_rect.get_center() + Vector2i(0, CROP_PX / 4)
	var at := (centre - Vector2i.ONE * CROP_PX / 2).clamp(
		Vector2i.ZERO, img.get_size() - Vector2i.ONE * CROP_PX
	)
	var crop := img.get_region(Rect2i(at, Vector2i.ONE * CROP_PX))
	crop.convert(Image.FORMAT_RGBA8)
	crop.resize(CROP_PX * CROP_ZOOM, CROP_PX * CROP_ZOOM, Image.INTERPOLATE_NEAREST)
	_save(crop, "wish_%s_crop.png" % label)
	return crop


func _crop_sheet(crops: Array[Image]) -> Image:
	var side := crops[0].get_width()
	var sheet := Image.create(side * crops.size(), side, false, Image.FORMAT_RGBA8)
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(Vector2i.ZERO, crops[i].get_size()), Vector2i(side * i, 0))
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
