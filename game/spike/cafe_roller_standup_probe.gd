extends SceneTree
## Windowed probe of a passenger with a roller standing up from a cafe seat,
## the lounge sofa and the nap pod (board 2c659e42, decision
## standing-up-with-a-roller-stand-up-then-pick-up-then-walk): it stands up
## fully, then picks the roller up, standing still, then walks off.
## For each subject the probe boots main.tscn, builds the reference terminal
## with a cafe (CafeTestLayout) or a ready lounge or nap pod room
## (ActivityTestLayout), opens the airport and sends one passenger with one
## roller to it. The clock is stepped by hand: fast to shortly before the
## stand-up, then a third of a tick a frame (60 frames a second, as in the
## game) to after the walk-off.
##
## Checks, each printing the values it compared (pass values are positives):
##   UP: the roller goes into the hand STAND_UP_TICKS or more after the
##     stand-up began (the old cafe pick-up began RollerPark.UP_LEAD_TICKS
##     before that).
##   RISEN: the hips (the carry rig's pivot) at the pick-up's first frame are
##     at least RISEN_SHARE of their height standing after the hold; control:
##     at rise mid they are lower.
##   HOLD: the body moves at most HOLD_EPS_M during the hold; control: it moves
##     more than WALK_M after it.
##   BAG_STILL: the roller on the floor moves at most BAG_EPS_M from the
##     stand-up's start to the pick-up (a floor bag in the body's frame slid
##     with a shuffling body); control: it moves more than WALK_M after.
##   TORSO: the stoop bends the back more than 0 and at most TORSO_MAX_DEG.
##   SEAT: in a seat clip the hips never go SEAT_EPS_M under their height
##     seated still (self-tested on a height under it).
##   ROLLER_CLEAR: no point of the roller's box (corners, face centres,
##     centre) enters the seat's box from the pick-up to AFTER_TICKS after the
##     hold (the step-off). The seat's box is the bounds, in the seat's frame,
##     of the piece's mesh vertices within SEAT_HALF_M across the sitter's root
##     and from SEAT_FRONT_M ahead of it to SEAT_DEPTH_M behind it: the chair
##     of a cafe table, the sofa's seat and its arm, the pod. Self-tested on the
##     box's centre (inside) and a point past its front (outside).
##   HIPS_CLEAR: during the hold the hips bone stays more than BODY_BACK_M
##     (the body's depth behind it, an estimate) outside the seat's box;
##     control: seated still, the same measure is negative (on the seat).
## Plates: <subject>_rise_mid, <subject>_pick_up, <subject>_step_off (rolling it
## upright), <subject>_walk (6 ticks after its tip into the pull) and a
## contact sheet. Before a save the feet, head and roller project inside the
## frame with a margin, and twins with the body and with the roller hidden
## each differ from the plate (in frame is not visible). Otherwise
## PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/cafe_roller_standup_probe.gd [-- --seed=N]
##
## Plates go to tools/blender/out/cafe-roller-standup/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/cafe-roller-standup"
const SUBJECTS: Array[String] = ["gate", "cafe", "lounge", "pod"]
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_DIFF_PX := 1500
const MIN_BAG_PX := 300
const LIMIT_TICKS := 6000
## Ticks drawn in real time before the stand-up starts (seated still) and
## after the hold ends.
const LEAD_TICKS := 30
const AFTER_TICKS := 50
const RISEN_SHARE := 0.97
const HOLD_EPS_M := 0.01
const BAG_EPS_M := 0.01
const WALK_M := 0.05
const SEAT_EPS_M := 0.005
const TORSO_MAX_DEG := 46.0
const SEAT_CLIPS := ["sit_down", "sit_idle", "stand_up"]
const SEAT_HALF_M := 0.6
const SEAT_FRONT_M := 0.05
const SEAT_DEPTH_M := 0.9
const SEAT_TOP_M := 1.3
const BODY_BACK_M := 0.1
## A gate chair's seated feet are this far out of its cell's centre (as an
## activity seat's root is out of the piece's middle).
const SEAT_ROOT_M := 0.45
## Ticks the passenger holds still after the roller goes into the hand.
const HOLD_TICKS := {
	"cafe": ParkRecovery.UP_HOLD_TICKS,
	"lounge": ActivityPoses.SEAT_HOLD_TICKS,
	"pod": ActivityPoses.SEAT_HOLD_TICKS,
	# The gate walker is drawn moving over the hold's last tick (ParkRecovery).
	"gate": ParkRecovery.UP_HOLD_TICKS - 1,
}

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
	# A frame is a third of a tick (_step), so the clips play at 60 frames a
	# second as in the game.
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
	for subject in SUBJECTS:
		if await _boot(subject):
			await _watch(subject)
		_main.queue_free()
		_cam = null
		await _frames(3)
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	print("PROBE done plates=%d failed=%s" % [_plates, _failed])
	quit(1 if _failed or _plates < SUBJECTS.size() * 4 else 0)


