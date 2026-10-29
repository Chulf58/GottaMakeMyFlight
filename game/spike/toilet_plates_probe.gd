extends SceneTree
## Windowed probe of the toilet in the real main scene (Toilets 5/5). The
## reference terminal stands on the Toon shell's doors with a landside and an
## airside toilet room beside it (ToiletTestLayout, three stalls and a sink
## each), built through the grid's own edits. Passengers with a pressing toilet
## need (half also hungry, with no cafe to go to, and most with carry-on bags)
## are spawned and the clock is stepped by hand.
##
## Plates, each taken the first tick its moment happens, the scene frozen:
##   in_use    the room with two stalls in use and a passenger walking in,
##             need icons over the passengers (game camera)
##   bags      a seated stall user's bags on the stall floor, from a steep
##             camera over the stall's back (the closed door hides them from
##             the front, as in the game)
##   strip     eight frames of a bag carrier sitting down in a stall, every
##             second tick, from that steep camera (one sheet); every bag
##             must stay inside the crop
##   strip_out the same carrier standing up and stepping out (the pick-up)
##   distance  the camera's home distance over the toilet rooms
##   ui        the Toilets tray open and the room panel over a ready toilet
## Proofs before a save: the subject point projects inside the frame with a
## margin; a walker is shown by PlateSight.person_shown (nine sight lines, the
## HUD twin). One passenger's need icons (the walker; at distance the one
## farthest from other icons) are proven by a twin with only its icons hidden:
## each icon must draw inside its own predicted rect, in the frame, with no HUD
## pixel over it; then a thought bubble is given to it and the icon row must
## draw wholly above the bubble. The bags are proven by a twin with them hidden
## and a clear sight line to each bag. The ui plate checks that the tray and
## the room panel lie inside the view and show the expected texts. Otherwise
## PROBE_INVALID, exit 1.
## A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/toilet_plates_probe.gd -- --ui-scale=1.25
##
## Plates go to tools/blender/out/toilets/.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/toilets"
const MARGIN_PX := 8.0
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews"
]
const MIN_SUBJECT_PX := 16.0
const HEAD_M := 1.6
const TICKS_PER_FRAME := 4
const LAST_TICK := 2400
const HANG_MS := 90000
const VISITORS := 14
## Ticks a seated user has sat before the bags plate, past the set-down move.
const SETTLED_TICKS := 20
const STRIP_FRAMES := 8
const STRIP_STEP_TICKS := 2
## Box searched around an overlay's anchor, in layout pixels.
const ICON_SEARCH_PX := Vector2(70.0, 70.0)
## Plate pixels an icon may draw past its predicted rect (filtering, outline).
const ICON_SLACK_PX := 3
## Height of the steep camera over the stall, and the strip's crop half size:
## room for a bag carried over the head on its way to the floor.
const STEEP_UP_M := 6.0
const STRIP_HALF_PX := Vector2i(300, 540)
const SHOTS := ["in_use", "bags", "strip", "strip_out", "distance", "ui"]

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _scale_tag := ""

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _rig: TycoonCamera
var _cam: Camera3D
var _ids := {}
var _plates := {}
var _images: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			root.content_scale_factor = float(arg.get_slice("=", 1))
	_scale_tag = "_s%.2f" % root.content_scale_factor
	print("PROBE ui_scale=%.2f out_dir=%s" % [root.content_scale_factor, _out_dir])
	_beat("boot")
	_guard.start(_watch)
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
	_beat("build")
	_ids = ToiletTestLayout.build(_mode.grid, 3, _mode.shell)
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.toilets.refresh()
	print("PROBE ids=%s usable_stalls=%d" % [_ids, _sim.toilets.layout.stalls.size()])
	if _sim.toilets.layout.stalls.size() != 6:
		_invalid("expected six usable stalls")
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff hired=%d opened tick=%d doors_close_tick=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		_finish()
		quit(1)
		return
	var last := _clock.tick + LAST_TICK
	for i in VISITORS:
		var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		var p := _sim.get_passenger(id)
		p.toilet_need = 95 if i < VISITORS / 2 else 72
		p.toilet_cooldown = 0
		p.hunger = CafeSim.HUNGER_MAX if i % 2 == 0 else 0
		p.carry_on = [2, 1, 2, 0][i % 4]
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	while _clock.tick < last and _plates.size() < SHOTS.size() - 2:
		_beat("tick %d" % _clock.tick)
		for i in TICKS_PER_FRAME:
			_clock.advance(SimClock.STEP)
			var moment := _moment()
			if not moment.is_empty():
				await _take(moment)
		await process_frame
	await _distance_plate()
	await _ui_plate()
	for shot in SHOTS:
		if not _plates.has(shot):
			_invalid("no '%s' moment happened by tick %d" % [shot, last])
	if not _images.is_empty():
		_save(_contact_sheet(_images), "contact_sheet%s.png" % _scale_tag)
	print("PROBE done tick=%d failed=%s plates=%s" % [_clock.tick, _failed, _plates])
	_finish()
	quit(1 if _failed else 0)


