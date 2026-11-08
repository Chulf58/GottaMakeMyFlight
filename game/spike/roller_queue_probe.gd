extends SceneTree
## Windowed probe of the roller queue stand (board 3dc86b54, decision a-guest-
## standing-still-in-a-queue-stands-the-roller-up-beside-them): guests with a
## roller standing in the cafe's counter queue and ordering (--place=cafe, the
## default) or in the check-in queue and at the desk (--place=checkin) stand it
## upright beside their feet, held by the bar, and tip it back into the pull to
## walk on. It boots main.tscn, builds the reference terminal with a cafe
## (CafeTestLayout), opens the airport and sends GUESTS passengers with one
## roller each, male and female in turn (PassengerSim.spawn_now's variant): to
## the cafe from airside, or in at the doors to check in. The subject is the
## first guest seen at the counter or desk (ORDER stage). The clock runs a third
## of a tick a frame (60 frames a second, as in the game).
##
## Checks, each printing the values it compared (pass values are positives):
##   STOOD: STILL_TICKS + QUEUE_STAND_TICKS + 3 ticks into its order the subject's
##     roller shell is upright (its +z to world up at least UPRIGHT_DOT), its axle
##     at most BESIDE_M from the feet, and held (held_by >= 0); control: walking
##     in before it, a guest's axle trailed more than TRAIL_M behind.
##   QUEUE_HIPS: the subject's hips (the carry rig's pivot) while it stands are at
##     least HIPS_SHARE of their height standing idle just before the stand (the
##     roller still in the pull, _idle_pulled()), and the stoop at most STOOP_EPS (walking hips
##     sit lower, so a walking reference hid a crouch: Opus review of 700ffaa).
##   BODY_IN_STOOD_BAG: per guest (its body type printed), no point of its body
##     (its holding hand left out) inside its stood roller's meshes on any frame
##     STOOD_AFTER into a stand before its tip (CarryContact, as drawn in this
##     window; a headless count proves nothing). At least one male and one female
##     guest must stand (board 03454587).
##   TIP_TIME: once the subject walks on, its tip starts after the wait for the
##     body's turn (RollerPark.tip_wait(): a desk or counter leaver keeps it) and
##     ends at most TURN_TICKS + 2 * QUEUE_TIP_TICKS after it was marked.
##   REPULLED: 3 ticks after that tip's end, the move is over and the axle trails
##     more than TRAIL_M behind again (a fixed QUEUE_TIP_TICKS + 3 ticks after
##     walking on sampled it 2 ticks into a tip that waited 6: board 03454587).
##   FLOAT: no frame from the order to the strip's end draws the bag floating
##     (spike/carry_float_check.gd).
## Plates: queue_stand (the subject stood at the counter or desk), one stand
## plate of a male and of a female guest (<place>_stand_<variant>_b<body>),
## tip_strip (a frame each tick from the tip's start, six frames, one
## camera) and a contact sheet. Before a save the feet, head and the roller's
## body (its rods left out) project inside the frame with a margin, at least
## MIN_ON of five sight lines land on the roller's body (its rods tagged apart,
## anti-pattern a-hide-the-bag-twin-diff-passes-on-the-roller-s-rods) with no
## blocker but its rods, the twin with the body hidden differs from the plate,
## and the twin with the roller hidden differs in a window round the projected
## roller body. A tip strip frame also has the holding hand's grip and the
## bar's top in frame, and the first thing every line (the five to the roller's
## body, one to the hand, one to the bar) meets is the subject's own body, rods
## or roller (board 03454587); a walker in the way sends the frame round the
## other views (the one that works is kept), at most STRIP_REFUSALS refused
## views a strip. The sight colliders are built once a frame, for every view
## tried on it. Otherwise the subject's plates are PROBE_INVALID, exit 1; a
## guest's stand plate is tried again each frame it stands, and PROBE_INVALID if
## none of a variant's stands gave one.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roller_queue_probe.gd [-- --seed=N] \
##     [--place=checkin] [--out=<dir under tools/blender/out>]
##
## Plates go to tools/blender/out/roller-queue/ (or --out).

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const OUT_ROOT := "res://../tools/blender/out/"
const GUESTS := 4
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_DIFF_PX := 1500
## Two plates of the same pose, a few frames apart, differ by at most this many
## pixels; more and the twins were not taken of one still scene.
const MAX_STILL_PX := 100
const MIN_BAG_PX := 120
const BAG_WINDOW_PX := 40
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
const STOOD_AFTER := RollerPark.QUEUE_STAND_TICKS + 2.0
const STRIP_FRAMES := 6
const TAG := "roller"
const SELF_TAG := "self"
const ROD_TAG := "rods"
const NO_TAG := "nothing_has_this_tag"
const VARIANTS := ["male", "female"]
## Camera ways round a plate's subject (_aim()), each low then high.
const VIEWS := 3
## Camera heights (m over the subject's mid point) for _aim(): a view k is
## way k % VIEWS at height k / VIEWS.
const VIEW_UPS: Array[float] = [1.1, 2.4, 4.0]
## Refused views a tip strip may spend (each costs a few frames) before the
## rest of its frames are skipped.
const STRIP_REFUSALS := 60
## A character this much nearer the camera than the subject crowds a tip strip
## view (_strip_view()).
const NEAR_M := 0.5
## The camera's distance from a plate's mid point (_aim()).
const AIM_M := 3.2
## The distances a tip strip's camera may take (_strip_view()), farthest first.
const STRIP_DISTS: Array[float] = [AIM_M, 2.6]
## Per place: the queue stages, the stage at the counter or desk, the stage
## walking off from it.
const PLACES := {
	"cafe":
	[
		[Passenger.Stage.CAFE_QUEUE, Passenger.Stage.CAFE_ORDER],
		Passenger.Stage.CAFE_ORDER,
		Passenger.Stage.CAFE_TO_SEAT
	],
	"checkin":
	[
		[Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.CHECKIN],
		Passenger.Stage.CHECKIN,
		Passenger.Stage.TO_SECURITY
	],
}

