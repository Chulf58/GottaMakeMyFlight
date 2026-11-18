extends RefCounted
## Every hand-led move of one passenger, swept finely for the booth crossing
## probe (basic_scanner_crossing_probe.gd, booth or --lane mode, calls scan()
## first on each sim tick). With `--grip-sweep=<passenger id>[,<id>...]` the
## probe holds the clock on the tick one of those passengers' bags starts a
## move, then steps
## it STEP_TICKS at a time, a frame drawn after each, until none of its bags is
## moving, printing for each moving bag its GRIP_ON gap and limit
## (carry_float_check.gd grip_on_gap()), its FLOAT state and where the holding
## hand's grip is in the bag's own frame (GRIP_SWEEP lines), then the largest
## gap of the move (GRIP_SWEEP_MAX). Then it lets the clock go and waits for the
## passenger's next move. Board item G (a365cb0b): GRIP_ON over the limit on a
## hard case's floor pick-up and a roller's put-in and pick-up; one windowed run
## samples a move on a handful of frames, which differ run to run (finding
## how-much-do-the-scanner-crossing-lane-probe-s-per-passenger).
## Load with preload(); no class_name.

enum State { IDLE, HELD }

const FloatCheck := preload("res://spike/carry_float_check.gd")
const PlateSteps := preload("res://spike/carry_plate_steps.gd")
const STEP_TICKS := 0.1
const MAX_STEPS := 600

## The passengers to sweep (--grip-sweep=4,5,6), null before the arguments are
## read.
static var _targets = null
## The one being swept now.
static var _target := -1
static var _state := State.IDLE
static var _moves := 0


## Called first on each sim tick. Once a bag of a target starts a move and no
## other plate runs, holds the plate task and sweeps it (_sweep). Returns
## whether it holds the plate task.
static func scan(probe) -> bool:
	if _targets == null:
		_targets = []
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--grip-sweep="):
				for id in arg.get_slice("=", 1).split(","):
					_targets.append(int(id))
		print("GRIP_SWEEP targets=%s" % [_targets])
	if _targets.is_empty():
		return false
	if _state == State.HELD:
		return true
	if probe._plate_task or probe._hold_frame >= 0:
		return false
	_target = -1
	for id: int in _targets:
		if _moving(probe, id):
			_target = id
			break
	if _target < 0:
		return false
	_state = State.HELD
	probe._plate_task = true
	probe._clock.set_paused(true)
	probe._clock._accumulator = 0.0
	print("GRIP_SWEEP held passenger=%d tick=%d" % [_target, probe._clock.tick])
	_sweep.call_deferred(probe)
	return true


## Whether passenger `id` is swept (the probe then plates none of its moves:
## a plate would hold the clock through the move the sweep is to step).
static func sweeps(id: int) -> bool:
	return _targets != null and (_targets as Array).has(id)


## Whether a bag of passenger `id` is in a move now.
static func _moving(probe, id: int) -> bool:
	var props: CarryOnProps = probe._views.carry_on_props()
	if probe._sim.get_passenger(id) == null or probe._views.node_for(id) == null:
		return false
	var bags: Array = props.props_of(id)["bags"]
	for i in bags.size():
		if FloatCheck.move_of(props, id, i) != "":
			return true
	return false


## Steps the target's moving bags to the end of their moves, printing each
## step (GRIP_SWEEP) and each move's largest gap (GRIP_SWEEP_MAX); lets the
## clock and the plate task go.
static func _sweep(probe) -> void:
	var clock: SimClock = probe._clock
	var props: CarryOnProps = probe._views.carry_on_props()
	var worst := {}
	var steps := 0
	await probe._frames(1)
	for _step in MAX_STEPS:
		var body: Node3D = probe._views.node_for(_target)
		var p: Passenger = probe._sim.get_passenger(_target)
		if body == null or p == null:
			break
		var bags: Array = props.props_of(_target)["bags"]
		var drawn: float = clock.tick + clock._accumulator / SimClock.STEP
		steps += 1
		var any := false
		for i in bags.size():
			var move := FloatCheck.move_of(props, _target, i)
			if move == "":
				continue
			any = true
			var line := measure(probe, body, p, i, move, drawn)
			var key := "%d %s" % [i, move]
			var was: Array = worst.get(key, [-1.0, 0.0, 0.0])
			if line[0] < INF and line[0] > was[0]:
				was = [line[0], line[1], line[2]]
			worst[key] = was
		if not any:
			break
		PlateSteps.step_clock(clock, STEP_TICKS)
		await probe._frames(1)
	for key: String in worst:
		var w: Array = worst[key]
		print(
			(
				"GRIP_SWEEP_MAX passenger=%d move#%d bag_move=%s gap_m=%.3f limit_m=%.3f at_k=%.3f"
				% [_target, _moves, key, w[0], w[2], w[1]]
			)
		)
	print("GRIP_SWEEP_DONE passenger=%d move#%d steps=%d" % [_target, _moves, steps])
	_moves += 1
	_state = State.IDLE
	clock.set_paused(false)
	probe._plate_task = false


## One step's line for bag `i` of the target: prints it and returns
## [gap, k, limit].
static func measure(probe, body: Node3D, p: Passenger, i: int, move: String, drawn: float) -> Array:
	var props: CarryOnProps = probe._views.carry_on_props()
	var bag: Node3D = props.props_of(_target)["bags"][i]
	var stall := FloatCheck.stall_move(props, _target, i, p)
	var on := FloatCheck.grip_on_gap(props, _target, i, body, stall)
	var state: Array = FloatCheck.float_state(probe._sim, probe._views, _target, i)
	var k := props.transfer_progress(_target, i)
	var rec := props.bag_state(_target, i)
	var holder: int = rec.get("held_by", -1)
	var grip_local := Vector3.INF
	if holder >= 0:
		grip_local = bag.global_transform.affine_inverse() * props.grip_of(body, holder)
	var lead: Dictionary = rec.get("lead", {})
	var target_gap := INF
	if holder >= 0 and lead.has("targets"):
		target_gap = props.grip_of(body, holder).distance_to(lead["targets"][holder])
	print(
		(
			(
				"GRIP_SWEEP passenger=%d bag=%d move=%s k=%.3f sim=%.2f holder=%d gap_m=%.3f"
				+ " limit_m=%.3f state=%s hand_gap_m=%.3f grip_local=%s anchor=%s"
				+ " hand_to_target_m=%.3f stage=%d phase=%d"
			)
			% [
				_target,
				i,
				move,
				k,
				drawn,
				holder,
				on[0],
				on[1],
				state[0],
				state[1],
				grip_local.snapped(Vector3.ONE * 0.001),
				(lead.get("anchor", Vector3.INF) as Vector3).snapped(Vector3.ONE * 0.001),
				target_gap,
				p.stage,
				p.security_phase,
			]
		)
	)
	return [on[0], k, on[1]]
