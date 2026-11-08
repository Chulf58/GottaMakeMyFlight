extends GdUnitTestSuite
## Guests at neighbouring gate chair fronts never lay two rollers in one gap
## between the fronts (ParkSide.gap_hand(), board 1fe04f01): two rollers that
## each clear their own guest's legs (GateRoller.LIE_SIDE_M) overlap there by
## up to 0.178 m. The reference world's first line of three seats in a row is
## filled in every order of arrival with every pair of hand_of() fallbacks;
## each guest chooses (SecurityLooks.hand_of() -> ParkSide.hand()) at its
## chair front, from sim state only.

## The roller shell's width across (test_gate_chair_roller_spot's shell box).
const SHELL_WIDTH_M := 0.328
## How far apart neighbouring chair fronts are.
const CELL_M := 1.0
const ORDERS_3 := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

var _world: PassengerTestWorld
## Three seats whose fronts follow each other along the row, each the next one's
## right-hand neighbour: seat i + 1's front is seat i's front plus `_left`.
var _seats: Array = []
var _left := Vector2i.ZERO
var _guests: Array[Passenger] = []


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
	for n in 3:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			ToiletTestLayout.calm(p)
			p.carry_on = 0
			p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.cleared = true
		p.stage = Passenger.Stage.TO_EXIT
		_guests.append(p)


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


## Seats guests `who` (indices into _guests and _seats) in `order`, guest i
## arriving with hand_of()'s own hand `fallbacks[i]`, each choosing at its
## front as it arrives; the others are away. Returns the hand each chose.
func _fill(who: Array, order: Array, fallbacks: Array) -> Dictionary:
	_world.sim.remove_meta(ParkSide.STAMPS)
	for p in _guests:
		p.stage = Passenger.Stage.TO_EXIT
		p.seat_cell = Passenger.NO_CELL
		p.seat_front = Passenger.NO_CELL
	var hands := {}
	for i: int in order:
		if i not in who:
			continue
		var p := _guests[i]
		var seat: Dictionary = _seats[i]
		p.stage = Passenger.Stage.TO_GATE
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		p.at = seat["front"]
		hands[i] = ParkSide.hand(_world.sim, p, fallbacks[i])
	return hands


## How many gaps between neighbouring fronts in `hands` hold two rollers: guest
## i lays its left-hand roller into the gap toward i + 1, whose right-hand
## roller lies in the same gap.
static func _shared(hands: Dictionary) -> int:
	var count := 0
	for i: int in hands:
		count += int(hands[i] == 1 and hands.get(i + 1, -1) == 0)
	return count


func test_the_seats_line_up() -> void:
	print(
		(
			"seats %s, left step %s"
			% [_seats.map(func(s: Dictionary) -> Vector2i: return s["front"]), _left]
		)
	)
	assert_int(_seats.size()).is_equal(3)


## Two neighbours, either arriving first, any fallbacks: no gap holds two
## rollers. Control: the fallbacks that point into one gap (the left guest's
## left hand, the right one's right) are what ParkSide stamped before
## (hand_of()'s own hand, no wall), and they overlap by the printed amount.
func test_two_neighbours_never_share_a_gap() -> void:
	var shared := 0
	var cases := 0
	for order in [[0, 1], [1, 0]]:
		for f0 in 2:
			for f1 in 2:
				var hands := _fill([0, 1], order, [f0, f1, 0])
				shared += _shared(hands)
				cases += 1
	var fallbacks := {0: 1, 1: 0}
	var male := GateRoller.side(0, 0) + GateRoller.side(0, 1) + SHELL_WIDTH_M - CELL_M
	var old := 0.34 * 2.0 + SHELL_WIDTH_M - CELL_M
	print(
		(
			(
				"two neighbours: %d of %d fills share a gap (0); fallbacks %s share %d (> 0),"
				+ " overlapping %.3f m for two male rollers, %.3f m at main's 0.34 m"
			)
			% [shared, cases, fallbacks, _shared(fallbacks), male, old]
		)
	)
	assert_int(_shared(fallbacks)).is_equal(1)
	assert_float(male).is_greater(0.0)
	assert_int(shared).is_equal(0)


## Three in a row, every order of arrival and every set of fallbacks: no gap
## holds two rollers. Printed as well: the same fills under the rule that keeps
## hand_of()'s own hand when both gaps are free (a model of it here), which
## shares a gap.
func test_three_in_a_row_never_share_a_gap() -> void:
	var shared := 0
	var modelled := 0
	var cases := 0
	for order: Array in ORDERS_3:
		for bits in 8:
			var fallbacks := [bits & 1, (bits >> 1) & 1, (bits >> 2) & 1]
			var hands := _fill([0, 1, 2], order, fallbacks)
			shared += _shared(hands)
			modelled += int(_shared(_keep_fallback(order, fallbacks)) > 0)
			cases += 1
	print(
		(
			(
				"three in a row: %d gaps shared over %d fills (0); keeping the fallback"
				+ " when both gaps are free: %d of %d fills share a gap"
			)
			% [shared, cases, modelled, cases]
		)
	)
	assert_int(cases).is_equal(48)
	assert_int(shared).is_equal(0)
	assert_int(modelled).is_greater(0)


## A wall on the right of the first front: its guest lays the roller on the
## left (the wall rule first) in every order, and the row still shares no gap.
## Control: without the wall the same guest lays it on the right.
func test_the_wall_still_wins() -> void:
	var seat: Dictionary = _seats[0]
	var side := BuildGrid.SIDE_STEP.find(-_left)
	assert_int(side).is_greater_equal(0)
	var free := _fill([0, 1, 2], [0, 1, 2], [0, 0, 0])
	var made := _world.grid.apply(BuildEdit.place_wall(seat["front"], side))
	assert_bool(made.ok).is_true()
	var shared := 0
	var first: Array[int] = []
	for order: Array in ORDERS_3:
		var hands := _fill([0, 1, 2], order, [0, 0, 0])
		shared += _shared(hands)
		first.append(hands[0])
	_world.grid.apply(BuildEdit.remove_wall(seat["front"], side))
	print(
		(
			"walled on the right: first guest's hands %s (1 each), gaps shared %d (0); unwalled %s"
			% [first, shared, free]
		)
	)
	assert_int(free[0]).is_equal(0)
	assert_array(first).contains_same([1, 1, 1, 1, 1, 1])
	assert_int(shared).is_equal(0)


## The rule ParkSide.gap_hand() replaced the fallback with, modelled: keep the
## fallback while both gaps are free, else as gap_hand().
static func _keep_fallback(order: Array, fallbacks: Array) -> Dictionary:
	var hands := {}
	for i: int in order:
		var right_taken: bool = hands.get(i - 1, -1) == 1
		var left_taken: bool = hands.get(i + 1, -1) == 0
		if not right_taken and not left_taken:
			hands[i] = fallbacks[i]
		else:
			hands[i] = 1 if right_taken and not left_taken else 0
	return hands
