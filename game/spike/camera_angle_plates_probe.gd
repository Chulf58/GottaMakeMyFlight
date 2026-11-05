extends SceneTree
## Windowed plate probe for the three camera angle steps (board 64cd3243,
## decision camera-angle-is-a-player-setting-fixed-while-zooming).
##
## Run (one windowed Godot run project-wide; import first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/camera_angle_plates_probe.gd
##
## Boots main.tscn on an empty grid and builds the reference terminal with its
## two cafes (CafeTestLayout) and a gate desk, hires the staff, opens the
## airport and spawns twelve hungry passengers, stepping the clock by hand. At
## the first cafe payment it stops the clock and freezes the '+$' pop, then
## plates every angle step (set on the rig directly, so the player's saved
## setting is not touched) at the closest zoom (on a passenger), a mid zoom and
## the widest zoom (on the terminal), a wall cutaway view from the landside and
## the pop over its cafe. Plates and a contact sheet go to
## tools/blender/out/camera-angle/.
##
## Each plate prints the step, pitch, tilt, distance, focus and its subject's
## screen point, and must show its subject: the focus point inside the viewport
## with a margin, the camera tilt equal to the step's pitch, and sight lines
## (PlateSight, against every visible mesh drawn: ground, terminal, roof,
## airside, planes, people) that land on the subject (passengers, the roof) or
## reach it with nothing in front (the pop). A positive control first casts rays
## through the terminal's outer walls, and at least one must be blocked, so a
## clear line is not just a world without colliders. Any failed proof prints
## PROBE_INVALID and the probe exits 1. A guard thread calls OS.crash() on a
## stall.

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/camera-angle"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const HANG_MS := 120000
## Ticks to wait for the first cafe payment, counted from the spawn.
const PAY_LIMIT_TICKS := 1500
const TICKS_PER_FRAME := 4
## Frames after placing the camera: the roof fades in 0.4 s.
const SETTLE_FRAMES := 50
const MID_DISTANCE := 40.0
const CUTAWAY_DISTANCE := 16.0
const POP_DISTANCE := 18.0
## How far the frozen pop is aged, so it is drawn part way up and faded a little.
const POP_AGE_S := 0.25
## A tag no collider carries: every first hit before the target is then a
## blocker (with "" every untagged body would count as the subject).
const NO_TAG := "no_subject"
## Passengers tried, nearest the terminal centre first, for the closest plate.
const CLOSE_TRIES := 4
## Scene nodes whose visible meshes can hide a subject.
const OCCLUDER_OWNERS: Array[String] = [
	"Ground",
	"BuildMode",
	"Airside",
	"PlaneView",
	"PlaneFleet",
	"ApronStand",
	"PassengerViews",
	"BaggageViews",
	"StaffCharacters",
	"LandsideViews",
	"RoofView",
]
const STEP_NAMES := ["low", "medium", "top_down"]
const SHEET_CELL := Vector2i(384, 216)
const SHEET_COLUMNS := 5

