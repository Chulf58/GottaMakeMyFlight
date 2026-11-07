class_name TestQueueStandSideSim
extends GdUnitTestSuite
## The side a queue-stood roller stands on (decision a-roller-stood-in-a-queue-
## beside-a-wall-goes-on-the-passenge) is chosen and drawn in one frame taken
## from sim state (ParkSide.choose_stand(), in CarryOnProps.sync(); the stand
## drawn there by RollerPark.plan()), never from the drawn body (anti-pattern
## view-state-stepped-on-from-the-previous-draw-makes-a-carry-p): a check-in
## queuer beside a wall, its body drawn facing any way, or turning through the
## way the hand choice would flip in the middle of its stand, stands its roller
## clear of the wall, read from the roller as placed. A two-bag guest keeps its
## usual side (SecurityLooks.hand_of() keeps a bag in each hand; decision
## pullside-as-built-a-pulled-roller-changes-hand-away-from-wal). The queuer is
## put on an open cell of the reference terminal with a wall built on the
## cell's south edge, the side on its right as it faces east, the way it walked
## in; the sim is not ticked, so its state holds.

const ROLLER := SecurityLooks.Kind.ROLLER
## East, the way the queuer walked to its cell, and the other way. Yaw 0 faces
## south, into the wall; PI faces north, away from it.
const EAST := PI / 2.0
const WEST := -PI / 2.0
const SOUTH := 0.0
const NORTH := PI
## Ticks drawn standing still: past RollerPark.STILL_TICKS, the change of hand
## and the stand's roll (RollerPark.QUEUE_STAND_TICKS).
const STILL_RUN := 20
## A half turn over PassengerTurns.TURN_TICKS, as a body turns.
const TURN_STEP := PI / float(PassengerTurns.TURN_TICKS)
## Ticks held after a turn.
const HOLD_RUN := 8
## The most a stood roller may move in one tick, world (test_roller_queue_stand).
const JUMP_M := 0.15
## Ticks drawn walking off: past RollerPark.QUEUE_TIP_TICKS.
const TIP_RUN := 10
## The most a tip may step in one tick past the tip of a body not turned.
const TIP_STEP_M := 0.05

var _world: PassengerTestWorld
var _views: PassengerViews
var _cell := Vector2i(-1, -1)


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world()
	var grid := _world.grid
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if _open(cell) and _open(cell - Vector2i(1, 0)):
				_cell = cell
				break
		if _cell.x >= 0:
			break
	assert_int(_cell.x).is_greater_equal(0)
	var result := grid.apply(BuildEdit.place_wall(_cell, BuildGrid.Side.SOUTH))
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null


## Whether `cell` is indoor floor a passenger walks, with no wall or piece of
## furniture near it (PullSide's boxes).
func _open(cell: Vector2i) -> bool:
	var grid := _world.grid
	if not grid.in_bounds(cell) or not grid.is_walkable(cell) or not grid.is_indoor(cell):
		return false
	var at := grid.cell_to_world(cell)
	return PullSide.walls_near(grid, at).is_empty() and PullSide.pieces_near(grid, at).is_empty()


## A guest with a roller first, standing still in a check-in queue on _cell,
## having walked east onto it, with `carry_on` bags.
func _queuer(carry_on := 1) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = carry_on
	p.late = false
	p.stage = Passenger.Stage.CHECKIN_QUEUE
	p.at = _cell
	var path: Array[Vector2i] = [_cell - Vector2i(1, 0), _cell]
	p.set_path(path)
	p.path_index = 1
	return p


