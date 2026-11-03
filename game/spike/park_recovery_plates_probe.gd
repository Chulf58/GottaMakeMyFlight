extends SceneTree
## Windowed plates of a walker collecting its roller after its gate seat went in
## the middle of the park (ParkRecovery, RollerPark "park_low", board
## d425a825). Boots main.tscn with no starter shell, builds the reference
## terminal and its gate desk, hires a member per station and opens the airport
## (anti-pattern a-main-tscn-probe-that-builds-its-own-terminal-at-raw-cells),
## then seats a passenger with one roller at the first gate chair and removes
## the chair by a build edit in the lift of its pull>floor (k 0.15). The clock
## is stepped by hand, a third of a tick a frame (1x).
##
## Plates of the pick-up (floor>pull) that follows, from the roller's side:
##   reach: the first frame the hand is within RollerPark.TAKE_M of the lying
##     bag's handle; take: the frame the hand took it ("park_took");
##   k050: the first frame at k 0.5 or later; before: one frame before the
##     lift's end (BEFORE_K); switch: the first at the lift's
##     end (RollerPark.up_ends().x, the stoop easing into HIPS_ALL); ease1, ease2:
##     a third and two thirds through the ease (EASE_K); walk: the first
##     frame the body is drawn moving.
## Proof before a save: the feet, the head and the bag project inside the frame
## by MARGIN_PX, the body is at least MIN_BODY_PX tall, a twin with the bag alone
## hidden differs by MIN_BAG_PX pixels, and a twin with the
## passenger and its bag hidden differs from the plate by MIN_DIFF_PX pixels
## (in frame is not visible). Otherwise PROBE_INVALID, exit 1. Each plate
## prints k, the grip's distance to the handle and the bar, the handle's height
## and the bag's lowest point.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/park_recovery_plates_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/park-recovery/, or to the directory --out=<dir>
## names. --seated-loss removes the chair once the walker is seated, after the
## park, and watches the bag's move per frame from then on (see _seated_loss).
##
## Hand-swap watch (board 6981b7ac part 3): the probe goes on FOLLOW_TICKS
## (or --follow=N) ticks after the plates, a third of a tick a frame, and
## prints for each frame both hands' grip distances to the roller's handle and
## bar, and the bag and
## both grips as offsets from the walker's origin (not turned with it: a body
## that turns on the spot in one frame would otherwise move everything it
## carries). The hand holding at the first frame after the plates is PINNED: a
## change of the bag's place to the other hand is
## printed as SWAP, and the pinned hand keeps being measured, so a jump of the
## pinned grip or of the bag (JUMP_M in a frame) is the bag or grip moving, and
## a jump only in the "live" hand (CarryLead.hand_of(home) read fresh each frame,
## as the plates do) is the measurement changing hands. The summary prints the
## largest of each.
## The follow also checks every clip change it draws for a jump (_kinks), and
## fails with PROBE_INVALID unless it measured at least one (board 908de167):
## the walker walks off to another chair and sits there, so a follow of
## FOLLOW_TICKS sees walk, run, idle and sit clips change.

const StarterFlight := preload("res://spike/starter_flight.gd")
const FloatCheck := preload("res://spike/carry_float_check.gd")
const OUT_REL := "res://../tools/blender/out/park-recovery"
const MARGIN_PX := 8.0
const MIN_BODY_PX := 300.0
const MIN_DIFF_PX := 2000
## The bag alone (a twin with only it hidden) must change this many pixels, so
## a roller hidden behind the body cannot pass.
const MIN_BAG_PX := 1500
## The stoop's ease from LAY_HIPS to HIPS_ALL after the lift (k), plated at a
## third and two thirds of the way.
const EASE_K := RollerPark.LOW_EASE_TICKS / RollerPark.TICKS_UP
## The camera, in the frame of the park (+z the way the walker faced as it sat
## down), out on the roller's side, and the point it looks at.
const CAM_AT := Vector3(-2.9, 1.3, 1.3)
const LOOK_AT := Vector3(-0.3, 0.8, 0.4)
const LIMIT_TICKS := 400
## "before" is the last frame within this much k of the lift's end (one frame at
## 1x is 1/48), drawn still bending the back first.
const BEFORE_K := 0.03
## A move relative to the walker's origin, in one frame (a third of a tick), above this
## is a jump (walking pulls the bag along smoothly, a few cm a frame at most).
const JUMP_M := 0.03
## The roller moving this much in the world in one frame (a third of a tick)
## after the chair went and before the hand took it is a jump (the bag lies
## still until then), and its move changing by LOSS_KINK_M between two
## frames is a kink (the pick-up's own lift starts at 0.032 m a frame from rest
## and peaks at 0.055 m a frame, measured); either fails --seated-loss
## (_loss_summary()). Frames moving LOSS_PRINT_M or more are printed.
const LOSS_JUMP_M := 0.05
const LOSS_KINK_M := 0.05
const LOSS_PRINT_M := 0.02
## The strip camera's place off the walker (world) and where it looks (--strip).
const STRIP_CAM := Vector3(-0.6, 1.6, 3.6)
const STRIP_LOOK := Vector3(-0.4, 0.7, 0.0)
const STRIP_CELL := Vector2i(480, 270)
## A kink (change of a frame's move against the frame before) of the roller,
## the pinned grip or the grip's gap to the roller's own grip bar, on a frame
## of a swap between the hand and the pull, over this fails the probe
## (SWAP_JUMP), on every swap frame: a clip change crossfades (ClipCrossfade,
## board 908de167), so a frame whose clip changed is checked like any other.
const SWAP_KINK_M := 0.05
## Ticks the follow watch runs after the plates unless --follow=N says
## otherwise: the walker reaches another chair and sits down in about 100.
const FOLLOW_TICKS := 200
## A turn over this in one frame (degrees) fails the probe (PassengerTurns
## eases every turn over 0.3 s).
const TURN_DEG := 20.0
## A walker sitting down at a chair, or seated, drawn with its Spine_01 bone
## more than this under where it is seated (sit_idle, no stoop) fails the
## probe (SEAT_LOW): its hips went under the seat (board 76cb23c0).
const SEAT_DROP_M := 0.05

