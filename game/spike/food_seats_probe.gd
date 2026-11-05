extends SceneTree
## Windowed probe of guests sitting down in the real game at the restaurant
## booth's four seats (two at each open end of the benches) and on the bar
## counter's two stools (board 64ee4dc0). For each piece the probe boots
## main.tscn, builds the reference terminal with two venues (CafeTestLayout: a
## restaurant with a booth, or a bar with only a bar counter), opens the
## airport and sends guests one at a time; each is kept on its seat once
## seated, so the next takes another seat. Other passengers are kept from the
## venues. From the guest's walk to its seat the clock is stepped a third of a
## tick a frame, with --fixed-fps 60, so the clips play in step with the sim.
##
## Checks, each printing the values it compared:
##   SIT_INSIDE: on every frame from the start of the sit-down to SETTLE_TICKS
##     after it, the body points (the posed mesh) inside a part of the seat's
##     piece, by part (end_panel, table, counter, cushion, seat). Must be none.
##   SEAT_GAP: seated still, the least outward distance of a body point from
##     the seat's own cushion; over FLOAT_M the guest floats. HIP_ABOVE prints
##     the hips bone over the cushion top.
##   CONTROL: seated still, the same tests see the body lifted LIFT_M (gap over
##     FLOAT_M), stepped back into the seat back (points inside) and, at the
##     booth, sideways into its end panel or, at the bar, forward into the
##     counter (points inside that part). A control that sees nothing fails.
##   BAG_INSIDE (a guest pulling a roller): on the same frames, the roller's
##     mesh points inside a part of the piece. Printed, not judged: where the
##     roller lies is RollerPark's.
## Plates (tools/blender/out/<--out, default food-seats>/):
## sitdown_<piece>_<seat>_strip.png (the sit-down at STRIP_TICKS, or
## ROLLER_STRIP_TICKS for a roller guest), sitdown_<piece>_<seat>_seated.png and
## a contact sheet. Before a save the body's bounds (and a roller guest's
## roller's) project inside the plate with a margin, and a twin with the body
## (or the roller) hidden differs over at least SEEN_SHARE of its box on screen
## (in frame is not visible). Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --fixed-fps 60 \
##     --path game -s res://spike/food_seats_probe.gd \
##     [-- --seed=N --out=DIR --subjects=booth,booth_alt]

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const OUT_REL := "res://../tools/blender/out/"
const OUT_DEFAULT := "food-seats"
## Piece -> [venue, counter, table piece (or empty), the bodies wanted in turn].
## male_02 and the female bodies take a booth step; female_01 and female_05 a
## lift (PassengerLooks.seat_shift()). booth_alt is the booth again with the
## rollers swapped to the other guests (ROLLER_GUESTS), so every seat is sat
## down on with a roller and without one.
const SUBJECTS := {
	"booth": [&"restaurant", &"cafe_counter", &"restaurant_booth", [1, 6, 9, 0]],
	"booth_alt": [&"restaurant", &"cafe_counter", &"restaurant_booth", [1, 6, 9, 0]],
	"booth_b": [&"restaurant", &"cafe_counter", &"restaurant_booth", [2, 4, 7, 10]],
	"booth_c": [&"restaurant", &"cafe_counter", &"restaurant_booth", [3, 5, 8, 11]],
	"bar": [&"bar", &"bar_counter", &"", [6, 9]],
}
const STRIP_TICKS: Array[int] = [0, 3, 6, 9, 12, 15, 18, 21]
## A roller guest's sit-down is CafeSim.STEP_IN_HOLD_TICKS (14) longer at a
## booth: two frames in the hold, then the step in and the sit as STRIP_TICKS
## from the hold's end.
const ROLLER_STRIP_TICKS: Array[int] = [0, 7, 14, 18, 21, 24, 28, 34]
## The guests (by their place in a subject's body list) who pull a roller: one
## at each end of the booth, held at the approach cell while the roller goes
## down (CafeSim.STEP_IN_HOLD_TICKS), then stepping in along the shuffle's path.
const ROLLER_GUESTS := {"booth": [1, 3], "booth_alt": [0, 2]}
## A booth roller guest's stand-up (CafeSim.up_ticks(): STAND_UP_TICKS 24, the
## step out over its last 12, then ParkRecovery.UP_HOLD_TICKS picking the roller
## up at the approach cell), strip frames by ticks into it.
const UP_STRIP_TICKS: Array[int] = [0, 8, 14, 18, 23, 28, 33, 39]
const UP_LIMIT_TICKS := 200
## A guest standing up must have moved at least this far from where it began
## (the positive control that the stand-up ran: a step out is about 0.7 m).
const UP_MOVED_MIN_M := 0.3
## A control guest with no roller stands up over STAND_UP_TICKS (24).
const CONTROL_UP_STRIP_TICKS: Array[int] = [0, 4, 8, 12, 15, 18, 20, 23]
## Guests with no roller (by place in the body list) who stand up too, as the
## control for a roller guest's stand-up at the same seat (UP_INSIDE).
const UP_CONTROLS := {"booth_alt": [1]}
## Subjects whose every guest with no roller stands up too (measured only, no
## strip), to find which seats and bodies read UP_INSIDE (board 17b87a51).
const UP_ALL: Array[String] = ["booth", "booth_alt", "booth_b", "booth_c"]
## Subjects measured only: their sit-downs and stand-ups are counted (SIT_INSIDE,
## UP_INSIDE) but take no plates, so a sit strip's frame hidden by a walker
## does not fail the run.
const MEASURE_ONLY: Array[String] = ["booth_b", "booth_c"]
## A roller park bends the back at most about 45 degrees (ruling
## roller-park-stoop-cap; park_recovery_plates_probe TORSO).
const TORSO_MAX_DEG := 46.0
## A wall's height, for the roller-in-wall count (above any roller).
const WALL_HEIGHT_M := 3.0
## The roller's move in the world in one frame (a third of a tick) growing by
## more than this over the frame before (a stop at a move's end is not a
## jump), from the frame before the sit-down
## on, is a jump (BAG_STEP; park_recovery_plates_probe's LOSS_KINK_M): a walk's
## pull moves it 0.033 m a frame and the park's own roll eases up to 0.13 m a
## frame by about 0.03 a frame, while 7648d56's push of the start out of a
## wall moved it 0.272 m in one frame.
const BAG_KINK_M := 0.05
const SETTLE_TICKS := 6
const LIMIT_TICKS := 2400
const MARGIN_PX := 8.0
const SEEN_SHARE := 0.15
const TILE := 320
const OVERLAP_SLACK_M := 0.002
const FLOAT_M := 0.03
const LIFT_M := 0.1
## A piece part whose top is in this height band and that is thinner than
## 0.2 m is a cushion.
const PAN_TOP_RANGE := Vector2(0.45, 0.6)

