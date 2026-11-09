class_name TestGateWalledReserved
extends GdUnitTestSuite
## A roller guest inside security holds a gate chair, and walls are built on
## both sides of its front before the guest is cleared (or between a save and
## its load): the chair is walled tight for that roller now, so the
## reservation is a lost place (GateCapacity._target(), recovered like a seat an
## edit removed) and the guest takes another chair or a standing spot, never
## that chair (decisions a-roller-guest-is-never-given-a-gate-chair-walled-
## tight-on-b and gate-full-design-passengers-reserve-a-gate-seat-or-standing,
## board f1fc1e54).

var _world: PassengerTestWorld
var _guest: Passenger
var _seat: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_guest = null


## A roller guest queued at the first scanner's lane front, admitted once the
## world steps: it holds the reserved gate chair `_seat`. Returns whether it did.
func _reserved(world: PassengerTestWorld) -> bool:
	var sim := world.sim
	sim.standing.rebuild(sim)
	var station: int = sim.layout.scanners.min()
	for attempt in 200:
		var p := TestStandingSpotClaims.cleared(world)
		p.carry_on = 1
		if not ParkRecovery.has_roller(p):
			sim._finish(p, true)
			continue
		p.cleared = false
		p.station = station
		p.stage = Passenger.Stage.SECURITY_QUEUE
		p.at = sim.layout.lanes[station][0]
		(sim._queue(station)["lane"] as Array).append(p.id)
		_guest = p
		break
	world.step()
	var key: String = sim.gates.seats.get(_guest.id, "")
	for seat: Dictionary in sim.layout.seats:
		if seat["key"] == key:
			_seat = seat
	return _guest.stage == Passenger.Stage.SECURITY and not _seat.is_empty()


## Walls on both side edges of the reserved chair's front, on `world`'s grid.
func _wall_in(world: PassengerTestWorld) -> void:
	var out: Vector2i = (_seat["front"] as Vector2i) - (_seat["cell"] as Vector2i)
	for step: Vector2i in [Vector2i(out.y, -out.x), Vector2i(-out.y, out.x)]:
		var edit := world.grid.apply(
			BuildEdit.place_wall(_seat["front"], BuildGrid.SIDE_STEP.find(step))
		)
		assert_bool(edit.ok).override_failure_message(edit.reason_text()).is_true()


## Steps `world` until `guest` is seated or standing, or `limit` ticks;
## returns the cells of the chair (seat_cell) it was ever bound to.
func _play(world: PassengerTestWorld, guest: Passenger, limit := 1500) -> Array[Vector2i]:
	var bound: Array[Vector2i] = []
	for i in limit:
		if guest.seat_cell != Passenger.NO_CELL and not bound.has(guest.seat_cell):
			bound.append(guest.seat_cell)
		if guest.stage in [Passenger.Stage.SEATED, Passenger.Stage.STANDING]:
			break
		world.step()
	return bound


func _assert_elsewhere(world: PassengerTestWorld, guest: Passenger) -> void:
	var bound := _play(world, guest)
	var spot := world.sim.standing.spot_of(guest.id)
	print(
		(
			"guest stage %d cleared %s; chair %s (reserved chair %s); spot %d; bound %s"
			% [guest.stage, guest.cleared, guest.seat_cell, _seat["cell"], spot, bound]
		)
	)
	assert_bool(guest.cleared).is_true()
	assert_bool(guest.stage in [Passenger.Stage.SEATED, Passenger.Stage.STANDING]).is_true()
	assert_bool(bound.has(_seat["cell"])).is_false()
	assert_bool(guest.seat_cell == _seat["cell"]).is_false()
	assert_bool(guest.seat_cell != Passenger.NO_CELL or spot != StandingSpots.NO_SPOT).is_true()


func test_walls_built_after_the_reservation_send_the_guest_elsewhere() -> void:
	_world = PassengerTestWorld.reference_world()
	assert_bool(_reserved(_world)).is_true()
	var sim := _world.sim
	assert_bool(sim.gates.holds_place(_guest, sim)).is_true()
	assert_bool(GateRoller.walled_tight(sim, _guest, _seat)).is_false()
	_wall_in(_world)
	assert_bool(GateRoller.walled_tight(sim, _guest, _seat)).is_true()
	assert_bool(sim.gates.holds_place(_guest, sim)).is_false()
	assert_bool(sim.gates.placed(_guest, sim)).is_false()
	_assert_elsewhere(_world, _guest)


func test_a_saved_reservation_on_a_grid_walled_tight_is_recovered() -> void:
	var a := PassengerTestWorld.reference_world()
	assert_bool(_reserved(a)).is_true()
	# The save holds the reservation; the loaded grid has the walls (a save
	# cannot be taken between a grid edit and the tick that settles it).
	var data: Dictionary = JSON.parse_string(JSON.stringify(a.sim.to_snapshot()))
	var clock: Dictionary = JSON.parse_string(JSON.stringify(a.clock.to_snapshot()))
	var flights: Dictionary = JSON.parse_string(JSON.stringify(a.flights.to_snapshot()))
	var places: Array = data["gate_places"]
	assert_int(places.size()).is_equal(1)
	assert_str(places[0].get("seat", "")).is_equal(_seat["key"])
	var id := _guest.id
	a.free_all()
	_world = PassengerTestWorld.reference_world()
	_wall_in(_world)
	assert_bool(_world.clock.from_snapshot(clock)).is_true()
	assert_bool(_world.flights.from_snapshot(flights)).is_true()
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	var loaded := _world.passenger(id)
	assert_bool(_world.sim.gates.holds_place(loaded, _world.sim)).is_false()
	_assert_elsewhere(_world, loaded)
