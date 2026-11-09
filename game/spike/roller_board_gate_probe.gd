extends SceneTree
## Windowed probe of the roller queue stand at the gate and in a boarding file
## (board 44b974cc): a guest standing at the gate for want of a seat (STANDING)
## and a walker waiting in a boarding file each stand the roller upright beside
## them, held by the bar, and tip it back into the pull when they walk on.
## It boots main.tscn, builds the reference terminal with its gate desk, takes
## every gate seat out (so cleared guests stand on spots), opens the airport and
## sends GATE_GUESTS cleared guests with one roller each to the gate. Once
## boarding opens and the first stander has walked off, file walkers with a
## roller each turn out on FILE_CELLS: they set off one at a time, so the later
## ones wait in their file. Then four walkers stacked on one cell are checked
## for other bags drawn on the stood roller (BLOCKER lines, no plate). The
## clock runs a third of a tick a frame.
##
## Checks, each printing the values it compared:
##   STOOD: each subject's roller upright (+z to up >= UPRIGHT_DOT), its axle at
##     most BESIDE_M from the feet, held, STOOD_AFTER ticks into the stand.
##   HIPS: the lowest hips holding it against the same guest's hips standing
##     still on the idle clip before the stand (>= HIPS_SHARE), and the stoop
##     (<= STOOP_EPS).
##   DESK_OVERLAP: points of the gate stander's stood roller body inside the
##     gate desk's mesh (parity test; control: a point inside the counter) and
##     the deepest from the mesh box's nearest face, on its first 30 stood frames.
##   BODY_IN_STOOD_BAG: body points (the holding hand left out) inside the stood
##     roller's meshes on stood frames (CarryContact, drawn in this window).
##   REPULLED: QUEUE_TIP_TICKS + 3 ticks after the tip starts the roller trails
##     more than TRAIL_M behind in the pull.
##   FLOAT: no frame from the stand to the strip's end draws the bag floating.
##   TURN (gate): the strip subject's tip waits PassengerTurns.TURN_TICKS
##     (RollerPark.tip_wait()) and its body turns more than TIP_TURN_RAD over
##     them (decision gate-full-as-built, board f115d5da). Its tick position
##     must move over them too, else TIP_ON_STILL_WALKER: a tip on a walker that
##     has not set off (board aa2db71d), named as such.
##   CARRY_UPRIGHT (gate): over those ticks the roller stays upright
##     (>= UPRIGHT_DOT), held and at most BESIDE_M from the feet.
##   CARRY_CLEAR (gate): from the mark to the tip's end no point of the roller
##     body is inside a built piece standing off the floor (wall, desk, seat);
##     the nearest piece and its box gap are printed.
## Plates: gate_stand, gate_carry_strip (the six-tick upright carry while the
## body turns), gate_tip_strip, file_stand, file_tip_strip (six frames a tick
## apart from the tip's start, one camera) and a contact sheet. Before a
## save the feet, head and roller project inside the frame with a margin, at
## least MIN_ON of five sight lines land on the roller's BODY (its rods tagged
## apart, anti-pattern a-hide-the-bag-twin-diff-passes-on-the-roller-s-rods) with
## no blocker but its own rods, and the twin with the roller hidden differs from
## the plate in a window round the projected bag body. A strip is shot low on
## the roller's side (STRIP_LOW_M), and each strip frame also has the holding
## hand's grip and the bar's top in frame, and the first thing every line (the
## five to the roller's body, one to the hand, one to the bar) meets is the
## subject's own body, rods or roller (board 03454587); a walker in the way
## sends the frame round the other views (the one that works is kept), at most
## STRIP_REFUSALS refused views a strip. The sight colliders are built once a
## frame, for every view tried on it; after the views on the roller's side
## come RING_VIEWS round the subject. The gate stand subject is the first
## stander that plates, those with no stood roller point inside the gate desk
## first, then farthest from the desk (the boarding crowd walks to the desk).
## The gate strip follows the first stander whose tip waits for its turn.
## Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roller_board_gate_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/gate-stand/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const OUT_REL := "res://../tools/blender/out/gate-stand"
const GATE_GUESTS := 5
## Where the file walkers turn out: three on one cell, then one on each cell
## beside it, a later id each. The walkers beside wait their turn in the file
## (pending) alone on their cell; on one cell a walker ahead that sets off
## pulls its roller back over the spot of the one behind (seed 44974: every
## sight line to the stood roller hit that roller, BLOCKER lines).
const FILE_CELLS: Array[Vector2i] = [
	Vector2i(19, 6), Vector2i(19, 6), Vector2i(19, 6), Vector2i(18, 6), Vector2i(20, 6)
]
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_BAG_PX := 120
const BAG_WINDOW_PX := 40
const MIN_ON := 1
const LIMIT_TICKS := 6000
const UPRIGHT_DOT := 0.95
const BESIDE_M := 0.6
const TRAIL_M := 0.8
## The strip subject's tick position must move more than this from the tip's
## mark to its start, else the tip is on a walker that has not set off.
const STILL_WALK_M := 0.01
const HIPS_SHARE := 0.99
const STOOP_EPS := 0.01
const STOOD_AFTER := RollerPark.QUEUE_STAND_TICKS + 2.0
const STRIP_FRAMES := 6
## The tip strip's camera height (m over the subject's mid point, _plate()).
const STRIP_LOW_M := 0.8
## Refused views a tip strip may spend (each costs a few frames) before the
## rest of its frames are skipped.
const STRIP_REFUSALS := 150
## The still hold before boarding is watched every this many ticks (_gate_stander()).
const HOLD_WATCH_TICKS := 10
## Ticks the other gate standers get to stand after the first (_gate_stander()).
const STAND_WAIT := 60
## Stand plate attempts (a third of a tick apart) a gate candidate gets when
## another is left to try (_plate_retry()).
const PLATE_TRIES_EARLY := 6
## Views round the subject at each ring height (_plate()).
const RING_VIEWS := 8
## A built mesh less tall than this is floor (_build_gap()).
const FLOOR_TOP_M := 0.05
const TAG := "roller"
const SELF_TAG := "self"
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
var _desk_control := {}
var _strip_refused := 0
## The gate standers watched against the gate desk from boarding (_step()).
var _board_watch: Array = []
## Gate stander id -> its boarding DESK_OVERLAP watch (_watch_board_desk()).
var _board_desk := {}


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
			await _stacked_diag()
		await _board_desk_settle()
		_board_desk_check()
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