var _seed := 0
var _measure_only := false
## --subjects=a,b: run only these SUBJECTS (all when empty).
var _only := PackedStringArray()
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _mine := {}
var _sheet: Array[Image] = []
var _plates := 0
var _seats_done := 0
## UP_INSIDE body points per stand-up label, for _judge_up_controls().
var _up_points := {}


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	var out := OUT_DEFAULT
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		if arg.begins_with("--subjects="):
			_only = arg.get_slice("=", 1).split(",")
	_out_dir = ProjectSettings.globalize_path(OUT_REL + out).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print(
		(
			"PROBE sim_seed=%d out_dir=%s fixed_fps=%d"
			% [_seed, _out_dir, Engine.physics_ticks_per_second]
		)
	)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return false


func _run() -> void:
	var wanted := 0
	for subject: String in SUBJECTS:
		if not _only.is_empty() and subject not in _only:
			continue
		wanted += (SUBJECTS[subject][3] as Array).size()
		if await _boot(subject):
			await _watch(subject)
		_main.queue_free()
		_cam = null
		await _frames(3)
	_judge_up_controls()
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "sitdown_contact_sheet.png")
	print("PROBE done seats=%d of %d plates=%d failed=%s" % [_seats_done, wanted, _plates, _failed])
	quit(1 if _failed or _seats_done < wanted else 0)


func _boot(subject: String) -> bool:
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
	var spec: Array = SUBJECTS[subject]
	var table: StringName = spec[2]
	var ids := CafeTestLayout.build(
		_mode.grid, false, spec[0], table != &"", spec[1], table if table != &"" else &"cafe_table"
	)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("%s: the gate desk was refused" % subject)
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.cafes.refresh()
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_mine.clear()
	# Only the probe's guests go to a venue.
	_clock.ticked.connect(_keep_others_away)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	var cafe := _sim.cafes.layout.cafe(ids["air_room"])
	print(
		(
			"PROBE %s ids=%s hired=%d opened tick=%d seats=%d"
			% [subject, ids, hired, _clock.tick, (cafe.get("seats", []) as Array).size()]
		)
	)
	if hired == 0 or doors < 0 or cafe.is_empty():
		_invalid("%s: the airport did not open or the venue has no seats" % subject)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	return true


func _keep_others_away(_tick: int) -> void:
	for id in _sim.passenger_ids():
		if not _mine.has(id):
			ToiletTestLayout.calm(_sim.get_passenger(id))


