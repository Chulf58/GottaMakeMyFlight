extends SceneTree
## Windowed probe of the roller queue stand at the gate and in a boarding file
## (board 44b974cc): a guest standing at the gate for want of a seat (STANDING)
## and a walker waiting in a boarding file each stand the roller upright beside
## them, held by the bar, and tip it back into the pull when they walk on.
## It boots main.tscn, builds the reference terminal with its gate desk, takes
## every gate seat out (so cleared guests stand on spots), opens the airport and
## sends GATE_GUESTS cleared guests with one roller each to the gate. Once
## boarding opens and the first stander has walked off, FILE_WALKERS walkers with
## a roller each turn out on one cell: they set off one at a time, so the later
## ones wait in their file. The clock runs a third of a tick a frame.
##
## Checks, each printing the values it compared:
##   STOOD: each subject's roller upright (+z to up >= UPRIGHT_DOT), its axle at
##     most BESIDE_M from the feet, held, STOOD_AFTER ticks into the stand.
##   HIPS: the lowest hips holding it against the same guest's hips standing
##     still on the idle clip before the stand (>= HIPS_SHARE; the gate stander
##     is held to it; a file waiter plays the walk clip on the spot while held,
##     so its share is printed only), and the stoop (<= STOOP_EPS).
##   BODY_IN_STOOD_BAG: body points (the holding hand left out) inside the stood
##     roller's meshes on stood frames (CarryContact, drawn in this window).
##   REPULLED: QUEUE_TIP_TICKS + 3 ticks after the tip starts the roller trails
##     more than TRAIL_M behind in the pull.
##   FLOAT: no frame from the stand to the strip's end draws the bag floating.
## Plates: gate_stand, file_stand, gate_tip_strip, file_tip_strip (six frames a
## tick apart from the tip's start, one camera) and a contact sheet. Before a
## save the feet, head and roller project inside the frame with a margin, at
## least MIN_ON of five sight lines land on the roller's BODY (its rods tagged
## apart, anti-pattern a-hide-the-bag-twin-diff-passes-on-the-roller-s-rods) with
## no blocker but its own rods, and the twin with the roller hidden differs from
## the plate in a window round the projected bag body. Otherwise PROBE_INVALID,
## exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roller_board_gate_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/roller-board-gate/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const OUT_REL := "res://../tools/blender/out/roller-board-gate"
const GATE_GUESTS := 3
## Four on one cell: the last waits about 24 ticks, alone on the cell once the
## third has set off (about 16), so its stood roller is not hidden by theirs.
const FILE_WALKERS := 4
const FILE_CELL := Vector2i(19, 6)
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_BAG_PX := 120
const BAG_WINDOW_PX := 40
const MIN_ON := 1
const LIMIT_TICKS := 6000
const UPRIGHT_DOT := 0.95
const BESIDE_M := 0.6
const TRAIL_M := 0.8
const HIPS_SHARE := 0.99
const STOOP_EPS := 0.01
const STOOD_AFTER := RollerPark.QUEUE_STAND_TICKS + 2.0
const STRIP_FRAMES := 6
const TAG := "roller"
const ROD_TAG := "rods"
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
var _offset := Vector2i.ZERO
var _keep: Array[Passenger] = []


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
		var gate := await _gate_stander()
		if not gate.is_empty():
			await _file_waiter()
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	print("PROBE done plates=%d failed=%s" % [_plates, _failed])
	quit(1 if _failed or _plates < 4 else 0)


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
	if not ReferenceTerminal.build(_mode.grid) or not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the reference terminal or its gate desk was refused")
		return false
	_offset = ReferenceTerminal.offset_on(_mode.grid)
	var seats: Array = ReferenceTerminal.object_ids(_mode.grid)["seats"]
	for id: int in seats:
		_mode.grid.apply(BuildEdit.remove_object(id))
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.standing.rebuild(_sim)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print(
		(
			"PROBE seats removed=%d spots=%d hired=%d opened tick=%d doors=%d offset=%s"
			% [
				seats.size(),
				_sim.standing.free_nearest(TestStandingSpotClaims.SCANNER_EXIT + _offset).size(),
				hired,
				_clock.tick,
				doors,
				_offset
			]
		)
	)
	if hired == 0 or doors < 0 or seats.is_empty():
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_clock.ticked.connect(
		func(_t: int) -> void:
			for p in _keep:
				p.late = false
	)
	return true


