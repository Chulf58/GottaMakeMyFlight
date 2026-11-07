class_name TestQueueStandGateFace
extends GdUnitTestSuite
## A gate stander's queue stand faces a way known to the sim (ParkSide.
## stand_face()), so its open side (decision a-roller-stood-in-a-queue-beside-
## a-wall-goes-on-the-passenge) is chosen and drawn in one frame: the way its
## body turns stepping from its cell's middle onto its spot, else the way it
## walked onto that cell (Passenger.stand_from, which GateCapacity.to_spot()
## keeps as it clears the path), else ParkSide.GATE_FACE. Before, to_spot()
## cleared the path and stand_face() was ZERO for every gate stander (board
## f71895c6). All of it is saved sim state (save version 30), so a save and
## load stands the roller in the same place.

const ROLLER := SecurityLooks.Kind.ROLLER
## A basic scanner's exit cell in the reference terminal.
const SCANNER_EXIT := TestStandingSpotClaims.SCANNER_EXIT
## Boarding opens long after the guest stands.
const BOARDING := 3000
const DOORS := 5000
## Ticks to walk to the spot and stand.
const WALK_LIMIT := 400
## Ticks drawn after standing: past the step onto the spot, the still wait and
## the stand's roll (RollerPark.QUEUE_STAND_TICKS).
const STAND_RUN := 30
## The roller drawn after a load stands where it stood before, to this (m).
const SAME_M := 0.01

var _world: PassengerTestWorld
var _views: PassengerViews
var _loaded: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	for world: PassengerTestWorld in [_world, _loaded]:
		if world != null:
			world.free_all()
	_world = null
	_loaded = null


## A seatless gate world: every cleared guest stands.
func _gate_world() -> PassengerTestWorld:
	return TestStandingSpotClaims.seatless_world(PassengerTestWorld.starts_with(BOARDING, DOORS))


## A calm, cleared guest with one roller on its way to the gate from the
## scanner exit, trying for a seat or spot on the next tick.
func _roller_guest(world: PassengerTestWorld) -> Passenger:
	var p := TestStandingSpotClaims.cleared(world)
	while true:
		p.carry_on = 1
		if SecurityLooks.bag_kind(p, 0) == ROLLER:
			return p
		p.carry_on = 0
		p = TestStandingSpotClaims.cleared(world)
	return p


## A view of `world`'s sim, added to the tree; snapped as a load does.
func _view(world: PassengerTestWorld) -> PassengerViews:
	_views = PassengerTestWorld.views()
	_views.clock = world.clock
	_views.sim = world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_views.snap()
	return _views


## One tick of `world` drawn: the sim and the views step, the frame is drawn
## and the skeleton reports.
func _tick(world: PassengerTestWorld) -> void:
	world.step()
	await get_tree().process_frame
	_views.carry_on_props()._unposed()


## Draws `p` of `world` STAND_RUN ticks from now: the roller as placed once it
## has rolled out to its queue stand, or null.
func _stood_roller(world: PassengerTestWorld, p: Passenger) -> Variant:
	var stood: Variant = null
	for n in STAND_RUN:
		await _tick(world)
		var bag := _views.carry_on_props().bag_state(p.id, 0)
		if RollerPark.queued(bag) and world.clock.tick - float(bag["since"]) >= 6.0:
			stood = (bag["node"] as Node3D).global_transform
	return stood


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## A guest walks to its spot and stands: its stand faces a way, and that way
## is the way its body is drawn facing, so the stand is placed beside the body.
## Its roller stands up there. Control: its path is cleared to its cell, so the
## way comes from the step onto the spot, not a path; and the cell it came from
## is kept, a step from its own.
func test_a_gate_stander_faces_the_way_its_body_turns() -> void:
	_world = _gate_world()
	var p := _roller_guest(_world)
	_view(_world)
	var limit := WALK_LIMIT
	while p.stage != Passenger.Stage.STANDING and limit > 0:
		await _tick(_world)
		limit -= 1
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	var stood: Variant = await _stood_roller(_world, p)
	var sim := _world.sim
	var face := ParkSide.stand_face(sim, p)
	var yaw := _views.node_for(p.id).rotation.y
	var spot := sim.standing.world_of(sim.grid, sim.standing.spot_of(p.id))
	var over := spot - sim.grid.cell_to_world(p.at)
	print(
		(
			(
				"stands on %s, path %s, onto the spot %s:"
				+ " faces %s (yaw %.3f), drawn %.3f, stood %s"
			)
			% [p.at, p.path, over, face, atan2(face.x, face.y), yaw, stood != null]
		)
	)
	assert_int(p.path.size()).is_equal(1)
	assert_int((p.at - p.stand_from).abs().x + (p.at - p.stand_from).abs().y).is_equal(1)
	assert_float(Vector2(over.x, over.z).length()).is_greater(ParkSide.SPOT_STEP_M)
	assert_bool(face != Vector2.ZERO).is_true()
	assert_float(absf(angle_difference(yaw, atan2(face.x, face.y)))).is_less(0.05)
	assert_bool(stood != null).is_true()