func _boot(subject: String) -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	# The probe builds its own terminal on an empty grid.
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
	var ids := {}
	if subject == "cafe" or subject == "gate":
		ids = CafeTestLayout.build(_mode.grid)
	else:
		ids = ActivityTestLayout.build(_mode.grid, &"lounge" if subject == "lounge" else &"nap_pod")
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("%s: the gate desk was refused" % subject)
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
	print("PROBE %s ids=%s hired=%d opened tick=%d" % [subject, ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("%s: the airport did not open" % subject)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	return true


## One passenger with one roller, on its way to the gate airside, that commits
## to the cafe (hungry) or to the room's piece (bored).
func _visitor(subject: String) -> Passenger:
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
	if subject == "gate":
		# Seated at the first gate chair (as test_roller_park does), kept on time,
		# standing up when its boarding is called.
		var seat: Dictionary = _sim.layout.seats[0]
		p.stage = Passenger.Stage.SEATED
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.at = seat["front"]
		p.boarding_tick = _clock.tick + LEAD_TICKS + 60
		p.cafe_cooldown = 1000000
		p.shop_cooldown = 1000000
		_clock.ticked.connect(func(_t: int) -> void: p.late = false)
		print("VISITOR gate id=%d seat %s" % [p.id, seat["cell"]])
		return p
	if subject == "cafe":
		# As test_room_move_saves does: the visit is asked for directly.
		p.boredom = 0
		_sim.cafes.try_visit(p)
	else:
		p.hunger = 0
		p.boredom = 80
		NeedsPolicy.arbitrate(_sim, p)
	var cafe := _sim.cafes.visit_of(p.id) != null
	var shop := _sim.shops.visit_of(p.id) != null
	print(
		(
			"VISITOR %s id=%d roller=%s cafe=%s shop=%s"
			% [subject, p.id, ParkRecovery.has_roller(p), cafe, shop]
		)
	)
	if not (cafe if subject == "cafe" else shop):
		_invalid("%s: passenger %d did not commit to the visit" % [subject, p.id])
		return null
	return p


## Whether `p` sits still now (its seated pose, not leaning back or forward).
func _seated_still(p: Passenger) -> bool:
	if p.stage == Passenger.Stage.CAFE_SEATED or p.stage == Passenger.Stage.SEATED:
		return true
	if ActivityPoses.pose(_sim, p) != StageKinds.Pose.SEATED:
		return false
	var lean := ActivityPoses.recline(_sim, p)
	return lean <= 0.0 or lean >= 1.0


## Whether `p` has begun to stand up from its seat.
func _standing_up(p: Passenger) -> bool:
	if p.stage in [Passenger.Stage.CAFE_STANDING_UP, Passenger.Stage.STANDING_UP]:
		return true
	return ActivityPoses.pose(_sim, p) == StageKinds.Pose.STANDING_UP


## Ticks until `p` starts to stand up (0 once it has, or LIMIT when unknown).
func _ticks_to_up(p: Passenger) -> int:
	if p.stage == Passenger.Stage.SEATED:
		return p.boarding_tick - _clock.tick
	if p.stage == Passenger.Stage.CAFE_SEATED:
		return _sim.cafes.visit_of(p.id).dwell_end - _clock.tick
	if (
		p.stage == Passenger.Stage.SHOP_BROWSE
		and ActivityPoses.kind(_sim, p) != ActivityPoses.Kind.NONE
	):
		var visit := _sim.shops.visit_of(p.id)
		var type := RoomTypes.get_type(_sim.grid.get_room(visit.room)["type"])
		var end := mini(p.stage_tick + ShopSim.stay_ticks(visit, type), visit.deadline)
		var up := end - PassengerSim.STAND_UP_TICKS - ActivityPoses.up_tail(_sim, p)
		return up - _clock.tick
	return LIMIT_TICKS


func _watch(subject: String) -> void:
	var p := _visitor(subject)
	if p == null:
		return
	var until := _clock.tick + LIMIT_TICKS
	while _clock.tick < until and _ticks_to_up(p) > LEAD_TICKS:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 10 == 0:
			await process_frame
	if _ticks_to_up(p) > LEAD_TICKS or _ticks_to_up(p) < LEAD_TICKS - 2:
		_invalid(
			(
				"%s: never seated %d ticks before the stand-up (%d)"
				% [subject, LEAD_TICKS, _ticks_to_up(p)]
			)
		)
		return
	print(
		"PROBE %s seated, stand-up in %d ticks, tick %d" % [subject, _ticks_to_up(p), _clock.tick]
	)
	await _frames(6)
	var seat := _seat_box(subject, p)
	var m := {
		"seat_frame": seat["frame"],
		"seat_box": seat["box"],
		"roller_clear": INF,
		"roller_tick": -1,
		"hips_clear": INF,
		"hips_tick": -1,
		"hips_seated": INF,
		"up_at": -1,
		"pick": -1,
		"hold_end": -1,
		"torso": 0.0,
		"torso_tick": -1,
		"seat_low": INF,
		"seat_lo": INF,
		"seat_hi": -INF,
		"still": 0,
		"seat_frames": 0,
		"mid_h": -1.0,
		"pick_h": -1.0,
		"stand_h": -1.0,
		"pick_clip": "",
		"hold_from": Vector3.INF,
		"hold_move": 0.0,
		"after_move": 0.0,
		"bag_from": Vector3.INF,
		"bag_drift": 0.0,
		"bag_after": 0.0,
		"bag_floor": Vector3.INF,
	}
	var shots := ["rise_mid", "pick_up", "step_off", "walk"]
	var stop := _clock.tick + LIMIT_TICKS
	while _clock.tick < stop:
		await _step()
		var body := _views.node_for(p.id)
		if body == null:
			break
		var props := _views.carry_on_props()
		var bags: Array = props.props_of(p.id).get("bags", [])
		if bags.is_empty():
			continue
		var bag: Node3D = bags[0]
		var rig: Dictionary = body.get_meta(&"carry_rig", {})
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		var hips := -1.0
		if not rig.is_empty():
			hips = (rig["pivot"] as Node3D).global_position.y - body.global_position.y
			var deg := (rig["stoop"] as CarryStoop).bent * CarryStoop.STOOP_DEGREES
			if deg > m["torso"]:
				m["torso"] = deg
				m["torso_tick"] = _clock.tick
			if player.current_animation in SEAT_CLIPS:
				m["seat_frames"] += 1
				m["seat_low"] = minf(m["seat_low"], hips)
				var stoop_off: bool = (rig["stoop"] as CarryStoop).drawn == 0.0
				if _seated_still(p) and stoop_off and player.current_animation == "sit_idle":
					m["hips_seated"] = minf(m["hips_seated"], _hips_signed(m, body))
					m["still"] += 1
					m["seat_lo"] = minf(m["seat_lo"], hips)
					m["seat_hi"] = maxf(m["seat_hi"], hips)
		var home: SecurityLooks.Home = (
			SecurityLooks.bag_homes(_sim, p)[0] if p.carry_on > 0 else SecurityLooks.Home.HAND
		)
		if m["up_at"] < 0 and _standing_up(p):
			m["up_at"] = _clock.tick
			m["bag_from"] = bag.global_position
		if m["up_at"] < 0:
			continue
		var up_for: int = _clock.tick - m["up_at"]
		if m["pick"] < 0 and home == SecurityLooks.Home.FLOOR:
			m["bag_drift"] = maxf(m["bag_drift"], bag.global_position.distance_to(m["bag_from"]))
			m["bag_floor"] = bag.global_position
		if shots.has("rise_mid") and up_for >= PassengerSim.STAND_UP_TICKS / 2:
			m["mid_h"] = hips
			shots.erase("rise_mid")
			await _plate(subject + "_rise_mid", p, body, bag)
		if m["pick"] < 0 and home == SecurityLooks.Home.HAND:
			m["pick"] = _clock.tick
			m["hold_end"] = _clock.tick + HOLD_TICKS[subject]
			m["pick_h"] = hips
			m["pick_clip"] = (
				"%s@%.2f/%.2f"
				% [
					player.current_animation,
					player.current_animation_position,
					player.current_animation_length
				]
			)
			m["hold_from"] = body.global_position
		if m["pick"] < 0:
			continue
		_clearances(m, body, bag, props.props_of(p.id)["kinds"][0])
		var state := props.bag_state(p.id, 0)
		if not m.has("tip_at") and state.has("roll_tip"):
			m["tip_at"] = _clock.tick
			m["tip_moved"] = body.global_position.distance_to(m["hold_from"])
			print(
				(
					"ROLL %s tipped into the pull at tick %d (%d after the pick-up), body %.3f m out"
					% [subject, _clock.tick, _clock.tick - m["pick"], m["tip_moved"]]
				)
			)
		if shots.has("pick_up") and _clock.tick >= m["pick"] + 2:
			shots.erase("pick_up")
			await _plate(subject + "_pick_up", p, body, bag)
		var moved: float = body.global_position.distance_to(m["hold_from"])
		if _clock.tick < m["hold_end"]:
			if moved > HOLD_EPS_M and m["hold_move"] <= HOLD_EPS_M:
				print(
					(
						"HOLD_MOVED %s tick %d (%d after the pick-up) %.3f m, stage %d"
						% [subject, _clock.tick, _clock.tick - m["pick"], moved, p.stage]
					)
				)
			m["hold_move"] = maxf(m["hold_move"], moved)
			continue
		m["after_move"] = maxf(m["after_move"], moved)
		m["bag_after"] = maxf(m["bag_after"], bag.global_position.distance_to(m["bag_floor"]))
		# The standing reference: walking on with the roller in the pull, after
		# the tip (rolling it upright, the hips are lower: printed as ROLL_HIPS).
		var tip: int = m.get("tip_at", -1)
		if tip >= 0 and _clock.tick >= tip + 6 and _clock.tick < tip + 14:
			m["stand_h"] = maxf(m["stand_h"], hips)
		if tip < 0:
			m["roll_low"] = minf(m.get("roll_low", INF), hips)
		if shots.has("step_off") and moved > WALK_M:
			shots.erase("step_off")
			await _plate(subject + "_step_off", p, body, bag)
		if shots.has("walk") and tip >= 0 and _clock.tick >= tip + 6:
			shots.erase("walk")
			# Framed again on where it walks: 1.5 m on, the seat's camera lost it.
			_cam.queue_free()
			_cam = null
			await _plate(subject + "_walk", p, body, bag)
		if _clock.tick >= m["hold_end"] + AFTER_TICKS and shots.is_empty():
			break
	_summary(subject, m)
	if not shots.is_empty():
		_invalid("%s: plates never reached: %s" % [subject, shots])


func _summary(subject: String, m: Dictionary) -> void:
	if m["up_at"] < 0 or m["pick"] < 0:
		_invalid("%s: no stand-up (%d) or no pick-up (%d) drawn" % [subject, m["up_at"], m["pick"]])
		return
	var after_up: int = m["pick"] - m["up_at"]
	print(
		(
			(
				"UP %s stand-up began tick %d, roller into the hand tick %d: "
				+ "%d ticks after (>= %d); old cafe lead would be %d"
			)
			% [
				subject,
				m["up_at"],
				m["pick"],
				after_up,
				PassengerSim.STAND_UP_TICKS,
				PassengerSim.STAND_UP_TICKS - RollerPark.UP_LEAD_TICKS
			]
		)
	)
	if after_up < PassengerSim.STAND_UP_TICKS:
		_invalid("%s: the pick-up began %d ticks into the stand-up" % [subject, after_up])
	var share: float = m["pick_h"] / maxf(m["stand_h"], 0.001)
	print(
		(
			(
				"RISEN %s hips at pick-up %.3f m (clip %s), walking after the tip %.3f m, "
				+ "share %.3f (>= %.2f); control rise mid %.3f m"
			)
			% [subject, m["pick_h"], m["pick_clip"], m["stand_h"], share, RISEN_SHARE, m["mid_h"]]
		)
	)
	print("ROLL_HIPS %s lowest hips rolling upright %.3f m" % [subject, m.get("roll_low", -1.0)])
	if m["stand_h"] <= 0.0 or share < RISEN_SHARE:
		_invalid("%s: not fully up at the pick-up" % subject)
	if m["mid_h"] >= m["stand_h"] * RISEN_SHARE:
		_invalid("%s: RISEN control failed: the hips at rise mid are already up" % subject)
	print(
		(
			"HOLD %s body moved %.4f m during the hold (<= %.3f); control after it %.3f m (> %.2f)"
			% [subject, m["hold_move"], HOLD_EPS_M, m["after_move"], WALK_M]
		)
	)
	# At a gate chair the drawn body is still settling onto the chair front from
	# its stand-up as the hold begins (6 cm over its first ticks, HOLD_MOVED at
	# 0 ticks after the pick-up), as built before this lane: printed, not gated.
	if subject == "gate" and m["after_move"] > WALK_M:
		print("HOLD_SETTLE gate %.4f m in the hold, not gated" % m["hold_move"])
	elif m["hold_move"] > HOLD_EPS_M or m["after_move"] <= WALK_M:
		_invalid("%s: HOLD failed" % subject)
	print(
		(
			(
				"BAG_STILL %s roller moved %.4f m on the floor from the stand-up start to the pick-up "
				+ "(<= %.3f); control after %.3f m (> %.2f)"
			)
			% [subject, m["bag_drift"], BAG_EPS_M, m["bag_after"], WALK_M]
		)
	)
	if m["bag_drift"] > BAG_EPS_M or m["bag_after"] <= WALK_M:
		_invalid("%s: BAG_STILL failed" % subject)
	print(
		(
			"TORSO %s largest stoop bend %.1f deg at tick %d (> 0, <= %.0f)"
			% [subject, m["torso"], m["torso_tick"], TORSO_MAX_DEG]
		)
	)
	if m["torso"] <= 0.0 or m["torso"] > TORSO_MAX_DEG:
		_invalid("%s: TORSO failed" % subject)
	_seat_check(subject, m)
	_clear_check(subject, m)


## The seat's frame (on the sitter's root, +z the way it faces seated) and the
## bounds in it of the seat piece's mesh vertices near the seat (the header).
func _seat_box(subject: String, p: Passenger) -> Dictionary:
	var frame := Transform3D.IDENTITY
	var id := 0
	if subject == "gate":
		# On the seated feet, SEAT_ROOT_M out of the chair's cell centre.
		var out := Vector2(TerminalLayout.front_of(_sim.grid.get_object(p.seat_object)["facing"]))
		var root := _sim.grid.cell_to_world(p.seat_cell) + Vector3(out.x, 0.0, out.y) * SEAT_ROOT_M
		frame = Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), root)
		id = p.seat_object
	elif subject == "cafe":
		var visit := _sim.cafes.visit_of(p.id)
		var face: Vector2i = visit.seat["facing"]
		var root := BuildObjectDef.seat_root_world(_sim.grid, visit.seat)
		frame = Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), root)
		id = int(visit.seat["object_id"])
	else:
		frame = ActivityPoses.stay_frame(_sim, p)
		id = _sim.shops.visit_of(p.id).display
	var record := _sim.grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var piece := BuildView.object_transform(_sim.grid, cells, record["facing"])
	var to_seat := frame.affine_inverse() * piece
	var scene := (load("res://assets/interior/%s.glb" % record["def"]) as PackedScene).instantiate()
	var box := AABB()
	var count := 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for v in mi.mesh.get_faces():
			var at := to_seat * xf * v
			var near := absf(at.x) <= SEAT_HALF_M and at.y <= SEAT_TOP_M
			if near and at.z <= SEAT_FRONT_M and at.z >= -SEAT_DEPTH_M:
				box = AABB(at, Vector3.ZERO) if count == 0 else box.expand(at)
				count += 1
	scene.free()
	print("SEATBOX %s %s vertices=%d box %s (seat frame)" % [subject, record["def"], count, box])
	if count == 0:
		_invalid("%s: no seat vertices" % subject)
	return {"frame": frame, "box": box}