## GATE_GUESTS standers: the one stood farthest from the desk is the subject; plate it, wait for
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
	m["desk"] = 0
	# The subject is the stander farthest from the gate desk: at boarding the
	# crowd walks to the desk, and beside it every view of the tip was blocked
	# (board 03454587). The others get STAND_WAIT ticks after the first stands.
	var desk := _desk_centre()
	var away := {}
	var first := -1
	var stop := _clock.tick + LIMIT_TICKS
	while _clock.tick < stop and (first < 0 or _clock.tick < first + STAND_WAIT):
		await _step()
		for p in guests:
			if p.stage == Passenger.Stage.STANDING and _stood(p, m):
				var at := _views.node_for(p.id).global_position - desk
				away[p] = Vector2(at.x, at.z).length()
				first = _clock.tick if first < 0 else first
		if away.size() == guests.size():
			break
	# Candidates, best first: a stood roller body clear of the gate desk, then
	# farthest from the desk. Since gate-full spacing the nearest standers stand
	# beside the desk and every view of their roller met the desk (board
	# f115d5da), so each candidate is tried in turn until one plates.
	var order: Array = away.keys()
	var in_desk := {}
	for p: Passenger in order:
		var depth := _desk_depth(_views.carry_on_props().props_of(p.id)["bags"][0])
		in_desk[p] = int(depth[0])
		print(
			(
				(
					"GATE stander id=%d cell %s tick %d stood %.2f m from the desk, "
					+ "DESK_OVERLAP stood roller points in the desk %d (0), deepest %.3f m, "
					+ "of %d roller body points"
				)
				% [p.id, p.at - _offset, _clock.tick, away[p], in_desk[p], depth[1], depth[2]]
			)
		)
		if in_desk[p] > 0:
			_invalid("GATE DESK_OVERLAP: stander %d stood its roller in the gate desk" % p.id)
	order.sort_custom(
		func(a: Passenger, b: Passenger) -> bool:
			if (in_desk[a] == 0) != (in_desk[b] == 0):
				return in_desk[a] == 0
			return away[a] > away[b]
	)
	if order.is_empty():
		_invalid("GATE: no stander stood its roller up")
		return {}
	var subject: Passenger = null
	var idle_by: Dictionary = m.get("idle_by", {})
	for p: Passenger in order:
		var mc := _metrics()
		mc["desk"] = 0
		mc["idle_by"] = idle_by
		print("GATE candidate id=%d at tick %d" % [p.id, _clock.tick])
		var last: bool = p == order.back()
		if await _plate_retry("gate_stand", p, mc, Passenger.Stage.STANDING, last):
			subject = p
			m = mc
			break
	if subject == null:
		# Evidence only (not a plate): the standers and the desk from above.
		_cam.look_at_from_position(desk + Vector3(0.0, 5.0, 3.0), desk, Vector3.UP)
		await _frames(2)
		_save(root.get_texture().get_image(), "gate_stand_diag.png")
		return {}
	m["id"] = subject.id
	print("GATE subject id=%d plated at tick %d" % [subject.id, _clock.tick])
	# Held through the wait: fast to two ticks before boarding, watching every
	# HOLD_WATCH_TICKS-th tick of the still hold (each watch costs about a
	# quarter of a second; every tick of the 3300-tick wait ran the probe past
	# 15 minutes) and every tick of the last HOLD_WATCH_TICKS * 2.
	while _clock.tick < subject.boarding_tick - 2 and subject.stage == Passenger.Stage.STANDING:
		_clock.advance(SimClock.STEP)
		await _frames(1)
		var late := _clock.tick >= subject.boarding_tick - HOLD_WATCH_TICKS * 2
		if late or posmod(_clock.tick, HOLD_WATCH_TICKS) == 0:
			_watch(subject, m)
	# The strip follows the first stander whose tip waits for its turn (the
	# turning tip, RollerPark.tip_wait), not always the plated one. Every
	# stander's roller is watched against the desk from here (_step()).
	_board_watch = order.duplicate()
	if not await _tip_strip("gate", order, m, true):
		return {}
	_summary("GATE", m, true)
	return m