var _seed := 0
var _place := "cafe"
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
## The tip strip's camera is placed: no guest plate moves it until the strip ends.
var _strip_on := false
var _strip_refused := 0


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	var out := "roller-queue"
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--place="):
			_place = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	_out_dir = ProjectSettings.globalize_path(OUT_ROOT + out).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d place=%s out_dir=%s" % [_seed, _place, _out_dir])
	if not PLACES.has(_place):
		_invalid("unknown place %s" % _place)
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		await _watch()
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "%s_contact_sheet.png" % _place)
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
	# The desk's "Queue full" sign is drawn over the world in the plates (board
	# 03454587 item 8); it is not what they show.
	(_views.get_node("MissMarkers") as Node3D).visible = false
	return true


## GUESTS passengers with one roller each, male and female in turn: airside and
## committed to the cafe, or walking in to check in.
func _guests() -> Array[Passenger]:
	var out: Array[Passenger] = []
	for attempt in 400:
		if out.size() >= GUESTS:
			break
		var p := _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0), out.size() % 2)
		)
		if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			p.carry_on = 0
			continue
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		p.shop_cooldown = 1000000
		p.boredom = 0
		if _place == "checkin":
			p.cafe_cooldown = 1000000
			out.append(p)
			continue
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _clock.tick
		p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
		p.clear_path()
		if _sim.cafes.try_visit(p):
			out.append(p)
	_clock.ticked.connect(
		func(_t: int) -> void:
			for p in out:
				p.late = false
	)
	var names: Array[String] = []
	for p in out:
		var b := PassengerLooks.body_of(p.id, p.variant)
		names.append("%d:%s(b%d)" % [p.id, PassengerLooks.BODIES[b], b])
	print("GUESTS %s" % [names])
	return out


