extends SceneTree
## Probe of a cafe guest's pulled roller passing the cafe chairs as it walks
## away from its table (board 2fcb8475 part 1): PullSide's walking-pull
## furniture guard is to keep the roller out of every chair. It boots
## main.tscn, builds the reference terminal with a cafe (CafeTestLayout), opens
## the airport and sends one passenger with one roller to the cafe, as
## cafe_roller_standup_probe does. The clock is stepped fast to the stand-up,
## then a third of a tick a frame (60 frames a second, as in the game) for
## WALK_TICKS after the pick-up.
##
## Checks (pass values are positives, each printing the values it compared):
##   IN_CHAIR: from the pick-up, no point of the pulled roller's box (corners,
##     face centres, centre) is inside the box of any cafe chair (the bounds of
##     a cafe_table mesh's vertices more than CHAIR_FROM_M out of its middle,
##     in the piece's frame). Controls: each chair box holds its own centre and
##     has vertices; the guest walks more than WALK_M from where it stood up.
##   Each tick it also prints the hand, PullSide's tallies and whether the
##   pulling side's footprint meets furniture where the guest is.
## Plates (windowed only): walk_near (the frame the roller is nearest a chair,
## or deepest in one), framed close on the roller and that chair, and a
## contact sheet with walk_start and walk_on. Before a save the roller, the
## chair and the guest's feet project inside the frame with a margin, and a
## twin with the roller hidden differs from the plate (in frame is not
## visible). Otherwise PROBE_INVALID, exit 1.
##
## Run (headless prints numbers only; windowed needs the one windowed slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cafe_chair_pull_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/cafe-chair-pull/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/cafe-chair-pull"
const LIMIT_TICKS := 6000
const LEAD_TICKS := 4
const WALK_TICKS := 70
const WALK_M := 1.0
const CHAIR_FROM_M := 0.55
const MARGIN_PX := 8.0
const MIN_BAG_PX := 300
## Ticks after the pick-up of the walk past the chair (the cafe_walk plate's tick).
const NEAR_SINCE := 48

var _seed := 0
var _out_dir := ""
var _failed := false
var _windowed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
## [piece frame (world), chair box (piece frame)] for every cafe chair.
var _chairs: Array = []
var _sheet: Array[Image] = []
## Each roller mesh's triangle vertices, read once.
var _faces := {}


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_windowed = DisplayServer.get_name() != "headless"
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d windowed=%s out_dir=%s" % [_seed, _windowed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		await _watch()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
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
	var ids := CafeTestLayout.build(_mode.grid)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the gate desk was refused")
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.cafes.refresh()
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE ids=%s hired=%d opened tick=%d" % [ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_chairs = _chair_boxes()
	return not _chairs.is_empty()


## Every cafe chair as [piece frame, box in the piece frame].
func _chair_boxes() -> Array:
	var out := []
	var scene := (load("res://assets/interior/cafe_table.glb") as PackedScene).instantiate()
	var boxes := [AABB(), AABB()]
	var counts := [0, 0]
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for v in mi.mesh.get_faces():
			var at := xf * v
			if absf(at.x) < CHAIR_FROM_M:
				continue
			var k := 0 if at.x < 0.0 else 1
			boxes[k] = AABB(at, Vector3.ZERO) if counts[k] == 0 else (boxes[k] as AABB).expand(at)
			counts[k] += 1
	scene.free()
	for id in _mode.grid.object_ids():
		var record := _mode.grid.get_object(id)
		if record.is_empty() or record["def"] != &"cafe_table":
			continue
		var def := BuildCatalog.get_def(record["def"])
		var cells := def.footprint(record["anchor"], record["facing"])
		var frame := BuildView.object_transform(_mode.grid, cells, record["facing"])
		for k in 2:
			out.append([frame, boxes[k]])
			var inside := (boxes[k] as AABB).has_point((boxes[k] as AABB).get_center())
			print(
				(
					"CHAIRBOX table %d chair %d vertices=%d box %s centre_inside=%s world %s"
					% [id, k, counts[k], boxes[k], inside, frame * (boxes[k] as AABB).get_center()]
				)
			)
			if counts[k] == 0 or not inside:
				_invalid("chair box %d of table %d is empty" % [k, id])
				return []
	return out


func _visitor() -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		p = _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	p.shop_cooldown = 0
	p.boredom = 0
	_sim.cafes.try_visit(p)
	print("VISITOR id=%d cafe=%s" % [p.id, _sim.cafes.visit_of(p.id) != null])
	if _sim.cafes.visit_of(p.id) == null:
		_invalid("passenger %d did not commit to the cafe" % p.id)
		return null
	return p