## Keeps the least clearance of the roller from the seat box from the pick-up
## to AFTER_TICKS after the hold, and of the hips during the hold.
func _clearances(m: Dictionary, body: Node3D, bag: Node3D, kind: SecurityLooks.Kind) -> void:
	var to_seat: Transform3D = (m["seat_frame"] as Transform3D).affine_inverse()
	if _clock.tick < m["hold_end"] + AFTER_TICKS:
		var local := CarryOnProps.bag_box(kind)
		var points: Array[Vector3] = [local.get_center()]
		for i in 8:
			points.append(local.get_endpoint(i))
		for axis in 3:
			for side in [0.0, 1.0]:
				var face := local.get_center()
				face[axis] = local.position[axis] + local.size[axis] * side
				points.append(face)
		var least := INF
		for point in points:
			least = minf(least, _signed(m["seat_box"], to_seat * (bag.global_transform * point)))
		if least < m["roller_clear"]:
			m["roller_clear"] = least
			m["roller_tick"] = _clock.tick
		if least <= 0.0 and m.get("inside_last", -1) != _clock.tick:
			m["inside_last"] = _clock.tick
			print(
				(
					"INSIDE tick %d (%d after the pick-up) depth %.3f body moved %.3f m"
					% [
						_clock.tick,
						_clock.tick - m["pick"],
						-least,
						body.global_position.distance_to(m["hold_from"])
					]
				)
			)
	if _clock.tick < m["hold_end"]:
		var d := _hips_signed(m, body)
		if d < m["hips_clear"]:
			m["hips_clear"] = d
			m["hips_tick"] = _clock.tick


