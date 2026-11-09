extends GdUnitTestSuite
## A gate chair whose front cell has no room beside it for a lying roller on
## either side (walls tight on both sides) is never given to a passenger
## carrying a roller; guests without one still take it (user ruling
## a-roller-guest-is-never-given-a-gate-chair-walled-tight-on-b, board
## f1fc1e54). The reference world's first line of three seats in a row is
## walled on both sides of one front at a time; the chair is asked of
## GateRoller.walled_tight(), GateCapacity.claim_seat() and reserve().

## Guest kinds: one roller, two bags with the roller as bag 0 or bag 1, none.
enum Bags { ONE, TWO_RIGHT, TWO_LEFT, NONE }

var _world: PassengerTestWorld
var _seats: Array = []
var _left := Vector2i.ZERO
## One guest per Bags kind.
var _pool: Array[Passenger] = [null, null, null, null]


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	for a: Dictionary in _world.sim.layout.seats:
		var out: Vector2i = (a["front"] as Vector2i) - (a["cell"] as Vector2i)
		var left := Vector2i(out.y, -out.x)
		var line := [a]
		for n in 2:
			var next := _seat_at((line[-1]["front"] as Vector2i) + left, out)
			if next.is_empty():
				break
			line.append(next)
		if line.size() == 3:
			_seats = line
			_left = left
			break
	while _pool.has(null):
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		var first := SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER
		var second := SecurityLooks.bag_kind(p, 1) == SecurityLooks.Kind.ROLLER
		var kind := Bags.NONE
		if first and _pool[Bags.ONE] == null:
			kind = Bags.ONE
		elif first and not second and _pool[Bags.TWO_RIGHT] == null:
			kind = Bags.TWO_RIGHT
		elif second and not first and _pool[Bags.TWO_LEFT] == null:
			kind = Bags.TWO_LEFT
		elif _pool[Bags.NONE] != null:
			continue
		p.carry_on = [1, 2, 2, 0][kind]
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
		_pool[kind] = p


func after() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func _seat_at(front: Vector2i, out: Vector2i) -> Dictionary:
	for s: Dictionary in _world.sim.layout.seats:
		if s["front"] == front and (s["front"] as Vector2i) - (s["cell"] as Vector2i) == out:
			return s
	return {}


## Walls on both side edges of seat `s`'s front cell; returns the sides made.
func _wall_in(s: int) -> Array:
	var made: Array = []
	for step: Vector2i in [_left, -_left]:
		var side_at := BuildGrid.SIDE_STEP.find(step)
		if _world.grid.apply(BuildEdit.place_wall(_seats[s]["front"], side_at)).ok:
			made.append(side_at)
	return made


func _wall_out(s: int, made: Array) -> void:
	for side_at: int in made:
		_world.grid.apply(BuildEdit.remove_wall(_seats[s]["front"], side_at))


