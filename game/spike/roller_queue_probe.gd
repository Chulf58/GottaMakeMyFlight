extends SceneTree
## Windowed probe of a cafe guest with a roller standing in the counter queue
## and ordering (board 3dc86b54, decision a-guest-standing-still-in-a-queue-
## stands-the-roller-up-beside-them): the roller stood upright beside its feet,
## held by the bar, and tipped back into the pull as it walks on to its seat.
## It boots main.tscn, builds the reference terminal with a cafe
## (CafeTestLayout), opens the airport and sends GUESTS hungry passengers with
## one roller each to the cafe, so the first waits at the counter while the
## rest queue. The subject is the first guest seen in CAFE_ORDER. The clock runs
## a third of a tick a frame (60 frames a second, as in the game).
##
## Checks, each printing the values it compared (pass values are positives):
##   STOOD: STILL_TICKS + QUEUE_STAND_TICKS + 3 ticks into its order the roller's
##     shell is upright (its +z to world up at least UPRIGHT_DOT), its axle at
##     most BESIDE_M from the feet, and held (held_by >= 0); control: walking in
##     before it, its axle trailed more than TRAIL_M behind.
##   QUEUE_HIPS: the hips (the carry rig's pivot) while it stands are at least
##     HIPS_SHARE of their height standing idle just before the stand (the
##     roller still in the pull), and the stoop at most STOOP_EPS (walking hips
##     sit lower, so a walking reference hid a crouch: Opus review of 700ffaa).
##   BODY_IN_STOOD_BAG: no point of the body (its holding hand left out) is
##     inside the stood roller's meshes on any stood frame (CarryContact, as
##     drawn in this window; a headless count proves nothing).
##   PLATE lines print the roller's up and flat (axle from the feet) as well.
##   REPULLED: QUEUE_TIP_TICKS + 3 ticks after it walks on, its move is over and
##     the axle trails more than TRAIL_M behind again.
##   FLOAT: no frame from the order to the strip's end draws the bag floating
##     (spike/carry_float_check.gd).
## Plates: queue_stand (the subject stood ordering, a queueing guest behind
## it), tip_strip (a frame each tick from the last still tick, six frames, one
## camera) and a contact sheet. Before a save the feet, head and roller project
## inside the frame with a margin, at least MIN_ON of five sight lines to the
## roller land on it (PlateSight, the roller's colliders tagged) with no
## blocker, and twins with the body and with the roller hidden each differ from
## the plate. Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roller_queue_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/roller-queue/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const OUT_REL := "res://../tools/blender/out/roller-queue"
const GUESTS := 4
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_DIFF_PX := 1500
const MIN_BAG_PX := 300
## One line landing is enough with none blocked: the roller is small, and tipping
## it turns its thin side to the camera (four of five lines went past it with no
## blocker on two tip frames); the twin with the roller hidden proves it drawn.
const MIN_ON := 1
const LIMIT_TICKS := 4000
const UPRIGHT_DOT := 0.95
const BESIDE_M := 0.6
const TRAIL_M := 0.8
const HIPS_SHARE := 0.99
const STOOP_EPS := 0.01
const STRIP_FRAMES := 6
const TAG := "roller"
const NO_TAG := "nothing_has_this_tag"

var _seed := 0
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _sheet: Array[Image] = []
var _plates := 0


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		await _watch()
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	print("PROBE done plates=%d failed=%s" % [_plates, _failed])
	quit(1 if _failed or _plates < 2 else 0)


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
	return true


## GUESTS passengers with one roller each, airside, committed to the cafe.
func _guests() -> Array[Passenger]:
	var out: Array[Passenger] = []
	for attempt in 400:
		if out.size() >= GUESTS:
			break
		var p := _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		)
		if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			p.carry_on = 0
			continue
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _clock.tick
		p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
		p.clear_path()
		p.shop_cooldown = 1000000
		p.boredom = 0
		if _sim.cafes.try_visit(p):
			out.append(p)
	_clock.ticked.connect(
		func(_t: int) -> void:
			for p in out:
				p.late = false
	)
	print("GUESTS %s" % [out.map(func(p: Passenger) -> int: return p.id)])
	return out