## An airside guest of body `body` (pulling one roller with `roller`) if one
## turns up in a few spawns (else the last spawned), walking to its gate and
## asked to the venue.
func _guest(body: int, roller: bool) -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		var id := _sim.spawn_now(
			FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0), floori(body / 6.0)
		)
		p = _sim.get_passenger(id)
		ToiletTestLayout.calm(p)
		p.carry_on = 1 if roller else 0
		var has := not roller or SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER
		if has and PassengerLooks.body_of(p.id, p.variant) == body:
			break
		p.carry_on = 0
	_mine[p.id] = true
	if roller and p.carry_on == 0:
		_invalid("no roller guest of body %d turned up" % body)
		return null
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	_clock.ticked.connect(func(_t: int) -> void: p.late = false)
	if not _sim.cafes.try_visit(p):
		_invalid("guest %d: the visit was refused" % p.id)
		return null
	return p


func _watch(subject: String) -> void:
	_measure_only = subject in MEASURE_ONLY
	var bodies: Array = SUBJECTS[subject][3]
	var risers: Array = []
	for i in bodies.size():
		var roller: bool = i in ROLLER_GUESTS.get(subject, [])
		var p := _guest(bodies[i], roller)
		if p == null:
			return
		var visit := _sim.cafes.visit_of(p.id)
		var seat: Dictionary = visit.seat
		var label := "%s_%s" % [subject, String(seat.get("key", "?")).replace(":", "-")]
		if roller:
			label += "_roller"
		print(
			(
				"GUEST %s id=%d body=%s seat=%s approach=%s root=%s facing=%s"
				% [
					label,
					p.id,
					PassengerLooks.BODIES[PassengerLooks.body_of(p.id, p.variant)],
					seat.get("cell"),
					seat.get("approach"),
					BuildObjectDef.seat_root_world(_sim.grid, seat),
					seat.get("facing"),
				]
			)
		)
		var stop := _clock.tick + LIMIT_TICKS
		while _clock.tick < stop and p.stage != Passenger.Stage.CAFE_TO_SEAT:
			_clock.advance(SimClock.STEP)
			if _clock.tick % 10 == 0:
				await process_frame
		if p.stage != Passenger.Stage.CAFE_TO_SEAT:
			_invalid("%s: never walked to its seat (stage %d)" % [label, p.stage])
			return
		await _sit(label, p, visit, roller)
		# Kept on its seat while the next guest comes.
		visit.dwell_end = _clock.tick + 1000000
		visit.deadline = _clock.tick + 1000000
		if roller or i in UP_CONTROLS.get(subject, []) or subject in UP_ALL:
			var strip: bool = roller or i in UP_CONTROLS.get(subject, [])
			risers.append([label, p, visit, roller, strip, bodies[i]])
	# Once every seat is taken (so no newcomer takes a freed one), each roller
	# guest, and each control guest with no roller, stands up and steps out.
	for riser: Array in risers:
		await _stand(riser[0], riser[1], riser[2], riser[3], riser[4], riser[5])