func _watch() -> void:
	var guests := _guests()
	if guests.size() < 2:
		_invalid("only %d guests set off" % guests.size())
		return
	var stages: Array = PLACES[_place][0]
	var order_stage: Passenger.Stage = PLACES[_place][1]
	var off_stage: Passenger.Stage = PLACES[_place][2]
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
	var by_guest := {}
	var plated := {}
	var stop := _clock.tick + LIMIT_TICKS
	var strip: Array[Image] = []
	while _clock.tick < stop:
		await _step()
		for p in guests:
			await _track(p, by_guest.get_or_add(p.id, {}), stages, plated)
		if subject == null:
			for p in guests:
				if p.stage == order_stage:
					subject = p
					m["order_at"] = _clock.tick
					print("SUBJECT id=%d at the %s at tick %d" % [p.id, _place, _clock.tick])
			for p in guests:
				if p.stage in [Passenger.Stage.CAFE_WALK, Passenger.Stage.TO_CHECKIN]:
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
		# Standing idle before the stand, the roller still settled in the pull.
		if subject.stage == order_stage and into >= 1 and _idle_pulled(s):
			m["idle_h"] = maxf(m.get("idle_h", -1.0), s["hips"])
			m["idle_n"] = int(m.get("idle_n", 0)) + 1
		if subject.stage == order_stage and into >= stood_by and s["queued"] and not s["tipping"]:
			m["stand_h"] = minf(m["stand_h"], s["hips"])
			m["stoop"] = maxf(m.get("stoop", 0.0), s["stoop"])
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
				if await _plate("%s_queue_stand" % _place, subject, true) == null:
					_invalid("%s_queue_stand: no valid plate" % _place)
		if subject.stage == off_stage and m["off_at"] < 0:
			m["off_at"] = _clock.tick
			_strip_on = true
			_strip_refused = 0
		if m["off_at"] < 0:
			continue
		var after: int = _clock.tick - m["off_at"]
		# A move running: the flags of a stand that ended stay on the record.
		if s["tipping"] and s["move"] != "" and not m.has("tip_end"):
			_mark_tip(m, s)
		var tried: int = m.get("tried", 0)
		var at_now := _clock.tick + _clock.alpha
		# The strip starts on the tip's first tick: before it the roller is carried
		# upright through the body's turn (the strip of six frames from the walk-off
		# showed only that carry: board 03454587).
		var strip_at: float = m.get("tip_at", INF)
		if tried == 0 and at_now >= strip_at and not m.has("strip_view"):
			m["strip_view"] = _strip_view(subject)
		if tried < STRIP_FRAMES and at_now >= strip_at + tried:
			# Frame k is tried on each third of tick k until one shows the bag
			# body (a walker in the queue behind can hide it for a frame).
			var img := await _plate("%s_tip_%d" % [_place, tried], subject, false, true)
			if img != null:
				strip.append(img)
			if img != null or at_now + 0.34 >= strip_at + tried + 1.0:
				m["tried"] = tried + 1
				_strip_on = tried + 1 < STRIP_FRAMES
		if m.has("tip_end") and _clock.tick >= m["tip_end"] + 3 and m["repulled"] < 0.0:
			m["repulled"] = s["flat"] if s["settled"] and s["up"] < 0.8 else 0.0
			print(
				(
					(
						"REPULLED tick %d (%d after walking on, %d after the tip's end) "
						+ "settled %s up %.3f trail %.3f m (> %.2f)"
					)
					% [
						_clock.tick,
						after,
						_clock.tick - m["tip_end"],
						s["settled"],
						s["up"],
						s["flat"],
						TRAIL_M
					]
				)
			)
		if after >= 8 and after < 16:
			m["walk_h"] = maxf(m["walk_h"], s["hips"])
		var all_off := guests.all(func(p: Passenger) -> bool: return not p.stage in stages)
		var done: bool = m["repulled"] >= 0.0 and int(m.get("tried", 0)) >= STRIP_FRAMES
		if after >= 16 and done and all_off:
			break
	if subject != null and float(m.get("idle_h", -1.0)) <= 0.0:
		# Stood up in the queue before it reached the desk: its idle in the queue.
		m["idle_h"] = float((by_guest[subject.id] as Dictionary).get("idle", -1.0))
	_summary(m, strip, guests, by_guest, plated)