func _watch() -> void:
	var p := _visitor()
	if p == null:
		return
	var until := _clock.tick + LIMIT_TICKS
	while _clock.tick < until:
		if p.stage == Passenger.Stage.CAFE_SEATED:
			if _sim.cafes.visit_of(p.id).dwell_end - _clock.tick <= LEAD_TICKS:
				break
		_clock.advance(SimClock.STEP)
		if _clock.tick % 10 == 0:
			await process_frame
	if p.stage != Passenger.Stage.CAFE_SEATED:
		_invalid("never seated (stage %d)" % p.stage)
		return
	var seat: Dictionary = _sim.cafes.visit_of(p.id).seat
	print("PROBE seated at %s tick %d" % [seat["cell"], _clock.tick])
	var m := {"pick": -1, "from": Vector3.INF, "walked": 0.0, "inside": 0, "deep": 0.0}
	m["near"] = INF
	var last_tick := -1
	var shots := {}
	while _clock.tick < until:
		await _step()
		var body := _views.node_for(p.id)
		if body == null:
			break
		var props := _views.carry_on_props()
		var bags: Array = props.props_of(p.id).get("bags", [])
		if bags.is_empty():
			continue
		var bag: Node3D = bags[0]
		var home: SecurityLooks.Home = (
			SecurityLooks.bag_homes(_sim, p)[0] if p.carry_on > 0 else SecurityLooks.Home.FLOOR
		)
		if m["pick"] < 0:
			if home != SecurityLooks.Home.HAND or p.stage == Passenger.Stage.CAFE_SEATED:
				continue
			m["pick"] = _clock.tick
			m["from"] = body.global_position
			print("PICK tick %d at %s" % [_clock.tick, body.global_position])
		if _clock.tick > m["pick"] + WALK_TICKS:
			break
		m["walked"] = maxf(m["walked"], body.global_position.distance_to(m["from"]))
		var hit := _deepest(bag)
		var state := props.bag_state(p.id, 0)
		if hit[0] > 0.0:
			m["inside"] += 1
			if m["inside"] == 1:
				m["first_in"] = _clock.tick
				shots["walk_near"] = hit[1]
			if hit[0] > m["deep"]:
				m["deep"] = hit[0]
				m["deep_tick"] = _clock.tick
				m["deep_part"] = hit[3]
		elif m["deep"] <= 0.0 and hit[2] < m["near"]:
			m["near"] = hit[2]
			shots["walk_near"] = hit[1]
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			_log(p, body, state, hit)
		if _windowed:
			await _maybe_plate(p, body, bag, m, shots)
	print(
		(
			"IN_CHAIR frames=%d first tick %s deepest=%.3f m (%s) at tick %s nearest_outside=%.3f m"
			% [
				m["inside"],
				m.get("first_in", -1),
				m["deep"],
				m.get("deep_part", ""),
				m.get("deep_tick", -1),
				m["near"]
			]
		)
	)
	print("WALKED %.3f m from the pick-up (control > %.2f)" % [m["walked"], WALK_M])
	if m["pick"] < 0:
		_invalid("the roller was never picked up")
	elif m["walked"] <= WALK_M:
		_invalid("the guest did not walk away (%.3f m)" % m["walked"])
	if m["inside"] > 0:
		print("FAIL IN_CHAIR the roller went into a cafe chair on %d frames" % m["inside"])
		_failed = true
	else:
		print("PASS IN_CHAIR")
	if _windowed and not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")


## Prints this tick's hand and PullSide's view of the pulling side.
func _log(p: Passenger, body: Node3D, state: Dictionary, hit: Array) -> void:
	var hand := CarryLead.hand_of(int(state.get("place", 0)))
	var frame := Transform3D(body.global_transform.basis.orthonormalized(), body.global_position)
	var reach := PullSide.blocked(_sim.grid, [frame], PullSide.footprint(hand, true), true)
	var other := PullSide.blocked(_sim.grid, [frame], PullSide.footprint(1 - hand, false), true)
	var tallies := []
	for key in ["pull_side_swaps", "pull_side_both", "pull_side_returns", "pull_side_queue"]:
		tallies.append(int(state.get(key, 0)))
	print(
		(
			(
				"TICK %d stage %d cell %s yaw %.0f hand %d tuck %.2f pull_reach_hit %s"
				+ " other_hit %s tallies %s chair_depth %.3f near %.3f"
			)
			% [
				_clock.tick,
				p.stage,
				p.at,
				rad_to_deg(body.global_rotation.y),
				hand,
				RollerPull.tuck_weight(state, _clock.tick),
				reach,
				other,
				tallies,
				hit[0],
				hit[2]
			]
		)
	)