func _watch() -> void:
	var guests := _guests()
	if guests.size() < 2:
		_invalid("only %d guests committed to the cafe" % guests.size())
		return
	var subject: Passenger = null
	var m := {
		"walk_trail": 0.0,
		"order_at": -1,
		"stood_ok": false,
		"stand_h": INF,
		"walk_h": -1.0,
		"off_at": -1,
		"repulled": -1.0,
		"floats": 0,
	}
	var stop := _clock.tick + LIMIT_TICKS
	var strip: Array[Image] = []
	while _clock.tick < stop:
		await _step()
		if subject == null:
			for p in guests:
				if p.stage == Passenger.Stage.CAFE_ORDER:
					subject = p
					m["order_at"] = _clock.tick
					print("SUBJECT id=%d ordering at tick %d" % [p.id, _clock.tick])
			for p in guests:
				if p.stage == Passenger.Stage.CAFE_WALK:
					var s := _sample(p)
					if not s.is_empty() and s["settled"]:
						m["walk_trail"] = maxf(m["walk_trail"], s["flat"])
			continue
		var s := _sample(subject)
		if s.is_empty():
			continue
		if FloatCheck.float_state(_sim, _views, subject.id, 0)[0] == "float":
			m["floats"] += 1
		var into: int = _clock.tick - m["order_at"]
		var stood_by := RollerPark.STILL_TICKS + RollerPark.QUEUE_STAND_TICKS + 3
		var bag_state := _views.carry_on_props().bag_state(subject.id, 0)
		# Standing idle before the stand, the roller still settled in the pull.
		if subject.stage == Passenger.Stage.CAFE_ORDER and s["move"] == "":
			if into >= 1 and not RollerPark.queued(bag_state):
				m["idle_h"] = maxf(m.get("idle_h", -1.0), s["hips"])
		if subject.stage == Passenger.Stage.CAFE_ORDER and into >= stood_by:
			m["stand_h"] = minf(m["stand_h"], s["hips"])
			m["stoop"] = maxf(m.get("stoop", 0.0), s["stoop"])
			m["inside"] = maxi(m.get("inside", 0), _inside(subject))
			if not m.has("stood_seen") and into >= stood_by + 2:
				m["stood_seen"] = true
				m["stood_ok"] = s["up"] >= UPRIGHT_DOT and s["flat"] <= BESIDE_M and s["held"] >= 0
				print(
					(
						(
							"STOOD tick %d (%d into the order) up %.3f (>= %.2f) "
							+ "beside %.3f m (<= %.2f) held_by %d move %s"
						)
						% [
							_clock.tick,
							into,
							s["up"],
							UPRIGHT_DOT,
							s["flat"],
							BESIDE_M,
							s["held"],
							s["move"]
						]
					)
				)
				await _plate("queue_stand", subject, true)
		if subject.stage == Passenger.Stage.CAFE_TO_SEAT and m["off_at"] < 0:
			m["off_at"] = _clock.tick
		if m["off_at"] < 0 and subject.stage == Passenger.Stage.CAFE_ORDER:
			# The last still tick's frames: the strip starts on the walk-off.
			continue
		if m["off_at"] >= 0:
			var after: int = _clock.tick - m["off_at"]
			var tried: int = m.get("tried", 0)
			if tried < STRIP_FRAMES and _clock.tick + _clock.alpha >= m["off_at"] + tried:
				# Each frame of the strip tried once, a tick apart.
				m["tried"] = tried + 1
				var img := await _plate("tip_%d" % tried, subject, false)
				if img != null:
					strip.append(img)
			if after == ceili(RollerPark.QUEUE_TIP_TICKS) + 3 and m["repulled"] < 0.0:
				m["repulled"] = s["flat"] if s["settled"] and s["up"] < 0.8 else 0.0
				print(
					(
						"REPULLED tick %d (%d after walking on) settled %s up %.3f trail %.3f m (> %.2f)"
						% [_clock.tick, after, s["settled"], s["up"], s["flat"], TRAIL_M]
					)
				)
			if after >= 8 and after < 16:
				m["walk_h"] = maxf(m["walk_h"], s["hips"])
			if after >= 16 and int(m.get("tried", 0)) >= STRIP_FRAMES:
				break
	_summary(m, strip)