## Every roller guest, either variant, at each of the row's chairs walled on
## both sides: the chair is walled tight, or (a two-bag roller small enough)
## its roller lies inside the walls clear of the legs (LEG_NEED_M) on its own
## hand, so no roller a guest is seated with lies in the legs or in or past a
## wall. Controls: unwalled, no chair is tight; a guest with no roller is
## never tight; and at least one walled case is tight.
func test_a_walled_tight_chair_is_tight_only_for_a_roller() -> void:
	var tight := 0
	var bad := 0
	var line := "walled tight:"
	for s in _seats.size():
		for kind in [Bags.ONE, Bags.TWO_RIGHT, Bags.TWO_LEFT, Bags.NONE]:
			var q: Passenger = _pool[kind]
			_bind(q, s)
			for variant in 2:
				q.variant = variant
				assert_bool(GateRoller.walled_tight(_world.sim, q, _seats[s])).is_false()
		var made := _wall_in(s)
		assert_int(made.size()).is_equal(2)
		for kind in [Bags.ONE, Bags.TWO_RIGHT, Bags.TWO_LEFT, Bags.NONE]:
			var q: Passenger = _pool[kind]
			_bind(q, s)
			for variant in 2:
				q.variant = variant
				var is_tight := GateRoller.walled_tight(_world.sim, q, _seats[s])
				line += " s%d k%d v%d %s" % [s, kind, variant, "T" if is_tight else "-"]
				if kind == Bags.NONE:
					assert_bool(is_tight).is_false()
					continue
				if is_tight:
					tight += 1
					continue
				var hand := _real_hand(q, kind, s)
				var frame := ParkSide._frame(_world.sim, _seats[s]["front"], _out(s))
				var sc := SecurityLooks.bag_scale(q)
				var placed := frame * GateRoller.spot(q, hand)
				placed = Transform3D(placed.basis.scaled(Vector3.ONE * sc), placed.origin)
				var walls := PullSide.walls_near(_world.sim.grid, placed.origin)
				var across := absf(GateRoller.spot(q, hand).origin.x)
				var depth := _need(q, hand) - 0.01 - across
				# Past the wall's inner face, in it or wholly through it.
				var face := 0.5 - BuildView.WALL_THICKNESS / 2.0
				var past := across + GateRoller.SHELL_HALF_M * sc > face
				if ParkWalls.inside(placed, walls) or past or depth > 0.0:
					bad += 1
		_wall_out(s, made)
	print(line)
	print("walled tight %d (> 0), seated with a roller in a wall or the legs %d (0)" % [tight, bad])
	assert_int(tight).is_greater(0)
	assert_int(bad).is_equal(0)


## With every other gate seat held, a guest with no roller is given the chair
## walled tight on both sides (claim_seat() and reserve()), and a one-bag
## roller guest is not: claim_seat() finds no seat and reserve() a standing
## spot. Control: unwalled, the roller guest is given that chair.
func test_a_roller_guest_takes_another_place() -> void:
	var sim := _world.sim
	var s := 1
	var key: String = _seats[s]["key"]
	var saved_claims: Dictionary = sim._seat_claims.duplicate()
	for seat: Dictionary in sim.layout.seats:
		if seat["key"] != key and not sim._seat_claims.has(seat["key"]):
			sim._seat_claims[seat["key"]] = -1
	var from: Vector2i = _seats[0]["front"]
	var roller := _pool[Bags.ONE]
	var plain := _pool[Bags.NONE]
	var got := {}
	for walled in [false, true]:
		var made := _wall_in(s) if walled else []
		for q: Passenger in [roller, plain]:
			_unbind(q)
			q.at = from
			var claimed := GateCapacity.claim_seat(sim, q)
			got["claim %s %s" % [walled, q == roller]] = (
				claimed and q.seat_cell == _seats[s]["cell"]
			)
			sim._seat_claims.erase(key)
			_unbind(q)
			var reserved := sim.gates.reserve(sim, q, from)
			got["reserve %s %s" % [walled, q == roller]] = (
				reserved and sim.gates.seats.get(q.id, "") == key
			)
			got["spot %s %s" % [walled, q == roller]] = sim.standing.reserved_of(q.id) >= 0
			sim.gates.seats.erase(q.id)
			sim.standing.unreserve(q.id)
		_wall_out(s, made)
	sim._seat_claims = saved_claims
	print("walled tight seat given: %s" % got)
	assert_bool(got["claim false true"]).is_true()
	assert_bool(got["reserve false true"]).is_true()
	assert_bool(got["claim true false"]).is_true()
	assert_bool(got["reserve true false"]).is_true()
	assert_bool(got["claim true true"]).is_false()
	assert_bool(got["reserve true true"]).is_false()
	assert_bool(got["spot true true"]).is_true()


## The hand `q` (of `kind`, bound by _bind() to seat `s`) really lays its
## roller down with at that chair: a one-bag guest's is what the sim asks
## (SecurityLooks.hand_of(), ParkSide.hand(), chosen once the guest is near the
## chair and kept), a two-bag guest's its roller bag's.
func _real_hand(q: Passenger, kind: int, s: int) -> int:
	if kind == Bags.TWO_LEFT:
		return 1
	if kind == Bags.TWO_RIGHT:
		return 0
	_world.sim.set_meta(ParkSide.STAMPS, {})
	q.at = _seats[s]["front"]
	return SecurityLooks.hand_of(_world.sim, q, 0)