## A calm passenger of the first flight with one roller.
func _roller_guest() -> Passenger:
	for attempt in 400:
		var p := _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			p.carry_on = 0
			continue
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		p.cleared = true
		p.shop_cooldown = 1000000
		p.boredom = 0
		p.apron = []
		p.apron_mm = 0
		p.clear_path()
		_keep.append(p)
		return p
	return null


## GATE_GUESTS standers: the first stood up is the subject; plate it, wait for
## boarding, and strip its tip as it walks off. Returns the metrics, empty on a
## failure.
func _gate_stander() -> Dictionary:
	var guests: Array[Passenger] = []
	for i in GATE_GUESTS:
		var p := _roller_guest()
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _clock.tick + 1
		p.at = TestStandingSpotClaims.SCANNER_EXIT + _offset
		guests.append(p)
	print(
		(
			"GATE guests %s boarding tick %d"
			% [guests.map(func(p: Passenger) -> int: return p.id), guests[0].boarding_tick]
		)
	)
	var m := _metrics()
	var subject: Passenger = null
	var stop := _clock.tick + LIMIT_TICKS
	while _clock.tick < stop and subject == null:
		await _step()
		for p in guests:
			if p.stage == Passenger.Stage.STANDING and _stood(p, m):
				subject = p
	if subject == null:
		_invalid("GATE: no stander stood its roller up")
		return {}
	print("GATE subject id=%d stood at tick %d" % [subject.id, _clock.tick])
	if not await _plate_retry("gate_stand", subject, m, Passenger.Stage.STANDING):
		return {}
	# Held through the wait: fast to two ticks before boarding, watching each tick.
	while _clock.tick < subject.boarding_tick - 2 and subject.stage == Passenger.Stage.STANDING:
		_clock.advance(SimClock.STEP)
		await _frames(1)
		_watch(subject, m)
	if not await _tip_strip("gate", subject, m):
		return {}
	_summary("GATE", m, true)
	return m


## FILE_WALKERS walkers turned out on FILE_CELL; the first whose roller stands
## up in its file is the subject.
func _file_waiter() -> void:
	var walkers: Array[Passenger] = []
	for i in FILE_WALKERS:
		var p := _roller_guest()
		p.stage = Passenger.Stage.TO_EXIT
		p.stage_tick = _clock.tick
		p.at = FILE_CELL + _offset
		walkers.append(p)
	print(
		(
			"FILE walkers %s at tick %d"
			% [walkers.map(func(p: Passenger) -> int: return p.id), _clock.tick]
		)
	)
	var m := _metrics()
	var subject: Passenger = null
	var stop := _clock.tick + 400
	while _clock.tick < stop and subject == null:
		await _step()
		for p in walkers:
			if p.stage == Passenger.Stage.TO_EXIT and _stood(p, m):
				subject = p
	if subject == null:
		_invalid("FILE: no file waiter stood its roller up")
		return
	var held := RollerPark.filed_still(_sim, subject)
	print(
		(
			"FILE subject id=%d stood at tick %d pending %s filed_still %s moving %s"
			% [
				subject.id,
				_clock.tick,
				_sim.files.is_pending(subject.id),
				held,
				subject.is_moving()
			]
		)
	)
	if not held:
		_invalid("FILE: the subject is not held in its file")
	if not await _plate_retry("file_stand", subject, m, Passenger.Stage.TO_EXIT):
		return
	if not await _tip_strip("file", subject, m):
		return
	_summary("FILE", m, false)


func _metrics() -> Dictionary:
	return {
		"stood_h": INF, "idle_h": -1.0, "stoop": 0.0, "inside": 0, "floats": 0, "repulled": -1.0
	}


## Watches `p` this frame into `m` (idle hips by id before any stand, FLOAT);
## whether its roller is stood STOOD_AFTER into a queue stand, upright, beside
## and held.
func _stood(p: Passenger, m: Dictionary) -> bool:
	var s := _sample(p)
	if s.is_empty():
		return false
	var idle: Dictionary = m.get_or_add("idle_by", {})
	if s["still"] and s["clip"] == &"idle" and not s["queued"] and s["move"] == "":
		idle[p.id] = maxf(float(idle.get(p.id, -1.0)), s["hips"])
	return (
		s["queued"]
		and s["into"] >= STOOD_AFTER
		and not s["tipping"]
		and s["up"] >= UPRIGHT_DOT
		and s["flat"] <= BESIDE_M
		and s["held"] >= 0
	)