var _failed := false
var _main: Node3D
var _rig: TycoonCamera
var _cam: Camera3D
var _views: PassengerViews
var _grid: BuildGrid
var _out_dir := ""
var _paid := false
var _control_done := false
var _sheet: Array[Image] = []
var _last_img: Image
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	# PROBE_SEED replays a failed run's printed seed.
	if OS.has_environment("PROBE_SEED"):
		world_seed = OS.get_environment("PROBE_SEED").to_int()
	clock.seed_rng(world_seed)
	print("PROBE seed=", world_seed)
	# The probe builds its own furnished terminal: the starter shell would
	# refuse the reference terminal's first wall.
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	# Processing turns on when the clock becomes ready; only this probe steps it.
	clock.set_process(false)
	clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_grid = mode.grid
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_views = _main.get_node("PassengerViews")
	var sim := _main.get_node("PassengerSim") as PassengerSim
	_beat("build")
	CafeTestLayout.build(_grid, true)
	if not StarterFlight.add_gate_desk(_grid):
		_invalid("the gate desk was refused")
	(mode.get_node("BuildView") as BuildView).refresh(_grid)
	await _frames(4)
	sim.cafes.refresh()
	print("PROBE usable_cafes=%d" % sim.cafes.layout.cafes.size())
	sim.cafes.paid.connect(_on_paid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(sim, staff)
	var doors := StarterFlight.advance_until_open(
		clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE staff hired=%d opened tick=%d doors_close_tick=%d" % [hired, clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		_end()
		return
	for i in 12:
		var id := sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		sim.get_passenger(id).hunger = 59 if i % 2 == 0 else 45
	var last_tick := clock.tick + PAY_LIMIT_TICKS
	while clock.tick < last_tick and not _paid:
		_beat("tick %d" % clock.tick)
		for i in TICKS_PER_FRAME:
			clock.advance(SimClock.STEP)
			if _paid:
				break
		await process_frame
	if not _paid:
		_invalid("no cafe payment by tick %d" % clock.tick)
		_end()
		return
	if _main.get_node("PlaneFleet").has_method("update_views"):
		_main.get_node("PlaneFleet").call("update_views")
	print("PROBE frozen tick=%d passengers=%d" % [clock.tick, _passenger_nodes().size()])
	await _plates()
	_save(_contact_sheet(), "contact_sheet.png")
	_end()


func _plates() -> void:
	var centre := _terminal_centre()
	var pop := _views.cafe_pops().live_labels()
	var pop_at: Vector3 = pop.back().global_position if not pop.is_empty() else Vector3.ZERO
	var close_pax := _passengers_by_distance(centre)
	var landside := _cell_point(Vector2(15.5, 14.0))
	for step in 3:
		var tag: String = STEP_NAMES[step]
		var shown := false
		for at: Vector3 in close_pax.slice(0, CLOSE_TRIES):
			shown = await _plate(step, tag + "_closest", 0.0, at, _rig.min_distance, "one")
			if shown:
				break
			print("PROBE %s_closest someone stands in front; trying the next passenger" % tag)
		_sheet.append(_last_img)
		if not shown:
			_invalid("%s_closest: no passenger tried is in plain sight" % tag)
		await _plate(step, tag + "_mid", 0.0, centre, MID_DISTANCE, "pax")
		_sheet.append(_last_img)
		await _plate(step, tag + "_widest", 0.0, centre, _rig.max_distance, "roof")
		_sheet.append(_last_img)
		await _plate(step, tag + "_cutaway", 0.5, landside, CUTAWAY_DISTANCE, "pax")
		_sheet.append(_last_img)
		await _plate(step, tag + "_cafe_pop", 0.0, pop_at, POP_DISTANCE, "pop")
		_sheet.append(_last_img)


## Places the camera, proves the subject, saves the plate (kept in _last_img).
## Returns false only for kind "one" when the passenger at `focus` is hidden.
func _plate(step: int, name: String, yaw: float, focus: Vector3, dist: float, kind: String) -> bool:
	_beat(name)
	_rig.angle_step = step as TycoonCamera.AngleStep
	_rig.pan(Vector2.ZERO)
	_rig.position = Vector3(focus.x, _rig.position.y, focus.z)
	_rig.yaw = yaw
	_rig.distance = dist
	if name.ends_with("_cutaway"):
		await _frames(2)
		# Look from the landside (+z), so the near (entrance) wall is the one cut.
		if _cam.global_position.z < focus.z:
			_rig.yaw = wrapf(yaw + PI, -PI, PI)
	await _frames(SETTLE_FRAMES)
	var ground := Vector3(_rig.position.x, 0.0, _rig.position.z)
	var at := _cam.unproject_position(ground)
	var size := root.get_visible_rect().size
	var tilt := rad_to_deg(-_cam.rotation.x)
	print(
		(
			"PROBE %s step=%d pitch=%.2f tilt=%.2f yaw=%.2f distance=%.1f focus=%s eye=%s screen=%s"
			% [
				name,
				step,
				_rig.pitch_degrees(),
				tilt,
				_rig.yaw,
				_rig.distance,
				ground,
				_cam.global_position.round(),
				at.round(),
			]
		)
	)
	if not _inside(at, size):
		_invalid("%s: the focus point is outside the viewport margin" % name)
	if not is_equal_approx(tilt, TycoonCamera.STEP_PITCH_DEGREES[step]):
		_invalid("%s: the camera tilt is not the step's pitch" % name)
	var subjects := {}
	if kind == "roof":
		subjects[_main.get_node("RoofView")] = "roof"
	elif kind == "pax" or kind == "one":
		var nodes := _passenger_nodes()
		for i in nodes.size():
			subjects[nodes[i]] = "pax_%d" % i
	var holder := PlateSight.colliders(root, _owners(), subjects)
	await physics_frame
	await physics_frame
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		_invalid("%s: unbaked skinned meshes %s" % [name, unbaked])
	var space := _cam.get_world_3d().direct_space_state
	if not _control_done:
		_control_done = true
		_control(space)
	var ok := true
	match kind:
		"pax", "one":
			ok = _check_people(space, holder, name, size, focus, kind == "one")
		"roof":
			_check_roof(space, holder, name, size)
		"pop":
			_check_pop(space, name, focus, size)
	holder.queue_free()
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_last_img = img
	_save(img, "angle_%s.png" % name)
	return ok


## Rays through the terminal's outer walls at chest height, from outside to
## inside. The near walls may be cut by the cutaway, the far ones are not, so
## at least one must be blocked.
func _control(space: PhysicsDirectSpaceState3D) -> void:
	var lo := Vector2(ReferenceTerminal.FLOOR_MIN)
	var hi := Vector2(ReferenceTerminal.FLOOR_MAX) + Vector2.ONE
	var rays: Array = [
		["west", Vector2(lo.x - 3.0, 5.5), Vector2(lo.x + 2.0, 5.5)],
		["west", Vector2(lo.x - 3.0, 13.5), Vector2(lo.x + 2.0, 13.5)],
		["north", Vector2(13.5, lo.y - 3.0), Vector2(13.5, lo.y + 2.0)],
		["south", Vector2(12.5, hi.y + 3.0), Vector2(12.5, hi.y - 2.0)],
	]
	var blocked := 0
	for ray in rays:
		var from := _cell_point(ray[1]) + Vector3.UP * 1.5
		var to := _cell_point(ray[2]) + Vector3.UP * 1.5
		var targets: Array[Vector3] = [to]
		var lines := PlateSight.sight_lines(space, from, targets, NO_TAG)
		var blockers: Array[String] = lines["blockers"]
		if not blockers.is_empty():
			blocked += 1
		print(
			(
				"PROBE control wall=%s from=%s to=%s %s by=%s"
				% [ray[0], from, to, "blocked" if not blockers.is_empty() else "clear", blockers]
			)
		)
	print("PROBE control blocked=%d of %d" % [blocked, rays.size()])
	if blocked == 0:
		_invalid(
			"control: no ray through a terminal wall was blocked, so a clear line proves nothing"
		)


## Passengers shown: centre in frame and at least one of three lines lands on
## the passenger's own meshes with nothing in front. With `need` set (the
## closest zoom), returns whether the passenger standing at `must` is one of
## them; otherwise true.
func _check_people(
	space: PhysicsDirectSpaceState3D,
	holder: Node3D,
	name: String,
	size: Vector2,
	must: Vector3,
	need: bool,
) -> bool:
	var bounds: Dictionary = holder.get_meta("bounds")
	var shown := 0
	var in_frame := 0
	var blocked := 0
	var must_shown := not need
	for tag in bounds:
		var box: AABB = bounds[tag]
		var centre := box.get_center()
		if _cam.is_position_behind(centre) or not _inside(_cam.unproject_position(centre), size):
			continue
		in_frame += 1
		var targets: Array[Vector3] = []
		for k in [0.3, 0.5, 0.75]:
			targets.append(Vector3(centre.x, box.position.y + box.size.y * k, centre.z))
		var lines := PlateSight.sight_lines(space, _cam.global_position, targets, tag)
		var on: Array[Vector3] = lines["on_subject"]
		var blockers: Array[String] = lines["blockers"]
		if not blockers.is_empty():
			blocked += 1
		if on.size() >= 1 and blockers.is_empty():
			shown += 1
			if need and Vector2(centre.x, centre.z).distance_to(Vector2(must.x, must.z)) < 0.6:
				must_shown = true
				print("PROBE %s subject %s at %s screen=%s" % [name, tag, centre, _px(centre)])
		elif need and Vector2(centre.x, centre.z).distance_to(Vector2(must.x, must.z)) < 0.6:
			print("PROBE %s subject %s hidden by %s" % [name, tag, blockers])
	print(
		(
			"PROBE %s people drawn=%d in_frame=%d shown=%d partly_blocked=%d"
			% [name, bounds.size(), in_frame, shown, blocked]
		)
	)
	if shown == 0:
		_invalid("%s: no passenger in frame is in plain sight" % name)
	return must_shown


func _check_roof(
	space: PhysicsDirectSpaceState3D, holder: Node3D, name: String, size: Vector2
) -> void:
	var bounds: Dictionary = holder.get_meta("bounds")
	if not bounds.has("roof"):
		_invalid("%s: no roof drawn" % name)
		return
	var box: AABB = bounds["roof"]
	var targets: Array[Vector3] = []
	for fx in [0.25, 0.5, 0.75]:
		for fz in [0.25, 0.75]:
			targets.append(box.position + box.size * Vector3(fx, 0.5, fz))
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, "roof")
	var on: Array[Vector3] = lines["on_subject"]
	var corners_in := 0
	for i in 8:
		var corner := box.get_endpoint(i)
		if not _cam.is_position_behind(corner) and _inside(_cam.unproject_position(corner), size):
			corners_in += 1
	print(
		(
			"PROBE %s roof box=%s screen=%s corners_in_frame=%d/8 on=%d past=%d blockers=%s"
			% [
				name,
				box,
				_px(box.get_center()),
				corners_in,
				on.size(),
				lines["past"],
				lines["blockers"]
			]
		)
	)
	if on.size() < 3 or corners_in < 8:
		_invalid("%s: the roof is not wholly in frame and in plain sight" % name)


## The pop has no mesh and ignores depth: it must be live, in frame, and a line
## to it must meet nothing in front.
func _check_pop(space: PhysicsDirectSpaceState3D, name: String, at: Vector3, size: Vector2) -> void:
	var live := _views.cafe_pops().live_labels()
	if live.is_empty() or at == Vector3.ZERO:
		_invalid("%s: no live pop" % name)
		return
	var label := live.back() as Label3D
	var point := label.global_position
	var screen := _cam.unproject_position(point)
	var targets: Array[Vector3] = [point]
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, NO_TAG)
	var blockers: Array[String] = lines["blockers"]
	print(
		(
			"PROBE %s pop text=%s at=%s screen=%s alpha=%.2f visible=%s blockers=%s"
			% [name, label.text, point, screen.round(), label.modulate.a, label.visible, blockers]
		)
	)
	if not label.visible or _cam.is_position_behind(point) or not _inside(screen, size):
		_invalid("%s: the pop is not in frame" % name)
	if not blockers.is_empty():
		_invalid("%s: a mesh stands in front of the pop" % name)
	_check_pop_clear(name, label)
	_check_labels_clear(name)


