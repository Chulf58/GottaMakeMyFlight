extends SceneTree
## Windowed probe of boarding-file waiters on their wait spots (board 3e3cb33e,
## FileWaiters): it boots main.tscn with the reference terminal and its gate desk, opens the
## airport, runs to boarding and turns walkers with a roller each out on
## FILE_CELLS. Once at least MIN_WAITERS of them wait in their file, each
## still for STILL_FOR ticks, it prints every waiter's sim and drawn point, the least
## distance between two waiters, and each roller's tilt (+z to up) and
## distance from its walker, then saves one plate. Before the save every
## waiter's feet, head and roller project inside the frame with a margin, each
## waiter is shown (PlateSight.person_shown) and a sight line lands on each
## roller; a control ray tagged with no collider's tag must come back blocked.
## Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/file_waiters_probe.gd [-- --seed=N]

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/file-walkers"
## Where the walkers turn out: four on seed 44974's cell and four on the cell
## behind it, so the file holds them long enough for three or more to wait on
## wait spots for STILL_FOR ticks. The last on each cell, finding no free spot,
## waits on its point with the walker it turned out with (the probe's own
## stack, inherited by the files); a plate subject stands alone.
const FILE_CELLS: Array[Vector2i] = [
	Vector2i(19, 6),
	Vector2i(19, 6),
	Vector2i(19, 6),
	Vector2i(19, 6),
	Vector2i(19, 7),
	Vector2i(19, 7),
	Vector2i(19, 7),
	Vector2i(19, 7)
]
const MIN_WAITERS := 3
const STILL_FOR := RollerPark.FILE_STILL_TICKS + RollerPark.QUEUE_STAND_TICKS + 3.0
const LIMIT_TICKS := 400
const MARGIN_PX := 8.0
const MIN_BODY_PX := 60.0
const NO_TAG := "nothing_has_this_tag"

var _seed := 0
var _out_dir := ""
var _main: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
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
	var ok := await _boot()
	if ok:
		ok = await _waiters()
	print("PROBE done ok=%s" % ok)
	quit(0 if ok else 1)


func _boot() -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	if not ReferenceTerminal.build(mode.grid) or not StarterFlight.add_gate_desk(mode.grid):
		return _invalid("the reference terminal or its gate desk was refused")
	_offset = ReferenceTerminal.offset_on(mode.grid)
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	await _frames(4)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE hired=%d opened tick=%d doors=%d offset=%s" % [hired, _clock.tick, doors, _offset])
	if hired == 0 or doors < 0:
		return _invalid("the airport did not open")
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_clock.ticked.connect(
		func(_t: int) -> void:
			for p in _keep:
				p.late = false
	)
	return true


## A calm, cleared passenger of the first flight with one roller, turning to
## the exit on `cell`.
func _walker(cell: Vector2i) -> Passenger:
	for attempt in 400:
		var p := _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
		if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			p.carry_on = 0
			continue
		# As TestBoardingFiles.turn_out() makes one, with its roller.
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		p.cleared = true
		p.shop_cooldown = 1000000
		p.boredom = 0
		p.stage = Passenger.Stage.TO_EXIT
		p.stage_tick = _clock.tick
		p.at = cell + _offset
		p.clear_path()
		p.apron = []
		p.apron_mm = 0
		_keep.append(p)
		return p
	return null


func _waiters() -> bool:
	var first := _walker(FILE_CELLS[0])
	if first == null:
		return _invalid("no roller guest")
	var boarding := first.boarding_tick
	print("PROBE boarding tick %d" % boarding)
	# Only its boarding tick was wanted: it goes to the gate like any guest.
	_keep.erase(first)
	first.stage = Passenger.Stage.TO_GATE
	while _clock.tick < boarding + 2:
		_clock.advance(SimClock.STEP)
	await _frames(2)
	var walkers: Array[Passenger] = []
	for cell in FILE_CELLS:
		var p := _walker(cell)
		if p == null:
			return _invalid("no roller guest")
		walkers.append(p)
	print(
		(
			"FILE walkers %s at tick %d"
			% [walkers.map(func(p: Passenger) -> int: return p.id), _clock.tick]
		)
	)
	var still := {}
	var stop := _clock.tick + LIMIT_TICKS
	var waiting: Array[Passenger] = []
	while _clock.tick < stop:
		_clock.advance(SimClock.STEP / 3.0)
		await _frames(1)
		waiting.clear()
		for p in walkers:
			var moved := _views.tick_position(p.id, true).distance_to(
				_views.tick_position(p.id, false)
			)
			var held := _sim.files.is_pending(p.id) and moved < 0.001
			still[p.id] = float(still.get(p.id, 0.0)) + 1.0 / 3.0 if held else 0.0
			# One of each group still on the point they all turned out on (the
			# stack is the probe's own, inherited by the files): the plate is
			# of waiters the files placed.
			if still[p.id] >= STILL_FOR and _apart_from(p, waiting) and _alone(p, walkers):
				waiting.append(p)
		if waiting.size() >= MIN_WAITERS:
			break
	for p in walkers:
		print(
			(
				"WALKER %d stage %d exit %d stuck %d pending %s at %s still %.1f"
				% [
					p.id,
					p.stage,
					p.exit_object,
					p.stuck,
					_sim.files.is_pending(p.id),
					p.at,
					still[p.id]
				]
			)
		)
	if waiting.size() < MIN_WAITERS:
		return _invalid("only %d waiters held still %.0f ticks" % [waiting.size(), STILL_FOR])
	return await _report(waiting)