## Stands guest `p` up from its seat and steps it until it has set off (or
## UP_LIMIT_TICKS), measuring every frame the body inside the piece
## (UP_INSIDE) and, with a `roller`, the roller inside the piece
## (UP_BAG_INSIDE) and the walls (UP_BAG_IN_WALL), the back's stoop (TORSO)
## and the hand on its bag (FLOAT and GRIP_ON, FloatCheck), and taking the
## strip at UP_STRIP_TICKS (CONTROL_UP_STRIP_TICKS with no roller).
func _stand(
	label: String, p: Passenger, visit: CafeVisit, roller: bool, with_strip: bool, body_index: int
) -> void:
	var piece := (_mode.get_node("BuildView") as BuildView).object_node(visit.seat["object_id"])
	var frame := _seat_frame(visit.seat)
	var islands := _islands(piece, frame)
	var walls := _walls_near(visit.seat["approach"])
	var ticks: Array[int] = []
	if with_strip:
		ticks = UP_STRIP_TICKS if roller else CONTROL_UP_STRIP_TICKS
	_aim(frame, visit.seat)
	visit.dwell_end = _clock.tick + 1
	var strip: Array[Image] = []
	var worst := {}
	var bag_worst := {}
	var wall_worst := {}
	var torso := {"deg": 0.0, "k": -1}
	var counts := FloatCheck.float_counts()
	var frames := 0
	var up_from := -1
	var missed := 0
	var start_at := Vector3.INF
	var moved := 0.0
	var stop := _clock.tick + UP_LIMIT_TICKS
	while _clock.tick < stop:
		_clock.advance(SimClock.STEP / 3.0)
		await _frames(1)
		if p.stage == Passenger.Stage.CAFE_SEATED:
			continue
		if p.stage != Passenger.Stage.CAFE_STANDING_UP:
			break
		if up_from < 0:
			up_from = p.stage_tick
		var body := _views.node_for(p.id)
		var bag := _bag_of(p) if roller else null
		if body == null or (roller and bag == null):
			_invalid("%s: no body or roller drawn standing up" % label)
			return
		var k := _clock.tick - up_from
		var at := "k%d+%.2f" % [k, _clock.alpha]
		frames += 1
		if start_at == Vector3.INF:
			start_at = body.global_position
		moved = maxf(moved, body.global_position.distance_to(start_at))
		var hits := _overlap(_points(body), islands)
		if not hits.is_empty():
			worst[at] = hits
		if bag != null:
			var in_piece := _overlap(_mesh_points(bag), islands)
			if not in_piece.is_empty():
				bag_worst[at] = in_piece
			var in_wall := _in_walls(_mesh_points(bag), walls)
			if in_wall > 0:
				wall_worst[at] = in_wall
			var rig: Dictionary = body.get_meta(&"carry_rig", {})
			if not rig.is_empty():
				var deg := (rig["stoop"] as CarryStoop).bent * CarryStoop.STOOP_DEGREES
				if deg > float(torso["deg"]):
					torso = {"deg": deg, "k": k}
			FloatCheck.watch_float(_sim, _views, counts)
		if strip.size() < ticks.size() and k >= ticks[strip.size()]:
			var shot := await _shot("%s_up_k%d" % [label, k], body, bag)
			strip.append(shot)
			missed += 1 if shot == null else 0
	var points := 0
	for key: String in worst:
		points += _sum(worst[key])
	_up_points[label] = points
	var reached := up_from >= 0
	var panel := 0
	for key: String in worst:
		panel += int((worst[key] as Dictionary).get("end_panel", 0))
	print(
		(
			"UP_TABLE %s body=%d roller=%s points=%d end_panel=%d moved=%.2f stage_reached=%s"
			% [label, body_index, roller, points, panel, moved, reached]
		)
	)
	print(
		(
			"UP_INSIDE %s frames=%d frames_inside=%d points=%d %s"
			% [label, frames, worst.size(), points, worst]
		)
	)
	if up_from < 0 or moved < UP_MOVED_MIN_M:
		_invalid("%s: never stood up (moved %.2f m)" % [label, moved])
	if roller:
		print(
			(
				"UP_BAG_INSIDE %s frames=%d frames_inside=%d %s"
				% [label, frames, bag_worst.size(), bag_worst]
			)
		)
		print(
			(
				"UP_BAG_IN_WALL %s walls=%d frames_inside=%d %s"
				% [label, walls.size(), wall_worst.size(), wall_worst]
			)
		)
		print("TORSO %s largest stoop bend %.1f deg at k%d" % [label, torso["deg"], torso["k"]])
		print("HAND %s %s" % [label, FloatCheck.float_report(counts)])
		if not bag_worst.is_empty() or not wall_worst.is_empty():
			_invalid("%s: the roller inside the piece or a wall standing up" % label)
		if float(torso["deg"]) <= 0.0 or float(torso["deg"]) > TORSO_MAX_DEG:
			_invalid("%s: the stoop bent the back %.1f degrees" % [label, torso["deg"]])
		if int(counts["float"]) > 0 or int(counts["grip_off"]) > 0:
			_invalid("%s: a bag floats or the hand is off its grip standing up" % label)
	if strip.size() < ticks.size() or missed > 0:
		_invalid(
			(
				"%s: %d of %d stand-up frames, %d unproven"
				% [label, strip.size(), ticks.size(), missed]
			)
		)
		return
	if with_strip:
		_save(_row(strip), "standup_%s_strip.png" % label)


## A roller guest's UP_INSIDE may only match its seat's control guest's with no
## roller (UP_CONTROLS): body points stepping out where a guest with no roller
## reads the same are the step out's own, not the roller's.
func _judge_up_controls() -> void:
	for label: String in _up_points:
		if not label.ends_with("_roller") or int(_up_points[label]) == 0:
			continue
		var seat := label.get_slice("_", label.get_slice_count("_") - 2)
		var control := -1
		for other: String in _up_points:
			if not other.ends_with("_roller") and other.ends_with("_" + seat):
				control = int(_up_points[other])
		print("UP_CONTROL %s points=%d control_points=%d" % [label, _up_points[label], control])
		if control <= 0:
			_invalid("%s: body points stepping out, with no control reading them" % label)