## [shot, passenger id] for the first plate whose moment is now, or [].
func _moment() -> Array:
	var in_use := {}
	var walking := {}
	for id in _sim.toilets.visit_ids():
		var p := _sim.get_passenger(id)
		var room: int = _sim.toilets.visit_of(id).stall["room"]
		var sat := _sim.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE:
			in_use[room] = in_use.get(room, 0) + 1
			if not _plates.has("bags") and p.carry_on > 0 and sat >= SETTLED_TICKS:
				return ["bags", id]
		if p.stage == Passenger.Stage.TOILET_WALK and p.path.size() - p.path_index <= 4:
			walking[room] = id
		if (
			not _plates.has("strip")
			and p.stage == Passenger.Stage.TOILET_SITTING_DOWN
			and p.carry_on > 0
			and sat == 0
		):
			return ["strip", id]
		if (
			not _plates.has("strip_out")
			and _plates.get("strip", 0) == id
			and p.stage == Passenger.Stage.TOILET_STANDING_UP
			and sat == PassengerSim.STAND_UP_TICKS - 6
		):
			return ["strip_out", id]
	if not _plates.has("in_use"):
		for room in in_use:
			if in_use[room] >= 2 and walking.has(room):
				return ["in_use", walking[room]]
	return []


func _take(moment: Array) -> void:
	_plates[moment[0]] = moment[1]
	match moment[0]:
		"in_use":
			await _in_use_plate(moment[1])
		"bags":
			await _bags_plate(moment[1])
		"strip":
			await _strip_plate(moment[1], "strip")
		"strip_out":
			await _strip_plate(moment[1], "strip_out")


## The stall's footprint centre, its way out and its room.
func _stall_of(id: int) -> Dictionary:
	var stall := _sim.toilets.visit_of(id).stall
	var out := SecurityLooks.world_dir(stall["front"])
	return {"centre": stall["use"] - out * ToiletLayout.USE_M, "out": out, "room": stall["room"]}


func _room_centre(room: int) -> Vector3:
	var rect: Rect2i = _mode.grid.get_room(room)["rect"]
	var a := _mode.grid.cell_to_world(rect.position)
	var b := _mode.grid.cell_to_world(rect.end - Vector2i.ONE)
	return (a + b) / 2.0