## Whether sample `s` (_sample()) stands still on the idle clip with its roller
## lying settled in the pull and no move running. A queue stand's "park" and
## "queue" flags stay on the bag's record after its tip has ended, so
## RollerPark.queued() alone cannot say the roller is in the pull: read that
## way the check-in subject never stood idle and QUEUE_HIPS had no baseline
## (board 03454587).
func _idle_pulled(s: Dictionary) -> bool:
	return (
		s["still"]
		and s["clip"] == &"idle"
		and s["move"] == ""
		and s["settled"]
		and s["up"] < 0.8
		and s["flat"] > TRAIL_M
	)


## The subject's tip into `m` on the first frame `s` (_sample()) has it marked
## (RollerPark.queue_stand()'s "queue_tip"): the tick it starts, after the wait
## for the body's turn (RollerPark.tip_wait()), and the tick it ends, its
## RollerPark.tip_ticks() later. TIP_TIME holds the end to the most the decision
## allows from the mark: a TURN_TICKS wait and a tip twice QUEUE_TIP_TICKS long
## (a half turn's yaw gap, decision open-side-queue-stand-as-built).
func _mark_tip(m: Dictionary, s: Dictionary) -> void:
	var mark := _clock.tick + _clock.alpha
	var start: float = s["since"] + s["tip"]
	m["tip_at"] = start
	m["tip_end"] = ceili(start + s["tip_ticks"])
	var most := mark + PassengerTurns.TURN_TICKS + 2.0 * RollerPark.QUEUE_TIP_TICKS
	print(
		(
			(
				"TIP_TIME marked at tick %.2f (%d after walking on): starts at %.2f "
				+ "(waits %.2f for the turn, <= %d), runs %.2f ticks, ends at %.2f (<= %.2f)"
			)
			% [
				mark,
				_clock.tick - m["off_at"],
				start,
				start - mark,
				PassengerTurns.TURN_TICKS,
				s["tip_ticks"],
				start + s["tip_ticks"],
				most
			]
		)
	)
	if start + s["tip_ticks"] > most + 0.01:
		_invalid("TIP_TIME the tip ends later than the turn wait and the longest tip allow")


## One frame of guest `p` into `g`: on frames STOOD_AFTER into a queue stand in
## `stages` before its tip, the most body points inside its roller and the
## frames counted; the first such stand of each variant tried for a plate.
func _track(p: Passenger, g: Dictionary, stages: Array, plated: Dictionary) -> void:
	var s := _sample(p)
	if s.is_empty() or not p.stage in stages:
		return
	if _idle_pulled(s):
		# Standing idle in the queue before a stand, the roller in the pull.
		g["idle"] = maxf(float(g.get("idle", -1.0)), s["hips"])
	if not s["queued"] or s["tipping"] or s["into"] < STOOD_AFTER or s["up"] < UPRIGHT_DOT:
		return
	g["frames"] = int(g.get("frames", 0)) + 1
	var inside := _inside(p)
	g["inside"] = maxi(int(g.get("inside", 0)), inside)
	g["flat"] = s["flat"]
	if inside > 0 and int(g.get("lines", 0)) < 3:
		g["lines"] = int(g.get("lines", 0)) + 1
		print(
			(
				"INSIDE tick %.2f id %d points %d stage %d into %.1f flat %.3f"
				% [_clock.tick + _clock.alpha, p.id, inside, p.stage, s["into"], s["flat"]]
			)
		)
	var variant: String = VARIANTS[p.variant]
	if plated.has(variant) or int(g.get("tries", 0)) >= 30 or _strip_on:
		return
	g["tries"] = int(g.get("tries", 0)) + 1
	var b := PassengerLooks.body_of(p.id, p.variant)
	var shot := "%s_stand_%s_b%d" % [_place, variant, b]
	if await _plate(shot, p, true, true) != null:
		plated[variant] = shot