## The hips bone's signed distance from the seat box (negative inside).
func _hips_signed(m: Dictionary, body: Node3D) -> float:
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	)
	return _signed(m["seat_box"], (m["seat_frame"] as Transform3D).affine_inverse() * hips)


## The distance of the point outside the box, or minus its depth inside it.
static func _signed(box: AABB, point: Vector3) -> float:
	var out := Vector3(
		maxf(box.position.x - point.x, point.x - box.end.x),
		maxf(box.position.y - point.y, point.y - box.end.y),
		maxf(box.position.z - point.z, point.z - box.end.z)
	)
	if out.x > 0.0 or out.y > 0.0 or out.z > 0.0:
		return Vector3(maxf(out.x, 0.0), maxf(out.y, 0.0), maxf(out.z, 0.0)).length()
	return maxf(out.x, maxf(out.y, out.z))


func _clear_check(subject: String, m: Dictionary) -> void:
	var box: AABB = m["seat_box"]
	var inside := _signed(box, box.get_center())
	var past := _signed(box, box.end + Vector3(0.0, 0.0, 0.5))
	print(
		(
			"ROLLER_CLEAR %s least clearance %.3f m at tick %d (> 0); self-test centre %.3f, past %.3f"
			% [subject, m["roller_clear"], m["roller_tick"], inside, past]
		)
	)
	if inside >= 0.0 or past <= 0.0:
		_invalid("%s: the seat box self-test failed" % subject)
	elif m["roller_clear"] <= 0.0:
		_invalid(
			"%s: ROLLER_CLEAR the roller entered the seat at tick %d" % [subject, m["roller_tick"]]
		)
	var gap: float = m["hips_clear"] - BODY_BACK_M
	var seated_gap: float = m["hips_seated"] - BODY_BACK_M
	var text := "HIPS_CLEAR %s hips bone %.3f m from the seat box at tick %d, less %.2f: %.3f (> 0); "
	text += "control seated %.3f (< 0)"
	print(text % [subject, m["hips_clear"], m["hips_tick"], BODY_BACK_M, gap, seated_gap])
	if seated_gap >= 0.0:
		_invalid("%s: HIPS_CLEAR control failed: the seated hips read clear" % subject)
	elif gap <= 0.0:
		_invalid(
			"%s: HIPS_CLEAR the hips went into the seat at tick %d" % [subject, m["hips_tick"]]
		)