var _seed := 0
var _follow_ticks := FOLLOW_TICKS
## Clip changes the follow measured for a jump (_kinks), as "from>to@tick".
var _clip_changes: Array[String] = []
## Whether the walker stepped on the tick before this one and on this one, as
## the views read it (tick positions), and the tick last read.
var _stepped := [false, false]
var _stepped_tick := -1
## --no-plates: no image is read or saved (a headless run of the follow watch).
var _no_plates := false
## --worn: the walker also wears a shoulder bag as its second bag (board 6981b7ac part 2).
var _worn := false
## --walk-route: no park; the walker walks from the first gate chair to the
## chair farthest from it by path, round its corners, and sits down there, so
## --strip can draw a walking corner and the turn on the spot to the chair.
var _walk_route := false
## --seated-loss: the chair is removed once the walker is SEATED, after the
## park (board 6981b7ac part 1, decision seat-lost-after-a-roller-park-a-seated-
## passenger-still-stand), not in the lift of the park. From the removal to the
## walk plate the bag's move in the world is watched every frame (_watch_loss(),
## also in the default mode, for comparison); --seated-loss fails the probe on a
## jump or a kink (_loss_summary()).
var _seated_loss := false
var _loss_prev := Vector3.INF
var _loss_last := 0.0
var _loss_before_take := 0.0
var _loss_worst := 0.0
var _loss_kink := 0.0
var _loss_frames := 0
## --strip=A-B[,C-D]: windowed frame strips of every frame from tick A to tick
## B (and C to D), from a camera fixed in the world for the window (STRIP_CAM
## off the walker at the window's first frame), so a turn or a jump shows; each
## frame is proved in frame and seen like a plate, and each window is also
## saved as one contact sheet.
var _strips: Array[Vector2i] = []
## --dump=A-B: the ticks _dump_row() prints (none by default).
var _dump := Vector2i(1, 0)
## The lowest Spine_01 height over the body sitting down or seated, its tick,
## the height seated still (sit_idle, no stoop) and the frames of each.
var _sit := {"low": INF, "tick": -1, "seated": NAN, "frames": 0, "still": 0}
var _strip_cam: Camera3D
var _strip_xf := {}
var _swap_starts := 0
var _reversals := 0
var _swap_worst := {"bag": 0.0, "pin": 0.0, "bar": 0.0, "exempt": 0}
var _strip_imgs := {}
var _strip_done := {}
var _last_yaw := INF
var _worn_prev := {}
var _worn_worst := {
	"w_body": 0.0,
	"w_joint": 0.0,
	"w_world": 0.0,
	"j_world": 0.0,
	"stale": 0.0,
	"turn_frames": 0,
	"turn_body": 0.0,
}
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _p: Passenger
var _cam: Camera3D
var _saved: Array[String] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--follow="):
			_follow_ticks = int(arg.get_slice("=", 1))
		elif arg == "--no-plates":
			_no_plates = true
		elif arg == "--worn":
			_worn = true
		elif arg == "--walk-route":
			_walk_route = true
		elif arg == "--seated-loss":
			_seated_loss = true
		elif arg.begins_with("--strip="):
			for part in arg.get_slice("=", 1).split(","):
				_strips.append(Vector2i(int(part.get_slice("-", 0)), int(part.get_slice("-", 1))))
		elif arg.begins_with("--dump="):
			var span := arg.get_slice("=", 1)
			_dump = Vector2i(int(span.get_slice("-", 0)), int(span.get_slice("-", 1)))
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d out_dir=%s follow=%d" % [_seed, _out_dir, _follow_ticks])
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		if _walk_route:
			await _route_walk()
		else:
			await _collect()
		_finish_strips()
		_seat_summary()
		if _worn:
			_worn_summary()
	print("PROBE done plates=%d failed=%s" % [_saved.size(), _failed])
	var plates_short := _saved.size() < 8 and not _no_plates and not _walk_route
	quit(1 if _failed or plates_short else 0)


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
	var refused := 0
	for result in _mode.grid.apply_batch(
		ReferenceTerminal.edits(ReferenceTerminal.offset_on(_mode.grid))
	):
		refused += int(not result.ok)
	print("PROBE terminal edits refused=%d" % refused)
	if refused > 0 or not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the reference terminal or its gate desk was refused")
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE hired=%d opened tick=%d doors=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	return true


## A passenger with one roller standing at the first gate chair's front, kept
## on time on every tick.
func _walker() -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		p = _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		var second := SecurityLooks.bag_kind(p, 1) == SecurityLooks.Kind.SHOULDER
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER and (second or not _worn):
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 2 if _worn else 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	var seat: Dictionary = _sim.layout.seats[0]
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.seat_object = 0
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _clock.tick + 100000
	_clock.ticked.connect(func(_t: int) -> void: p.late = false)
	print("PROBE walker %d seat %s" % [p.id, seat["cell"]])
	return p