## The file walkers turned out on FILE_CELLS; the first whose roller stands
## up in its file is the subject.
func _file_waiter() -> void:
	var walkers: Array[Passenger] = []
	for cell in FILE_CELLS:
		var p := _roller_guest()
		p.stage = Passenger.Stage.TO_EXIT
		p.stage_tick = _clock.tick
		p.at = cell + _offset
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
	if not await _tip_strip("file", [subject], m, false):
		return
	_summary("FILE", m, true)


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
		var inside := _inside(p)
		if inside > 0 and int(m.get("inside_lines", 0)) < 5:
			m["inside_lines"] = int(m.get("inside_lines", 0)) + 1
			print(
				(
					"INSIDE tick %.2f id %d points %d clip %s into %.1f stage %d up %.3f flat %.3f"
					% [
						_clock.tick + _clock.alpha,
						p.id,
						inside,
						s["clip"],
						s["into"],
						p.stage,
						s["up"],
						s["flat"]
					]
				)
			)
		m["inside"] = maxi(m["inside"], inside)
		# The stood roller holds still: its first 30 stood frames are measured.
		if m.has("desk") and int(m.get("desk_n", 0)) < 30:
			m["desk_n"] = int(m.get("desk_n", 0)) + 1
			var desk := _desk_depth(_views.carry_on_props().props_of(p.id)["bags"][0])
			m["desk"] = maxi(int(m["desk"]), desk[0])
			m["desk_m"] = maxf(float(m.get("desk_m", 0.0)), desk[1])
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
## The stood roller's body (not its rods) against the gate desk's meshes:
## [points of the body's surface (sampled every 2 cm) inside a desk mesh,
## the deepest of them from the nearest face of that mesh's box, in metres].
func _desk_depth(bag: Node3D) -> Array:
	var points := _shell_points(bag)
	var count := 0
	var deepest := 0.0
	var desks := _mode.get_node("BuildView").find_children(
		"GateDesk*", "MeshInstance3D", true, false
	)
	if desks.is_empty() or points.is_empty():
		_invalid("DESK_OVERLAP: no gate desk mesh or no roller body points")
	for mi in desks:
		var desk := mi as MeshInstance3D
		var to_local := desk.global_transform.affine_inverse()
		var faces := desk.mesh.get_faces()
		var box := desk.mesh.get_aabb()
		var scale := desk.global_transform.basis.get_scale()
		if not _desk_control.has(desk.name):
			# Control: a point half a metre up in the middle of the counter is inside.
			var probe := Vector3(box.get_center().x, 0.5, box.get_center().z)
			_desk_control[desk.name] = CarryContact._odd(probe, faces)
			print(
				(
					"DESK_CONTROL mesh %s box %s scale %s centre inside %s"
					% [desk.name, box, scale, _desk_control[desk.name]]
				)
			)
		for point in points:
			var lp := to_local * point
			if not box.has_point(lp) or not CarryContact._odd(lp, faces):
				continue
			count += 1
			var lo := (lp - box.position) * scale
			var hi := (box.end - lp) * scale
			deepest = maxf(
				deepest, minf(minf(minf(lo.x, hi.x), minf(lo.y, hi.y)), minf(lo.z, hi.z))
			)
	return [count, deepest, points.size()]


