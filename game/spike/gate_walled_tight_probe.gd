extends SceneTree
## Windowed plates of a gate chair walled tight on both sides of its front
## (board f1fc1e54, decision a-roller-guest-is-never-given-a-gate-chair-walled-
## tight-on-b): a roller guest asks the sim for a seat (GateCapacity.
## claim_seat()) and is given another chair, then a guest with no roller asks
## from the same cell and is given the tight chair. Both walk in and sit; one
## plate shows the tight chair with the plain guest seated, one the roller
## guest at its chair with its roller laid down.
##
## Boots main.tscn with no starter shell, builds the reference terminal and a
## gate desk and opens the airport (as gate_chair_roller_probe). Each plate
## proves its subjects in frame (unproject, MARGIN_PX in) and in sight (sight
## lines against the drawn meshes, PlateSight, walls included); the HUD is
## hidden. Otherwise PROBE_INVALID and exit 1.
##
## Run windowed (holds the one windowed slot):
##   godot --path game --display-driver windows --rendering-driver vulkan
##     --audio-driver Dummy -s res://spike/gate_walled_tight_probe.gd [-- --seed=N]

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/gate-walled-tight"
const MARGIN_PX := 8.0
const MIN_ON := 3
const TAG := "subject"
const LIMIT_TICKS := 300
const SETTLE_TICKS := 30
## How far out from a candidate chair's front the two guests ask from (cells).
const START_CELLS := 1

var _seed := 0
var _failed := false
var _out_dir := ""
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _tight: Dictionary = {}
var _roller: Passenger
var _plain: Passenger
var _saved: Array[String] = []


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot() and _choose():
		await _watch()
		if not _failed:
			await _plate("tight_chair_plain_guest", _plain, false, _seat_of(_plain))
			await _plate("roller_guest_other_chair", _roller, true, _seat_of(_roller))
	print("PROBE done plates=%d failed=%s" % [_saved.size(), _failed])
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
	var refused := 0
	for result in _mode.grid.apply_batch(
		ReferenceTerminal.edits(ReferenceTerminal.offset_on(_mode.grid))
	):
		refused += int(not result.ok)
	print("PROBE terminal edits refused=%d" % refused)
	if refused > 0 or not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the reference terminal or its gate desk was refused")
		return false
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


## A one-bag roller guest and a guest with no roller, of the first flight,
## kept on time and calm, on their way to the gate.
func _guest(roller: bool) -> Passenger:
	var p: Passenger = null
	for attempt in 400:
		p = _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		if not roller or SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
	ToiletTestLayout.calm(p)
	p.carry_on = 1 if roller else 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.boarding_tick = _clock.tick + 100000
	_clock.ticked.connect(func(_t: int) -> void: p.late = false)
	return p