func _aim(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus * Vector3(1, 0, 1)
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	await _frames(8)


func _in_use_plate(walker: int) -> void:
	_beat("in_use")
	var room: int = _stall_of(walker)["room"]
	var focus := _room_centre(room)
	await _aim(focus + Vector3(0.0, 0.0, 1.0), 13.0, 0.3)
	_report_camera("in_use")
	var ok := _in_frame(_cam, focus, "in_use room", true)
	paused = true
	var img: Image = await PlateSight.grab(self, 4)
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	ok = _walker_shown(img, bare, walker) and ok
	var users := []
	for id in _sim.toilets.visit_ids():
		var p := _sim.get_passenger(id)
		users.append([id, Passenger.Stage.keys()[p.stage], NeedIcons.shown(p).size()])
	print("IN_USE room=%d visitors=%s" % [room, users])
	ok = await _icons_shown(img, bare, walker, "in_use") and ok
	ok = await _bubble_clear(walker, "in_use") and ok
	paused = false
	_keep(img, "in_use", ok)


func _walker_shown(img: Image, bare: Image, id: int) -> bool:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var node := _views.node_for(id)
	var holder := PlateSight.colliders(root, owners, {node: "walker"})
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get("walker", AABB())
	var seen := PlateSight.person_shown(
		_cam, box, "walker", _frame_rect(), img, bare, MIN_SUBJECT_PX
	)
	holder.free()
	print(
		(
			"VISIBLE walker=%d stage=%s px=%s height_px=%.0f on=%d blockers=%s hud_px=%s ok=%s"
			% [
				id,
				Passenger.Stage.keys()[_sim.get_passenger(id).stage],
				seen.get("px"),
				seen.get("height_px", 0.0),
				seen["on"],
				seen["blockers"],
				seen.get("hud_px"),
				seen["ok"]
			]
		)
	)
	return seen["ok"]


## The need icons of passenger `id`, proven one by one: a twin with only its
## icons hidden must differ inside each icon's own predicted rect (anchor,
## offset and ICON_PX on screen, grown by ICON_SLACK_PX), the differing box
## must lie inside that rect, and no HUD pixel may cover it.
func _icons_shown(img: Image, bare: Image, id: int, label: String) -> bool:
	var node := _views.node_for(id)
	var sprites: Array[Sprite3D] = []
	for sprite_name in NeedIcons.SPRITES:
		var sprite := node.get_node(sprite_name) as Sprite3D
		if sprite.visible:
			sprites.append(sprite)
	if sprites.is_empty():
		print("ICONS %s passenger=%d shows no icon" % [label, id])
		return false
	var rects: Array[Rect2i] = []
	for sprite in sprites:
		rects.append(_icon_rect(sprite, img))
	for sprite in sprites:
		sprite.visible = false
	var hidden: Image = await PlateSight.grab(self, 4)
	for sprite in sprites:
		sprite.visible = true
	await PlateSight.grab(self, 2)
	# The row as a whole draws inside its predicted rects: icons sit GAP_PX
	# apart, so one icon's search would reach into its neighbour.
	var row := Rect2i()
	for rect in rects:
		row = rect if not row.has_area() else row.merge(rect)
	var plate := Rect2i(Vector2i.ZERO, img.get_size())
	var row_box := PlateSight.differing_box(
		img, hidden, row.grow(ICON_SLACK_PX * 3).intersection(plate)
	)
	var ok := row_box.has_area() and row.grow(ICON_SLACK_PX).encloses(row_box)
	print("ICONS %s passenger=%d row=%s drawn_row_box=%s" % [label, id, row, row_box])
	for rect in rects:
		var drawn_box := PlateSight.differing_box(img, hidden, rect)
		var inside := drawn_box.has_area()
		var drawn := PlateSight.differing(img, hidden, rect, 1)
		var under := PlateSight.differing(img, bare, rect, 1)
		var in_frame := Rect2i(Vector2i.ZERO, img.get_size()).encloses(rect)
		print(
			(
				"ICONS %s passenger=%d rect=%s drawn_box=%s drawn_px=%d of %d inside=%s hud_px=%d"
				% [label, id, rect, drawn_box, drawn, rect.get_area(), inside, under]
			)
		)
		ok = ok and inside and in_frame and under == 0 and drawn > rect.get_area() / 3
	return ok


## Where `sprite` draws in the plate, in plate pixels: its anchor on screen
## moved by its offset (texture pixels, y up) at ICON_PX per SIZE.
func _icon_rect(sprite: Sprite3D, img: Image) -> Rect2i:
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var anchor := _cam.unproject_position(sprite.global_position) / per_screen
	var to_px := NeedIcons.ICON_PX / NeedIcons.SIZE
	var centre := anchor + Vector2(sprite.offset.x, -sprite.offset.y) * to_px
	var half := Vector2.ONE * NeedIcons.ICON_PX / 2.0
	return Rect2i(Rect2(centre - half, half * 2.0))


## The icon-bearing passenger in the frame whose icon anchor is farthest from
## every other drawn icon anchor, so its icons are judged alone; 0 for none.
func _lone_icon_passenger() -> int:
	var anchors := {}
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or not node.visible or int(node.get_meta(&"needs", 0)) == 0:
			continue
		var sprite := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
		if _cam.is_position_behind(sprite.global_position):
			continue
		var at := _cam.unproject_position(sprite.global_position)
		if _frame_rect().grow(-ICON_SEARCH_PX.x).has_point(at):
			anchors[id] = at
	var best := 0
	var best_gap := -1.0
	for id in anchors:
		var gap := INF
		for other in anchors:
			if other != id:
				gap = minf(gap, (anchors[id] as Vector2).distance_to(anchors[other]))
		if gap > best_gap:
			best = id
			best_gap = gap
	print("ICONS lone passenger=%d gap_px=%.0f of %d" % [best, best_gap, anchors.size()])
	return best


## Gives passenger `id` a thought bubble and requires its icon row to stand
## clear above it on screen: the bubble's drawn box (a twin with the bubble
## hidden) and the icons' drawn box (a twin with the icons hidden) must not
## overlap, the icons' bottom at least 1 px over the bubble's top.
func _bubble_clear(id: int, label: String) -> bool:
	var node := _views.node_for(id)
	var bubble := node.get_node("Bubble") as Label3D
	var was := bubble.text
	bubble.text = "I'm late!"
	# Laid out in the same frame the text changes, as the game's first frame
	# with a new bubble is (NeedIcons.bubble_top_m reads the label's settings).
	_views.draw()
	var img: Image = await PlateSight.grab(self, 4)
	var rects: Array[Rect2i] = []
	for sprite_name in NeedIcons.SPRITES:
		var sprite := node.get_node(sprite_name) as Sprite3D
		if sprite.visible:
			rects.append(_icon_rect(sprite, img))
	var search := Rect2i()
	for rect in rects:
		search = rect if not search.has_area() else search.merge(rect)
	search = search.grow(160).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	bubble.visible = false
	var no_bubble: Image = await PlateSight.grab(self, 4)
	bubble.visible = true
	for sprite_name in NeedIcons.SPRITES:
		(node.get_node(sprite_name) as Sprite3D).visible = false
	var no_icons: Image = await PlateSight.grab(self, 4)
	NeedIcons.show_needs(node, NeedIcons.shown(_sim.get_passenger(id)))
	var bubble_box := PlateSight.differing_box(img, no_bubble, search)
	var icon_box := PlateSight.differing_box(img, no_icons, search)
	var clear := (
		bubble_box.has_area() and icon_box.has_area() and icon_box.end.y <= bubble_box.position.y
	)
	print(
		(
			"BUBBLE %s passenger=%d bubble_box=%s icon_box=%s gap_px=%d clear=%s"
			% [label, id, bubble_box, icon_box, bubble_box.position.y - icon_box.end.y, clear]
		)
	)
	bubble.text = was
	_views.draw()
	await PlateSight.grab(self, 2)
	return clear


## A camera over the stall's back, looking steeply down past its door side.
func _steep_camera(id: int) -> Camera3D:
	var stall := _stall_of(id)
	var spot: Vector3 = stall["centre"] + stall["out"] * SecurityLooks.STALL_BAG_M
	var cam := Camera3D.new()
	cam.fov = 40.0
	_main.add_child(cam)
	cam.look_at_from_position(spot - stall["out"] * 1.0 + Vector3(0.0, STEEP_UP_M, 0.0), spot)
	cam.make_current()
	return cam


func _bags_plate(id: int) -> void:
	_beat("bags")
	var cam := _steep_camera(id)
	await _frames(6)
	var p := _sim.get_passenger(id)
	var bags: Array = _views.carry_on_props().props_of(id)["bags"]
	var stall := _stall_of(id)
	var ok := bags.size() == p.carry_on and not bags.is_empty()
	for bag: Node3D in bags:
		var rel: Vector3 = bag.global_position - stall["centre"]
		print(
			(
				"BAG passenger=%d at=%s out_m=%.3f across_m=%.3f homes=%s"
				% [
					id,
					bag.global_position,
					rel.dot(stall["out"]),
					rel.dot(stall["out"].cross(Vector3.UP)),
					SecurityLooks.bag_homes(_sim, p)
				]
			)
		)
		ok = _in_frame(cam, bag.global_position, "bag", true) and ok
	paused = true
	var img: Image = await PlateSight.grab(self, 4)
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	ok = await _bags_shown(cam, img, twin["image"], bags) and ok
	paused = false
	_keep(img, "bags", ok)
	cam.queue_free()
	_cam.make_current()


## The bags against a twin with them hidden, and one clear sight line to each.
func _bags_shown(cam: Camera3D, img: Image, bare: Image, bags: Array) -> bool:
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var subjects := {}
	for i in bags.size():
		subjects[bags[i]] = "bag%d" % i
	var holder := PlateSight.colliders(root, owners, subjects)
	await physics_frame
	await physics_frame
	var bounds: Dictionary = holder.get_meta("bounds")
	var box := AABB()
	var on := 0
	var blockers: Array[String] = []
	var space := cam.get_world_3d().direct_space_state
	for i in bags.size():
		var bag_box: AABB = bounds.get("bag%d" % i, AABB())
		box = bag_box if i == 0 else box.merge(bag_box)
		var targets: Array[Vector3] = [bag_box.get_center()]
		var lines := PlateSight.sight_lines(space, cam.global_position, targets, "bag%d" % i)
		var landed: int = (lines["on_subject"] as Array).size()
		print("BAG %d box=%s sight_on=%d blockers=%s" % [i, bag_box, landed, lines["blockers"]])
		on += 1 if landed > 0 else 0
		blockers.append_array(lines["blockers"])
	holder.free()
	for bag: Node3D in bags:
		bag.visible = false
	var hidden: Image = await PlateSight.grab(self, 4)
	for bag: Node3D in bags:
		bag.visible = true
	var at := cam.unproject_position(box.get_center())
	var search := PlateSight.to_screen(
		Rect2(at - Vector2(200, 200), Vector2(400, 400)), per_screen, img.get_size()
	)
	var changed := PlateSight.differing_box(img, hidden, search)
	var drawn := PlateSight.differing(img, hidden, changed, 1) if changed.has_area() else 0
	var under := PlateSight.differing(img, bare, changed, 1) if changed.has_area() else 0
	print(
		(
			"BAGS box=%s screen_box=%s drawn_px=%d hud_px=%d bags_seen=%d of %d blockers=%s"
			% [box, changed, drawn, under, on, bags.size(), blockers]
		)
	)
	return drawn > 0 and under == 0 and on == bags.size()


## Eight frames of the bag carrier sitting down (`label` "strip") or standing
## up and stepping out ("strip_out"), from the steep camera. Every frame must
## hold each bag's centre inside the crop.
func _strip_plate(id: int, label: String) -> void:
	_beat(label)
	var cam := _steep_camera(id)
	await _frames(6)
	var stall := _stall_of(id)
	var spot: Vector3 = stall["centre"] + stall["out"] * SecurityLooks.STALL_BAG_M
	var ok := _in_frame(cam, spot, "%s stall" % label, true)
	var crop_half := STRIP_HALF_PX
	var frames: Array[Image] = []
	for i in STRIP_FRAMES:
		var img: Image = await PlateSight.grab(self, 3)
		var at := Vector2i(
			cam.unproject_position(spot) / (root.get_visible_rect().size.y / img.get_height())
		)
		var crop := Rect2i(at - crop_half, crop_half * 2).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		frames.append(img.get_region(crop))
		var p := _sim.get_passenger(id)
		var bags: Array = _views.carry_on_props().props_of(id)["bags"]
		var bag_at := (bags[0] as Node3D).global_position if not bags.is_empty() else Vector3.ZERO
		var per := root.get_visible_rect().size.y / img.get_height()
		for bag: Node3D in bags:
			var bag_px := Vector2i(cam.unproject_position(bag.global_position) / per)
			if not crop.grow(-8).has_point(bag_px):
				ok = false
				print("STRIP frame=%d bag at %s leaves the crop %s" % [i, bag_px, crop])
		print(
			(
				"STRIP frame=%d tick=%d stage=%s body_out_m=%.3f bag_out_m=%.3f bag_y=%.3f"
				% [
					i,
					_sim.tick,
					Passenger.Stage.keys()[p.stage],
					(_views.node_for(id).global_position - stall["centre"]).dot(stall["out"]),
					(bag_at - stall["centre"]).dot(stall["out"]),
					bag_at.y
				]
			)
		)
		for t in STRIP_STEP_TICKS:
			_clock.advance(SimClock.STEP)
	var sheet := _row(frames)
	_save(sheet, "toilets_%s%s.png" % [label, _scale_tag])
	if not ok:
		_invalid("%s: the stall or a bag is out of frame" % label)
	cam.queue_free()
	_cam.make_current()


func _distance_plate() -> void:
	_beat("distance")
	_plates["distance"] = 0
	var focus := (_room_centre(_ids["air_room"]) + _room_centre(_ids["land_room"])) / 2.0
	await _aim(focus, _rig.home_distance, 0.3)
	_report_camera("distance")
	var ok := _in_frame(_cam, focus, "distance rooms", true)
	paused = true
	var img: Image = await PlateSight.grab(self, 4)
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var lone := _lone_icon_passenger()
	ok = lone != 0 and ok
	if lone != 0:
		ok = await _icons_shown(img, twin["image"], lone, "distance") and ok
		ok = await _bubble_clear(lone, "distance") and ok
	paused = false
	_keep(img, "distance", ok)


func _ui_plate() -> void:
	_beat("ui")
	_plates["ui"] = 0
	var menu := _main.find_child("BuildMenu", true, false) as BuildMenu
	var focus := _room_centre(_ids["land_room"])
	await _aim(focus, 16.0, 0.3)
	menu.press_card(BuildMode.Tool.TOILET_STALL)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_mode.update_room_focus(focus)
	await _frames(6)
	var view := root.get_visible_rect()
	var tray := menu.tray().get_global_rect()
	var panel := menu.room_panel().get_global_rect()
	var texts := []
	for label in menu.room_panel().find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var cards := []
	for tool in [
		BuildMode.Tool.TOILET_ROOM, BuildMode.Tool.TOILET_STALL, BuildMode.Tool.TOILET_SINK
	]:
		var card := menu.card(tool)
		cards.append([card.is_visible_in_tree(), view.encloses(card.get_global_rect())])
	var upkeep := "Upkeep $%d per day" % RoomRules.daily_upkeep(_mode.grid, _ids["land_room"])
	var ok := menu.is_tray_open() and view.encloses(tray) and menu.room_panel().visible
	ok = ok and view.encloses(panel) and texts.has(upkeep) and texts.has("Stalls 3")
	print(
		(
			"UI view=%s tray=%s panel=%s panel_texts=%s cards(visible,inside)=%s ok=%s"
			% [view, tray, panel, texts, cards, ok]
		)
	)
	for card in cards:
		ok = ok and card[0] and card[1]
	var img: Image = await PlateSight.grab(self, 4)
	_keep(img, "ui", ok)
	var to_px: float = img.get_height() / view.size.y
	for pair in [["ui_tray_crop", tray], ["ui_panel_crop", panel]]:
		var rect: Rect2 = pair[1]
		var crop := Rect2i(Rect2(rect.position * to_px, rect.size * to_px).grow(12.0)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		var region := img.get_region(crop)
		region.resize(crop.size.x * 2, crop.size.y * 2, Image.INTERPOLATE_NEAREST)
		_save(region, "toilets_%s%s.png" % [pair[0], _scale_tag])


func _keep(img: Image, shot: String, ok: bool) -> void:
	if ok:
		_save(img, "toilets_%s%s.png" % [shot, _scale_tag])
		_images.append(img)
	else:
		_invalid("%s: the subject is out of frame, hidden or under the HUD" % shot)
		_save(img, "toilets_%s_INVALID%s.png" % [shot, _scale_tag])


func _report_camera(shot: String) -> void:
	print(
		(
			"CAMERA %s%s pos=%s distance=%.1f pitch_deg=%.1f yaw=%.2f"
			% [
				shot,
				_scale_tag,
				_cam.global_position,
				_rig.distance,
				-_cam.rotation_degrees.x,
				_rig.yaw
			]
		)
	)


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _in_frame(cam: Camera3D, point: Vector3, label: String, report: bool) -> bool:
	var rect := _frame_rect()
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	if report:
		print(
			(
				"INFRAME %s screen=(%.0f,%.0f) frame=%s behind=%s ok=%s"
				% [label, screen.x, screen.y, rect, behind, ok]
			)
		)
	return ok


## Frames side by side in one row.
func _row(frames: Array[Image]) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var sheet := Image.create(w * frames.size(), h, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(w * i, 0))
	return sheet


## The plates in a 2-column sheet at half size.
func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var rows := ceili(plates.size() / 2.0)
	var sheet := Image.create(w * 2, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("toilet_plates_probe: main thread stalled in %s" % stage)