## Every room label on screen draws on its cream card, and no need icon covers
## the card unless the label had no clear spot in reach (decision room-labels-
## sit-on-a-cream-card-and-slide-clear-of-need-icons, and room-label-card-and-
## cafe-pop-clearance-as-built, which accepts the HUD-only slide as the
## fallback). An icon's or wish bubble's drawn box overlapping the card fails
## the plate when _had_clear_spot() finds a spot the label did not take. Icons
## within 200 px of a card count as near, the control that the labels stand in a
## crowd. Each label prints which case applied: clear, fallback_used or
## missed_spot.
func _check_labels_clear(name: String) -> void:
	var rooms := _main.get_node("BuildMode/RoomView")
	var unit := _unit()
	var icons: Array[Rect2] = []
	for entry in _overhead_boxes(false):
		icons.append(entry[1])
	var size := root.get_visible_rect().size
	var cards := 0
	var near := 0
	var card_boxes := {}
	for child in rooms.get_children():
		var other := child as Label3D
		if other == null or not other.visible:
			continue
		var other_card := other.get_node_or_null(RoomLabelLayout.CARD) as Sprite3D
		if other_card != null:
			card_boxes[other] = RoomLabelLayout.sprite_rect(other_card, _cam, unit)
	for child in rooms.get_children():
		var label := child as Label3D
		if label == null or not label.visible:
			continue
		var card := label.get_node_or_null(RoomLabelLayout.CARD) as Sprite3D
		if card == null:
			_invalid("%s: room label '%s' has no card" % [name, label.text])
			continue
		var box := RoomLabelLayout.sprite_rect(card, _cam, unit)
		if not Rect2(Vector2.ZERO, size).encloses(box):
			continue
		cards += 1
		var covered: Array[String] = []
		for icon in icons:
			if icon.get_center().distance_to(box.get_center()) < 200.0:
				near += 1
			if box.intersects(icon):
				covered.append(str(Rect2(icon.position.round(), icon.size.round())))
		var verdict := "clear"
		if not covered.is_empty():
			verdict = (
				"fallback_used" if not _had_clear_spot(label, box, card_boxes) else "missed_spot"
			)
		print(
			(
				"PROBE %s label '%s' card=%s offset=%s covered=%s case=%s"
				% [
					name,
					label.text.replace("\n", " "),
					Rect2(box.position.round(), box.size.round()),
					label.offset.round(),
					covered,
					verdict
				]
			)
		)
		if verdict == "missed_spot":
			_invalid(
				"%s: need icons cover room label '%s' that had a clear spot" % [name, label.text]
			)
	print("PROBE %s room cards in frame=%d icons near=%d" % [name, cards, near])
	if cards == 0 or near == 0:
		_invalid("%s: no room card in frame among icons, so the label check proves nothing" % name)