## The walls (an AABB each, world) on the edges of the cells within two of
## `cell`.
func _walls_near(cell: Vector2i) -> Array[AABB]:
	var out: Array[AABB] = []
	var half := BuildView.WALL_THICKNESS / 2.0
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var at := cell + Vector2i(dx, dy)
			for side in 4:
				if not _mode.grid.has_wall(at, side):
					continue
				var step: Vector2i = BuildGrid.SIDE_STEP[side]
				var mid := _mode.grid.cell_to_world(at) + Vector3(step.x, 0.0, step.y) * 0.5
				var size := Vector3(
					1.0 + 2.0 * half if step.x == 0 else 2.0 * half,
					WALL_HEIGHT_M,
					1.0 + 2.0 * half if step.y == 0 else 2.0 * half
				)
				out.append(AABB(mid - Vector3(size.x / 2.0, 0.0, size.z / 2.0), size))
	return out


## How many of `points` lie inside any of `walls`.
func _in_walls(points: PackedVector3Array, walls: Array[AABB]) -> int:
	var inside := 0
	for at in points:
		for wall in walls:
			if wall.has_point(at):
				inside += 1
				break
	return inside


## Steps the guest from its walk to the seat to SETTLE_TICKS after it is
## seated, measuring every frame and taking the strip and the still.
func _sit(label: String, p: Passenger, visit: CafeVisit, roller: bool) -> void:
	var ticks: Array[int] = []
	if not _measure_only:
		ticks = ROLLER_STRIP_TICKS if roller else STRIP_TICKS
	var bag_worst := {}
	var wall_worst := {}
	var walls := _walls_near(visit.seat["approach"])
	var wall_easing := {}
	var last_bag := Vector3.INF
	var last_step := -1.0
	var jumps := {}
	var step_max := 0.0
	var piece := (_mode.get_node("BuildView") as BuildView).object_node(visit.seat["object_id"])
	var frame := _seat_frame(visit.seat)
	var islands := _islands(piece, frame)
	var strip: Array[Image] = []
	var worst := {}
	var frames := 0
	var seated_at := -1
	var sit_from := -1
	var missed := 0
	_aim(frame, visit.seat)
	var stop := _clock.tick + LIMIT_TICKS
	while _clock.tick < stop:
		_clock.advance(SimClock.STEP / 3.0)
		await _frames(1)
		var body := _views.node_for(p.id)
		if body == null:
			_invalid("%s: no body drawn" % label)
			return
		if p.stage == Passenger.Stage.CAFE_TO_SEAT:
			# The roller's place the frame before the sit-down, for BAG_STEP.
			var pulled := _bag_of(p) if roller else null
			if pulled != null and last_bag != Vector3.INF:
				last_step = pulled.global_position.distance_to(last_bag)
			last_bag = pulled.global_position if pulled != null else Vector3.INF
			continue
		if sit_from < 0:
			sit_from = p.stage_tick
		if p.stage == Passenger.Stage.CAFE_SEATED and seated_at < 0:
			seated_at = _clock.tick
		var k := _clock.tick - sit_from
		var hits := _overlap(_points(body), islands)
		frames += 1
		if not hits.is_empty():
			var at := "k%d+%.2f" % [k, _clock.alpha]
			worst[at] = hits
		var bag := _bag_of(p) if roller else null
		if roller and bag == null:
			_invalid("%s: no roller drawn" % label)
			return
		if bag != null:
			var in_piece := _overlap(_mesh_points(bag), islands)
			if not in_piece.is_empty():
				bag_worst["k%d+%.2f" % [k, _clock.alpha]] = in_piece
			var in_wall := _in_walls(_mesh_points(bag), walls)
			# A set-down that starts in a wall (the walk's pull trail, board
			# 578435a7) eases out over BoothRoller.EASE_TICKS: reported, not judged.
			var easing := k + _clock.alpha < BoothRoller.EASE_TICKS
			if in_wall > 0 and easing:
				wall_easing["k%d+%.2f" % [k, _clock.alpha]] = in_wall
			elif in_wall > 0:
				wall_worst["k%d+%.2f" % [k, _clock.alpha]] = in_wall
			if last_bag != Vector3.INF:
				var step := bag.global_position.distance_to(last_bag)
				step_max = maxf(step_max, step)
				if last_step >= 0.0 and step - last_step > BAG_KINK_M:
					jumps["k%d+%.2f" % [k, _clock.alpha]] = snappedf(step, 0.001)
				last_step = step
			last_bag = bag.global_position
		var due := strip.size() < ticks.size() and k >= ticks[strip.size()]
		if due and p.stage == Passenger.Stage.CAFE_SITTING_DOWN:
			# A roller strip's first frame is the first in which the roller is in
			# clear view before its second frame is due: a walker arriving can hide
			# the roller it pulls behind it (7% seen at 13-3, k0).
			var retry := bag != null and strip.is_empty() and k < ticks[1]
			var shot := await _shot("%s_k%d" % [label, k], body, bag, retry)
			if shot != null or not retry:
				# A frame that fails its proof is left blank, and the strip is not saved.
				strip.append(shot)
				missed += 1 if shot == null else 0
		if seated_at >= 0 and _clock.tick - seated_at >= SETTLE_TICKS:
			break
	if seated_at < 0:
		_invalid("%s: never seated" % label)
		return
	print("SIT_INSIDE %s frames=%d frames_inside=%d %s" % [label, frames, worst.size(), worst])
	if roller:
		print(
			(
				"BAG_INSIDE %s frames=%d frames_inside=%d %s"
				% [label, frames, bag_worst.size(), bag_worst]
			)
		)
	if not worst.is_empty():
		_invalid("%s: body points inside the piece while sitting down or seated" % label)
	if roller:
		print(
			(
				"BAG_IN_WALL %s walls=%d frames_inside=%d %s easing_out=%s"
				% [label, walls.size(), wall_worst.size(), wall_worst, wall_easing]
			)
		)
	if not bag_worst.is_empty() or not wall_worst.is_empty():
		_invalid(
			"%s: roller points inside the piece or a wall while sitting down or seated" % label
		)
	if roller:
		print(
			"BAG_STEP %s largest=%.3f m frames_over=%d %s" % [label, step_max, jumps.size(), jumps]
		)
		if jumps.size() > 0 or step_max <= 0.0:
			_invalid(
				"%s: the roller jumped (or never moved) from the frame before the sit-down" % label
			)
	var body := _views.node_for(p.id)
	_seated_checks(label, body, islands, frame)
	if _measure_only:
		_seats_done += 1
		return
	var still := await _shot("%s_seated" % label, body, _bag_of(p) if roller else null)
	if strip.size() < ticks.size() or missed > 0 or still == null:
		_invalid(
			"%s: %d of %d strip frames, %d unproven" % [label, strip.size(), ticks.size(), missed]
		)
		return
	var tiles: Array[Image] = strip.duplicate()
	_save(_row(tiles), "sitdown_%s_strip.png" % label)
	_save(still, "sitdown_%s_seated.png" % label)
	_sheet.append(still)
	_seats_done += 1