## Draws `p` standing still, as the game syncs and draws a tick and the
## skeleton reports (the bag placed from the hand), its body drawn facing
## `yaws[n]` on tick n (the last kept after the list ends) for `ticks` ticks:
## the hand its queue stand was chosen with ("queue_hand"), whether the stand
## is under way, the yaw it was drawn with last, and the roller as placed on
## each tick its stand ran ("placed": [tick n, its transform, whether it has
## rolled out to its stand, RollerPark.QUEUE_STAND_TICKS into the move]).
func _stood(p: Passenger, yaws: Array, ticks := STILL_RUN) -> Dictionary:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_views.sync()
	var props := _views.carry_on_props()
	var placed := []
	for n in ticks:
		_views._turns.place(p.id, float(yaws[mini(n, yaws.size() - 1)]))
		_world.clock.tick += 1
		_views.sync()
		_views.draw()
		await get_tree().process_frame
		props._unposed()
		var now := props.bag_state(p.id, 0)
		if RollerPark.queued(now):
			var into := _world.clock.tick - float(now["since"])
			var xf := (now["node"] as Node3D).global_transform
			placed.append([n, xf, into >= RollerPark.QUEUE_STAND_TICKS])
	var bag := props.bag_state(p.id, 0)
	var mark: Array = bag.get("queue_hand", [])
	var seen := {
		"chosen": int(mark[1]) if not mark.is_empty() else -1,
		"queued": RollerPark.queued(bag),
		"yaw": _views.node_for(p.id).rotation.y,
		"placed": placed,
	}
	_views.free()
	_views = null
	return seen


## The placed rollers (_stood()'s "placed") from tick `from` on that have
## rolled out to their stand.
func _out(placed: Array, from := 0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for at: Array in placed:
		if int(at[0]) >= from and at[2]:
			out.append(at[1])
	return out


## The frame a body drawn facing `yaw` on _cell stands in.
func _drawn_frame(yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), _world.grid.cell_to_world(_cell))


## How far (m) the roller placed at `xf` keeps north of the wall's face on
## _cell's south edge: the face less the roller box's southmost corner. Below 0
## the roller stands in or past the wall.
func _clear_of_wall(xf: Transform3D) -> float:
	var face := _world.grid.cell_to_world(_cell).z + 0.5 - BuildView.WALL_THICKNESS / 2.0
	var box := CarryOnProps.bag_box(ROLLER)
	var south := -INF
	for k in 8:
		south = maxf(south, (xf * box.get_endpoint(k)).z)
	return face - south


## The least wall clearance (_clear_of_wall()) over `placed`, and the largest
## move of the roller's centre from one tick to the next.
func _worst(placed: Array[Transform3D]) -> Vector2:
	var box := CarryOnProps.bag_box(ROLLER)
	var clear := INF
	var step := 0.0
	for n in placed.size():
		clear = minf(clear, _clear_of_wall(placed[n]))
		if n > 0:
			var was := placed[n - 1] * box.get_center()
			step = maxf(step, was.distance_to(placed[n] * box.get_center()))
	return Vector2(clear, step)


## One sim state, its body drawn facing east and facing west: the roller as
## placed stands clear of the wall both times, north of the body (the open
## side for the way the sim has it face), one hand chosen. Control: the side
## chosen from each drawn body's own facing differs, the west one walled on the
## left, so a side read from the drawn body would flip; and the stand ran.
func test_one_sim_state_drawn_two_ways_stands_clear_of_the_wall() -> void:
	var p := _queuer()
	var walls := PullSide.walls_near(_world.grid, _world.grid.cell_to_world(_cell))
	var look := PassengerLooks.body_of(p.id, p.variant)
	var by_view := [
		ParkSide.stand_hand(_drawn_frame(EAST), 1, 1.0, look, walls),
		ParkSide.stand_hand(_drawn_frame(WEST), 1, 1.0, look, walls),
	]
	var body_z := _world.grid.cell_to_world(_cell).z
	for yaw: float in [EAST, WEST]:
		var seen: Dictionary = await _stood(p, [yaw])
		var placed := _out(seen["placed"])
		assert_int(placed.size()).is_greater(0)
		var last := placed[placed.size() - 1]
		var centre := last * CarryOnProps.bag_box(ROLLER).get_center()
		print(
			(
				(
					"cell %s drawn %.2f: chosen %d, %d stood ticks, clear of the wall %.3f m,"
					+ " centre z %.3f (body %.3f); chosen by the drawn facing %s"
				)
				% [
					_cell,
					yaw,
					seen["chosen"],
					placed.size(),
					_worst(placed).x,
					centre.z,
					body_z,
					by_view
				]
			)
		)
		assert_float(absf(angle_difference(float(seen["yaw"]), yaw))).is_less(0.01)
		assert_bool(seen["queued"]).is_true()
		assert_int(seen["chosen"]).is_equal(1)
		assert_float(_worst(placed).x).is_greater(0.0)
		assert_float(centre.z).is_less(body_z)
	assert_int(by_view[0]).is_equal(1)
	assert_int(by_view[1]).is_equal(0)