func _collect() -> void:
	_p = _walker()
	for n in 6:
		await _step()
	var seat: Dictionary = _sim.layout.seats[0]
	_p.seat_object = seat["object_id"]
	_p.stage = Passenger.Stage.SITTING_DOWN
	_p.clear_path()
	_p.stage_tick = _sim.tick
	var props := _views.carry_on_props()
	var gone := false
	var wants := ["reach", "take", "k050", "before", "switch", "ease1", "ease2", "walk"]
	var last_body := Vector3.INF
	var limit := _clock.tick + LIMIT_TICKS
	while _clock.tick < limit and not wants.is_empty():
		await _step()
		var body := _views.node_for(_p.id)
		if _worn:
			_watch_worn(props, body)
		await _strip_step(props, body)
		var bag := props.bag_state(_p.id, 0)
		var k := props.transfer_progress(_p.id, 0)
		var moved := body.global_position.distance_to(last_body)
		last_body = body.global_position
		var off_floor: bool = (
			bag.get("park", false) and CarryLead.start_of(bag)[0] == CarryLead.End.REST
		)
		var lost_now := _p.stage == Passenger.Stage.SEATED if _seated_loss else k >= 0.15
		if not gone and bag.get("park", false) and not off_floor and lost_now:
			gone = true
			_mode.grid.apply(BuildEdit.remove_object(seat["object_id"]))
			(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
			print(
				(
					"PROBE seat removed at pull>floor k=%.3f tick %d stage %d"
					% [k, _clock.tick, _p.stage]
				)
			)
		if gone:
			_watch_loss(props, float(bag.get("park_took", -1.0)) >= 0.0)
		if not gone or not off_floor or k >= 1.0:
			continue
		if not bag.get("park_low", false):
			_invalid("the pick-up is not marked park_low")
			return
		var node: Node3D = props.props_of(_p.id)["bags"][0]
		var lead := CarryLead.hand_of(bag["home"])
		var grip := props.grip_of(body, lead)
		var handle := node.global_transform * CarryOnProps.ROLLER_HANDLE
		var took := float(bag.get("park_took", -1.0))
		var shot := ""
		if wants.has("reach") and took < 0.0 and grip.distance_to(handle) <= RollerPark.TAKE_M:
			shot = "reach"
		elif wants.has("take") and took >= 0.0:
			shot = "take"
		elif wants.has("k050") and k >= 0.5:
			shot = "k050"
		elif (
			wants.has("before")
			and k >= RollerPark.up_ends(bag).x - BEFORE_K
			and k < RollerPark.up_ends(bag).x
		):
			shot = "before"
		elif wants.has("switch") and k >= RollerPark.up_ends(bag).x:
			shot = "switch"
		elif wants.has("ease1") and k >= RollerPark.up_ends(bag).x + EASE_K / 3.0:
			shot = "ease1"
		elif wants.has("ease2") and k >= RollerPark.up_ends(bag).x + EASE_K * 2.0 / 3.0:
			shot = "ease2"
		elif (
			wants.has("walk")
			and moved > 0.005
			# The body sliding from the chair to its cell as the seat goes is not the walk.
			and (not _seated_loss or k >= RollerPark.up_ends(bag).y)
		):
			shot = "walk"
		if shot != "":
			wants.erase(shot)
			if _no_plates:
				print("PLATE %s skipped (--no-plates) k=%.3f tick %d" % [shot, k, _clock.tick])
			else:
				await _plate(shot, body, node, bag, k, lead)
	_loss_summary()
	if not wants.is_empty():
		_invalid("plates never reached: %s" % [wants])
	else:
		await _follow(props)


## --walk-route: the walker, standing at the first gate chair's front, walks to
## the chair farthest from it by path and sits down there, a third of a tick a
## frame, with its turns checked and any --strip window drawn (_strip_step).
## Prints the ticks it turned at a walking corner and began to sit down, so
## strip windows can be set on them, and the largest turn in one frame while
## walking on and on the spot.
func _route_walk() -> void:
	_p = _walker()
	for n in 6:
		await _step()
	var best := {}
	var route: Array[Vector2i] = []
	for seat: Dictionary in _sim.layout.seats:
		var path := _sim.grid.find_path(_p.at, seat["front"])
		if path.size() > route.size():
			route = path
			best = seat
	if best.is_empty():
		_invalid("no gate chair has a path from the first one")
		return
	_sim._seat_claims[best["key"]] = _p.id
	_p.seat_object = best["object_id"]
	_p.seat_cell = best["cell"]
	_p.seat_front = best["front"]
	_p.set_path(route)
	print("ROUTE to seat %s, %d cells" % [best["cell"], route.size()])
	var props := _views.carry_on_props()
	var corners: Array[int] = []
	var sat := -1
	var worst := {"walk": 0.0, "spot": 0.0}
	var heading := INF
	var yaw := INF
	var limit := _clock.tick + LIMIT_TICKS
	while _clock.tick < limit and (sat < 0 or _clock.tick < sat + 40):
		var tick := _clock.tick
		await _step()
		var body := _views.node_for(_p.id)
		await _strip_step(props, body)
		if _clock.tick != tick:
			var step := _views.tick_position(_p.id, true) - _views.tick_position(_p.id, false)
			var now := atan2(step.x, step.z) if step.length() > 0.001 else INF
			if is_finite(now) and is_finite(heading) and absf(angle_difference(heading, now)) > 0.5:
				corners.append(_clock.tick)
			heading = now
			if sat < 0 and _p.stage == Passenger.Stage.SITTING_DOWN:
				sat = _clock.tick
		var turn := absf(angle_difference(yaw, body.rotation.y)) if is_finite(yaw) else 0.0
		yaw = body.rotation.y
		var key := "walk" if _stepped[0] and _stepped[1] else "spot"
		worst[key] = maxf(worst[key], rad_to_deg(turn))
	print(
		(
			(
				"ROUTE walking corners at ticks %s, sitting down at tick %d; largest turn a frame"
				% [corners, sat]
			)
			+ " walking on %.1f deg, on the spot %.1f deg" % [worst["walk"], worst["spot"]]
		)
	)
	if corners.is_empty() or sat < 0:
		_invalid("the route walk turned no corner or never sat down")


## This frame's move of the roller in the world since the chair went (`took`:
## the hand has taken it), kept for the largest before the take, the largest
## overall and the largest change of the move between two frames; frames moving
## LOSS_PRINT_M or more are printed.
func _watch_loss(props: CarryOnProps, took: bool) -> void:
	var node: Node3D = props.props_of(_p.id)["bags"][0]
	var at := node.global_position
	if is_finite(_loss_prev.x):
		var move := at.distance_to(_loss_prev)
		_loss_frames += 1
		_loss_worst = maxf(_loss_worst, move)
		_loss_kink = maxf(_loss_kink, absf(move - _loss_last))
		if not took:
			_loss_before_take = maxf(_loss_before_take, move)
		if move >= LOSS_PRINT_M:
			print("LOSS tick=%d bag_move=%.3f took=%s" % [_clock.tick, move, took])
		_loss_last = move
	_loss_prev = at


## The roller's moves since the chair went (_watch_loss()): the largest in a
## frame before the take, overall, and the largest kink. --seated-loss fails
## the probe on a jump, a kink, or no frame measured.
func _loss_summary() -> void:
	print(
		(
			(
				"LOSS summary frames=%d max bag move per frame (world, m): before the take=%.3f"
				% [_loss_frames, _loss_before_take]
			)
			+ " overall=%.3f max kink=%.3f" % [_loss_worst, _loss_kink]
		)
	)
	if not _seated_loss:
		return
	if _loss_frames == 0:
		_invalid("the seated-loss watch measured no frame")
	elif _loss_before_take > LOSS_JUMP_M:
		_invalid("the bag moved %.3f m in a frame before the hand took it" % _loss_before_take)
	elif _loss_kink > LOSS_KINK_M:
		_invalid("the bag's move changed by %.3f m between two frames" % _loss_kink)


## Follows the roller for _follow_ticks more ticks and prints the hand-swap watch
## (see the header): flagged frames, then the largest jump of each measure.
func _follow(props: CarryOnProps) -> void:
	var body := _views.node_for(_p.id)
	var pin := -1
	var prev := {}
	var worst := {"bag": 0.0, "pin": 0.0, "other": 0.0, "live": 0.0, "pin_gap": 0.0}
	for key in ["kink_bag", "kink_bag_clip", "kink_pin", "kink_pin_clip"]:
		worst[key] = 0.0
	var live_switches := 0
	var swaps := 0
	var jumps_pin := 0
	var end := _clock.tick + _follow_ticks
	while _clock.tick < end:
		await _step()
		body = _views.node_for(_p.id)
		await _strip_step(props, body)
		var bag := props.bag_state(_p.id, 0)
		var node: Node3D = props.props_of(_p.id)["bags"][0]
		var handle := node.global_transform * CarryOnProps.ROLLER_HANDLE
		var bar := node.global_transform * Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, 0.255)
		var grips: Array[Vector3] = [props.grip_of(body, 0), props.grip_of(body, 1)]
		var place_hand := CarryLead.hand_of(int(bag.get("place", 0)))
		var live := CarryLead.hand_of(int(bag["home"]))
		if pin < 0:
			pin = int(bag.get("held_by", -1))
			pin = pin if pin >= 0 else place_hand
		var swap_now: bool = place_hand != pin
		var row := {
			"bag": node.global_position - body.global_position,
			"g": [grips[0] - body.global_position, grips[1] - body.global_position],
			"live": live,
			"body": body.global_position,
			"yaw": body.global_rotation.y,
			"gw": grips[pin] if pin >= 0 else Vector3.ZERO,
			"gap": [grips[0].distance_to(handle), grips[1].distance_to(handle)],
			"clip": (body.get_node("AnimationPlayer") as AnimationPlayer).current_animation,
		}
		_swap_row(props, bag, row, grips[pin])
		var flag := ""
		if not prev.is_empty():
			var bag_jump: float = row["bag"].distance_to(prev["bag"])
			var pin_jump: float = row["g"][pin].distance_to(prev["g"][pin])
			var other_jump: float = row["g"][1 - pin].distance_to(prev["g"][1 - pin])
			var live_jump: float = row["g"][live].distance_to(prev["g"][prev["live"]])
			var gap_jump := absf(row["gap"][pin] - prev["gap"][pin])
			worst["bag"] = maxf(worst["bag"], bag_jump)
			worst["pin"] = maxf(worst["pin"], pin_jump)
			worst["other"] = maxf(worst["other"], other_jump)
			worst["live"] = maxf(worst["live"], live_jump)
			worst["pin_gap"] = maxf(worst["pin_gap"], gap_jump)
			live_switches += int(live != prev["live"])
			if bag_jump > JUMP_M or pin_jump > JUMP_M or gap_jump > JUMP_M:
				jumps_pin += 1
				flag += " PIN_JUMP"
			if live_jump > JUMP_M and bag_jump <= JUMP_M and pin_jump <= JUMP_M:
				flag += " LIVE_ONLY_JUMP"
			if swap_now != bool(prev["swap"]):
				swaps += 1
				flag += " SWAP_%s" % ("START" if swap_now else "END")
			flag += _kinks(row, prev, pin, worst)
			flag += _swap_check(row, prev)
			if flag != "":
				print(
					(
						(
							"FOLLOW tick=%d k=%.3f pin=%d live=%d place_hand=%d held_by=%d swap=%s"
							% [
								_clock.tick,
								props.transfer_progress(_p.id, 0),
								pin,
								live,
								place_hand,
								int(bag.get("held_by", -1)),
								bag.get("swap", false)
							]
						)
						+ (
							" bag_jump=%.3f pin_jump=%.3f other_jump=%.3f live_jump=%.3f"
							% [bag_jump, pin_jump, other_jump, live_jump]
						)
						+ (
							" gap_pin=%.3f gap_other=%.3f bar_pin=%.3f%s"
							% [
								row["gap"][pin],
								row["gap"][1 - pin],
								grips[pin].distance_to(bar),
								flag
							]
						)
						+ (
							" | world: body_move=%.3f yaw_deg=%.1f grip_move=%.3f stage=%d place=%d home=%d park=%s"
							% [
								row["body"].distance_to(prev["body"]),
								rad_to_deg(angle_difference(prev["yaw"], row["yaw"])),
								grips[pin].distance_to(prev["gw"]),
								_p.stage,
								int(bag.get("place", -9)),
								int(bag["home"]),
								bag.get("park", false)
							]
						)
					)
				)
		if _worn:
			_watch_worn(props, body)
		row["swap"] = swap_now
		prev = row
	print(
		(
			"FOLLOW summary ticks=%d pin=%d swaps=%d live_switches=%d pin_jump_frames=%d"
			% [_follow_ticks, pin, swaps, live_switches, jumps_pin]
		)
	)
	print(
		(
			(
				"FOLLOW swaps started=%d turned_back=%d max on swap frames (m): bag=%.3f"
				% [_swap_starts, _reversals, _swap_worst["bag"]]
			)
			+ (
				" pinned_grip=%.3f bar_gap=%.3f axle=%.3f exempt_frames=%d"
				% [
					_swap_worst["pin"],
					_swap_worst["bar"],
					_swap_worst.get("axle", 0.0),
					_swap_worst["exempt"]
				]
			)
		)
	)
	if _reversals < 1:
		_invalid("no swap between the hand and the pull turned back in the follow")
	print(
		(
			(
				"FOLLOW max kink per frame (m; clip kept / clip changed): bag=%.3f / %.3f"
				% [worst["kink_bag"], worst["kink_bag_clip"]]
			)
			+ " pinned_grip=%.3f / %.3f" % [worst["kink_pin"], worst["kink_pin_clip"]]
		)
	)
	print(
		(
			(
				"FOLLOW max per frame (m, from the walker origin): bag=%.3f pinned_grip=%.3f other_grip=%.3f"
				% [worst["bag"], worst["pin"], worst["other"]]
			)
			+ " live_hand_grip=%.3f pinned_gap=%.3f" % [worst["live"], worst["pin_gap"]]
		)
	)
	print(
		(
			"FOLLOW clip changes measured=%d (limit %.3f m): %s"
			% [_clip_changes.size(), SWAP_KINK_M, ", ".join(_clip_changes)]
		)
	)
	if _clip_changes.is_empty():
		_invalid("the follow measured no clip change (follow=%d ticks)" % _follow_ticks)