## The subject's frame watched into `m` while it holds or tips its roller.
func _watch(p: Passenger, m: Dictionary) -> Dictionary:
	var s := _sample(p)
	if s.is_empty():
		return s
	if m["idle_h"] < 0.0:
		m["idle_h"] = float((m.get("idle_by", {}) as Dictionary).get(p.id, -1.0))
	if FloatCheck.float_state(_sim, _views, p.id, 0)[0] == "float":
		m["floats"] += 1
		print("FLOAT tick %.2f id %d move %s" % [_clock.tick + _clock.alpha, p.id, s["move"]])
	if s["queued"] and s["into"] >= STOOD_AFTER and not s["tipping"]:
		m["stood_h"] = minf(m["stood_h"], s["hips"])
		m["stoop"] = maxf(m["stoop"], s["stoop"])
		m["inside"] = maxi(m["inside"], _inside(p))
	return s


func _sample(p: Passenger) -> Dictionary:
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	if body == null or props.props_of(p.id).get("bags", []).is_empty():
		return {}
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var bag := props.bag_state(p.id, 0)
	var axle := node.global_transform * CarryOnProps.ROLLER_AXLE
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	var now := _clock.tick + _clock.alpha
	return {
		"up": node.global_transform.basis.z.normalized().dot(Vector3.UP),
		"flat": Vector2(axle.x - body.global_position.x, axle.z - body.global_position.z).length(),
		"held": int(bag.get("held_by", -1)),
		"settled": props.transfer_progress(p.id, 0) >= 1.0,
		"hips":
		(
			(rig["pivot"] as Node3D).global_position.y - body.global_position.y
			if rig.has("pivot")
			else -1.0
		),
		"stoop": (rig["stoop"] as CarryStoop).drawn if rig.has("stoop") else 0.0,
		"move": FloatCheck.move_of(props, p.id, 0),
		"queued": RollerPark.queued(bag),
		"tipping": bag.has("queue_tip"),
		"into": now - float(bag.get("since", now)),
		"still":
		_views.tick_position(p.id, true).distance_to(_views.tick_position(p.id, false)) < 0.001,
		"clip": (body.get_node("AnimationPlayer") as AnimationPlayer).current_animation,
	}


func _inside(p: Passenger) -> int:
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var holder := int(props.bag_state(p.id, 0).get("held_by", -1))
	var sides: Array = [[".R", ".L"][holder]] if holder >= 0 else []
	return CarryContact.inside_meshes(CarryContact.body_points(body, sides), node)


## Tries the stood plate of `p` each tick while it holds the stand in `stage`.
func _plate_retry(shot: String, p: Passenger, m: Dictionary, stage: Passenger.Stage) -> bool:
	var s := _watch(p, m)
	print(
		(
			"STOOD %s tick %d up %.3f (>= %.2f) beside %.3f m (<= %.2f) held_by %d into %.1f move %s clip %s"
			% [
				shot,
				_clock.tick,
				s["up"],
				UPRIGHT_DOT,
				s["flat"],
				BESIDE_M,
				s["held"],
				s["into"],
				s["move"],
				s["clip"]
			]
		)
	)
	for attempt in 40:
		if await _plate(shot, p, true) != null:
			return true
		await _step()
		s = _watch(p, m)
		if s.is_empty() or p.stage != stage or s["tipping"]:
			break
	_invalid("%s: no valid plate while the roller stood" % shot)
	return false