## stand_face() at the gate, from sim state alone: the step onto the spot when
## there is one; with none (a spot on its cell's middle), the way it walked
## onto the cell, standing or setting off; walked none, GATE_FACE. Control:
## the same guest with no spot (in the check-in queue) has no way at all.
func test_a_gate_stander_with_no_step_onto_its_spot_faces_its_way_in() -> void:
	_world = _gate_world()
	var sim := _world.sim
	var middle := StandingSpots.NO_SPOT
	var off := StandingSpots.NO_SPOT
	for id: int in sim.standing.spots:
		var mm: Vector2i = sim.standing.spots[id]["mm"]
		var centred := mm % StandingSpots.CELL_MM == Vector2i.ONE * StandingSpots.HALF_CELL_MM
		if centred and middle == StandingSpots.NO_SPOT:
			middle = id
		if mm.x % StandingSpots.CELL_MM == 100 and mm.y % StandingSpots.CELL_MM == 500:
			off = id
	assert_int(middle).is_not_equal(StandingSpots.NO_SPOT)
	assert_int(off).is_not_equal(StandingSpots.NO_SPOT)
	var p := TestStandingSpotClaims.cleared(_world)
	var seen := []
	# [spot, stage, came from south (or walked none)]
	var cases := [
		[off, Passenger.Stage.STANDING, true],
		[middle, Passenger.Stage.STANDING, true],
		[middle, Passenger.Stage.TO_EXIT, true],
		[middle, Passenger.Stage.STANDING, false],
	]
	for case: Array in cases:
		sim.standing.release(p.id)
		sim.standing.claim(p.id, case[0])
		p.stage = case[1]
		p.at = sim.standing.cell_of(case[0])
		p.stand_from = p.at + Vector2i(0, 1) if case[2] else Passenger.NO_CELL
		p.clear_path()
		seen.append(ParkSide.stand_face(sim, p))
	sim.standing.release(p.id)
	p.stage = Passenger.Stage.CHECKIN_QUEUE
	var none := ParkSide.stand_face(sim, p)
	print(
		(
			"onto a spot 0.4 m west; on a middle came north, setting off, walked none: %s; no spot: %s"
			% [seen, none]
		)
	)
	assert_float((seen[0] as Vector2).normalized().dot(Vector2.LEFT)).is_greater(0.99)
	var north := Vector2(0.0, -1.0)
	assert_array(seen.slice(1)).is_equal([north, north, ParkSide.GATE_FACE])
	assert_bool(none == Vector2.ZERO).is_true()


## A guest stands its roller at the gate; the game is saved and loaded and
## drawn again from the load (every bag record starts over): the roller
## stands up again where it stood, and the stand faces the same way. Control:
## the loaded guest is the same, standing on the same cell.
func test_a_gate_stand_stands_in_the_same_place_after_a_load() -> void:
	_world = _gate_world()
	var p := _roller_guest(_world)
	_view(_world)
	var limit := WALK_LIMIT
	while p.stage != Passenger.Stage.STANDING and limit > 0:
		await _tick(_world)
		limit -= 1
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING)
	var before: Variant = await _stood_roller(_world, p)
	assert_bool(before != null).is_true()
	var face := ParkSide.stand_face(_world.sim, p)
	var save := [
		_json(_world.clock.to_snapshot()),
		_json(_world.flights.to_snapshot()),
		_json(_world.sim.to_snapshot()),
	]
	_views.free()
	_views = null
	_loaded = _gate_world()
	assert_bool(_loaded.clock.from_snapshot(save[0])).is_true()
	assert_bool(_loaded.flights.from_snapshot(save[1])).is_true()
	assert_bool(_loaded.sim.from_snapshot(save[2])).is_true()
	var q := _loaded.passenger(p.id)
	_view(_loaded)
	var after: Variant = await _stood_roller(_loaded, q)
	assert_bool(after != null).is_true()
	var moved := (before as Transform3D).origin.distance_to((after as Transform3D).origin)
	print(
		(
			(
				"before the load faced %s, stood at %s; after %s (path %s, body drawn %.3f),"
				+ " stood at %s: %.4f m apart"
			)
			% [
				face,
				(before as Transform3D).origin,
				ParkSide.stand_face(_loaded.sim, q),
				q.path,
				_views.node_for(q.id).rotation.y,
				(after as Transform3D).origin,
				moved
			]
		)
	)
	assert_int(q.stage).is_equal(Passenger.Stage.STANDING)
	assert_that(q.at).is_equal(p.at)
	assert_that(q.stand_from).is_equal(p.stand_from)
	assert_bool(ParkSide.stand_face(_loaded.sim, q) == face).is_true()
	assert_float(moved).is_less(SAME_M)