func _sample(p: Passenger) -> Dictionary:
	var body := _views.node_for(p.id)
	var props := _views.carry_on_props()
	if body == null or props.props_of(p.id).get("bags", []).is_empty():
		return {}
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var bag := props.bag_state(p.id, 0)
	var axle := node.global_transform * CarryOnProps.ROLLER_AXLE
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	var hips := -1.0
	var stoop := 0.0
	if not rig.is_empty():
		hips = (rig["pivot"] as Node3D).global_position.y - body.global_position.y
		stoop = (rig["stoop"] as CarryStoop).drawn
	var now := _clock.tick + _clock.alpha
	return {
		"up": node.global_transform.basis.z.normalized().dot(Vector3.UP),
		"flat": Vector2(axle.x - body.global_position.x, axle.z - body.global_position.z).length(),
		"held": int(bag.get("held_by", -1)),
		"settled": props.transfer_progress(p.id, 0) >= 1.0,
		"hips": hips,
		"stoop": stoop,
		"move": FloatCheck.move_of(props, p.id, 0),
		"queued": RollerPark.queued(bag),
		"tipping": bag.has("queue_tip"),
		"into": now - float(bag.get("since", now)),
		"still":
		_views.tick_position(p.id, true).distance_to(_views.tick_position(p.id, false)) < 0.001,
		"clip": (body.get_node("AnimationPlayer") as AnimationPlayer).current_animation,
		"tip": float(bag.get("queue_tip", -1.0)),
		"tip_ticks": RollerPark.tip_ticks(bag),
		"since": float(bag.get("since", -1.0)),
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


func _summary(
	m: Dictionary, strip: Array[Image], guests: Array[Passenger], by: Dictionary, plated: Dictionary
) -> void:
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
				"QUEUE_HIPS lowest hips stood %.3f m, standing idle before the stand %.3f m "
				+ "(%d idle frames at the desk, %s), share %.3f (>= %.2f), stoop %.3f (<= %.2f); "
				+ "walking after %.3f m (info)"
			)
			% [
				m["stand_h"],
				idle,
				int(m.get("idle_n", 0)),
				"the queue's idle instead" if int(m.get("idle_n", 0)) == 0 else "taken there",
				share,
				HIPS_SHARE,
				m.get("stoop", -1.0),
				STOOP_EPS,
				m["walk_h"]
			]
		)
	)
	if idle <= 0.0 or share < HIPS_SHARE or float(m.get("stoop", 1.0)) > STOOP_EPS:
		_invalid("QUEUE_HIPS the guest crouches holding its stood roller")
	var stood_by := {}
	for p in guests:
		var g: Dictionary = by.get(p.id, {})
		var b := PassengerLooks.body_of(p.id, p.variant)
		print(
			(
				(
					"BODY_IN_STOOD_BAG %s guest %d %s b%d %s: stood frames %d, "
					+ "most points inside %d (0), axle %.3f m out"
				)
				% [
					_place,
					p.id,
					VARIANTS[p.variant],
					b,
					PassengerLooks.BODIES[b],
					int(g.get("frames", 0)),
					int(g.get("inside", 0)),
					float(g.get("flat", -1.0))
				]
			)
		)
		if int(g.get("inside", 0)) != 0:
			_invalid("BODY_IN_STOOD_BAG guest %d b%d" % [p.id, b])
		if int(g.get("frames", 0)) > 0:
			stood_by[p.variant] = int(stood_by.get(p.variant, 0)) + 1
	print("STOOD guests by variant %s; plates %s" % [stood_by, plated])
	for v in VARIANTS.size():
		if not stood_by.has(v):
			_invalid("no %s guest stood its roller up" % VARIANTS[v])
		elif not plated.has(VARIANTS[v]):
			_invalid("no valid stand plate of a %s guest" % VARIANTS[v])
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
	_save(sheet, "%s_tip_strip.png" % _place)
	_sheet.append(sheet)
	_plates += 1


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


## Places the camera on `p` and its roller: behind on the roller's side (from
## in front, the counter or desk it faces hid it), `dist` m from its mid point.
## `view` (VIEWS) picks the way round: in a check-in queue the walkers behind
## can hide the first.
func _aim(p: Passenger, view := 0, dist := AIM_M) -> void:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var target := (body.global_position + bag.global_position) * 0.5 + Vector3.UP * 0.6
	var ahead := body.global_transform.basis.z
	ahead.y = 0.0
	var side := bag.global_position - body.global_position
	side.y = 0.0
	var out := side.normalized()
	var fwd := ahead.normalized()
	var aways := [(-fwd * 0.8 + out * 1.3).normalized(), out, (fwd * 0.8 + out * 1.3).normalized()]
	var away: Vector3 = aways[view % VIEWS]
	var up: float = VIEW_UPS[view / VIEWS]
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	_cam.look_at_from_position(target + away * dist + Vector3.UP * up, target, Vector3.UP)