## The node of `p`'s first bag (its roller), or null when none is drawn.
func _bag_of(p: Passenger) -> Node3D:
	return _views.carry_on_props().bag_state(p.id, 0).get("node") as Node3D


## Every vertex of the visible meshes under `node`, in the world.
func _mesh_points(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				out.append(mi.global_transform * v)
	return out


## The seat's frame: origin the seat root, x to the guest's right, z the way
## it faces.
func _seat_frame(seat: Dictionary) -> Transform3D:
	var facing: Vector2i = seat["facing"]
	var f := Vector3(facing.x, 0.0, facing.y).normalized()
	var r := f.cross(Vector3.UP)
	return Transform3D(Basis(r, Vector3.UP, f), BuildObjectDef.seat_root_world(_sim.grid, seat))


func _seated_checks(label: String, body: Node3D, islands: Array, frame: Transform3D) -> void:
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	)
	var own := _own_cushion(islands)
	if own.is_empty():
		_invalid("%s: no cushion at the seat root" % label)
		return
	var top: float = (own["box"] as AABB).end.y
	var gap := _gap(_points(body), own)
	print("SEAT_GAP %s gap=%.3f HIP_ABOVE=%.3f cushion_top=%.3f" % [label, gap, hips.y - top, top])
	if gap > FLOAT_M:
		_invalid("%s floats %.3f m over the cushion" % [label, gap])
	# Controls: the same tests on the body moved where they must see it.
	var at := body.global_position
	body.global_position = at + Vector3.UP * LIFT_M
	var lifted := _gap(_points(body), own)
	body.global_position = at - frame.basis.z * 0.2
	var back := _sum(_overlap(_points(body), islands))
	var side_part := "end_panel"
	var aside := Vector3.ZERO
	if label.begins_with("bar"):
		side_part = "counter"
		aside = frame.basis.z * 0.35
	else:
		# Towards the bench's open end, where the end panel stands.
		var lateral := frame.basis.x * signf(_end_side(islands))
		aside = lateral * 0.45
	body.global_position = at + aside
	var side := _overlap(_points(body), islands)
	body.global_position = at
	print(
		(
			"CONTROL %s lifted_gap=%.3f back_points=%d %s_points=%d %s"
			% [label, lifted, back, side_part, side.get(side_part, 0), side]
		)
	)
	if lifted <= FLOAT_M or back == 0 or side.get(side_part, 0) == 0:
		_invalid("%s: a control saw nothing" % label)