## The body drawn facing the wall, away from it and on the diagonals between:
## each stands the roller clear of the wall and north of the body, on the open
## side of the way the sim has it face. Control: the stand ran each time.
func test_a_body_drawn_at_or_across_the_wall_stands_on_the_open_side() -> void:
	var yaws := [SOUTH, NORTH, PI / 4.0, -3.0 * PI / 4.0]
	var body_z := _world.grid.cell_to_world(_cell).z
	var seen_at := []
	for yaw: float in yaws:
		var p := _queuer()
		var seen: Dictionary = await _stood(p, [yaw])
		var placed := _out(seen["placed"])
		assert_int(placed.size()).is_greater(0)
		var centre := placed[placed.size() - 1] * CarryOnProps.bag_box(ROLLER).get_center()
		seen_at.append([snappedf(_worst(placed).x, 0.001), snappedf(centre.z - body_z, 0.001)])
	print("drawn %s: [clear of the wall, centre z less the body's] %s" % [yaws, seen_at])
	for at: Array in seen_at:
		assert_float(at[0]).is_greater(0.0)
		assert_float(at[1]).is_less(0.0)


## The body turns a half turn in the middle of its stand, through the way the
## hand choice flips (east to west, by the south, facing the wall, and by the
## north), then holds: no tick moves the stood roller more than JUMP_M, and
## none puts it in the wall. Control: the stand ran through every tick of the
## turn and the hold.
func test_a_turn_through_the_side_boundary_mid_stand_neither_jumps_nor_clips() -> void:
	for way: float in [-1.0, 1.0]:
		var p := _queuer()
		var yaws := []
		for n in STILL_RUN:
			yaws.append(EAST)
		for n in PassengerTurns.TURN_TICKS:
			yaws.append(EAST + way * TURN_STEP * (n + 1))
		var seen: Dictionary = await _stood(
			p, yaws, STILL_RUN + PassengerTurns.TURN_TICKS + HOLD_RUN
		)
		# From the tick before the turn: stood out beside the body, then turning.
		var placed := _out(seen["placed"], STILL_RUN - 1)
		var worst := _worst(placed)
		print(
			(
				"turned %+.0f: %d stood ticks, drawn last %.2f, clear of the wall %.3f m, largest step %.3f m"
				% [way, placed.size(), seen["yaw"], worst.x, worst.y]
			)
		)
		assert_bool(seen["queued"]).is_true()
		assert_int(placed.size()).is_equal(PassengerTurns.TURN_TICKS + HOLD_RUN + 1)
		assert_float(absf(angle_difference(float(seen["yaw"]), WEST))).is_less(0.01)
		assert_float(worst.x).is_greater(0.0)
		assert_float(worst.y).is_less(JUMP_M)