## Places the tip strip's camera (_aim()) on the first view, at each of
## STRIP_DISTS and in VIEWS order at each of VIEW_UPS, that has the subject's
## feet, head and roller in frame and the fewest points of other characters
## (passengers and staff) in frame nearer the camera than `p` by NEAR_M: one
## such walker filled a corner of every check-in tip frame (board 03454587
## item 8). Returns [view, distance].
func _strip_view(p: Passenger) -> Array:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var others: Array[Vector3] = []
	for skel in _main.find_children("*", "Skeleton3D", true, false):
		var at := (skel as Node3D).global_position
		if not body.is_ancestor_of(skel) and (skel as Node3D).is_visible_in_tree():
			for up in [0.3, 0.9, 1.5]:
				others.append(at + Vector3.UP * up)
	var own: Array[Vector3] = [
		body.global_position, body.global_position + Vector3.UP * 1.7, bag.global_position
	]
	var inside := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * 2.0 * MARGIN_PX
	)
	var best := [0, AIM_M]
	var fewest := -1
	for dist in STRIP_DISTS:
		for view in VIEWS * VIEW_UPS.size():
			_aim(p, view, dist)
			var framed := own.all(
				func(at: Vector3) -> bool:
					return (
						not _cam.is_position_behind(at)
						and inside.has_point(_cam.unproject_position(at))
					)
			)
			var far := _cam.global_position.distance_to(body.global_position) - NEAR_M
			var near := others.filter(
				func(at: Vector3) -> bool:
					return (
						_cam.is_position_in_frustum(at)
						and _cam.global_position.distance_to(at) < far
					)
			)
			if framed and (fewest < 0 or near.size() < fewest):
				best = [view, dist]
				fewest = near.size()
	_aim(p, best[0], best[1])
	print(
		(
			"STRIP_VIEW view %d at %.1f m, other character points nearer the camera %d"
			% [best[0], best[1], fewest]
		)
	)
	return best


## A plate of `p` and its roller. `fresh`: the camera is placed on the subject
## now (_aim()), else it only turns to it. `quiet`: a refusal is printed, not
## PROBE_INVALID (tried again later). Returns the image (saved, and on the sheet
## when `fresh`), or null when the subject is not in frame or not in sight.
func _plate(shot: String, p: Passenger, fresh: bool, quiet := false) -> Image:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var holder := await _colliders(bag, body)
	var img: Image = null
	if not fresh:
		# A strip frame: the strip's camera, then the other views while refusals
		# are left (a walker in the queue behind can cross it).
		# Over the heads first (the queue crowds the low views: seed 2430301318
		# refused every low view of frames 3 to 5), the low views last.
		var views: Array = [-1]
		for k in range(VIEW_UPS.size() * VIEWS - 1, -1, -1):
			views.append(k)
		for view: int in views:
			if img != null or _strip_refused >= STRIP_REFUSALS:
				break
			img = await _plate_from(shot, p, view >= 0, true, maxi(view, 0), holder)
			if img == null:
				_strip_refused += 1
				if _strip_refused == STRIP_REFUSALS:
					print("PLATE %s: the strip spent its %d refused views" % [shot, STRIP_REFUSALS])
	else:
		for view in VIEWS * 2:
			img = await _plate_from(
				shot, p, true, false, view, holder, quiet or view < VIEWS * 2 - 1
			)
			if img != null:
				break
	holder.free()
	return img