## The subject's roller as drawn now: {up, flat (axle from the feet, level),
## held, settled, hips, move}; empty with no body or bag.
func _sample(p: Passenger) -> Dictionary:
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	if body == null or props.props_of(p.id).get("bags", []).is_empty():
		return {}
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var axle := node.global_transform * CarryOnProps.ROLLER_AXLE
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	var hips := -1.0
	var stoop := 0.0
	if not rig.is_empty():
		hips = (rig["pivot"] as Node3D).global_position.y - body.global_position.y
		stoop = (rig["stoop"] as CarryStoop).drawn
	return {
		"up": node.global_transform.basis.z.normalized().dot(Vector3.UP),
		"flat": Vector2(axle.x - body.global_position.x, axle.z - body.global_position.z).length(),
		"held": int(props.bag_state(p.id, 0).get("held_by", -1)),
		"settled": props.transfer_progress(p.id, 0) >= 1.0,
		"hips": hips,
		"stoop": stoop,
		"move": FloatCheck.move_of(props, p.id, 0),
	}


## The body points of `p` (its holding hand left out) inside its roller's
## meshes as drawn now (CarryContact).
func _inside(p: Passenger) -> int:
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var holder := int(props.bag_state(p.id, 0).get("held_by", -1))
	var sides: Array = [[".R", ".L"][holder]] if holder >= 0 else []
	return CarryContact.inside_meshes(CarryContact.body_points(body, sides), node)