## The worn shoulder bag (bag 1, --worn) this frame: its origin in the world,
## in the body's own (turned) frame and off its shoulder joint (the Arm bone it
## hangs from), and, while it is settled on the shoulder, how far it is drawn
## from where the worn pose puts it with the body as it is now ("stale": a
## bag placed before the body turned is off by the turn). A move of the bag on
## the body or a stale bag is printed as WORN_JUMP, with the body's turn, move
## and clip; the largest of each is kept for the summary (_worn_summary()).
func _watch_worn(props: CarryOnProps, body: Node3D) -> void:
	var worn: Node3D = props.props_of(_p.id)["bags"][1]
	var joint: Vector3 = props._shoulder_of(body, SecurityLooks.worn_side(1))
	var rig: Dictionary = props._rig(body)
	var pivot: Vector3 = (rig["pivot"] as Node3D).global_position
	var row := {
		"w_world": worn.global_position,
		"w_body": body.global_transform.affine_inverse() * worn.global_position,
		"w_joint": worn.global_position - joint,
		"j_world": joint,
		"j_body": body.global_transform.affine_inverse() * joint,
		"shift": body.global_basis.inverse() * CarryWorn.stoop_shift(rig["stoop"], pivot, joint),
		"yaw": body.global_rotation.y,
		"body": body.global_position,
	}
	var stale := 0.0
	var on_shoulder: bool = (
		props.bag_state(_p.id, 1).get("carry", -1) == SecurityLooks.Carry.SHOULDER
		and int(props.bag_state(_p.id, 1).get("home", -1)) / 4 == SecurityLooks.Home.HAND
		and props.transfer_progress(_p.id, 1) >= 1.0
	)
	if on_shoulder:
		var fresh: Transform3D = props._carry_transform(props._held[_p.id], body, 1, [0.0])
		stale = fresh.origin.distance_to(worn.global_position)
	var prev := _worn_prev
	_worn_prev = row
	if prev.is_empty():
		return
	var jumps := {}
	for key in ["w_body", "w_joint", "w_world", "j_world"]:
		jumps[key] = (row[key] as Vector3).distance_to(prev[key])
		_worn_worst[key] = maxf(_worn_worst[key], jumps[key])
	_worn_worst["stale"] = maxf(_worn_worst["stale"], stale)
	var turn := rad_to_deg(angle_difference(prev["yaw"], row["yaw"]))
	if on_shoulder and absf(turn) > 1.0:
		_worn_worst["turn_frames"] += 1
		_worn_worst["turn_body"] = maxf(_worn_worst["turn_body"], jumps["w_body"])
	var flagged: bool = jumps["w_body"] > JUMP_M or jumps["w_joint"] > JUMP_M or stale > 0.01
	if not flagged and absf(turn) <= 1.0:
		return
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	print(
		(
			(
				"WORN tick=%d k=%.3f home=%d stage=%d shoulder=%s yaw_deg=%.1f body_move=%.3f clip=%s"
				% [
					_clock.tick,
					props.transfer_progress(_p.id, 1),
					int(props.bag_state(_p.id, 1).get("home", -1)),
					_p.stage,
					on_shoulder,
					turn,
					row["body"].distance_to(prev["body"]),
					player.current_animation
				]
			)
			+ (
				(
					" body_frame=%.3f off_joint=%.3f world=%.3f joint_world=%.3f stale=%.3f"
					+ " shift_body=%s was %s joint_body=%s was %s drawn=%.2f world_at=%s%s"
				)
				% [
					jumps["w_body"],
					jumps["w_joint"],
					jumps["w_world"],
					jumps["j_world"],
					stale,
					row["shift"],
					prev["shift"],
					row["j_body"],
					prev["j_body"],
					(rig["stoop"] as CarryStoop).drawn,
					row["w_world"],
					" WORN_JUMP" if flagged else ""
				]
			)
		)
	)