## _plate() from camera `view` (_aim()), placed now when `aim`, with the
## frame's sight colliders `holder`. A `strip` frame has the hand and bar in
## frame too, and every line's first hit is the subject's own; any other plate
## has no blocker on its lines. A refused strip frame is printed, not
## PROBE_INVALID. The scene is held (tree paused, every animation stopped)
## while the plate and its twins are taken, so the twins differ by what was
## hidden and not by a clip playing on.
func _plate_from(
	shot: String, p: Passenger, aim: bool, strip: bool, view: int, holder: Node3D, quiet := true
) -> Image:
	_hold_scene(true)
	var img := await _shoot(shot, p, aim, strip, view, holder, quiet)
	_hold_scene(false)
	return img


## Pauses (or lets go again) the tree and every AnimationPlayer under the
## passenger views: in manual callback mode a player keeps its pose until
## advanced, whatever calls play() or seek() on it.
func _hold_scene(hold: bool) -> void:
	paused = hold
	var mode := (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if hold
		else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	for player in _views.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).callback_mode_process = mode


func _shoot(
	shot: String, p: Passenger, aim: bool, strip: bool, view: int, holder: Node3D, quiet: bool
) -> Image:
	var body := _views.node_for(p.id)
	var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
	var target := (body.global_position + bag.global_position) * 0.5 + Vector3.UP * 0.6
	if aim or _cam == null:
		_aim(p, view)
	else:
		_cam.look_at(target, Vector3.UP)
	_cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	# unproject_position() answers in the viewport's own size; the image is the
	# window's (content scaling), so the bag window is scaled into it.
	var size := root.get_visible_rect().size
	var to_img := Vector2(img.get_size()) / size
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var points := {
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
		"bag_body": _shell_box(bag).get_center(),
	}
	if strip:
		# The hand on the bar shows as well as the bag body (board 03454587).
		var top := bag.find_child(
			CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER][1], true, false
		)
		points["bar"] = (top as Node3D).global_position
		var hand := int(_views.carry_on_props().bag_state(p.id, 0).get("held_by", -1))
		if hand >= 0:
			points["hand"] = _views.carry_on_props().grip_of(body, hand)
	var flat := {}
	var why := ""
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			why = "%s at %s is out of frame %s" % [name, at, size]
	if why != "":
		return _refused(shot, why, quiet)
	var sight := _sight(holder, points)
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
	await _frames(2)
	var again := root.get_texture().get_image()
	var still_px := _diff(img, again)
	var body_px := _diff(img, no_body)
	var centre := Vector2i((flat["bag_body"] as Vector2) * to_img)
	var window := Rect2i(centre - Vector2i.ONE * BAG_WINDOW_PX, Vector2i.ONE * BAG_WINDOW_PX * 2)
	window = window.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var bag_px := PlateSight.differing(img, no_bag, window, 2)
	var points_in := _inside(p)
	print(
		(
			(
				"PLATE %s tick %.2f id %d b%d stage %d up %.3f flat %.3f hips %.3f "
				+ "BODY_IN_STOOD_BAG %d at=%s body_px=%.0f still_diff=%d body_diff=%d "
				+ "bag_body_diff=%d unbaked=%d sight=%s"
			)
			% [
				shot,
				_clock.tick + _clock.alpha,
				p.id,
				PassengerLooks.body_of(p.id, p.variant),
				p.stage,
				now["up"],
				now["flat"],
				now["hips"],
				points_in,
				flat,
				tall,
				still_px,
				body_px,
				bag_px,
				(holder.get_meta("unbaked") as Array).size(),
				sight
			]
		)
	)
	var seen: bool = sight["on"] >= MIN_ON and sight["control_on"] == 0
	if strip:
		seen = seen and points.has("hand") and sight["own"] == sight["lines"]
	else:
		seen = seen and (sight["blockers"] as Array).is_empty()
	if (
		tall < MIN_BODY_PX
		or still_px > MAX_STILL_PX
		or body_px < MIN_DIFF_PX
		or bag_px < MIN_BAG_PX
		or not seen
	):
		var moved := Rect2i()
		if still_px > MAX_STILL_PX:
			moved = PlateSight.differing_box(img, again, Rect2i(Vector2i.ZERO, img.get_size()))
		why = (
			"body %.0f px, %d px between two still plates (in %s), %d px body, %d px round the bag, sight %s"
			% [tall, still_px, moved, body_px, bag_px, sight]
		)
		return _refused(shot, why, quiet)
	_save(img, shot + ".png")
	if not strip:
		_sheet.append(img)
		_plates += 1
	return img


