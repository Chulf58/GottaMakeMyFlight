class_name TestForecastGateVariant
extends GdUnitTestSuite
## The security forecast's copy of a passenger keeps its variant
## (SecurityForecast._add()), so a gate seat reservation is valid in the
## forecast exactly when it is live: whether a chair is walled tight for a
## roller (GateRoller.walled_tight()) depends on the body of the variant. A
## two-bag female guest reserves a gate chair and walls go up on both sides of
## its front; the chair still has room for her roller live, and is walled tight
## for the male body the forecast's copy took before the copy kept the
## variant (decisions a-roller-guest-is-never-given-a-gate-chair-walled-
## tight-on-b and gate-full-design-passengers-reserve-a-gate-seat-or-standing,
## board 9d191535).

## Guests tried for a chair walled tight for the male body and clear for the
## female.
const ATTEMPTS := 30
const FEMALE := 1

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


## Walls on both side edges of the chair `seat`'s front (`place`) or taken
## away again; returns whether every edit was accepted.
func _walls(seat: Dictionary, place: bool) -> bool:
	var out: Vector2i = (seat["front"] as Vector2i) - (seat["cell"] as Vector2i)
	var ok := true
	for step: Vector2i in [Vector2i(out.y, -out.x), Vector2i(-out.y, out.x)]:
		var side_at := BuildGrid.SIDE_STEP.find(step)
		var edit: BuildEdit = (
			BuildEdit.place_wall(seat["front"], side_at)
			if place
			else BuildEdit.remove_wall(seat["front"], side_at)
		)
		ok = _world.grid.apply(edit).ok and ok
	return ok


## A two-bag female roller guest is admitted at the first scanner and holds a
## gate chair (`_seat`); walls go up on both sides of that chair's front.
## Repeats with the next guest until the chair is walled tight for the male
## body and not for hers (live). Returns whether such a guest was found.
func _find_variant_sensitive_guest() -> bool:
	var sim := _world.sim
	sim.standing.rebuild(sim)
	var station: int = sim.layout.scanners.min()
	for attempt in ATTEMPTS:
		var p := TestStandingSpotClaims.cleared(_world)
		p.carry_on = 2
		p.variant = FEMALE
		if not ParkRecovery.has_roller(p):
			sim._finish(p, true)
			continue
		p.cleared = false
		p.station = station
		p.stage = Passenger.Stage.SECURITY_QUEUE
		p.at = sim.layout.lanes[station][0]
		(sim._queue(station)["lane"] as Array).append(p.id)
		_world.step()
		var key: String = sim.gates.seats.get(p.id, "")
		_seat = {}
		for seat: Dictionary in sim.layout.seats:
			if seat["key"] == key:
				_seat = seat
		if p.stage == Passenger.Stage.SECURITY and not _seat.is_empty() and _walls(_seat, true):
			_guest = p
			var female_tight := GateRoller.walled_tight(sim, p, _seat)
			p.variant = 0
			var male_tight := GateRoller.walled_tight(sim, p, _seat)
			p.variant = FEMALE
			if male_tight and not female_tight:
				return true
			_walls(_seat, false)
		sim._finish(p, true)
	return false


## A replay's copy of the gate places and the guests inside.
func _replay(sim: PassengerSim) -> SecurityForecast:
	var replay := SecurityForecast.new()
	replay._setup(sim, _guest.station, true)
	return replay


func test_a_forecast_copy_keeps_the_variant_and_the_reservation_agrees_with_live() -> void:
	_world = PassengerTestWorld.reference_world()
	assert_bool(_find_variant_sensitive_guest()).is_true()
	var sim := _world.sim
	# The positive control: live, the female guest keeps her chair, which is
	# walled tight for the male body.
	var live := sim.gates.holds_place(_guest, sim)
	_guest.variant = 0
	var as_male := GateRoller.walled_tight(sim, _guest, _seat)
	_guest.variant = FEMALE
	var replay := _replay(sim)
	var copy := replay.get_passenger(_guest.id)
	var forecast := replay._places.holds_place(copy, replay)
	print(
		(
			(
				"guest %d variant %d, copy variant %d; live holds %s, forecast holds %s,"
				+ " walled tight as male %s"
			)
			% [_guest.id, _guest.variant, copy.variant, live, forecast, as_male]
		)
	)
	replay._runtime.bind(null)
	assert_bool(as_male).is_true()
	assert_bool(live).is_true()
	assert_int(copy.variant).is_equal(_guest.variant)
	assert_bool(forecast).is_equal(live)
	assert_bool(forecast).is_true()