## Walls in a chair front on both sides, then lets the sim seat the two guests
## (GateCapacity.claim_seat()) from START_CELLS out of it: the roller guest
## first, then the plain guest. Kept when the roller guest is given another
## chair and the plain guest the walled one; otherwise undone and the next
## chair is tried.
func _choose() -> bool:
	_roller = _guest(true)
	_plain = _guest(false)
	# The chair the sim gives the plain guest from each start, unwalled: the
	# first in claim_seat()'s own order (reach to the gate desk, then distance).
	var firsts := []
	var near := PassengerGates.gate_cells(_sim, _plain)
	var reach := []
	for seat: Dictionary in _sim.layout.seats:
		reach.append(GateReach.cells_from(seat["cell"], near))
	reach.sort()
	print(
		(
			"PROBE seats %d gate cells %d nearest reaches %s claims %d"
			% [_sim.layout.seats.size(), near.size(), reach.slice(0, 6), _sim._seat_claims.size()]
		)
	)
	for seat: Dictionary in _sim.layout.seats:
		var from: Vector2i = (
			(seat["front"] as Vector2i) * (START_CELLS + 1)
			- (seat["cell"] as Vector2i) * START_CELLS
		)
		_plain.at = from
		_plain.clear_path()
		var claimed := GateCapacity.claim_seat(_sim, _plain)
		print(
			(
				"PROBE start %s for chair %s: path to its front %d cells, claimed %s"
				% [from, seat["cell"], _sim.grid.find_path(from, seat["front"]).size(), claimed]
			)
		)
		if claimed:
			var first := _seat_of(_plain)
			_sim._seat_claims.erase(first["key"])
			_unseat(_plain)
			if not firsts.any(func(f: Array) -> bool: return f[0] == first):
				firsts.append([first, from])
	print("PROBE first chairs from each start: %d" % firsts.size())
	for pick: Array in firsts:
		var seat: Dictionary = pick[0]
		var front: Vector2i = seat["front"]
		var start: Vector2i = pick[1]
		var made := _wall_in(seat)
		print(
			(
				"PROBE try chair %s front %s from %s: walls %d tight %s"
				% [
					seat["cell"],
					front,
					start,
					made.size(),
					made.size() == 2 and GateRoller.walled_tight(_sim, _roller, seat)
				]
			)
		)
		if made.size() == 2 and GateRoller.walled_tight(_sim, _roller, seat):
			for p: Passenger in [_roller, _plain]:
				p.at = start
				p.clear_path()
				GateCapacity.claim_seat(_sim, p)
			if _roller.seat_cell != seat["cell"] and _plain.seat_cell == seat["cell"]:
				_tight = seat
				print(
					(
						(
							"PROBE tight chair %s front %s walls %d; walled_tight roller %s plain %s;"
							+ " from %s the roller guest %d took %s, the plain guest %d took %s"
						)
						% [
							seat["cell"],
							front,
							made.size(),
							GateRoller.walled_tight(_sim, _roller, seat),
							GateRoller.walled_tight(_sim, _plain, seat),
							start,
							_roller.id,
							_roller.seat_cell,
							_plain.id,
							_plain.seat_cell,
						]
					)
				)
				return true
			for p: Passenger in [_roller, _plain]:
				if p.seat_cell != Passenger.NO_CELL:
					_sim._seat_claims.erase(_seat_of(p)["key"])
				_unseat(p)
		for side_at: int in made:
			_mode.grid.apply(BuildEdit.remove_wall(front, side_at))
	_invalid("no chair where the plain guest took the walled chair and the roller guest did not")
	return false


func _unseat(p: Passenger) -> void:
	p.seat_object = 0
	p.seat_cell = Passenger.NO_CELL
	p.seat_front = Passenger.NO_CELL
	p.seat_piece = {}
	p.clear_path()


func _wall_in(seat: Dictionary) -> Array:
	var front: Vector2i = seat["front"]
	var out: Vector2i = front - (seat["cell"] as Vector2i)
	var made: Array = []
	for step: Vector2i in [Vector2i(out.y, -out.x), Vector2i(-out.y, out.x)]:
		var side_at := BuildGrid.SIDE_STEP.find(step)
		if _mode.grid.apply(BuildEdit.place_wall(front, side_at)).ok:
			made.append(side_at)
	if made.size() < 2:
		for side_at: int in made:
			_mode.grid.apply(BuildEdit.remove_wall(front, side_at))
		return []
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	return made


func _seat_of(p: Passenger) -> Dictionary:
	for seat: Dictionary in _sim.layout.seats:
		if seat["cell"] == p.seat_cell and seat["object_id"] == p.seat_object:
			return seat
	return {}