func _refused(shot: String, why: String, quiet: bool) -> Image:
	if quiet:
		print("PLATE %s refused: %s" % [shot, why])
	else:
		_invalid("%s: %s" % [shot, why])
	return null


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


## The sight colliders for one frame (PlateSight: every passenger and the
## built terminal), `body` tagged SELF_TAG, the rods ROD_TAG before the bag
## (the first match wins) and the bag TAG. Built once a frame (_plate()).
func _colliders(bag: Node3D, body: Node3D) -> Node3D:
	var owners: Array[Node] = [_views, _mode.get_node("BuildView")]
	var subjects := {body: SELF_TAG}
	var rod_meshes := {}
	for rod in _rods(bag):
		subjects[rod] = ROD_TAG
		for mi in rod.find_children("*", "MeshInstance3D", true, false):
			rod_meshes[mi.name] = true
		if rod is MeshInstance3D:
			rod_meshes[rod.name] = true
	subjects[bag] = TAG
	var holder := PlateSight.colliders(root, owners, subjects)
	holder.set_meta("rod_meshes", rod_meshes)
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		# A skinned mesh without a collider is nothing a line can hit, so a
		# line past it would read as clear.
		_invalid("skinned meshes without a sight collider: %s" % [unbaked])
	await physics_frame
	await physics_frame
	return holder


## Sight lines from the camera to the roller body's centre and four points round
## it, against `holder` (_colliders()); a rod in front is not a blocker.
## "own" counts the lines (those five, and one to each of `points`' hand and
## bar) whose first hit is the subject's own body, rods or roller, or nothing
## short of the point. Control: the same lines with a tag no collider has land
## on nothing.
func _sight(holder: Node3D, points: Dictionary) -> Dictionary:
	var rod_meshes: Dictionary = holder.get_meta("rod_meshes")
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get(TAG, AABB())
	var targets: Array[Vector3] = [box.get_center()]
	for f in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0.3, 0), Vector3(0, -0.3, 0)]:
		targets.append(box.get_center() + _cam.global_basis * (f * box.size.length() * 0.5))
	var space := _cam.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, TAG)
	var control := PlateSight.sight_lines(space, _cam.global_position, targets, NO_TAG)
	var ends: Array[Vector3] = targets.duplicate()
	var parts := {}
	for name in ["hand", "bar"]:
		if points.has(name):
			ends.append(points[name])
			parts[name] = _first_hit(space, points[name])
	var own := ends.filter(func(at: Vector3) -> bool: return _first_is_own(space, at)).size()
	var blockers: Array = (lines["blockers"] as Array).filter(
		func(n: String) -> bool: return not rod_meshes.has(n)
	)
	return {
		"on": (lines["on_subject"] as Array).size(),
		"blockers": blockers,
		"control_on": (control["on_subject"] as Array).size(),
		"own": own,
		"lines": ends.size(),
		"parts": parts,
	}


## The mesh a line from the camera to `at` first meets when it is not the
## subject's own (_first_is_own()), else "" (printed with a refusal).
func _first_hit(space: PhysicsDirectSpaceState3D, at: Vector3) -> String:
	if _first_is_own(space, at):
		return ""
	var from := _cam.global_position
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, at + (at - from).normalized() * 0.05)
	)
	return str((hit.collider as Node).get_meta("mesh", "?"))


## Whether the first thing a line from the camera to `at` (run 5 cm on) meets
## is the subject's own body, its rods or roller (_colliders()' tags), or
## nothing short of `at`.
func _first_is_own(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var from := _cam.global_position
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, at + (at - from).normalized() * 0.05)
	)
	if hit.is_empty() or from.distance_to(hit.position) >= from.distance_to(at) - 0.05:
		return true
	return str((hit.collider as Node).get_meta("subject", "")) in [SELF_TAG, ROD_TAG, TAG]


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