func _summary(m: Dictionary, strip: Array[Image]) -> void:
	print(
		"CONTROL walking in, the roller's axle trailed %.3f m (> %.2f)" % [m["walk_trail"], TRAIL_M]
	)
	if m["walk_trail"] <= TRAIL_M:
		_invalid("CONTROL: no guest seen pulling its roller walking in")
	if not m["stood_ok"]:
		_invalid("STOOD failed")
	var idle: float = m.get("idle_h", -1.0)
	var share: float = m["stand_h"] / maxf(idle, 0.001)
	print(
		(
			(
				"QUEUE_HIPS lowest hips stood %.3f m, standing idle before the stand %.3f m, "
				+ "share %.3f (>= %.2f), stoop %.3f (<= %.2f); walking after %.3f m (info)"
			)
			% [m["stand_h"], idle, share, HIPS_SHARE, m.get("stoop", -1.0), STOOP_EPS, m["walk_h"]]
		)
	)
	if idle <= 0.0 or share < HIPS_SHARE or float(m.get("stoop", 1.0)) > STOOP_EPS:
		_invalid("QUEUE_HIPS the guest crouches holding its stood roller")
	print("BODY_IN_STOOD_BAG most body points inside the stood roller %d (0)" % m.get("inside", -1))
	if int(m.get("inside", -1)) != 0:
		_invalid("BODY_IN_STOOD_BAG body points inside the stood roller")
	if m["repulled"] <= TRAIL_M:
		_invalid("REPULLED failed: %.3f" % m["repulled"])
	print("FLOAT frames %d (0)" % m["floats"])
	if m["floats"] > 0:
		_invalid("FLOAT frames drawn")
	if strip.size() < STRIP_FRAMES:
		_invalid("tip strip has %d of %d frames" % [strip.size(), STRIP_FRAMES])
		return
	var w := strip[0].get_width() / 2
	var h := strip[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in strip.size():
		var small := strip[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
	_save(sheet, "tip_strip.png")
	_sheet.append(sheet)
	_plates += 1


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


## A plate of `p` and its roller from behind on the roller's side (from in front,
## the counter it faces hid it). `fresh`: the camera is placed on the subject
## now (kept for the strip after it), else
## it only turns to the body. Returns the image (saved and on the sheet when
## `fresh`), or null when the subject is not in frame or not in sight.
func _plate(shot: String, p: Passenger, fresh: bool) -> Image:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var target := (body.global_position + bag.global_position) * 0.5 + Vector3.UP * 0.6
	if fresh or _cam == null:
		var ahead := body.global_transform.basis.z
		ahead.y = 0.0
		var side := bag.global_position - body.global_position
		side.y = 0.0
		var away := (-ahead.normalized() * 0.8 + side.normalized() * 1.3).normalized()
		if _cam == null:
			_cam = Camera3D.new()
			_cam.fov = 45.0
			_main.add_child(_cam)
		_cam.look_at_from_position(target + away * 3.2 + Vector3.UP * 1.1, target, Vector3.UP)
	else:
		_cam.look_at(target, Vector3.UP)
	_cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var points := {
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
		"bag": bag.global_position,
	}
	var flat := {}
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			_invalid("%s: %s at %s is out of frame %s" % [shot, name, at, size])
			return null
	var sight := await _sight(bag)
	var now := _sample(p)
	var tall := (flat["feet"] as Vector2).distance_to(flat["head"])
	body.visible = false
	await _frames(2)
	var no_body := root.get_texture().get_image()
	body.visible = true
	bag.visible = false
	await _frames(2)
	var no_bag := root.get_texture().get_image()
	bag.visible = true
	var body_px := _diff(img, no_body)
	var bag_px := _diff(img, no_bag)
	print(
		(
			(
				"PLATE %s tick %d stage %d up %.3f flat %.3f hips %.3f inside %d at=%s "
				+ "body_px=%.0f body_diff=%d bag_diff=%d sight=%s"
			)
			% [
				shot,
				_clock.tick,
				p.stage,
				now["up"],
				now["flat"],
				now["hips"],
				_inside(p),
				flat,
				tall,
				body_px,
				bag_px,
				sight
			]
		)
	)
	var seen: bool = sight["on"] >= MIN_ON and (sight["blockers"] as Array).is_empty()
	seen = seen and sight["control_on"] == 0
	if tall < MIN_BODY_PX or body_px < MIN_DIFF_PX or bag_px < MIN_BAG_PX or not seen:
		_invalid(
			(
				"%s: body %.0f px, %d px body, %d px bag, sight %s"
				% [shot, tall, body_px, bag_px, sight]
			)
		)
		return null
	_save(img, shot + ".png")
	if fresh:
		_sheet.append(img)
		_plates += 1
	return img


## Sight lines from the camera to the roller's centre and four points round it
## (PlateSight, the roller's colliders tagged TAG, every passenger and the
## built terminal as possible blockers). Control: the same lines with a tag no
## collider has land on nothing.
func _sight(bag: Node3D) -> Dictionary:
	var owners: Array[Node] = [_views, _mode.get_node("BuildView")]
	var holder := PlateSight.colliders(root, owners, {bag: TAG})
	await physics_frame
	await physics_frame
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get(TAG, AABB())
	var targets: Array[Vector3] = [box.get_center()]
	for f in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0.3, 0), Vector3(0, -0.3, 0)]:
		targets.append(box.get_center() + _cam.global_basis * (f * box.size.length() * 0.5))
	var space := _cam.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, TAG)
	var control := PlateSight.sight_lines(space, _cam.global_position, targets, NO_TAG)
	holder.free()
	return {
		"on": (lines["on_subject"] as Array).size(),
		"blockers": lines["blockers"],
		"control_on": (control["on_subject"] as Array).size(),
	}


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