## One frame of the boarding DESK_OVERLAP watch: each of _board_watch's
## standers' roller body against the gate desk (_desk_depth()), every frame
## from boarding until QUEUE_TIP_TICKS + 3 ticks past its tip's end.
func _watch_board_desk() -> void:
	var props := _views.carry_on_props()
	var now := _clock.tick + _clock.alpha
	for c: Passenger in _board_watch:
		var w: Dictionary = _board_desk.get_or_add(
			c.id, {"points": 0, "deepest": 0.0, "frames": 0, "sampled": 0, "end": INF, "at": -1.0}
		)
		if now > w["end"] or c.is_done() or c.stage == Passenger.Stage.APRON:
			continue
		if _views.node_for(c.id) == null or props.props_of(c.id).get("bags", []).is_empty():
			continue
		var bag := props.bag_state(c.id, 0)
		if bag.has("queue_tip") and is_inf(float(w["end"])):
			var tip_end := float(bag["since"]) + float(bag["queue_tip"])
			w["end"] = tip_end + RollerPark.QUEUE_TIP_TICKS + 3.0
			print(
				(
					(
						"GATE BOARD_TIP id %d tip marked at tick %.2f, ends %.2f, stage %d, "
						+ "moving %s, filed_still %s, front %s"
					)
					% [
						c.id,
						now,
						tip_end,
						c.stage,
						c.is_moving(),
						RollerPark.filed_still(_sim, c),
						SecurityLooks.carry_front(_sim, c)
					]
				)
			)
		var depth := _desk_depth(props.props_of(c.id)["bags"][0])
		w["frames"] += 1
		w["sampled"] = maxi(int(w["sampled"]), int(depth[2]))
		if int(depth[0]) > int(w["points"]):
			w["points"] = int(depth[0])
			w["at"] = now
		w["deepest"] = maxf(float(w["deepest"]), float(depth[1]))


## Steps until every watched stander's boarding DESK_OVERLAP window has
## ended (it left the grid or is past its tip's end), at most 600 ticks.
func _board_desk_settle() -> void:
	var stop := _clock.tick + 600
	var open := func(c: Passenger) -> bool:
		var w: Dictionary = _board_desk.get(c.id, {})
		var out := c.is_done() or c.stage == Passenger.Stage.APRON
		return not out and (w.is_empty() or _clock.tick + _clock.alpha <= float(w["end"]))
	while _clock.tick < stop and _board_watch.any(open):
		await _step()


## The boarding DESK_OVERLAP line per gate stander: no roller body point in
## the gate desk from boarding to its tip's end, each measured to that end.
func _board_desk_check() -> void:
	if _board_watch.is_empty():
		_invalid("GATE BOARD_DESK: no stander was watched at boarding")
	for c: Passenger in _board_watch:
		var w: Dictionary = _board_desk.get(c.id, {})
		var out := c.is_done() or c.stage == Passenger.Stage.APRON
		var ended: bool = not w.is_empty() and (out or _clock.tick + _clock.alpha > float(w["end"]))
		print(
			(
				(
					"GATE BOARD_DESK id %d DESK_OVERLAP roller body points in the desk %d (0) "
					+ "at tick %.2f, deepest %.3f m, over %d frames of %d body points, "
					+ "measured to the tip's end %s"
				)
				% [
					c.id,
					w.get("points", 0),
					w.get("at", -1.0),
					w.get("deepest", 0.0),
					w.get("frames", 0),
					w.get("sampled", 0),
					ended
				]
			)
		)
		if int(w.get("frames", 0)) == 0 or not ended:
			_invalid("GATE BOARD_DESK: stander %d not measured to its tip's end" % c.id)
		elif int(w["points"]) > 0:
			_invalid("GATE BOARD_DESK: stander %d's roller went into the gate desk" % c.id)