## The sign (in the seat frame's x) of the end panel nearest the seat root.
func _end_side(islands: Array) -> float:
	var best := INF
	var side := 0.0
	for island: Dictionary in islands:
		if island["part"] == "end_panel" and absf(island["local_x"]) < best:
			best = absf(island["local_x"])
			side = island["local_x"]
	return side


func _own_cushion(islands: Array) -> Dictionary:
	var best := {}
	for island: Dictionary in islands:
		if island["part"] == "cushion" and absf(island["local_x"]) < 0.45:
			if best.is_empty() or absf(island["local_x"]) < absf(best["local_x"]):
				best = island
	return best


# ------------------------------------------------------------ geometry


func _points(body: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(body)
	var baked := mi.bake_mesh_from_current_skeleton_pose()
	var out := PackedVector3Array()
	if baked == null:
		_invalid("%s: the posed body could not be baked" % body.name)
		return out
	for s in baked.get_surface_count():
		for v: Vector3 in baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(mi.global_transform * v)
	return out


func _sum(hits: Dictionary) -> int:
	var total := 0
	for key: String in hits:
		total += hits[key]
	return total


func _overlap(points: PackedVector3Array, islands: Array) -> Dictionary:
	var counts := {}
	for p in points:
		var part := _inside(islands, p)
		if part != "":
			counts[part] = counts.get(part, 0) + 1
	return counts


func _gap(points: PackedVector3Array, island: Dictionary) -> float:
	var gap := INF
	for p in points:
		var out := -INF
		for plane: Array in island["planes"]:
			out = maxf(out, (p - (plane[0] as Vector3)).dot(plane[1]))
		gap = minf(gap, out)
	return gap


## The piece's welded mesh islands in world space, each named by its bounds in
## the seat frame: a thin tall part to a side is the booth's end_panel, a part
## ahead of the root the table or the counter, a thin part with its top at
## cushion height a cushion, anything else seat.
func _islands(piece: Node3D, frame: Transform3D) -> Array:
	var out := []
	var to_seat := frame.affine_inverse()
	var bar := String(piece.get_meta("record", {}).get("def", "")) == "bar_counter"
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		var tris := faces.size() / 3
		var parent := {}
		for t in tris:
			var a := _root_of(parent, _weld(faces[t * 3]))
			for c in [1, 2]:
				var b := _root_of(parent, _weld(faces[t * 3 + c]))
				if a != b:
					parent[b] = a
		var groups := {}
		for t in tris:
			var r := _root_of(parent, _weld(faces[t * 3]))
			if not groups.has(r):
				groups[r] = []
			(groups[r] as Array).append(t)
		for r: Vector3i in groups:
			var pts := PackedVector3Array()
			for t: int in groups[r]:
				for c in 3:
					pts.append(mi.global_transform * faces[t * 3 + c])
			var box := AABB(pts[0], Vector3.ZERO)
			var local := AABB(to_seat * pts[0], Vector3.ZERO)
			for p in pts:
				box = box.expand(p)
				local = local.expand(to_seat * p)
			var centre := box.get_center()
			var planes := []
			for i in range(0, pts.size(), 3):
				var n := (pts[i + 1] - pts[i]).cross(pts[i + 2] - pts[i])
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if n.dot(centre - pts[i]) > 0.0:
					n = -n
				planes.append([pts[i], n])
			var convex := true
			for plane: Array in planes:
				for p in pts:
					if (p - (plane[0] as Vector3)).dot(plane[1]) > 1e-3:
						convex = false
						break
				if not convex:
					break
			var part := "seat"
			var mid := local.get_center()
			if local.size.x < 0.1 and local.size.y > 0.5:
				part = "end_panel"
			elif mid.z > 0.25:
				part = "counter" if bar else "table"
			elif (
				local.end.y > PAN_TOP_RANGE.x
				and local.end.y < PAN_TOP_RANGE.y
				and local.size.y < 0.2
			):
				part = "cushion"
			(
				out
				. append(
					{
						"part": part,
						"planes": planes,
						"convex": convex,
						"tris": pts,
						"box": box,
						"local_x": mid.x,
					}
				)
			)
	var names := {}
	for island: Dictionary in out:
		names[island["part"]] = names.get(island["part"], 0) + 1
	print("ISLANDS %s %s" % [piece.get_meta("record", {}).get("def", "?"), names])
	return out


func _inside_by_parity(tris: PackedVector3Array, p: Vector3) -> bool:
	var o := p + Vector3(1.3e-4, 0.0, 0.7e-4)
	var crossings := 0
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var det := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		if absf(det) < 1e-12:
			continue
		var u := ((o.x - a.x) * (c.z - a.z) - (c.x - a.x) * (o.z - a.z)) / det
		var v := ((b.x - a.x) * (o.z - a.z) - (o.x - a.x) * (b.z - a.z)) / det
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		if a.y + u * (b.y - a.y) + v * (c.y - a.y) > o.y:
			crossings += 1
	return crossings % 2 == 1


func _weld(p: Vector3) -> Vector3i:
	return Vector3i((p * 1000.0).round())


func _root_of(parent: Dictionary, k: Vector3i) -> Vector3i:
	while parent.has(k):
		k = parent[k]
	return k


func _inside(islands: Array, p: Vector3) -> String:
	for island: Dictionary in islands:
		if not (island["box"] as AABB).grow(0.01).has_point(p):
			continue
		if not island["convex"]:
			if _inside_by_parity(island["tris"], p):
				return island["part"]
			continue
		var ok := true
		for plane: Array in island["planes"]:
			if (p - (plane[0] as Vector3)).dot(plane[1]) > -OVERLAP_SLACK_M:
				ok = false
				break
		if ok:
			return island["part"]
	return ""


# ------------------------------------------------------------ plates


## A camera high on the side the guest comes from, a little in front of the
## seat, looking at the seat root: the step in and the hips on the cushion
## show, over the booth's end panel and the table's end.
func _aim(frame: Transform3D, seat: Dictionary) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 40.0
		_main.add_child(_cam)
	var approach := _sim.grid.cell_to_world(seat["approach"]) - frame.origin
	var lateral := approach.dot(frame.basis.x)
	var across := frame.basis.x * (signf(lateral) if absf(lateral) > 0.1 else 1.0)
	var dir := (across * 0.6 + frame.basis.z * 0.5 + Vector3.UP * 1.2).normalized()
	var target := (frame.origin + approach * 0.5) + Vector3.UP * 0.6
	_cam.look_at_from_position(target + dir * 4.6, target, Vector3.UP)
	_cam.current = true
	(_mode.get_node("BuildView") as BuildView).update_cutaway(_cam.global_transform.basis.z)


## The square crop of the window round the subject, proven in frame and seen
## (a twin with the body hidden differs over SEEN_SHARE of its box), and with
## `bag` the same for the bag, or null.
func _shot(name: String, body: Node3D, bag: Node3D = null, quiet := false) -> Image:
	Engine.time_scale = 0.0
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var ok := await _proven(name, img, body, _points(body), quiet)
	if ok and bag != null:
		ok = await _proven(name + "_bag", img, bag, _mesh_points(bag), quiet)
	Engine.time_scale = 1.0
	if not ok:
		return null
	_plates += 1
	var side := mini(img.get_width(), img.get_height())
	return img.get_region(
		Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side)
	)