## A stand asked for on a roller in the right hand, walled on the right for
## the way the sim has the guest face: a one-bag guest goes to the left first
## (side_first() puts the stand off), a two-bag guest keeps the right and the
## stand goes ahead as asked, no side chosen.
func test_a_two_bag_guest_keeps_its_usual_side() -> void:
	var right := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var counts := [1, 2]
	var seen := []
	for carry_on: int in counts:
		var p := _queuer(carry_on)
		var bag := {"kind": ROLLER, "place": right, "still_from": 100.0, "queue_still": true}
		ParkSide.choose_stand(_world.sim, p, bag)
		seen.append([bag.get("queue_hand", []), RollerPark.restamps(bag)])
	print("asked in the right hand, (queue_hand, still asked) by bag count %s: %s" % [counts, seen])
	assert_array(seen[0][0]).is_equal([100.0, 1, true])
	assert_bool(seen[0][1]).is_false()
	assert_array(seen[1][0]).is_empty()
	assert_bool(seen[1][1]).is_true()


## Draws `p` stood up beside the wall drawn facing east, then its body drawn
## turned by `turn` (radians) while it stays still, then walking off the way it
## is drawn facing (its path opened a cell that way, the sim not ticked), so
## the tip starts with the body turned from the stand's frame and needs no turn
## wait (RollerPark.tip_wait()): [the roller's centre on each tick from the
## turn on, its least wall clearance, whether the tip ran].
func _tipped(p: Passenger, turn: float) -> Array:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_views.sync()
	var props := _views.carry_on_props()
	var box := CarryOnProps.bag_box(ROLLER)
	var centres: Array[Vector3] = []
	var clear := INF
	var tipped := false
	var ahead := Vector2i(roundi(sin(EAST + turn)), roundi(cos(EAST + turn)))
	for n in STILL_RUN + HOLD_RUN + TIP_RUN:
		_views._turns.place(p.id, EAST if n < STILL_RUN else EAST + turn)
		if n == STILL_RUN + HOLD_RUN:
			var way: Array[Vector2i] = [_cell, _cell + ahead]
			p.set_path(way)
		_world.clock.tick += 1
		_views.sync()
		_views.draw()
		await get_tree().process_frame
		props._unposed()
		var bag := props.bag_state(p.id, 0)
		tipped = tipped or bag.has("queue_tip")
		if n >= STILL_RUN - 1:
			var xf := (bag["node"] as Node3D).global_transform
			centres.append(xf * box.get_center())
			clear = minf(clear, _clear_of_wall(xf))
	_views.free()
	_views = null
	return [centres, clear, tipped]


## The body is drawn turned away from the way its stand was chosen in (a
## quarter turn to face the wall, and a half turn) before it walks off that
## way: the tip takes the stood roller from where it stood with no tick moving
## it more than TIP_STEP_M past the largest step of the tip of a body not turned
## (the first case, the tip's own pace: about 0.36 m a tick, 0.12 m a frame at
## three frames a tick). Wall clearance is checked only not turned and for the
## quarter turn. A half turn is left out of the wall check: the roller stays in its
## stand's hand (RollerPark.hold_park()), the left, which for a body facing
## west is the walled side, so the walking pull it tips into stands in the wall
## (board aa2db71d's walking-pull clip; printed). Control: the tip ran each time.
func test_a_tip_after_the_body_turned_from_the_stand_does_not_jump() -> void:
	var seen := []
	for turn: float in [0.0, -PI / 2.0, PI]:
		var p := _queuer()
		var got: Array = await _tipped(p, turn)
		var centres: Array[Vector3] = got[0]
		var step := 0.0
		for n in range(1, centres.size()):
			step = maxf(step, centres[n - 1].distance_to(centres[n]))
		seen.append([turn, snappedf(step, 0.001), snappedf(got[1], 0.001), got[2]])
		p.clear_path()
	print("[turned, largest step, clear of the wall, tipped]: %s" % [seen])
	for at: Array in seen:
		assert_bool(at[3]).is_true()
		assert_float(at[1]).is_less_equal(float(seen[0][1]) + TIP_STEP_M)
	for at: Array in seen.slice(0, 2):
		assert_float(at[2]).is_greater(0.0)