## The tip strip: a frame each tick from the tip's start, one camera, then the
## REPULLED check.
func _tip_strip(label: String, p: Passenger, m: Dictionary) -> bool:
	var stop := _clock.tick + 600
	var tip_at := -1.0
	while _clock.tick < stop and tip_at < 0.0:
		await _step()
		var s := _watch(p, m)
		if not s.is_empty() and s["tipping"]:
			tip_at = float(_clock.tick)
	if tip_at < 0.0:
		_invalid("%s: the roller never tipped" % label)
		return false
	print("TIP %s id %d starts at tick %.0f stage %d" % [label, p.id, tip_at, p.stage])
	var strip: Array[Image] = []
	var tried := 0
	while _clock.tick < tip_at + RollerPark.QUEUE_TIP_TICKS + 16:
		# Frame k is tried on each third of tick k until one shows the bag body
		# (a walker crossing the view can hide it for a frame), else skipped.
		var now := _clock.tick + _clock.alpha
		if tried < STRIP_FRAMES and now >= tip_at + tried:
			var img := await _plate(
				"%s_tip_%d" % [label, tried], p, tried == 0 and strip.is_empty(), false
			)
			if img != null:
				strip.append(img)
			if img != null or now + 0.34 >= tip_at + tried + 1.0:
				tried += 1
		await _step()
		var s := _watch(p, m)
		if not s.is_empty() and _clock.tick >= tip_at + ceili(RollerPark.QUEUE_TIP_TICKS) + 3:
			var trail: float = s["flat"] if s["settled"] and s["up"] < 0.8 else 0.0
			if trail > m["repulled"]:
				print(
					(
						"REPULLED %s tick %.2f settled %s up %.3f trail %.3f m (> %.2f) move %s"
						% [
							label,
							_clock.tick + _clock.alpha,
							s["settled"],
							s["up"],
							s["flat"],
							TRAIL_M,
							s["move"]
						]
					)
				)
			m["repulled"] = maxf(m["repulled"], trail)
	if strip.size() < STRIP_FRAMES:
		_invalid("%s tip strip has %d of %d frames" % [label, strip.size(), STRIP_FRAMES])
		return false
	var w := strip[0].get_width() / 2
	var h := strip[0].get_height() / 2
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in strip.size():
		var small := strip[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
	_save(sheet, "%s_tip_strip.png" % label)
	_sheet.append(sheet)
	_plates += 1
	return true


func _summary(label: String, m: Dictionary, posture: bool) -> void:
	var idle: float = m["idle_h"]
	var share: float = m["stood_h"] / maxf(idle, 0.001)
	print(
		(
			(
				"%s HIPS lowest stood %.3f m, idle before the stand %.3f m, "
				+ "share %.3f (>= %.2f, %s), stoop %.3f (<= %.2f)"
			)
			% [
				label,
				m["stood_h"],
				idle,
				share,
				HIPS_SHARE,
				"held to" if posture else "info",
				m["stoop"],
				STOOP_EPS
			]
		)
	)
	if posture and (idle <= 0.0 or share < HIPS_SHARE):
		_invalid("%s HIPS the guest crouches holding its stood roller" % label)
	if m["stoop"] > STOOP_EPS:
		_invalid("%s stoop drawn" % label)
	print(
		(
			"%s BODY_IN_STOOD_BAG most body points inside the stood roller %d (0)"
			% [label, m["inside"]]
		)
	)
	if m["inside"] != 0:
		_invalid("%s BODY_IN_STOOD_BAG" % label)
	if m["repulled"] <= TRAIL_M:
		_invalid("%s REPULLED failed: %.3f" % [label, m["repulled"]])
	print("%s FLOAT frames %d (0)" % [label, m["floats"]])
	if m["floats"] > 0:
		_invalid("%s FLOAT frames drawn" % label)


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


## A plate of `p` and its roller from behind on the roller's side (then from
## the side, then the front, if a camera's sight is blocked). `fresh`: the
## camera is placed now (kept for the strip after it), else it only turns to
## the body. Returns the image, or null when not in frame or not in sight.
func _plate(shot: String, p: Passenger, fresh: bool, strict := true) -> Image:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var target := (body.global_position + bag.global_position) * 0.5 + Vector3.UP * 0.6
	var ahead := body.global_transform.basis.z
	ahead.y = 0.0
	var side := bag.global_position - body.global_position
	side.y = 0.0
	# Each a direction and a height: low behind the roller's side first, then
	# higher (over the walkers crowding the gate at boarding).
	var aways: Array = [
		[(-ahead.normalized() * 0.8 + side.normalized() * 1.3).normalized(), 1.1],
		[side.normalized(), 1.1],
		[(ahead.normalized() * 0.8 + side.normalized() * 1.3).normalized(), 1.1],
		[(-ahead.normalized() * 0.8 + side.normalized() * 1.3).normalized(), 2.6],
		[side.normalized(), 2.6],
		[(-ahead.normalized() * 0.8 + side.normalized() * 1.3).normalized(), 4.5],
		[side.normalized(), 4.5],
	]
	if not strict:
		# A strip in a crowd: steep views first, over the heads round it.
		aways = aways.slice(3) + aways.slice(0, 3)
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	var why := ""
	for k in aways.size() if fresh else 1:
		if fresh:
			var away: Vector3 = aways[k][0]
			var up: float = aways[k][1]
			_cam.look_at_from_position(
				target + away * (3.2 - up * 0.3) + Vector3.UP * up, target, Vector3.UP
			)
		else:
			_cam.look_at(target, Vector3.UP)
		_cam.current = true
		await _frames(2)
		why = await _check(shot, p, body, bag, strict)
		if why == "":
			var img := root.get_texture().get_image()
			_save(img, shot + ".png")
			if fresh and strict:
				_sheet.append(img)
				_plates += 1
			return img
		print("PLATE %s view %d refused: %s" % [shot, k, why])
	return null


## "" when the plate now shows `p` and its roller body, else why not.
## A strip frame (not `strict`) may have a blocker on some lines (walkers
## passing, its own legs as it turns) if MIN_ON lines land on the bag body and
## the hidden-bag twin differs round it.
func _check(shot: String, p: Passenger, body: Node3D, bag: Node3D, strict: bool) -> String:
	var img := root.get_texture().get_image()
	# unproject_position() answers in the viewport's own size; the image is the
	# window's (content scaling), so the bag window is scaled into it.
	var size := root.get_visible_rect().size
	var to_img := Vector2(img.get_size()) / size
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var shell := _shell_box(bag)
	var points := {
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
		"bag_body": shell.get_center(),
	}
	var flat := {}
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			return "%s at %s is out of frame %s" % [name, at, size]
	var sight := await _sight(bag)
	bag.visible = false
	await _frames(2)
	var no_bag := root.get_texture().get_image()
	bag.visible = true
	await _frames(2)
	var centre := Vector2i((flat["bag_body"] as Vector2) * to_img)
	var window := Rect2i(centre - Vector2i.ONE * BAG_WINDOW_PX, Vector2i.ONE * BAG_WINDOW_PX * 2)
	window = window.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var bag_px := PlateSight.differing(img, no_bag, window, 2)
	var tall := (flat["feet"] as Vector2).distance_to(flat["head"])
	var s := _sample(p)
	print(
		(
			(
				"PLATE %s tick %.2f stage %d up %.3f flat %.3f hips %.3f clip %s inside %d "
				+ "at=%s body_px=%.0f bag_body_diff=%d sight=%s"
			)
			% [
				shot,
				_clock.tick + _clock.alpha,
				p.stage,
				s["up"],
				s["flat"],
				s["hips"],
				s["clip"],
				_inside(p),
				flat,
				tall,
				bag_px,
				sight
			]
		)
	)
	var seen: bool = (
		sight["on"] >= MIN_ON and (not strict or (sight["blockers"] as Array).is_empty())
	)
	seen = seen and sight["control_on"] == 0
	if tall < MIN_BODY_PX or bag_px < MIN_BAG_PX or not seen:
		return "body %.0f px, %d px round the bag body, sight %s" % [tall, bag_px, sight]
	return ""


## The roller's body box (its meshes but the rods'), world space.
func _shell_box(bag: Node3D) -> AABB:
	var rods := _rods(bag)
	var box := AABB()
	var first := true
	for mi in bag.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if (
			inst.mesh == null
			or rods.any(func(r: Node) -> bool: return r == inst or r.is_ancestor_of(inst))
		):
			continue
		var part := inst.global_transform * inst.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func _rods(bag: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	for name in CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]:
		var node := bag.find_child(name, true, false)
		if node != null:
			out.append(node)
	return out


## Sight lines from the camera to the roller body's centre and four points round
## it. The rods are tagged ROD_TAG before the bag (the first match wins), so a
## line landing on them is not on the body; a rod in front is not a blocker.
## Control: the same lines with a tag no collider has land on nothing.
func _sight(bag: Node3D) -> Dictionary:
	var owners: Array[Node] = [_views, _mode.get_node("BuildView")]
	var subjects := {}
	var rod_meshes := {}
	for rod in _rods(bag):
		subjects[rod] = ROD_TAG
		for mi in rod.find_children("*", "MeshInstance3D", true, false):
			rod_meshes[mi.name] = true
		if rod is MeshInstance3D:
			rod_meshes[rod.name] = true
	subjects[bag] = TAG
	var holder := PlateSight.colliders(root, owners, subjects)
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
	var blockers: Array = (lines["blockers"] as Array).filter(
		func(n: String) -> bool: return not rod_meshes.has(n)
	)
	return {
		"on": (lines["on_subject"] as Array).size(),
		"blockers": blockers,
		"rod_hits": (lines["blockers"] as Array).size() - blockers.size(),
		"control_on": (control["on_subject"] as Array).size(),
	}


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for i in mini(plates.size(), 4):
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 2), h * (i / 2)))
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