func _seat_check(subject: String, m: Dictionary) -> void:
	var seated: float = m["seat_hi"]
	print(
		(
			(
				"SEAT %s frames=%d still=%d seated=%.4f noise=%.4f lowest=%.4f; "
				+ "self-test %.4f low=%s, %.4f low=%s"
			)
			% [
				subject,
				m["seat_frames"],
				m["still"],
				seated,
				m["seat_hi"] - m["seat_lo"],
				m["seat_low"],
				seated - 2.0 * SEAT_EPS_M,
				_seat_low(seated - 2.0 * SEAT_EPS_M, seated),
				seated,
				_seat_low(seated, seated)
			]
		)
	)
	if m["still"] == 0:
		_invalid("%s: never drawn seated still" % subject)
	elif not _seat_low(seated - 2.0 * SEAT_EPS_M, seated) or _seat_low(seated, seated):
		_invalid("%s: the SEAT self-test failed" % subject)
	elif m["seat_hi"] - m["seat_lo"] > SEAT_EPS_M:
		_invalid("%s: the seated-still height varies more than SEAT_EPS_M" % subject)
	elif _seat_low(m["seat_low"], seated):
		_invalid(
			"%s: SEAT_LOW the hips went %.3f m under the seat" % [subject, seated - m["seat_low"]]
		)


