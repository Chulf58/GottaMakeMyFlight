class_name TestQueueStandSideSim
extends GdUnitTestSuite
## The side a queue-stood roller stands on (decision a-roller-stood-in-a-queue-
## beside-a-wall-goes-on-the-passenge) is chosen from sim state only
## (ParkSide.choose_stand(), in CarryOnProps.sync()), never from the drawn body
## (anti-pattern view-state-stepped-on-from-the-previous-draw-makes-a-carry-p):
## a check-in queuer beside a wall, drawn facing two ways, stands its roller on
## one side. A two-bag guest keeps its usual side (SecurityLooks.hand_of() keeps
## a bag in each hand; decision pullside-as-built-a-pulled-roller-changes-hand-
## away-from-wal). The queuer is put on an open cell of the reference terminal
## with a wall built on the cell's south edge, the side on its right as it
## faces east, the way it walked in; the sim is not ticked, so its state holds.

const ROLLER := SecurityLooks.Kind.ROLLER
## East, the way the queuer walked to its cell, and the other way.
const EAST := PI / 2.0
const WEST := -PI / 2.0
## Ticks drawn standing still: past RollerPark.STILL_TICKS and the stand's start.
const STILL_RUN := 20

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


## Draws `p` standing still STILL_RUN ticks, its body drawn facing `yaw`, as
## the game syncs and draws a tick: the hand its queue stand was chosen with
## ("queue_hand"), whether the stand is under way, the hand of its place and
## the yaw it was drawn with last.
func _stood(p: Passenger, yaw: float) -> Dictionary:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_views.sync()
	_views._turns.place(p.id, yaw)
	var props := _views.carry_on_props()
	for n in STILL_RUN:
		_world.clock.tick += 1
		_views.sync()
		_views.draw()
		props._unposed()
	var bag := props.bag_state(p.id, 0)
	var mark: Array = bag.get("queue_hand", [])
	var seen := {
		"chosen": int(mark[1]) if not mark.is_empty() else -1,
		"queued": RollerPark.queued(bag),
		"hand": CarryLead.hand_of(int(bag.get("place", 0))),
		"yaw": _views.node_for(p.id).rotation.y,
	}
	_views.free()
	_views = null
	return seen


## The frame a body drawn facing `yaw` on _cell stands in.
func _drawn_frame(yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), _world.grid.cell_to_world(_cell))


## One sim state, drawn facing east and facing west: both stand the roller in
## the same hand, the left (the open side for the way the sim has it face),
## both choices made and both stands under way. Control: the side chosen from
## each drawn body's own facing (as CarryPlace did in draw) differs, the west
## one walled on the left, so a choice read from the view would flip.
func test_one_sim_state_drawn_two_ways_stands_one_side() -> void:
	var p := _queuer()
	var east := _stood(p, EAST)
	var west := _stood(p, WEST)
	var walls := PullSide.walls_near(_world.grid, _world.grid.cell_to_world(_cell))
	var look := PassengerLooks.body_of(p.id, p.variant)
	var by_view := [
		ParkSide.stand_hand(_drawn_frame(EAST), 1, 1.0, look, walls),
		ParkSide.stand_hand(_drawn_frame(WEST), 1, 1.0, look, walls),
	]
	print(
		(
			"cell %s: drawn east %s, drawn west %s; chosen by the drawn facing %s"
			% [_cell, east, west, by_view]
		)
	)
	assert_float(absf(angle_difference(float(east["yaw"]), EAST))).is_less(0.01)
	assert_float(absf(angle_difference(float(west["yaw"]), WEST))).is_less(0.01)
	assert_int(by_view[0]).is_equal(1)
	assert_int(by_view[1]).is_equal(0)
	for seen: Dictionary in [east, west]:
		assert_int(seen["chosen"]).is_equal(1)
		assert_bool(seen["queued"]).is_true()
		assert_int(seen["hand"]).is_equal(1)


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