## Whether `label`, whose card now fills `box` (viewport pixels), had a spot clear
## of the HUD, the need icons and the other labels' cards within its nudge reach:
## the same search RoomLabelLayout runs (slide_clear() over nudge_reach()), from
## the card's anchored place (its box less the nudge the layout stored on it).
## Every other card counts as a blocker, a superset of the cards the layout had
## placed before this one, so the probe never finds a spot the layout could not.
func _had_clear_spot(label: Label3D, box: Rect2, card_boxes: Dictionary) -> bool:
	var out := root.get_stretch_transform().get_scale().y
	var anchored := Rect2(
		box.position * out - label.get_meta(&"nudge", Vector2.ZERO), box.size * out
	)
	var blockers := HudRects.collect(_main.get_node("BuildMode/RoomView"), out)
	blockers.append_array(RoomLabelLayout.icon_rects(_views, _cam, out))
	for other: Label3D in card_boxes:
		if other != label:
			var rect: Rect2 = card_boxes[other]
			blockers.append(Rect2(rect.position * out, rect.size * out))
	var spot := RoomLabelLayout.slide_clear(
		anchored,
		blockers,
		root.get_visible_rect().size * out,
		RoomLabelLayout.nudge_reach(anchored.size.y)
	)
	return spot.size != Vector2.ZERO