func _watch() -> void:
	var limit := _clock.tick + LIMIT_TICKS
	var settled := -1
	while _clock.tick < limit:
		await _step()
		var sat := _roller.stage == Passenger.Stage.SEATED
		sat = sat and _plain.stage == Passenger.Stage.SEATED
		if sat and settled < 0:
			settled = _clock.tick
			print("PROBE both seated tick %d" % settled)
		if settled >= 0 and _clock.tick >= settled + SETTLE_TICKS:
			return
	_invalid(
		(
			"not both seated within %d ticks (roller %s, plain %s)"
			% [
				LIMIT_TICKS,
				Passenger.Stage.keys()[_roller.stage],
				Passenger.Stage.keys()[_plain.stage]
			]
		)
	)


## One plate of `p` seated at `seat`, its roller too when `with_bag`: views
## from ahead of the chair, above and to each side, the first that proves the
## body's feet and head (and the roller) in frame and in sight is saved.
func _plate(shot: String, p: Passenger, with_bag: bool, seat: Dictionary) -> void:
	var body := _views.node_for(p.id)
	var bag: Node3D = null
	if with_bag:
		bag = _views.carry_on_props().props_of(p.id)["bags"][0]
	var front: Vector2i = seat["front"]
	var out: Vector2i = front - (seat["cell"] as Vector2i)
	var frame := Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), _sim.grid.cell_to_world(front))
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		root.add_child(_cam)
	var views := [Vector3(0.0, 2.6, 2.4), Vector3(1.2, 2.4, 2.2), Vector3(-1.2, 2.4, 2.2)]
	for view in views.size():
		_cam.look_at_from_position(frame * views[view], frame * Vector3(0, 0.5, -0.5), Vector3.UP)
		_cam.current = true
		await _frames(2)
		if await _proved(shot, view, body, bag):
			return
	_invalid("%s: no view proved its subject in frame and in sight" % shot)


func _proved(shot: String, view: int, body: Node3D, bag: Node3D) -> bool:
	var img := root.get_texture().get_image()
	var inside := Rect2(
		Vector2.ONE * MARGIN_PX, Vector2(img.get_size()) - Vector2.ONE * MARGIN_PX * 2.0
	)
	var points := {"feet": body.global_position, "head": body.global_position + Vector3.UP * 1.3}
	if bag != null:
		points["bag"] = bag.global_position
	for name: String in points:
		var px := _cam.unproject_position(points[name])
		if _cam.is_position_behind(points[name]) or not inside.has_point(px):
			print("PLATE_REFUSED %s view %d: %s at %s out of frame" % [shot, view, name, px])
			return false
		print("PLATE %s view %d %s at %s" % [shot, view, name, px.round()])
	var subject: Node3D = bag if bag != null else body
	var holder := PlateSight.colliders(root, [_views, _mode.get_node("BuildView")], {subject: TAG})
	if not (holder.get_meta("unbaked") as Array).is_empty():
		holder.free()
		_invalid("%s: skinned meshes without a sight collider" % shot)
		return false
	await physics_frame
	await physics_frame
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get(TAG, AABB())
	var c := box.get_center()
	var targets: Array[Vector3] = [c]
	for d: Vector3 in [
		Vector3(0.08, 0, 0), Vector3(-0.08, 0, 0), Vector3(0, 0, 0.1), Vector3(0, 0, -0.1)
	]:
		targets.append(c + d)
	var space := _cam.get_world_3d().direct_space_state
	var lines := PlateSight.sight_lines(space, _cam.global_position, targets, TAG)
	var on: int = (lines["on_subject"] as Array).size()
	holder.free()
	print(
		(
			"PLATE %s view %d %s box %s sight on %d past %d blockers %s"
			% [
				shot,
				view,
				"roller" if bag != null else "body",
				box,
				on,
				lines["past"],
				lines["blockers"]
			]
		)
	)
	if on < MIN_ON:
		print("PLATE_REFUSED %s view %d: %d of 5 lines on the subject" % [shot, view, on])
		return false
	var path := _out_dir.path_join("%s.png" % shot)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return false
	_saved.append(path)
	print("PLATE saved %s view %d" % [path, view])
	return true


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID %s" % why)