## Whether `subject` (its points `pts`) is inside the square crop of `img` with
## a margin and seen: a twin with it hidden differs over SEEN_SHARE of its box.
func _proven(
	name: String, img: Image, subject: Node3D, pts: PackedVector3Array, quiet := false
) -> bool:
	var side := mini(img.get_width(), img.get_height())
	var crop := Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side)
	var per_px := _cam.get_viewport().get_visible_rect().size.y / float(img.get_height())
	if pts.is_empty():
		_invalid("%s: no points to prove" % name)
		return false
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in 8:
		var px := _cam.unproject_position(box.get_endpoint(k)) / per_px
		lo = lo.min(px)
		hi = hi.max(px)
	var inside := Rect2(crop).grow(-MARGIN_PX)
	var in_frame := inside.has_point(lo) and inside.has_point(hi)
	subject.visible = false
	var twin := await PlateSight.grab(self, 2)
	subject.visible = true
	await PlateSight.grab(self, 2)
	var rect := Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil())).intersection(crop)
	var seen := PlateSight.differing(img, twin, rect, 2)
	var samples := maxi(1, ceili(rect.size.x / 2.0) * ceili(rect.size.y / 2.0))
	var share := seen / float(samples)
	print(
		(
			"PROOF %s tick=%d box=%s px=%s..%s crop=%s in_frame=%s seen=%d of %d share=%.2f"
			% [
				name,
				_clock.tick,
				box.size,
				lo.round(),
				hi.round(),
				crop,
				in_frame,
				seen,
				samples,
				share
			]
		)
	)
	if not in_frame or share < SEEN_SHARE:
		if quiet:
			print("PROOF_RETRY %s: not in clear view yet" % name)
		else:
			_invalid("%s: the subject is not in frame or not seen" % name)
		return false
	return true


func _row(images: Array[Image]) -> Image:
	var out := Image.create(TILE * images.size(), TILE, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var small := images[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(i * TILE, 0))
	return out


func _contact_sheet(plates: Array[Image]) -> Image:
	var cols := 3
	var rows := ceili(plates.size() / float(cols))
	var out := Image.create(cols * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1))
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(
			small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(i % cols, i / cols) * TILE
		)
	return out


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