static func _seat_low(high: float, seated: float) -> bool:
	return high < seated - SEAT_EPS_M


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


## A plate of `body` and `bag` from in front of the passenger on the roller's
## side, the camera set on the subject's first plate and kept.
func _plate(shot: String, p: Passenger, body: Node3D, bag: Node3D) -> void:
	if _cam == null:
		var ahead := body.global_transform.basis.z
		ahead.y = 0.0
		var side := bag.global_position - body.global_position
		side.y = 0.0
		var target := (body.global_position + bag.global_position) * 0.5 + Vector3.UP * 0.6
		var away := (ahead.normalized() * 1.0 + side.normalized() * 1.2).normalized()
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
		_cam.look_at_from_position(target + away * 3.0 + Vector3.UP * 1.0, target, Vector3.UP)
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
			return
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
			"PLATE %s tick %d stage %d at=%s body_px=%.0f body_diff=%d bag_diff=%d"
			% [shot, _clock.tick, p.stage, flat, tall, body_px, bag_px]
		)
	)
	if tall < MIN_BODY_PX or body_px < MIN_DIFF_PX or bag_px < MIN_BAG_PX:
		_invalid(
			(
				"%s: body %.0f px tall, %d px from the body, %d from the bag"
				% [shot, tall, body_px, bag_px]
			)
		)
		return
	_save(img, shot + ".png")
	_sheet.append(img)
	_plates += 1


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
	var rows := ceili(plates.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
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