func _worn_summary() -> void:
	print(
		(
			(
				"WORN max per frame (m): body_frame=%.3f off_joint=%.3f world=%.3f joint_world=%.3f"
				% [
					_worn_worst["w_body"],
					_worn_worst["w_joint"],
					_worn_worst["w_world"],
					_worn_worst["j_world"]
				]
			)
			+ (
				" stale=%.3f; on the shoulder in %d turning frames, body_frame max %.3f"
				% [_worn_worst["stale"], _worn_worst["turn_frames"], _worn_worst["turn_body"]]
			)
		)
	)


## The kink of the bag and the pinned grip this frame (`row` against `prev`,
## each as an offset from the walker's origin): how much its move this frame
## differs from its move the frame before. A fast but smooth move (a hand
## swinging the bag up) changes its speed a little a frame; a snap moves at
## once and stops. Kept in `worst` apart for frames whose clip changed (the
## change crossfades, ClipCrossfade), so the two can be compared. Returns the
## flags for the frame.
func _kinks(row: Dictionary, prev: Dictionary, pin: int, worst: Dictionary) -> String:
	row["d_bag"] = (row["bag"] as Vector3) - prev["bag"]
	row["d_pin"] = (row["g"][pin] as Vector3) - prev["g"][pin]
	if not prev.has("d_bag"):
		return ""
	var clip_changed: bool = row["clip"] != prev["clip"]
	row["clip_changed"] = clip_changed
	var suffix := "_clip" if clip_changed else ""
	var bag_kink := (row["d_bag"] as Vector3).distance_to(prev["d_bag"])
	var pin_kink := (row["d_pin"] as Vector3).distance_to(prev["d_pin"])
	worst["kink_bag" + suffix] = maxf(worst.get("kink_bag" + suffix, 0.0), bag_kink)
	worst["kink_pin" + suffix] = maxf(worst.get("kink_pin" + suffix, 0.0), pin_kink)
	var flags := ""
	if clip_changed:
		flags += " CLIP_%s>%s" % [prev["clip"], row["clip"]]
		var over := bag_kink > SWAP_KINK_M or pin_kink > SWAP_KINK_M
		if over and _in_strip_window():
			# A strip capture's stall plays the clips on into the next sim
			# steps (see _swap_check); the headless run (--no-plates) checks it.
			flags += " EXEMPT_STRIP"
		else:
			_clip_changes.append("%s>%s@%d" % [prev["clip"], row["clip"], _clock.tick])
			if over:
				# Clips crossfade (board 908de167): a change moves nothing at once.
				flags += " CLIP_JUMP"
				_invalid(
					(
						"clip change jump at tick %d: bag kink %.3f, pinned grip kink %.3f m"
						% [_clock.tick, bag_kink, pin_kink]
					)
				)
	if bag_kink > JUMP_M or pin_kink > JUMP_M:
		flags += " KINK bag=%.3f pin=%.3f" % [bag_kink, pin_kink]
	return flags