## The pop must cover no passenger's head and no need icon (board a48bca8d).
## The pops are frozen, so the probe lays them out for this view itself. Each
## head (the band from a seated chin to a standing crown, 0.6 m wide) and each
## icon and wish bubble at its drawn size is projected here; each within 150 px
## of the pop counts as near, as a control that the spot is crowded, and each
## overlapping the pop's box fails the plate.
func _check_pop_clear(name: String, label: Label3D) -> void:
	var pops := _views.cafe_pops()
	pops.lay_out(_cam)
	var slot: int = label.get_meta(&"slot")
	var box := pops.screen_rect(label, _cam, slot).grow(-CafePops.CLEAR_PX)
	var near := 0
	var covered: Array[String] = []
	for entry in _overhead_boxes(true):
		var rect: Rect2 = entry[1]
		if rect.get_center().distance_to(box.get_center()) < 150.0:
			near += 1
		if box.intersects(rect):
			covered.append("%s@%s" % [entry[0], Rect2(rect.position.round(), rect.size.round())])
	print(
		(
			"PROBE %s pop slot=%d box=%s near=%d covered=%s"
			% [name, slot, Rect2(box.position.round(), box.size.round()), near, covered]
		)
	)
	if near == 0:
		_invalid("%s: no head or icon near the pop, so the clearance check proves nothing" % name)
	if not covered.is_empty():
		_invalid("%s: the pop covers %s" % [name, covered])


## Viewport pixels per metre at one metre from the camera, inverted.
func _unit() -> float:
	return 2.0 * tan(deg_to_rad(_cam.fov) / 2.0) / root.get_visible_rect().size.y


