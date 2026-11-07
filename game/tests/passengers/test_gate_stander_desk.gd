class_name TestGateStanderDesk
extends GdUnitTestSuite
## Gate standers and the gate desk (board 34a0d0aa): no standing spot lies
## within StandingSpots.DESK_CLEAR_MM of a gate desk's footprint, so a stood
## roller does not stand in the desk; and a gate stander that has turned to
## the exit but has no path yet still counts as standing still
## (RollerPark.setting_off()), so its roller's tip waits until its way is known.

## Boarding opens here in the gate world, long after the guest is on its spot.
const GATE_BOARDING := 240
## The cells round the reference gate desk (ReferenceTerminal.GATE_DESK_CELL,
## 2 x 1 facing south) that held spots before: behind it and at its west end
## (roller_board_gate_probe seed 2012072536: stander 17 on (20, 4) stood its
## roller 0.202 m deep in the desk; stander 26 on (18, 5) tipped into it).
const BESIDE_DESK: Array[Vector2i] = [Vector2i(19, 4), Vector2i(20, 4), Vector2i(18, 5)]

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## Every spot keeps DESK_CLEAR_MM from the desk's footprint, and the cells
## beside the desk hold none. Control: the same terminal without the desk has
## spots on those cells, so the clearance is what removed them.
func test_no_standing_spot_is_within_reach_of_the_gate_desk() -> void:
	_world = TestStandingSpotClaims.seatless_world()
	var standing := _world.sim.standing
	var without := _cells_with_spots(standing)
	var result := _world.grid.apply(ReferenceTerminal.gate_desk_edit())
	assert_bool(result.ok).is_true()
	_world.sim.standing.rebuild(_world.sim)
	var desk := Rect2i(ReferenceTerminal.GATE_DESK_CELL * 1000, Vector2i(2000, 1000))
	var nearest := INF
	for id: int in standing.spots:
		var mm: Vector2i = standing.spots[id]["mm"]
		var dx := maxi(maxi(desk.position.x - mm.x, mm.x - desk.end.x), 0)
		var dy := maxi(maxi(desk.position.y - mm.y, mm.y - desk.end.y), 0)
		nearest = minf(nearest, sqrt(float(dx * dx + dy * dy)))
	var with := _cells_with_spots(standing)
	print(
		(
			"spots without the desk %d, with it %d; nearest to the desk %.0f mm (>= %d)"
			% [without.size(), with.size(), nearest, StandingSpots.DESK_CLEAR_MM]
		)
	)
	assert_float(nearest).is_greater_equal(StandingSpots.DESK_CLEAR_MM)
	assert_bool(standing.spots.is_empty()).is_false()
	for cell in BESIDE_DESK:
		assert_bool(without.has(cell)).is_true()
		assert_bool(with.has(cell)).is_false()


## A seatless guest stands on its spot; at boarding it turns to the exit with
## no path yet and keeps its spot: it is still (setting_off()). Once it walks
## it is not. Control: a walker turned to the exit with no path and no spot,
## held in no file, is not still.
func test_a_gate_stander_setting_off_counts_as_still() -> void:
	_world = TestStandingSpotClaims.seatless_world(
		PassengerTestWorld.starts_with(GATE_BOARDING, 4000)
	)
	var p := TestStandingSpotClaims.cleared(_world)
	var limit := GATE_BOARDING + 200
	while p.stage != Passenger.Stage.TO_EXIT and limit > 0:
		_world.step()
		limit -= 1
	var sim := _world.sim
	print(
		(
			"tick %d stage %d moving %s spot %d"
			% [_world.clock.tick, p.stage, p.is_moving(), sim.standing.spot_of(p.id)]
		)
	)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_EXIT)
	assert_bool(p.is_moving()).is_false()
	assert_int(sim.standing.spot_of(p.id)).is_not_equal(StandingSpots.NO_SPOT)
	assert_bool(RollerPark.setting_off(sim, p)).is_true()
	assert_bool(RollerPark.queue_still(sim, p)).is_true()
	# Control: with no spot it is a walker turned out with no way, not a stander.
	var spot := sim.standing.spot_of(p.id)
	sim.standing.release(p.id)
	assert_bool(RollerPark.queue_still(sim, p)).is_false()
	sim.standing.claim(p.id, spot)
	var walked := false
	for i in 200:
		_world.step()
		if p.is_moving() and not RollerPark.filed_still(sim, p):
			walked = true
			break
	assert_bool(walked).is_true()
	assert_bool(RollerPark.setting_off(sim, p)).is_false()
	assert_bool(RollerPark.queue_still(sim, p)).is_false()


func _cells_with_spots(standing: StandingSpots) -> Dictionary:
	var out := {}
	for id: int in standing.spots:
		out[standing.cell_of(id)] = true
	return out
