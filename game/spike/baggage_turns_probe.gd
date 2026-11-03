extends SceneTree
## Windowed plate probe for how a drawn bag turns (board item baggage-
## residuals-from-b3-b4, article baggage-sim): a frame strip of a bag through
## a belt corner, one of a bag turning onto the line at a merge, and a plate of
## bags queued about one cell apart.
##
## Boots main.tscn with a new random sim seed (printed), BuildMode.starter_shell
## off, and builds the starter terminal with the HUD button, then, every cell
## moved by ReferenceTerminal.offset_on(grid), a 3 x 3 bag room at x 15..17,
## y 13..15 and belts laid with BuildMode.lay_belt in the row behind the agent
## row (decision desk-belts-run-one-row-back-desk-then-the-agent-row-then-the),
## so both desks' staff spots keep a way in: desk B (11, 11) feeds up through
## (12, 10) into a corner at (12, 9), the line runs east along y 9 to a merge
## at (15, 9) that desk A (14, 11) feeds up through (15, 10), then a corner at
## (16, 9) turns it south to an end at (16, 13); a wall east of (15, 10) keeps
## desk A's feed cell from linking to the south leg. It hires the staff, runs the
## real flights at 3x until a flight has its cutoff far enough ahead, then
## checks in BAGS_PER_DESK bags at each desk at once, so bags queue behind the
## merge.
##
## From then on the probe drives the clock itself, 1/60 s of sim time a frame
## at 1x, so every frame is a 60 fps frame. For the first desk A bag through
## the merge and the first desk B bag through the corner at (16, 9) it prints, per
## frame on that cell, the drawn heading and the sim's heading for that tick
## (what BaggageViews drew before the turn smoothing), and the largest
## frame-to-frame step of each. Every sixth frame on the cell is a strip tile,
## cropped round the cell, after checking the bag's projected bounds are inside
## the tile with a margin. Nine sight lines from the fixed strip camera to each
## subject cell (and to each queued bag's cell), against colliders PlateSight
## builds from the terminal, belts, plane and passengers, check nothing stands
## in front. A failed check prints PROBE_INVALID and exits 1. A guard thread
## calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://spike/baggage_turns_probe.gd
##
## Plates go to tools/blender/out/baggage-turns/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/baggage-turns"
const MAIN_SCENE := "res://main/main.tscn"
const ROOM := Rect2i(15, 13, 3, 3)
## Belt lines laid in order, [from, to] each.
const LINES := [
	[Vector2i(12, 10), Vector2i(12, 9)],
	[Vector2i(12, 9), Vector2i(16, 9)],
	[Vector2i(16, 9), Vector2i(16, 13)],
	[Vector2i(15, 10), Vector2i(15, 9)],
]
const DESK_A := Vector2i(14, 11)
const DESK_B := Vector2i(11, 11)
const MERGE := Vector2i(15, 9)
const CORNER := Vector2i(16, 9)
## The cells a queue forms on, behind the merge.
const QUEUE_CELLS: Array[Vector2i] = [
	Vector2i(12, 10), Vector2i(12, 9), Vector2i(13, 9), Vector2i(14, 9)
]
## How many bags on QUEUE_CELLS (two of them stopped) make the queue plate.
const QUEUE_MIN := 3
## Ticks to wait after a queue moment with a bag hidden.
const QUEUE_RETRY := 10
const SHAPES := {
	Vector2i(12, 10): &"baggage_belt",
	Vector2i(12, 9): &"baggage_belt_corner",
	Vector2i(13, 9): &"baggage_belt",
	Vector2i(14, 9): &"baggage_belt",
	Vector2i(15, 9): &"baggage_belt_feed",
	Vector2i(15, 10): &"baggage_belt",
	Vector2i(16, 9): &"baggage_belt_corner",
	Vector2i(16, 10): &"baggage_belt",
	Vector2i(16, 11): &"baggage_belt",
	Vector2i(16, 12): &"baggage_belt",
	Vector2i(16, 13): &"baggage_belt_end",
}
const BAGS_PER_DESK := 6
const PASSENGER_BASE := 900000
const FRAME_DT := 1.0 / 60.0
const TILE_EVERY := 6
## Half the side of a strip tile, in metres round the cell centre.
const TILE_HALF_M := 0.9
const TILE_PX := 240
const MARGIN_PX := 4.0
const MAX_FRAMES := 4000
const CUTOFF_AHEAD := 3000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 800000
const WAIT_LIMIT_MS := 400000
const TICK_LIMIT := 30000
## What may stand between the camera and a cell (the bags are the subjects).
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews", "StaffCharacters"
]

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _hud: PassengerHud
var _build: BuildMode
var _flights: FlightSim
var _sim: BaggageSim
var _views: BaggageViews
var _grid: BuildGrid
var _shift := Vector2i.ZERO
var _sheet: Array[Image] = []
var _queue_done := false
var _queue_next_tick := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		var total_ms := Time.get_ticks_msec()
		if idle_ms > HANG_LIMIT_MS or total_ms > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, %d ms in all"
					% [stage, idle_ms, total_ms]
				)
			)
			OS.crash("baggage turns probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	await _boot()
	var flight := ""
	if not _failed:
		flight = await _flight()
	if not _failed and flight != "":
		await _strips(flight)
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _sheet.is_empty():
		_save(_contact_sheet(), "contact_sheet", false)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _cell(at: Vector2i) -> Vector2i:
	return at + _shift


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_build = _main.get_node("BuildMode")
	_build.starter_shell = false
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	current_scene = _main
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_hud = _main.get_node("PassengerHud")
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("BaggageSim")
	_views = _main.get_node("BaggageViews")
	await _frames(5)
	_grid = _build.grid
	_shift = ReferenceTerminal.offset_on(_grid)
	print("PROBE offset=", _shift)
	_hud.dismiss_intro()
	_hud.press_starter_terminal()
	var room := RoomTool.mark(
		_grid, Rect2i(_cell(ROOM.position), ROOM.size), &"bag_room", _build.wallet()
	)
	print("BUILD bag_room ok=%s reason=%s" % [room.ok, room.reason_text()])
	if not room.ok:
		_invalid("the bag room was refused")
		return
	# A wall between desk A's feed cell and the line's south leg, so the two do
	# not link side by side and fuse into feeds.
	var wall := _grid.apply(BuildEdit.place_wall(_cell(Vector2i(15, 10)), BuildGrid.Side.EAST))
	print("BUILD wall ok=%s reason=%s" % [wall.ok, wall.reason_text()])
	if not wall.ok:
		_invalid("the wall was refused")
		return
	(_build.get_node("BuildView") as BuildView).refresh(_grid)
	_build.set_tool(BuildMode.Tool.BELT)
	for line in LINES:
		var belt := _build.lay_belt(_cell(line[0]), _cell(line[1]))
		print("BUILD belt %s..%s ok=%s reason=%s" % [line[0], line[1], belt.ok, belt.reason_text()])
		if not belt.ok:
			_build.set_tool(BuildMode.Tool.NONE)
			_invalid("the belt line was refused")
			return
	_build.set_tool(BuildMode.Tool.NONE)
	for cell in SHAPES:
		var def := StringName(_grid.get_object(_grid.object_at(_cell(cell))).get("def", ""))
		print("SHAPE %s %s" % [cell, def])
		if def != SHAPES[cell]:
			_invalid("%s took %s, expected %s" % [cell, def, SHAPES[cell]])
	await _frames(2)
	var staff := _main.get_node("Staff") as StaffSim
	for object_id in _grid.object_ids():
		match StringName(_grid.get_object(object_id)["def"]):
			&"checkin_desk":
				staff.hire(StaffMember.Role.CHECKIN)
			&"security_scanner":
				staff.hire(StaffMember.Role.SECURITY)
	print("PROBE hired=%d" % staff.member_ids().size())
	_hud.press_speed(3)


## Runs the real game until a flight's bag cutoff is CUTOFF_AHEAD ticks away.
func _flight() -> String:
	_beat("flight")
	var start_ms := Time.get_ticks_msec()
	while true:
		for id in _flights.flight_ids():
			var cutoff := _flights.doors_close_tick(id) - BaggageSim.LOAD_LEAD_TICKS
			if cutoff > _clock.tick + CUTOFF_AHEAD:
				print("PROBE flight=%s cutoff=%d tick=%d" % [id, cutoff, _clock.tick])
				return id
		if _clock.tick > TICK_LIMIT or Time.get_ticks_msec() - start_ms > WAIT_LIMIT_MS:
			_invalid(
				"no flight with its cutoff %d ticks ahead by tick %d" % [CUTOFF_AHEAD, _clock.tick]
			)
			return ""
		await process_frame
	return ""


static func _yaw(basis: Basis) -> float:
	return atan2(basis.z.x, basis.z.z)


static func _step_deg(a: float, b: float) -> float:
	return absf(rad_to_deg(wrapf(b - a, -PI, PI)))


func _strips(flight: String) -> void:
	_beat("strips")
	_hud.press_speed(1)
	_clock.process_mode = Node.PROCESS_MODE_DISABLED
	_clock.set_paused(false)
	_clock.set_speed(1)
	# The camera south of the line (toward desk rows), steep, over both cells.
	var south := (
		_grid.cell_to_world(_cell(Vector2i(0, 1))) - _grid.cell_to_world(_cell(Vector2i.ZERO))
	)
	var centre := (_grid.cell_to_world(_cell(MERGE)) + _grid.cell_to_world(_cell(CORNER))) / 2.0
	_rig.angle_step = TycoonCamera.AngleStep.TOP_DOWN
	var best_yaw := 0.0
	var best_dot := -INF
	for turn in 4:
		var yaw := wrapf(turn * PI / 2.0, -PI, PI)
		_aim(centre, 6.0, yaw)
		await _frames(30)
		var dot := (_cam.global_position - centre).normalized().dot(south.normalized())
		print("AIM yaw=%.2f cam=%s dot=%.2f" % [yaw, _cam.global_position, dot])
		if dot > best_dot:
			best_dot = dot
			best_yaw = yaw
	_aim(centre, 6.0, best_yaw)
	await _frames(90)
	print(
		(
			"AIM chosen yaw=%.2f cam=%s pitch_deg=%.1f"
			% [best_yaw, _cam.global_position, rad_to_deg(_cam.global_rotation.x)]
		)
	)
	var desk_a := _grid.object_at(_cell(DESK_A))
	var desk_b := _grid.object_at(_cell(DESK_B))
	var a_ids: Array[int] = []
	var b_ids: Array[int] = []
	for i in BAGS_PER_DESK:
		var bag_b := _sim.check_in(PASSENGER_BASE + i, flight, desk_b)
		var bag_a := _sim.check_in(PASSENGER_BASE + 100 + i, flight, desk_a)
		if bag_a == null or bag_b == null:
			_invalid("check_in refused a probe bag")
			return
		b_ids.append(bag_b.id)
		a_ids.append(bag_a.id)
	print("PROBE injected tick=%d desk_a=%s desk_b=%s" % [_clock.tick, a_ids, b_ids])
	var subjects := {
		"merge": {"id": a_ids[0], "cell": _cell(MERGE)},
		"turn": {"id": b_ids[0], "cell": _cell(CORNER)},
	}
	for kind in subjects:
		var s: Dictionary = subjects[kind]
		s["frames"] = 0
		s["tiles"] = []
		s["max_raw"] = 0.0
		s["max_drawn"] = 0.0
		s["seen"] = false
		s["left"] = false
		s["last"] = []
		s["boxes"] = []
	var all_raw := 0.0
	var all_drawn := 0.0
	var last_drawn := {}
	var last_raw := {}
	for frame in MAX_FRAMES:
		await process_frame
		_beat("strips frame %d" % frame)
		_clock.advance(FRAME_DT)
		await RenderingServer.frame_post_draw
		var img: Image = null
		# Every drawn riding bag's frame-to-frame steps.
		for bag in _sim.bags():
			var node := _views.node_for(bag.id)
			if node == null or not bag.on_belt():
				last_drawn.erase(bag.id)
				last_raw.erase(bag.id)
				continue
			var drawn := _yaw(node.transform.basis)
			var raw := _yaw(BaggageViews.belt_transform(_grid, bag).basis)
			if last_drawn.has(bag.id):
				all_drawn = maxf(all_drawn, _step_deg(last_drawn[bag.id], drawn))
				all_raw = maxf(all_raw, _step_deg(last_raw[bag.id], raw))
			last_drawn[bag.id] = drawn
			last_raw[bag.id] = raw
		for kind in subjects:
			var s: Dictionary = subjects[kind]
			if s["left"]:
				continue
			var bag := _sim.get_bag(s["id"])
			var node: Node3D = null
			if bag != null:
				node = _views.node_for(s["id"])
			var on_cell: bool = (
				node != null and bag.on_belt() and _grid.world_to_cell(node.position) == s["cell"]
			)
			if not on_cell:
				if s["seen"]:
					s["left"] = true
					print(
						(
							"HEAD_MAX %s bag=%d frames=%d before_raw_deg=%.2f after_drawn_deg=%.2f"
							% [kind, s["id"], s["frames"], s["max_raw"], s["max_drawn"]]
						)
					)
				continue
			var drawn := _yaw(node.transform.basis)
			var raw := _yaw(BaggageViews.belt_transform(_grid, bag).basis)
			var prev: Array = s["last"]
			var drawn_step := 0.0
			var raw_step := 0.0
			if not prev.is_empty():
				drawn_step = _step_deg(prev[0], drawn)
				raw_step = _step_deg(prev[1], raw)
				s["max_drawn"] = maxf(s["max_drawn"], drawn_step)
				s["max_raw"] = maxf(s["max_raw"], raw_step)
			s["last"] = [drawn, raw]
			s["seen"] = true
			print(
				(
					(
						"HEAD %s frame=%d tick=%d alpha=%.2f remain=%d from=%s"
						+ " drawn_deg=%.2f raw_deg=%.2f drawn_step=%.2f raw_step=%.2f"
					)
					% [
						kind,
						s["frames"],
						_clock.tick,
						_clock.alpha,
						bag.remain_mm,
						bag.from_step,
						rad_to_deg(drawn),
						rad_to_deg(raw),
						drawn_step,
						raw_step
					]
				)
			)
			if s["frames"] % TILE_EVERY == 0:
				if img == null:
					img = root.get_texture().get_image()
					img.convert(Image.FORMAT_RGBA8)
				var tile: Variant = _tile(kind, s, node, img)
				if tile != null:
					s["tiles"].append(tile)
			s["frames"] += 1
		if not _queue_done:
			await _queue_plate()
		if subjects["merge"]["left"] and subjects["turn"]["left"] and _queue_done:
			break
	print(
		(
			"HEAD_ALL riding_bags before_raw_max_deg=%.2f after_drawn_max_deg=%.2f"
			% [all_raw, all_drawn]
		)
	)
	for kind in subjects:
		var s: Dictionary = subjects[kind]
		if not s["left"] or (s["tiles"] as Array).size() < 3:
			_invalid("%s: the bag did not cross its cell (tiles=%d)" % [kind, s["tiles"].size()])
			continue
		_save(_strip(s["tiles"]), "%s_strip" % kind)
		# Occlusion, from the same fixed camera, to the cell the bag crossed.
		if not await _sight(kind, _grid.cell_to_world(s["cell"])):
			_invalid("%s: something stands between the camera and the cell" % kind)
	if not _queue_done:
		_invalid("queue: no moment with three bags queued behind the merge")


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


## The bag's drawn world bounds.
func _box(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for inst in node.find_children("*", "VisualInstance3D", true, false):
		var vis := inst as VisualInstance3D
		var box := vis.global_transform * vis.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## The layout-pixel rect of a tile round `cell`.
func _tile_rect(cell: Vector2i) -> Rect2:
	var c := _grid.cell_to_world(cell) + Vector3(0.0, BaggageViews.BELT_TOP, 0.0)
	var rect := Rect2(_cam.unproject_position(c), Vector2.ZERO)
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			rect = rect.expand(_cam.unproject_position(c + Vector3(dx, 0.0, dz) * TILE_HALF_M))
	return rect


## A strip tile cropped round the subject cell, or null (PROBE_INVALID) when
## the bag's projected bounds are not inside it with a margin.
func _tile(kind: String, s: Dictionary, node: Node3D, img: Image) -> Variant:
	var rect := _tile_rect(s["cell"])
	var inner := rect.grow(-MARGIN_PX)
	var box := _box(node)
	var ok := not _cam.is_position_behind(box.get_center())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var px := _cam.unproject_position(box.get_endpoint(i))
		lo = lo.min(px)
		hi = hi.max(px)
		ok = ok and inner.has_point(px)
	print(
		(
			"IN_FRAME %s tile=%d bag=%d box_px=%s..%s tile_px=%s ok=%s"
			% [kind, (s["tiles"] as Array).size(), s["id"], lo.round(), hi.round(), rect, ok]
		)
	)
	if not ok:
		_invalid("%s tile %d: the bag is not inside its tile" % [kind, s["tiles"].size()])
		return null
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var screen := PlateSight.to_screen(rect, per_screen, img.get_size())
	var out := img.get_region(screen)
	out.resize(TILE_PX, TILE_PX, Image.INTERPOLATE_BILINEAR)
	return out


func _strip(tiles: Array) -> Image:
	var gap := 4
	var out := Image.create(
		tiles.size() * (TILE_PX + gap) - gap, TILE_PX, false, Image.FORMAT_RGBA8
	)
	out.fill(Color(0.1, 0.1, 0.1))
	for i in tiles.size():
		var tile: Image = tiles[i]
		out.blit_rect(
			tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(i * (TILE_PX + gap), 0)
		)
	return out


## Nine sight lines from the strip camera to a bag-sized box at `c` (on the
## ground; no bag needs to be there: the lines land on the belt when none is,
## which still proves nothing stands between the camera and the place). True
## when every line is clear; prints the count either way.
func _sight(kind: String, c: Vector3) -> bool:
	var targets: Array[Vector3] = []
	for dx in [-0.2, 0.0, 0.2]:
		for dz in [-0.2, 0.0, 0.2]:
			targets.append(c + Vector3(dx, BaggageViews.BELT_TOP + 0.15, dz))
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, {})
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var blocked := PackedStringArray()
	var clear := 0
	for at in targets:
		var query := PhysicsRayQueryParameters3D.create(_cam.global_position, at)
		var hit := space.intersect_ray(query)
		var dist := _cam.global_position.distance_to(at)
		if hit.is_empty() or _cam.global_position.distance_to(hit["position"]) > dist - 0.25:
			clear += 1
		else:
			blocked.append(str(hit["collider"].name))
	holder.free()
	print("SIGHT %s clear=%d of %d blockers=%s" % [kind, clear, targets.size(), blocked])
	return clear == targets.size()


## When QUEUE_MIN drawn bags are on the queue cells behind the merge, one of
## them stopped: a full plate from the strip camera, each queued bag checked in
## frame, the centre-to-centre gaps and each bag's progress.
func _queue_plate() -> void:
	var queued: Array[Bag] = []
	var stopped := 0
	for bag in _sim.bags():
		var node := _views.node_for(bag.id)
		if node == null or not bag.on_belt():
			continue
		if QUEUE_CELLS.map(_cell).has(_grid.world_to_cell(node.position)):
			queued.append(bag)
			stopped += int(bag.remain_mm == 0)
	if queued.size() < QUEUE_MIN or stopped < 2 or _clock.tick < _queue_next_tick:
		return
	_beat("queue")
	# Nothing may stand in front of a queued bag (a check-in agent walks just
	# south of the line); a moment that fails is skipped for QUEUE_RETRY ticks.
	for bag in queued:
		var at := _views.node_for(bag.id).position
		if not await _sight("queue_bag_%d" % bag.id, Vector3(at.x, 0.0, at.z)):
			print("QUEUE_SKIP tick=%d bag=%d hidden" % [_clock.tick, bag.id])
			_queue_next_tick = _clock.tick + QUEUE_RETRY
			return
	_queue_done = true
	var img: Image = await PlateSight.grab(self)
	var gaps := PackedStringArray()
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var ok := true
	for bag in queued:
		var node := _views.node_for(bag.id)
		var near := INF
		for other in queued:
			if other != bag:
				near = minf(near, node.position.distance_to(_views.node_for(other.id).position))
		gaps.append("%d@%s remain=%d:%.2f" % [bag.id, bag.cell - _shift, bag.remain_mm, near])
		var box := _box(node)
		for i in 8:
			ok = ok and frame.has_point(_cam.unproject_position(box.get_endpoint(i)))
		print(
			(
				"QUEUE_IN_FRAME bag=%d px=%s ok=%s"
				% [bag.id, _cam.unproject_position(box.get_center()).round(), ok]
			)
		)
	print("QUEUE tick=%d queued=%d nearest_m=%s" % [_clock.tick, queued.size(), ", ".join(gaps)])
	if not ok:
		_invalid("queue: a queued bag is outside the frame")
	_save(img, "queue")


func _save(img: Image, name: String, sheet := true) -> void:
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		_sheet.append(img)


## Every sheet plate scaled to one width, one per row.
func _contact_sheet() -> Image:
	var w := 1440
	var rows: Array[Image] = []
	var h := 0
	for img in _sheet:
		var small := img.duplicate() as Image
		small.resize(
			w, int(img.get_height() * w / float(img.get_width())), Image.INTERPOLATE_BILINEAR
		)
		rows.append(small)
		h += small.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var y := 0
	for small in rows:
		out.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(0, y))
		y += small.get_height()
	return out