## Prints a turn of the walker over TURN_DEG in a frame (TURN, so a strip
## window can be set on it, marked walking when it stepped on the tick before
## and steps on this one) and fails the probe on it: every turn eases, a
## walking corner too (PassengerTurns), and with --strip draws the frame of a
## window it is in from the window's camera (proved in frame: feet, head,
## roller and the holding hand inside MARGIN_PX; seen: hiding the walker and
## its roller changes MIN_DIFF_PX pixels, else PROBE_INVALID). A window's
## sheet is saved once its last tick has passed.
func _strip_step(props: CarryOnProps, body: Node3D) -> void:
	if _clock.tick != _stepped_tick:
		_stepped_tick = _clock.tick
		var step := _views.tick_position(_p.id, true) - _views.tick_position(_p.id, false)
		_stepped = [_stepped[1], step.length() > 0.001]
	var yaw := body.global_rotation.y
	if is_finite(_last_yaw) and absf(angle_difference(_last_yaw, yaw)) > deg_to_rad(TURN_DEG):
		var walking: bool = _stepped[0] and _stepped[1]
		print(
			(
				"TURN tick=%d yaw_deg=%.1f walking=%s"
				% [_clock.tick, rad_to_deg(angle_difference(_last_yaw, yaw)), walking]
			)
		)
		# Turns ease over 0.3 s (PassengerTurns, board 908de167).
		_invalid("the walker turned over 20 degrees in one frame at tick %d" % _clock.tick)
	_last_yaw = yaw
	_dump_row(props, body)
	_seat_row(body)
	if _no_plates:
		return
	for w in _strips.size():
		if _clock.tick > _strips[w].y and _strip_imgs.has(w) and not _strip_done.has(w):
			_strip_done[w] = true
			_save_sheet(w)
		if _clock.tick < _strips[w].x or _clock.tick > _strips[w].y or _failed:
			continue
		var node: Node3D = props.props_of(_p.id)["bags"][0]
		var bag := props.bag_state(_p.id, 0)
		var hand := maxi(int(bag.get("held_by", -1)), 0)
		if not _strip_imgs.has(w):
			_strip_imgs[w] = []
			if _strip_cam == null:
				_strip_cam = Camera3D.new()
				_strip_cam.fov = 50.0
				root.add_child(_strip_cam)
			var at := body.global_position
			_strip_cam.look_at_from_position(at + STRIP_CAM, at + STRIP_LOOK, Vector3.UP)
			_strip_xf[w] = _strip_cam.global_transform
		_strip_cam.global_transform = _strip_xf[w]
		_strip_cam.current = true
		# Time stands still while the strip frame and its twin are drawn (the clips,
		# the skeleton modifiers and physics take no delta): played on, the
		# four extra frames moved the arms between two sim steps, a grip kink of
		# 0.23 m the follow watch then failed on.
		Engine.time_scale = 0.0
		await _frames(2)
		var img := root.get_texture().get_image()
		var points := {
			"feet": body.global_position,
			"head": body.global_position + Vector3.UP * 1.7,
			"roller": node.global_position,
			"hand": props.grip_of(body, hand),
		}
		var inside := Rect2(
			Vector2.ONE * MARGIN_PX, Vector2(img.get_size()) - Vector2.ONE * 2.0 * MARGIN_PX
		)
		var flat := {}
		for name: String in points:
			flat[name] = _strip_cam.unproject_position(points[name])
			if _strip_cam.is_position_behind(points[name]) or not inside.has_point(flat[name]):
				_invalid(
					(
						"strip %d tick %d: %s at %s is out of frame"
						% [w, _clock.tick, name, flat[name]]
					)
				)
				Engine.time_scale = 1.0
				return
		body.visible = false
		node.visible = false
		await _frames(2)
		var diff := _diff(img, root.get_texture().get_image())
		body.visible = true
		node.visible = true
		# One more frame with the clips still: it takes the pixel diff's long
		# delta, which played on moved the arm 0.11 m in the next sim step.
		await _frames(1)
		Engine.time_scale = 1.0
		if diff < MIN_DIFF_PX:
			_invalid("strip %d tick %d: the walker changes %d px" % [w, _clock.tick, diff])
			return
		var n: int = (_strip_imgs[w] as Array).size()
		var path := _out_dir.path_join("park_strip%d_%02d_t%d.png" % [w, n, _clock.tick])
		img.save_png(path)
		img.resize(STRIP_CELL.x, STRIP_CELL.y)
		(_strip_imgs[w] as Array).append(img)
		print(
			(
				"STRIP %d #%d tick=%d k=%.3f place=%d swap=%s held_by=%d diff_px=%d at=%s saved %s"
				% [
					w,
					n,
					_clock.tick,
					props.transfer_progress(_p.id, 0),
					int(bag.get("place", -9)),
					bag.get("swap", false),
					int(bag.get("held_by", -1)),
					diff,
					flat,
					path
				]
			)
		)