## [depth inside the deepest chair (0 when outside all), that chair's world
## centre, distance of the nearest vertex outside, the part (mesh node) deepest
## in] of the roller `bag` as drawn: every vertex of every mesh under it, the
## rods stretched to the hand as well as the bag.
func _deepest(bag: Node3D) -> Array:
	var deep := 0.0
	var near := INF
	var at := Vector3.ZERO
	var part := ""
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var faces: PackedVector3Array = _faces.get(mi.mesh, PackedVector3Array())
		if faces.is_empty():
			faces = mi.mesh.get_faces()
			_faces[mi.mesh] = faces
		var xf := mi.global_transform
		for chair: Array in _chairs:
			var to_piece := (chair[0] as Transform3D).affine_inverse() * xf
			var box: AABB = chair[1]
			for v in faces:
				var d := _signed(box, to_piece * v)
				if d <= 0.0 and -d > deep:
					deep = -d
					at = (chair[0] as Transform3D) * box.get_center()
					part = mi.name
				elif d > 0.0 and d < near:
					near = d
					if deep <= 0.0:
						at = (chair[0] as Transform3D) * box.get_center()
	return [deep, at, near, part]


static func _signed(box: AABB, point: Vector3) -> float:
	var out := Vector3(
		maxf(box.position.x - point.x, point.x - box.end.x),
		maxf(box.position.y - point.y, point.y - box.end.y),
		maxf(box.position.z - point.z, point.z - box.end.z)
	)
	if out.x > 0.0 or out.y > 0.0 or out.z > 0.0:
		return Vector3(maxf(out.x, 0.0), maxf(out.y, 0.0), maxf(out.z, 0.0)).length()
	return maxf(out.x, maxf(out.y, out.z))


## Plates walk_start (2 ticks after the pick-up), walk_on (30 ticks after),
## and walk_near (from beside) and walk_top (from above) on the first frame the
## roller is in a chair, or NEAR_SINCE ticks after the pick-up (the walk past
## the chair, cafe_roller_standup_probe's cafe_walk) when it never is.
func _maybe_plate(
	p: Passenger, body: Node3D, bag: Node3D, m: Dictionary, shots: Dictionary
) -> void:
	var since: int = _clock.tick - m["pick"]
	if since == 2 and not shots.has("walk_start_done"):
		shots["walk_start_done"] = true
		await _plate("walk_start", p, body, bag, bag.global_position, false)
	if since == 30 and not shots.has("walk_on_done"):
		shots["walk_on_done"] = true
		await _plate("walk_on", p, body, bag, bag.global_position, false)
	var chair: Vector3 = shots.get("walk_near", Vector3.INF)
	var first: bool = m.get("first_in", -1) == _clock.tick
	var past: bool = m["inside"] == 0 and since == NEAR_SINCE
	if chair != Vector3.INF and (first or past) and not shots.has("near_done"):
		shots["near_done"] = true
		await _plate("walk_near", p, body, bag, chair, false)
		await _plate("walk_top", p, body, bag, chair, true)


## A plate of the guest, its roller and the chair at `chair`: from beside, on
## the roller's side, or with `top` straight down from above.
func _plate(
	shot: String, p: Passenger, body: Node3D, bag: Node3D, chair: Vector3, top: bool
) -> void:
	var target := (bag.global_position + chair) * 0.5 + Vector3.UP * 0.4
	var side := bag.global_position - body.global_position
	side.y = 0.0
	var away := (side.normalized() + Vector3(0.3, 0.0, 0.3)).normalized()
	var cam := Camera3D.new()
	cam.fov = 45.0
	_main.add_child(cam)
	if top:
		var mid := (bag.global_position + chair + body.global_position) / 3.0
		cam.look_at_from_position(mid + Vector3.UP * 4.0, mid, Vector3.FORWARD)
	else:
		cam.look_at_from_position(target + away * 2.2 + Vector3.UP * 1.6, target, Vector3.UP)
	cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var points := {"feet": body.global_position, "bag": bag.global_position, "chair": chair}
	var flat := {}
	for name: String in points:
		var at: Vector2 = cam.unproject_position(points[name])
		flat[name] = at
		if cam.is_position_behind(points[name]) or not inside.has_point(at):
			_invalid("%s: %s at %s is out of frame %s" % [shot, name, at, size])
			cam.queue_free()
			return
	bag.visible = false
	await _frames(2)
	var no_bag := root.get_texture().get_image()
	bag.visible = true
	var bag_px := _diff(img, no_bag)
	cam.queue_free()
	print(
		"PLATE %s tick %d stage %d at=%s bag_diff=%d" % [shot, _clock.tick, p.stage, flat, bag_px]
	)
	if bag_px < MIN_BAG_PX:
		_invalid("%s: %d px from the roller" % [shot, bag_px])
		return
	_save(img, shot + ".png")
	_sheet.append(img)


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * plates.size(), h, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	# Headless draws no frame, so frame_post_draw never comes.
	if _windowed:
		await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
