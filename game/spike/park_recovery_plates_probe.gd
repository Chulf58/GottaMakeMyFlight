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
## Plates go to tools/blender/out/park-recovery/.

const StarterFlight := preload("res://spike/starter_flight.gd")
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

var _seed := 0
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
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		await _collect()
	print("PROBE done plates=%d failed=%s" % [_saved.size(), _failed])
	quit(1 if _failed or _saved.size() < 8 else 0)


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
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
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
		var bag := props.bag_state(_p.id, 0)
		var k := props.transfer_progress(_p.id, 0)
		var moved := body.global_position.distance_to(last_body)
		last_body = body.global_position
		var off_floor: bool = (
			bag.get("park", false) and CarryLead.start_of(bag)[0] == CarryLead.End.REST
		)
		if not gone and bag.get("park", false) and not off_floor and k >= 0.15:
			gone = true
			_mode.grid.apply(BuildEdit.remove_object(seat["object_id"]))
			(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
			print("PROBE seat removed at pull>floor k=%.3f tick %d" % [k, _clock.tick])
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
		elif wants.has("walk") and moved > 0.005:
			shot = "walk"
		if shot != "":
			wants.erase(shot)
			await _plate(shot, body, node, bag, k, lead)
	if not wants.is_empty():
		_invalid("plates never reached: %s" % [wants])


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
	await RenderingServer.frame_post_draw


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID %s" % why)