## Saves every strip window not saved yet, and fails on a window with no
## frame or fewer than its ticks' frames (three a tick).
func _finish_strips() -> void:
	if _no_plates:
		return
	for w in _strips.size():
		var want := (_strips[w].y - _strips[w].x + 1) * 3
		var got: int = (_strip_imgs.get(w, []) as Array).size()
		print("STRIP %d frames %d of %d" % [w, got, want])
		if got == 0:
			_invalid("strip %d (ticks %s) has no frame" % [w, _strips[w]])
			continue
		if not _strip_done.has(w):
			_strip_done[w] = true
			_save_sheet(w)
		if got != want:
			_invalid("strip %d (ticks %s) has %d frames of %d" % [w, _strips[w], got, want])


## The swap watch's part of the follow row: the roller's place (with its lift
## bit), whether a swap between the hand and the pull is under way, and the
## pinned grip's gap to the roller's own grip bar (from its geometry,
## FloatCheck.own_grips, never from a placement function).
func _swap_row(props: CarryOnProps, bag: Dictionary, row: Dictionary, grip: Vector3) -> void:
	row["place"] = int(bag.get("place", -9))
	row["lift_swap"] = bag.get("swap", false)
	row["swap_on"] = row["lift_swap"] and props.transfer_progress(_p.id, 0) < 1.0
	row["bar"] = grip.distance_to(FloatCheck.own_grips(props, _p.id, 0)[0])
	var node: Node3D = props.props_of(_p.id)["bags"][0]
	row["axle"] = node.global_transform * CarryOnProps.ROLLER_AXLE - (row["body"] as Vector3)
	row["d_axle"] = Vector3.ZERO


## Counts the swaps that start and the ones that turn back a swap under way
## (the place changes while one is), and on a frame of a swap fails the probe
## on a kink of the roller or the pinned grip, or a jump of the grip's gap to
## the bar, over SWAP_KINK_M, clip-change frames included. Returns the frame's
## flags.
func _swap_check(row: Dictionary, prev: Dictionary) -> String:
	var flags := ""
	var changed: bool = row["place"] != prev.get("place", row["place"])
	if changed and row["lift_swap"]:
		_swap_starts += 1
		flags += " SWAP_PLACE %d>%d" % [prev["place"], row["place"]]
		if prev.get("swap_on", false):
			_reversals += 1
			flags += " TURNED_BACK"
	if not (row["swap_on"] or (changed and row["lift_swap"])) or not row.has("d_bag"):
		return flags
	if prev.has("axle"):
		row["d_axle"] = (row["axle"] as Vector3) - prev["axle"]
	var axle_kink: float = (row["d_axle"] as Vector3).distance_to(prev.get("d_axle", Vector3.ZERO))
	_swap_worst["axle"] = maxf(_swap_worst.get("axle", 0.0), axle_kink)
	if axle_kink > SWAP_KINK_M:
		flags += " SWAP_JUMP"
		_invalid("swap jump at tick %d: roller axle kink %.3f m" % [_clock.tick, axle_kink])
	# A strip frame's capture (a GPU read-back and a pixel diff) stalls the
	# frames after it, and the clips play that stall into the next sim steps:
	# windowed, the free arm moved 0.24 m a step while walking inside a strip
	# window and 0.01 m outside one. The grip, roller and bar checks there are
	# the headless run's (--no-plates); the axle is still checked.
	if _in_strip_window():
		_swap_worst["exempt"] += 1
		print(
			(
				(
					"EXEMPT tick=%d strip capture: grip, roller and bar kinks not checked; the axle"
					% _clock.tick
				)
				+ " kink %.3f m is" % axle_kink
			)
		)
		return flags
	var bag_kink: float = (
		(row["d_bag"] as Vector3).distance_to(prev.get("d_bag", Vector3.ZERO))
		if prev.has("d_bag")
		else 0.0
	)
	var pin_kink: float = (
		(row["d_pin"] as Vector3).distance_to(prev.get("d_pin", Vector3.ZERO))
		if prev.has("d_pin")
		else 0.0
	)
	var bar_jump := absf(float(row["bar"]) - float(prev["bar"]))
	_swap_worst["bag"] = maxf(_swap_worst["bag"], bag_kink)
	_swap_worst["pin"] = maxf(_swap_worst["pin"], pin_kink)
	_swap_worst["bar"] = maxf(_swap_worst["bar"], bar_jump)
	if bag_kink > SWAP_KINK_M or pin_kink > SWAP_KINK_M or bar_jump > SWAP_KINK_M:
		flags += " SWAP_JUMP"
		_invalid(
			(
				"swap jump at tick %d: roller kink %.3f, grip kink %.3f, bar gap jump %.3f m"
				% [_clock.tick, bag_kink, pin_kink, bar_jump]
			)
		)
	return flags


## Keeps the lowest Spine_01 height over the body while the walker sits down or
## is seated at a gate chair, and its height seated still (SEATED in sit_idle,
## the stoop not drawn; the last such frame, past the clip's crossfade), for
## _seat_summary().
func _seat_row(body: Node3D) -> void:
	if _p.stage not in [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED]:
		return
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.is_empty():
		return
	var high: float = (rig["pivot"] as Node3D).global_position.y - body.global_position.y
	_sit["frames"] += 1
	if high < _sit["low"]:
		_sit["low"] = high
		_sit["tick"] = _clock.tick
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	var still: bool = (
		_p.stage == Passenger.Stage.SEATED
		and (rig["stoop"] as CarryStoop).drawn == 0.0
		and player.current_animation == "sit_idle"
	)
	if still:
		_sit["seated"] = high
		_sit["still"] += 1