func _report(waiting: Array[Passenger]) -> bool:
	var nearest := INF
	var nearest_sim := INF
	var bags := {}
	for i in waiting.size():
		var p := waiting[i]
		var body := _views.node_for(p.id)
		var bag: Node3D = _views.carry_on_props().props_of(p.id)["bags"][0]
		bags[p.id] = bag
		var up := bag.global_transform.basis.z.normalized().dot(Vector3.UP)
		print(
			(
				"WAITER %d sim %s drawn %s roller up %.3f beside %.3f m"
				% [
					p.id,
					_sim.world_position(p),
					body.global_position,
					up,
					_flat(body.global_position).distance_to(_flat(bag.global_position))
				]
			)
		)
		for k in range(i + 1, waiting.size()):
			var other := _views.node_for(waiting[k].id)
			nearest = minf(
				nearest, _flat(body.global_position).distance_to(_flat(other.global_position))
			)
			var in_sim := _sim.world_position(p).distance_to(_sim.world_position(waiting[k]))
			nearest_sim = minf(nearest_sim, in_sim)
	print(
		(
			"MIN_WAITER_DISTANCE drawn %.3f m, sim %.3f m between %d waiters"
			% [nearest, nearest_sim, waiting.size()]
		)
	)
	var centre := Vector3.ZERO
	for p in waiting:
		centre += _views.node_for(p.id).global_position
	centre = centre / waiting.size() + Vector3.UP * 0.6
	var cam := Camera3D.new()
	cam.fov = 45.0
	_main.add_child(cam)
	for away: Vector3 in [
		Vector3(1, 0, 1),
		Vector3(-1, 0, 1),
		Vector3(1, 0, -1),
		Vector3(-1, 0, -1),
		Vector3(1, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(0, 0, 1),
		Vector3(0, 0, -1)
	]:
		# Steep, so each roller beside its walker shows over the bodies.
		cam.look_at_from_position(centre + away.normalized() * 1.8 + Vector3.UP * 5.5, centre)
		cam.current = true
		await _frames(3)
		var why := await _check(cam, waiting, bags)
		if why == "":
			var img := root.get_texture().get_image()
			var path := _out_dir.path_join("file_waiters.png")
			if img.save_png(path) != OK:
				return _invalid("could not save %s" % path)
			print("PLATE saved %s size=%s" % [path, img.get_size()])
			return nearest >= BoardingFiles.GAP_MM / 1000.0 - 0.001 or _invalid("waiters too close")
		print("PLATE view %s refused: %s" % [away, why])
	return _invalid("no view shows every waiter and roller")


## "" when the plate now shows every waiter and its roller, else why not.
func _check(cam: Camera3D, waiting: Array[Passenger], bags: Dictionary) -> String:
	var size := root.get_visible_rect().size
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var subjects := {}
	var owners: Array[Node] = [_main]
	for p in waiting:
		subjects[_views.node_for(p.id)] = "w%d" % p.id
		subjects[bags[p.id]] = "b%d" % p.id
	var holder := PlateSight.colliders(root, owners, subjects)
	await physics_frame
	await physics_frame
	var img := root.get_texture().get_image()
	var bounds: Dictionary = holder.get_meta("bounds", {})
	var space := cam.get_world_3d().direct_space_state
	var why := ""
	for p in waiting:
		var body := _views.node_for(p.id)
		var bag: Node3D = bags[p.id]
		for point: Vector3 in [
			body.global_position, body.global_position + Vector3.UP * 1.7, bag.global_position
		]:
			var at := cam.unproject_position(point)
			print("FRAME %d point %s at %s" % [p.id, point, at])
			if cam.is_position_behind(point) or not inside.has_point(at):
				why = "waiter %d point %s out of frame at %s" % [p.id, point, at]
		var shown := PlateSight.person_shown(
			cam, bounds.get("w%d" % p.id, AABB()), "w%d" % p.id, inside, img, img, MIN_BODY_PX
		)
		var box: AABB = bounds.get("b%d" % p.id, AABB())
		var to_bag: Array[Vector3] = [
			box.get_center(),
			box.get_center() + Vector3.UP * box.size.y * 0.3,
			box.get_center() - Vector3.UP * box.size.y * 0.3,
			box.get_center() + Vector3.UP * box.size.y * 0.45
		]
		var bag_line := PlateSight.sight_lines(space, cam.global_position, to_bag, "b%d" % p.id)
		print("SIGHT %d person %s bag %s" % [p.id, shown, bag_line])
		if not shown["ok"] or (bag_line["on_subject"] as Array).is_empty():
			why = "waiter %d or its roller not in sight" % p.id
	# Control: a line to a waiter's body under a tag no collider has is blocked.
	var control_to: Array[Vector3] = [bounds.get("w%d" % waiting[0].id, AABB()).get_center()]
	var control := PlateSight.sight_lines(space, cam.global_position, control_to, NO_TAG)
	print("CONTROL %s" % control)
	if (control["blockers"] as Array).is_empty():
		why = "the control line hit no collider"
	holder.free()
	return why


static func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## Whether no other walker of `walkers` still heading out stands on `p`'s point.
func _alone(p: Passenger, walkers: Array[Passenger]) -> bool:
	for q in walkers:
		var near := _flat(_sim.world_position(p)).distance_to(_flat(_sim.world_position(q)))
		if q != p and q.stage == Passenger.Stage.TO_EXIT and near < 0.05:
			return false
	return true


## Whether `p` stands the gap or more from every one of `chosen` in the sim.
func _apart_from(p: Passenger, chosen: Array[Passenger]) -> bool:
	for q in chosen:
		var d := _flat(_sim.world_position(p)).distance_to(_flat(_sim.world_position(q)))
		if d < FileWaiters.ROOM_M:
			return false
	return true


func _invalid(msg: String) -> bool:
	print("PROBE_INVALID ", msg)
	return false


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
