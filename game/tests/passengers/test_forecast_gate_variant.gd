class_name TestForecastGateVariant
extends GdUnitTestSuite
## The security forecast's copy of a passenger keeps its variant and carry-on
## (SecurityForecast._add()), so a gate seat reservation is valid in the
## forecast exactly when it is live: a one-bag roller guest reserves a gate
## chair, keeps it when one side of the front is walled, and loses it when walls
## go up on both sides (GateRoller.walled_tight(), whereas a non-roller guest
## keeps it). VisitForecast._leaving() preserves variant and carry-on alike
## (decisions a-roller-guest-is-never-given-a-gate-chair-walled-tight-on-b and
## gate-full-design-passengers-reserve-a-gate-seat-or-standing, board 9d191535).

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


## Places or removes side edge wall `side_idx` (0 or 1) of `seat`'s front.
func _wall(seat: Dictionary, side_idx: int, place: bool) -> bool:
	var out: Vector2i = (seat["front"] as Vector2i) - (seat["cell"] as Vector2i)
	var steps: Array[Vector2i] = [Vector2i(out.y, -out.x), Vector2i(-out.y, out.x)]
	var side_at := BuildGrid.SIDE_STEP.find(steps[side_idx])
	var edit: BuildEdit = (
		BuildEdit.place_wall(seat["front"], side_at)
		if place
		else BuildEdit.remove_wall(seat["front"], side_at)
	)
	return _world.grid.apply(edit).ok


## A one-bag female roller guest is admitted at the first scanner and holds a
## gate chair (`_seat`). Returns whether such a guest was found.
func _find_roller_guest() -> bool:
	var sim := _world.sim
	sim.standing.rebuild(sim)
	var station: int = sim.layout.scanners.min()
	for attempt in ATTEMPTS:
		var p := TestStandingSpotClaims.cleared(_world)
		p.carry_on = 1
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
		if p.stage == Passenger.Stage.SECURITY and not _seat.is_empty():
			_guest = p
			return true
		sim._finish(p, true)
	return false


## A replay's copy of the gate places and the guests inside.
func _replay(sim: PassengerSim) -> SecurityForecast:
	var replay := SecurityForecast.new()
	replay._setup(sim, _guest.station, true)
	return replay


func test_a_forecast_copy_keeps_the_variant_and_the_reservation_agrees_with_live() -> void:
	_world = PassengerTestWorld.reference_world()
	assert_bool(_find_roller_guest()).is_true()
	var sim := _world.sim
	# One side wall: the 1-bag roller keeps room on the open side, live and forecast.
	assert_bool(_wall(_seat, 0, true)).is_true()
	var live_open := sim.gates.holds_place(_guest, sim)
	var replay_open := _replay(sim)
	var copy_open := replay_open.get_passenger(_guest.id)
	var forecast_open := replay_open._places.holds_place(copy_open, replay_open)
	replay_open._runtime.bind(null)
	assert_bool(live_open).is_true()
	assert_int(copy_open.variant).is_equal(_guest.variant)
	assert_bool(forecast_open).is_equal(live_open)
	assert_bool(forecast_open).is_true()
	# Both side walls: walled tight for the 1-bag roller (control: non-roller is clear).
	assert_bool(_wall(_seat, 1, true)).is_true()
	_guest.carry_on = 0
	var as_plain := GateRoller.walled_tight(sim, _guest, _seat)
	_guest.carry_on = 1
	var live_tight := sim.gates.holds_place(_guest, sim)
	var replay_tight := _replay(sim)
	var copy_tight := replay_tight.get_passenger(_guest.id)
	var forecast_tight := replay_tight._places.holds_place(copy_tight, replay_tight)
	print(
		(
			(
				"guest %d variant %d, copy variant %d; open live/forecast %s/%s,"
				+ " tight live/forecast %s/%s, walled tight plain %s"
			)
			% [
				_guest.id,
				_guest.variant,
				copy_tight.variant,
				live_open,
				forecast_open,
				live_tight,
				forecast_tight,
				as_plain,
			]
		)
	)
	replay_tight._runtime.bind(null)
	assert_bool(as_plain).is_false()
	assert_bool(live_tight).is_false()
	assert_int(copy_tight.variant).is_equal(_guest.variant)
	assert_bool(forecast_tight).is_equal(live_tight)
	assert_bool(forecast_tight).is_false()


## The same guest leaving a landside visit (VisitForecast._leaving(), the copy
## the journey forecast hands the security forecast as its candidate) is
## walled tight at the chair exactly when the guest is live.
func test_a_visit_forecast_copy_of_the_guest_agrees_with_live_at_the_chair() -> void:
	_world = PassengerTestWorld.reference_world()
	assert_bool(_find_roller_guest()).is_true()
	var sim := _world.sim
	assert_bool(_wall(_seat, 0, true)).is_true()
	var after_open := VisitForecast._leaving(_guest, _guest.at, Passenger.Stage.TO_SECURITY)
	var live_open := GateRoller.walled_tight(sim, _guest, _seat)
	var forecast_open := GateRoller.walled_tight(sim, after_open, _seat)
	assert_bool(live_open).is_false()
	assert_int(after_open.variant).is_equal(_guest.variant)
	assert_bool(forecast_open).is_equal(live_open)
	assert_bool(_wall(_seat, 1, true)).is_true()
	var after_tight := VisitForecast._leaving(_guest, _guest.at, Passenger.Stage.TO_SECURITY)
	var live_tight := GateRoller.walled_tight(sim, _guest, _seat)
	var forecast_tight := GateRoller.walled_tight(sim, after_tight, _seat)
	print(
		(
			("guest %d variant %d, visit copy variant %d; walled tight open %s/%s, tight %s/%s")
			% [
				_guest.id,
				_guest.variant,
				after_tight.variant,
				live_open,
				forecast_open,
				live_tight,
				forecast_tight,
			]
		)
	)
	assert_bool(live_tight).is_true()
	assert_int(after_tight.variant).is_equal(_guest.variant)
	assert_bool(forecast_tight).is_equal(live_tight)