## [kind, drawn box in viewport pixels] for every shown need icon and wish
## bubble over a drawn passenger, at its real size (texture size times pixel
## size, per metre of depth unless fixed size) and offset, and with `heads`
## every passenger's head band too.
func _overhead_boxes(heads: bool) -> Array:
	var unit := _unit()
	var boxes := []
	for node in _passenger_nodes():
		var depth := (node.global_position - _cam.global_position).dot(-_cam.global_basis.z)
		if depth <= _cam.near:
			continue
		if heads:
			var crown := _cam.unproject_position(node.global_position + Vector3(0.0, 1.85, 0.0))
			var chin := _cam.unproject_position(node.global_position + Vector3(0.0, 0.9, 0.0))
			var half := 0.3 / (depth * unit)
			var head := Rect2(crown, Vector2.ZERO).expand(chin)
			boxes.append(["head_%s" % node.name, head.grow_individual(half, 0.0, half, 0.0)])
		for sprite_name: String in NeedIcons.SPRITES + [WishIconView.SPRITE]:
			var sprite := node.get_node_or_null(sprite_name) as Sprite3D
			if (
				sprite == null
				or not sprite.visible
				or sprite.texture == null
				or sprite.modulate.a <= 0.0
			):
				continue
			var at := sprite.global_position
			var d := (at - _cam.global_position).dot(-_cam.global_basis.z)
			if d <= _cam.near:
				continue
			var scale := sprite.pixel_size / ((1.0 if sprite.fixed_size else d) * unit)
			var size := sprite.texture.get_size() * scale
			var centre := (
				_cam.unproject_position(at) + Vector2(sprite.offset.x, -sprite.offset.y) * scale
			)
			boxes.append(["%s_%s" % [sprite_name, node.name], Rect2(centre - size / 2.0, size)])
	return boxes


func _on_paid(id: int, room: int, amount: int) -> void:
	if _paid:
		return
	_paid = true
	# Freeze the pop part way through its rise, so every angle plates the same one.
	var pops := _views.cafe_pops()
	pops.set_process(false)
	pops.advance(POP_AGE_S)
	print(
		"PROBE paid passenger=%d room=%d amount=%d pops=%d" % [id, room, amount, pops.live_count()]
	)


func _owners() -> Array[Node]:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		var node := _main.get_node_or_null(path)
		if node == null:
			_invalid("occluder owner %s is missing from main.tscn" % path)
			continue
		owners.append(node)
	return owners


func _passenger_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for child in _views.get_children():
		if child is Node3D and child.has_meta(&"body") and (child as Node3D).visible:
			nodes.append(child)
	return nodes


## Drawn passengers' positions, nearest `to` first.
func _passengers_by_distance(to: Vector3) -> Array[Vector3]:
	var at: Array[Vector3] = []
	for node in _passenger_nodes():
		at.append(node.global_position)
	at.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return a.distance_to(to) < b.distance_to(to)
	)
	print("PROBE closest_subject candidates=%s" % [at.slice(0, CLOSE_TRIES)])
	return at


func _terminal_centre() -> Vector3:
	var lo := Vector2(ReferenceTerminal.FLOOR_MIN)
	var hi := Vector2(ReferenceTerminal.FLOOR_MAX) + Vector2.ONE
	return _cell_point((lo + hi) * 0.5)


## A world point on the ground at a reference-terminal cell coordinate (cell
## units, so 10.0 is the west edge of cell 10), moved by the grid's offset.
func _cell_point(at: Vector2) -> Vector3:
	var off := Vector2(ReferenceTerminal.offset_on(_grid))
	var corner := _grid.cell_to_world(Vector2i.ZERO) - Vector3(0.5, 0.0, 0.5)
	return corner + Vector3(at.x + off.x, 0.0, at.y + off.y)


func _inside(at: Vector2, size: Vector2) -> bool:
	return (
		at.x > MARGIN_PX
		and at.y > MARGIN_PX
		and at.x < size.x - MARGIN_PX
		and at.y < size.y - MARGIN_PX
	)


func _px(point: Vector3) -> Vector2:
	return _cam.unproject_position(point).round()


func _contact_sheet() -> Image:
	var rows := ceili(_sheet.size() / float(SHEET_COLUMNS))
	var sheet := Image.create(
		SHEET_CELL.x * SHEET_COLUMNS, SHEET_CELL.y * rows, false, Image.FORMAT_RGBA8
	)
	for i in _sheet.size():
		var cell := _sheet[i].duplicate() as Image
		cell.resize(SHEET_CELL.x, SHEET_CELL.y, Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(i % SHEET_COLUMNS, floori(i / float(SHEET_COLUMNS))) * SHEET_CELL
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, SHEET_CELL), at)
	return sheet


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	img.save_png(path)
	print("PROBE plate ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _end() -> void:
	print("PROBE done failed=%s" % _failed)
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	quit(1 if _failed else 0)


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


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
			OS.crash("camera_angle_plates_probe: main thread stalled in %s" % stage)