## Prints the lowest the walker was drawn sitting down or seated against its
## height seated still, and fails the probe (SEAT_LOW) when it went more than
## SEAT_DROP_M under it, or when no seated frame was measured.
func _seat_summary() -> void:
	print(
		(
			"SEAT frames=%d still=%d spine_seated=%.3f lowest=%.3f at tick %d"
			% [_sit["frames"], _sit["still"], _sit["seated"], _sit["low"], _sit["tick"]]
		)
	)
	if _walk_route:
		return
	if _sit["still"] == 0:
		_invalid("the walker was never drawn seated still")
	elif _sit["low"] < float(_sit["seated"]) - SEAT_DROP_M:
		print("SEAT_LOW the hips went %.3f m under the seat" % (_sit["seated"] - _sit["low"]))
		_invalid("the walker sitting down was drawn under its seat at tick %d" % _sit["tick"])


## --dump=A-B: prints a row a frame from tick A to tick B of the roller's move
## and the stoop the walker is drawn with.
func _dump_row(props: CarryOnProps, body: Node3D) -> void:
	if _clock.tick < _dump.x or _clock.tick > _dump.y:
		return
	var bag := props.bag_state(_p.id, 0)
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.is_empty():
		return
	var stoop: CarryStoop = rig["stoop"]
	var pivot := (rig["pivot"] as Node3D).global_position
	var ys: Array[String] = []
	for t in stoop.targets:
		var local := body.global_transform.affine_inverse() * t
		ys.append(
			(
				"(%.2f %.2f %.2f) yaw %.0f"
				% [local.x, local.y, local.z, rad_to_deg(body.global_rotation.y)]
			)
		)
	var start: Array = CarryLead.start_of(bag) if bag.has("was") else []
	print(
		(
			(
				"DUMP tick=%d a=%.2f stage=%s k=%.3f home=%s place=%s park=%s led=%s since=%s ticks=%s"
				% [
					_clock.tick,
					_clock.alpha,
					Passenger.Stage.keys()[_p.stage],
					props.transfer_progress(_p.id, 0),
					bag.get("home"),
					bag.get("place"),
					bag.get("park", false),
					bag.get("led", false),
					bag.get("since"),
					bag.get("ticks"),
				]
			)
			+ (
				" start=%s drawn=%.3f targets_y=%s weights=%s keeps=%s drops=%s spine_y=%.3f"
				% [start, stoop.drawn, ys, stoop.weights, stoop.keeps, stoop.drops, pivot.y]
			)
		)
	)


## Whether this tick is in a strip window, or the tick after one (--strip; a
## headless --no-plates run draws none).
func _in_strip_window() -> bool:
	if _no_plates:
		return false
	for window in _strips:
		if _clock.tick >= window.x and _clock.tick <= window.y + 1:
			return true
	return false


## Saves strip window `w`'s frames as one contact sheet, four to a row.
func _save_sheet(w: int) -> void:
	var imgs: Array = _strip_imgs[w]
	var rows := ceili(imgs.size() / 4.0)
	var sheet := Image.create(STRIP_CELL.x * 4, STRIP_CELL.y * rows, false, Image.FORMAT_RGBA8)
	for n in imgs.size():
		var img: Image = imgs[n]
		img.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(n % 4 * STRIP_CELL.x, n / 4 * STRIP_CELL.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, STRIP_CELL), at)
	var path := _out_dir.path_join("park_strip%d_sheet.png" % w)
	sheet.save_png(path)
	print("STRIP %d sheet %d frames saved %s" % [w, imgs.size(), path])


## One sim step a third of a tick on, drawn.
func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


func _plate(shot: String, body: Node3D, node: Node3D, bag: Dictionary, k: float, lead: int) -> void:
	var frame: Transform3D = bag["park_frame"]
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		root.add_child(_cam)
		var out := -1.0 if lead == 0 else 1.0
		var at := Vector3(CAM_AT.x * -out, CAM_AT.y, CAM_AT.z)
		var look := Vector3(LOOK_AT.x * -out, LOOK_AT.y, LOOK_AT.z)
		_cam.look_at_from_position(frame * at, frame * look, Vector3.UP)
	_cam.current = true
	await _frames(2)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var points := {
		"feet": body.global_position,
		"head": body.global_position + Vector3.UP * 1.7,
		"bag": node.global_position,
	}
	var flat := {}
	for name: String in points:
		var at: Vector2 = _cam.unproject_position(points[name])
		flat[name] = at
		var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
		if _cam.is_position_behind(points[name]) or not inside.has_point(at):
			_invalid("%s: %s at %s is out of frame %s" % [shot, name, at, size])
			return
	var tall := (flat["feet"] as Vector2).distance_to(flat["head"])
	body.visible = false
	node.visible = false
	await _frames(2)
	var twin := root.get_texture().get_image()
	body.visible = true
	await _frames(2)
	var bag_twin := root.get_texture().get_image()
	node.visible = true
	var diff := _diff(img, twin)
	var bag_diff := _diff(img, bag_twin)
	var props := _views.carry_on_props()
	var grip := props.grip_of(body, lead)
	var handle := node.global_transform * CarryOnProps.ROLLER_HANDLE
	var bar := node.global_transform * Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, 0.255)
	var low := INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		low = minf(low, (mi.global_transform * mi.get_aabb()).position.y)
	print(
		(
			(
				"PLATE %s k=%.3f took=%.3f holder=%d grip-handle=%.3f grip-bar=%.3f"
				% [
					shot,
					k,
					bag.get("park_took", -1.0),
					bag.get("held_by", -1),
					grip.distance_to(handle),
					grip.distance_to(bar)
				]
			)
			+ (
				" handle_y=%.3f bag_low=%.3f floor=%.3f body_px=%.0f diff_px=%d at=%s"
				% [handle.y, low, _mode.grid.origin.y, tall, diff, flat]
			)
		)
	)
	print("PLATE %s bag alone changes %d px" % [shot, bag_diff])
	if tall < MIN_BODY_PX or diff < MIN_DIFF_PX or bag_diff < MIN_BAG_PX:
		_invalid(
			(
				"%s: body %.0f px tall, %d px from the passenger, %d from the bag"
				% [shot, tall, diff, bag_diff]
			)
		)
		return
	var path := _out_dir.path_join("park_recovery_%s.png" % shot)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_saved.append(path)
	print("PLATE saved %s" % path)


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	# Headless (--no-plates) draws nothing, so frame_post_draw never comes.
	if not _no_plates:
		await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID %s" % why)