## The stood roller body's surface (its meshes but the rods'), a point every 2 cm.
func _shell_points(bag: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var rods := _rods(bag)
	for mi in bag.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null or rods.any(func(r: Node) -> bool: return r.is_ancestor_of(inst)):
			continue
		var faces := inst.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := inst.global_transform * faces[i]
			var ab := inst.global_transform * faces[i + 1] - a
			var ac := inst.global_transform * faces[i + 2] - a
			var n := maxi(1, ceili(maxf(ab.length(), ac.length()) / 0.02))
			for u in n + 1:
				for v in n + 1 - u:
					points.append(a + ab * (u / float(n)) + ac * (v / float(n)))
	return points


## Diagnosis only (no plate): four walkers stacked on one cell, as the first
## file plates were; while the last holds its stood roller, BLOCKER lines name
## every other bag drawn within 0.6 m of it.
func _stacked_diag() -> void:
	var walkers: Array[Passenger] = []
	for i in 4:
		var p := _roller_guest()
		p.stage = Passenger.Stage.TO_EXIT
		p.stage_tick = _clock.tick
		p.at = Vector2i(19, 6) + _offset
		walkers.append(p)
	var last := walkers[3]
	var m := _metrics()
	var stop := _clock.tick + 60
	var lines := 0
	while _clock.tick < stop and lines < 12:
		await _step()
		if last.stage == Passenger.Stage.TO_EXIT and _stood(last, m):
			_near_bags(last, _views.carry_on_props().props_of(last.id)["bags"][0])
			lines += 1
	print("STACKED diag: %d stood frames of %d checked" % [lines, last.id])


## Every bag drawn within 0.6 m of `bag` (the subject `p`'s roller): whose it
## is, its stage, move and distance.
func _near_bags(p: Passenger, bag: Node3D) -> void:
	var props := _views.carry_on_props()
	for id in _sim.passenger_ids():
		var bags: Array = props.props_of(id).get("bags", [])
		for i in bags.size():
			var node: Node3D = bags[i]
			var d := node.global_position.distance_to(bag.global_position)
			if node != bag and d < 0.6:
				var other := _sim.get_passenger(id)
				print(
					(
						"BLOCKER near %d: passenger %d bag %d stage %d move %s at %.3f m, cell %s (subject %s)"
						% [
							p.id,
							id,
							i,
							other.stage,
							FloatCheck.move_of(props, id, i),
							d,
							other.at,
							p.at
						]
					)
				)


## `last`: no candidate is left after `p`, so a failure is PROBE_INVALID; else
## it is printed and the caller tries the next one after PLATE_TRIES_EARLY.
func _plate_retry(
	shot: String, p: Passenger, m: Dictionary, stage: Passenger.Stage, last := true
) -> bool:
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
	for attempt in 40 if last else PLATE_TRIES_EARLY:
		if await _plate(shot, p, true) != null:
			return true
		await _step()
		s = _watch(p, m)
		if s.is_empty() or p.stage != stage or s["tipping"]:
			break
	if last:
		_invalid("%s: no valid plate while the roller stood" % shot)
	else:
		print("PLATE %s: no valid plate of %d, next candidate" % [shot, p.id])
	return false


## The first of `candidates` whose roller is marked to tip (its walker walks
## off), watched into `m` if it is m's "id" (else only sampled). `turning`:
## only one whose tip waits for its turn (RollerPark.tip_wait()) counts.
## Returns [passenger, mark tick, turn wait in whole ticks], empty on none.
func _await_tip(label: String, candidates: Array, m: Dictionary, turning: bool) -> Array:
	var stop := _clock.tick + 600
	var skipped := {}
	while _clock.tick < stop:
		await _step()
		for c: Passenger in candidates:
			var s := _watch(c, m) if int(m.get("id", c.id)) == c.id else _sample(c)
			if s.is_empty() or not s["tipping"] or skipped.has(c):
				continue
			var bag := _views.carry_on_props().bag_state(c.id, 0)
			var wait := float(bag["queue_tip"]) - float(s["into"])
			var turn := PassengerTurns.TURN_TICKS if wait > PassengerTurns.TURN_TICKS / 2.0 else 0
			print(
				(
					"TIP %s id %d marked at tick %.2f stage %d: queue_tip %.2f - into %.2f = %.2f, turn %d"
					% [
						label,
						c.id,
						_clock.tick + _clock.alpha,
						c.stage,
						bag["queue_tip"],
						s["into"],
						wait,
						turn
					]
				)
			)
			if turning and turn == 0:
				skipped[c] = true
				continue
			return [c, float(_clock.tick), turn]
		if turning and skipped.size() == candidates.size():
			# No tip waits (seed 2012072536: all five marked at the boarding tick
			# with turn 0): strip the plated one, measuring every stander's turn
			# during its tip (_tip_turns()); TURN then fails.
			var own: Passenger = candidates[0]
			for c: Passenger in candidates:
				own = c if c.id == int(m.get("id", -1)) else own
			print("TIP %s: no stander's tip waits for a turn; strip of id %d" % [label, own.id])
			return [own, float(_clock.tick), 0]
	_invalid("%s: no roller tipped" % label)
	return []


## The tip strip of the first of `candidates` to tip (_await_tip()): a frame
## each tick from the mark, one camera, the turn's upright carry (TURN_TICKS
## frames when its tip waits) then STRIP_FRAMES of the tip; then the TURN,
## CARRY_UPRIGHT, CARRY_CLEAR and REPULLED checks.
func _tip_strip(label: String, candidates: Array, m: Dictionary, turning: bool) -> bool:
	var got := await _await_tip(label, candidates, m, turning)
	if got.is_empty():
		return false
	var p: Passenger = got[0]
	var tip_at: float = got[1]
	var turn: int = got[2]
	var frames := STRIP_FRAMES + turn
	var c := {"up": INF, "flat": 0.0, "free": 0, "gap": INF, "near": "", "points": 0}
	c["yaw0"] = _views.node_for(p.id).global_rotation.y
	c["pos0"] = _views.tick_position(p.id, true)
	# Every candidate's yaw at the mark, for the body's turn during its tip.
	var yaws := {}
	for o: Passenger in candidates:
		if _views.node_for(o.id) != null:
			yaws[o] = [_views.node_for(o.id).global_rotation.y, 0.0]
	c["yaws"] = yaws
	_strip_refused = 0
	var strip: Array[Image] = []
	var tried := 0
	while _clock.tick < tip_at + turn + RollerPark.QUEUE_TIP_TICKS + 16:
		# Frame k is tried on each third of tick k until one shows the bag body
		# (a walker crossing the view can hide it for a frame), else skipped.
		var now := _clock.tick + _clock.alpha
		if now < tip_at + turn + RollerPark.QUEUE_TIP_TICKS:
			_carry(p, c, now < tip_at + turn)
			for o: Passenger in yaws:
				var node := _views.node_for(o.id)
				if node != null:
					var off := absf(angle_difference(float(yaws[o][0]), node.global_rotation.y))
					yaws[o][1] = maxf(float(yaws[o][1]), off)
		if tried == turn and not c.has("yaw1"):
			c["yaw1"] = _views.node_for(p.id).global_rotation.y
			c["pos1"] = _views.tick_position(p.id, true)
		if tried < frames and now >= tip_at + tried:
			var img := await _plate(
				"%s_tip_%d" % [label, tried], p, tried == 0 and strip.is_empty(), false
			)
			if img != null:
				strip.append(img)
			if img != null or now + 0.34 >= tip_at + tried + 1.0:
				tried += 1
		await _step()
		var s := _watch(p, m)
		var settle := tip_at + turn + ceili(RollerPark.QUEUE_TIP_TICKS) + 3
		if not s.is_empty() and _clock.tick >= settle:
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
	# The measures print whatever the strip's frames (a strip short of frames
	# still says whether the body turned during its tip).
	if turning:
		_carry_check(label, p, c, turn)
	if strip.size() < frames:
		_invalid(
			(
				"%s tip strip has %d of %d frames (%d of %d refused views spent)"
				% [label, strip.size(), frames, _strip_refused, STRIP_REFUSALS]
			)
		)
		return false
	if turn > 0:
		var carry := _contact_sheet(strip.slice(0, turn), 3)
		_save(carry, "%s_carry_strip.png" % label)
		_sheet.append(carry)
		_plates += 1
	var sheet := _contact_sheet(strip.slice(turn), 3)
	_save(sheet, "%s_tip_strip.png" % label)
	_sheet.append(sheet)
	_plates += 1
	return true


## One frame of `p`'s strip into `c`: on the upright carry (`carrying`, before
## the tip) its lowest uprightness, farthest axle from the feet and frames not
## held; to the tip's end the roller body's nearest built piece (_build_gap()).
func _carry(p: Passenger, c: Dictionary, carrying: bool) -> void:
	var s := _sample(p)
	if s.is_empty():
		return
	if carrying:
		c["up"] = minf(c["up"], s["up"])
		c["flat"] = maxf(c["flat"], s["flat"])
		c["free"] += int(s["held"] < 0)
		c["carry_n"] = int(c.get("carry_n", 0)) + 1
	var gap := _build_gap(_views.carry_on_props().props_of(p.id)["bags"][0])
	if gap["gap"] < c["gap"]:
		c["gap"] = gap["gap"]
		c["near"] = gap["near"]
		c["gap_at"] = _clock.tick + _clock.alpha
	c["points"] = maxi(c["points"], gap["points"])


## TURN, CARRY_UPRIGHT and CARRY_CLEAR of the turning strip subject `p`.
func _carry_check(label: String, p: Passenger, c: Dictionary, turn: int) -> void:
	# Each stander's largest body turn from the strip's mark to its tip's end:
	# over TIP_TURN_RAD with no wait is the swing tip_wait() is there to stop.
	for o: Passenger in c["yaws"]:
		print(
			(
				"%s TIP_TURN id %d body turned at most %.3f rad from the mark to the tip's end (%s)"
				% [label, o.id, c["yaws"][o][1], "strip" if o == p else "other"]
			)
		)
	var turned := absf(angle_difference(float(c["yaw0"]), float(c.get("yaw1", c["yaw0"]))))
	print(
		(
			"%s TURN id %d tip waited %d ticks (%d), body turned %.3f rad over them (> %.2f)"
			% [label, p.id, turn, PassengerTurns.TURN_TICKS, turned, RollerPark.TIP_TURN_RAD]
		)
	)
	var walked := Vector3(c["pos0"]).distance_to(Vector3(c.get("pos1", c["pos0"])))
	print(
		(
			"%s TURN id %d tick position moved %.3f m from the mark to the tip's start (> %.2f)"
			% [label, p.id, walked, STILL_WALK_M]
		)
	)
	if walked <= STILL_WALK_M:
		_invalid(
			(
				"%s TIP_ON_STILL_WALKER id %d: its roller tips, its body has not set off"
				% [label, p.id]
			)
		)
	if turn != PassengerTurns.TURN_TICKS or turned <= RollerPark.TIP_TURN_RAD:
		_invalid("%s TURN: the strip subject did not turn before its tip" % label)
	print(
		(
			(
				"%s CARRY_UPRIGHT %d carry frames: lowest up %.3f (>= %.2f), "
				+ "axle at most %.3f m from the feet (<= %.2f), frames not held %d (0)"
			)
			% [label, c.get("carry_n", 0), c["up"], UPRIGHT_DOT, c["flat"], BESIDE_M, c["free"]]
		)
	)
	if int(c.get("carry_n", 0)) == 0 or c["up"] < UPRIGHT_DOT or c["free"] > 0:
		_invalid("%s CARRY_UPRIGHT: the roller was not carried upright" % label)
	if c["flat"] > BESIDE_M:
		_invalid("%s CARRY_UPRIGHT: the roller left the body's side" % label)
	print(
		(
			(
				"%s CARRY_CLEAR carry and tip: nearest built piece %s, box gap %.3f m at tick %.2f; "
				+ "roller body points inside built meshes %d (0)"
			)
			% [label, c["near"], c["gap"], c.get("gap_at", -1.0), c["points"]]
		)
	)
	if c["near"] == "":
		_invalid("%s CARRY_CLEAR: no built piece measured" % label)
	elif c["points"] > 0:
		_invalid("%s CARRY_CLEAR: the roller went into %s" % [label, c["near"]])


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
	if m.has("desk"):
		print(
			(
				"%s DESK_OVERLAP stood roller body points inside the gate desk %d, deepest %.3f m"
				% [label, m["desk"], m.get("desk_m", 0.0)]
			)
		)
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
	if not _board_watch.is_empty():
		_watch_board_desk()


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
		# A strip: low on the roller's side first, away from the crowd at the desk
		# ahead, so the hand on the bar shows as well as the bag body (board
		# 03454587: from the steep views the tip did not show); steep views last.
		var out := side.normalized()
		var fwd := ahead.normalized()
		aways = [
			[out, STRIP_LOW_M],
			[(out * 1.3 - fwd * 0.6).normalized(), STRIP_LOW_M],
			[(out * 1.3 + fwd * 0.6).normalized(), STRIP_LOW_M],
			[out, 1.6],
		]
		aways += [[(-fwd * 0.8 + out * 1.3).normalized(), 2.6], [out, 2.6]]
		# Over the heads of the standers on the spots beside it (seed 2012072536
		# and the first run of this fix: every lower view crossed a neighbour).
		aways += [[out, 4.5], [(-fwd * 0.8 + out * 1.3).normalized(), 4.5], [-fwd, 4.5]]
	# Then round the subject (board f115d5da: beside the gate desk every view on
	# the roller's side met the desk).
	for up in [1.6, 3.0] if strict else [1.6]:
		for k in RING_VIEWS:
			var a := TAU * k / RING_VIEWS
			aways.append([Vector3(sin(a), 0.0, cos(a)), up])
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	var holder := await _colliders(bag, body)
	# View -1 only turns the camera kept from before to the body. A strip frame
	# tries that, then the other views while refusals are left (walkers crowding
	# the desk at boarding cross it); the view that works is kept.
	var views: Array = range(aways.size()) if fresh else [-1]
	if not fresh and not strict:
		views += range(aways.size())
	var img: Image = null
	for k: int in views:
		if not strict and _strip_refused >= STRIP_REFUSALS:
			break
		if k >= 0:
			var away: Vector3 = aways[k][0]
			var up: float = aways[k][1]
			_cam.look_at_from_position(
				target + away * (3.2 - up * 0.3) + Vector3.UP * up, target, Vector3.UP
			)
		else:
			_cam.look_at(target, Vector3.UP)
		_cam.current = true
		await _frames(2)
		var why := await _check(shot, p, body, bag, strict, holder)
		if why == "":
			img = root.get_texture().get_image()
			_save(img, shot + ".png")
			if fresh and strict:
				_sheet.append(img)
				_plates += 1
			break
		print("PLATE %s view %d refused: %s" % [shot, k, why])
		if not strict:
			_strip_refused += 1
		if fresh and k == 0:
			_near_bags(p, bag)
	holder.free()
	return img


## "" when the plate now shows `p` and its roller body, else why not.
## A strip frame (not `strict`) may have a blocker on some lines (walkers
## passing, its own legs as it turns) if MIN_ON lines land on the bag body and
## the hidden-bag twin differs round it.
func _check(
	shot: String, p: Passenger, body: Node3D, bag: Node3D, strict: bool, holder: Node3D
) -> String:
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
	var hand := int(_views.carry_on_props().bag_state(p.id, 0).get("held_by", -1))
	if not strict:
		# A strip frame shows the hand on the bar too (board 03454587).
		var top := bag.find_child(
			CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER][1], true, false
		)
		points["bar"] = (top as Node3D).global_position
		if hand >= 0:
			points["hand"] = _views.carry_on_props().grip_of(body, hand)
	var flat := {}
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			return "%s at %s is out of frame %s" % [name, at, size]
	var sight := _sight(holder, points)
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
				+ "at=%s body_px=%.0f bag_body_diff=%d unbaked=%d sight=%s"
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
				(holder.get_meta("unbaked") as Array).size(),
				sight
			]
		)
	)
	var seen: bool = sight["on"] >= MIN_ON and sight["control_on"] == 0
	if strict:
		seen = seen and (sight["blockers"] as Array).is_empty()
	else:
		# Every line, to the bag body, the hand and the bar, first meets the
		# subject's own body, its rods or roller, or nothing before the point.
		seen = seen and points.has("hand") and sight["own"] == sight["lines"]
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
		"rod_hits": (lines["blockers"] as Array).size() - blockers.size(),
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