## A wall on one edge of the chair front cell (a side edge, or the edge across
## the row ahead of the feet or behind them) can leave a one-bag roller room on
## one side only. The hand the guest really lays it down with
## (SecurityLooks.hand_of()) is that side, at each of the row's chairs, for each
## wall and both body variants; the roller there lies in no wall
## (GateRoller.walled_tight() lets the chair through on that side). Control: the
## cases where one side fits are counted and some exist.
func test_the_real_hand_is_the_side_that_fits() -> void:
	var q: Passenger = _pool[Bags.ONE]
	var one_side := 0
	var wrong := []
	var line := "one side fits:"
	for s in _seats.size():
		_bind(q, s)
		for across: Vector2i in [_left, -_left, _out(s), -_out(s)]:
			var edge := BuildGrid.SIDE_STEP.find(across)
			var front: Vector2i = _seats[s]["front"]
			assert_bool(_world.grid.apply(BuildEdit.place_wall(front, edge)).ok).is_true()
			for variant in 2:
				q.variant = variant
				var fits := GateRoller.clear_hand(_world.sim, q)
				if fits < 0:
					continue
				one_side += 1
				var got := _real_hand(q, Bags.ONE, s)
				var frame := ParkSide._frame(_world.sim, front, _out(s))
				var lying := frame * GateRoller.spot(q, got)
				lying = Transform3D(
					lying.basis.scaled(Vector3.ONE * SecurityLooks.bag_scale(q)), lying.origin
				)
				var walls := PullSide.walls_near(_world.sim.grid, lying.origin)
				line += " s%d wall %s v%d fits %d got %d" % [s, across, variant, fits, got]
				if got != fits or ParkWalls.inside(lying, walls):
					wrong.append([s, across, variant, fits, got])
			_world.grid.apply(BuildEdit.remove_wall(front, edge))
	print(line)
	print("walls leaving one side %d (> 0), real hand on the other %s (none)" % [one_side, wrong])
	assert_int(one_side).is_greater(0)
	assert_array(wrong).is_empty()


func _out(s: int) -> Vector2i:
	return (_seats[s]["front"] as Vector2i) - (_seats[s]["cell"] as Vector2i)


## Binds `q` to seat `s` as bound for it (GateRoller.slide_of() reads it).
func _bind(q: Passenger, s: int) -> void:
	q.stage = Passenger.Stage.TO_GATE
	q.seat_object = _seats[s]["object_id"]
	q.seat_cell = _seats[s]["cell"]
	q.seat_front = _seats[s]["front"]
	q.seat_piece = Relocation.placement(_world.sim.grid, _seats[s]["object_id"])


func _unbind(q: Passenger) -> void:
	q.stage = Passenger.Stage.TO_GATE
	q.seat_object = 0
	q.seat_cell = Passenger.NO_CELL
	q.seat_front = Passenger.NO_CELL
	q.seat_piece = {}
	q.clear_path()


## TestGateRollerGaps' LEG_NEED_M for `q` (bound by _bind()) in `hand`.
static func _need(q: Passenger, hand: int) -> float:
	var look := PassengerLooks.body_of(q.id, q.variant)
	var slide := GateRoller.slide_of(q)
	var toward := (hand == 1 and slide > 0.0) or (hand == 0 and slide < 0.0)
	var at := 0 if not toward else (1 if absf(slide) < GateRoller.FAR_SLIDE_M else 2)
	var scale_by := SecurityLooks.bag_scale(q)
	var need: Array = TestGateRollerGaps.LEG_NEED_M
	return need[0 if scale_by >= 1.0 else 1][at][look / PassengerLooks.PER_VARIANT][hand]