## The gate desk's middle (its meshes' world box).
func _desk_centre() -> Vector3:
	var desks := _mode.get_node("BuildView").find_children(
		"GateDesk*", "MeshInstance3D", true, false
	)
	if desks.is_empty():
		_invalid("GATE: no gate desk mesh found")
		return Vector3.ZERO
	var box := AABB()
	for i in desks.size():
		var mi := desks[i] as MeshInstance3D
		var part := mi.global_transform * mi.get_aabb()
		box = part if i == 0 else box.merge(part)
	return box.get_center()


## `plates` at half size, `cols` to a row.
func _contact_sheet(plates: Array[Image], cols := 2) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var rows := ceili(plates.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % cols), h * (i / cols)))
	return sheet


## The roller body's (not its rods') nearest built piece that stands off the
## floor (BuildView meshes and multimesh instances FLOOR_TOP_M tall or more), the
## gap between their world boxes (0 when they overlap), and the body's surface
## points inside the meshes it overlaps (parity, CarryContact):
## {near, gap, points}.
func _build_gap(bag: Node3D) -> Dictionary:
	var shell := _shell_box(bag)
	var out := {"near": "", "gap": INF, "points": 0}
	var pieces: Array = []
	var view := _mode.get_node("BuildView")
	for mi in view.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh != null and inst.is_visible_in_tree():
			pieces.append([inst.name, inst.mesh, inst.global_transform])
	for mmi in view.find_children("*", "MultiMeshInstance3D", true, false):
		var multi := mmi as MultiMeshInstance3D
		if multi.multimesh == null or multi.multimesh.mesh == null:
			continue
		if not multi.is_visible_in_tree():
			continue
		var mm := multi.multimesh
		var count := (
			mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		)
		for i in count:
			pieces.append(
				[multi.name, mm.mesh, multi.global_transform * mm.get_instance_transform(i)]
			)
	var points := PackedVector3Array()
	for piece: Array in pieces:
		var mesh: Mesh = piece[1]
		var xf: Transform3D = piece[2]
		var box := xf * mesh.get_aabb()
		if box.size.y < FLOOR_TOP_M:
			continue
		var gap := _box_gap(shell, box)
		if gap < out["gap"]:
			out["gap"] = gap
			out["near"] = str(piece[0])
		if gap > 0.0:
			continue
		if points.is_empty():
			points = _shell_points(bag)
		var to_local := xf.affine_inverse()
		var faces := mesh.get_faces()
		for point in points:
			var lp := to_local * point
			if mesh.get_aabb().has_point(lp) and CarryContact._odd(lp, faces):
				out["points"] += 1
	return out


## The distance between two boxes, 0 when they overlap.
static func _box_gap(a: AABB, b: AABB) -> float:
	var d := Vector3.ZERO
	for axis in 3:
		d[axis] = maxf(maxf(b.position[axis] - a.end[axis], a.position[axis] - b.end[axis]), 0.0)
	return d.length()


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
