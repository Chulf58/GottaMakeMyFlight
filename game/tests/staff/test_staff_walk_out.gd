class_name TestStaffWalkOut
extends GdUnitTestSuite
## A fired member walks to the terminal entrance and is removed there. While
## it walks it is no longer staff: it is out of count(), on_duty_count(),
## leaving_count() and the station claims, so it draws no wage. With no path
## or no entrance it goes at once (decisions
## fired-staff-walk-out-a-fired-member-walks-to-the-terminal-en and
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, point 5).

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const WALKING_OUT := StaffMember.State.WALKING_OUT
const LIMIT_TICKS := 1500

var _w: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false


func after_test() -> void:
	for world in [_w, _b]:
		if world != null:
			world.free_all()
	_w = null
	_b = null


## An agent on duty at a desk, seated by the kit.
func _seated_agent() -> StaffMember:
	assert_int(StaffTestKit.staff_all(_w.staff, [CHECKIN])).is_equal(2)
	# fire() takes the highest id first.
	return _w.staff.get_member(_w.staff.member_ids()[1])


## A second entrance on the hall's east edge above the desks, so a wall across
## the hall below them cuts the first entrance (where members walk out) off
## while staff can still reach every spot; a wall that left a spot with no
## way from any entrance would be refused (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3).
func _second_entrance() -> void:
	PassengerTestWorld.place(_w.grid, &"entrance_door", Vector2i(21, 12), 1)
	assert_that(_w.sim.layout.door_cell(_w.grid, _w.sim.layout.entrances[0])).is_equal(
		ReferenceTerminal.ENTRANCE_CELL
	)


func _assert_not_staff(m: StaffMember) -> void:
	assert_int(m.state).is_equal(WALKING_OUT)
	assert_int(m.station).is_equal(0)
	assert_bool(m.leaving).is_false()
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.on_duty_count(CHECKIN)).is_equal(1)
	assert_int(_w.staff.leaving_count(CHECKIN)).is_equal(0)
	assert_bool(_w.staff.member_ids().has(m.id)).is_true()


## Steps until the member is gone; returns the cell it stood on when it went
## (the record keeps it), or NO_CELL on a timeout.
func _until_gone(world: PassengerTestWorld, id: int) -> Vector2i:
	var m := world.staff.get_member(id)
	var start := world.clock.tick
	while world.clock.tick - start < LIMIT_TICKS:
		world.step()
		if world.staff.get_member(id) == null:
			assert_bool(m.is_moving()).is_false()
			return m.at
	return StaffMember.NO_CELL


func test_a_fired_agent_walks_to_the_entrance_and_is_removed_on_arrival() -> void:
	var m := _seated_agent()
	var desk := m.station
	var spot := m.at
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	_assert_not_staff(m)
	assert_bool(_w.staff.is_staffed(desk)).is_false()
	assert_that(m.at).is_equal(spot)
	var door := _w.sim.layout.door_cell(_w.grid, _w.sim.layout.entrances[0])
	assert_that(m.path_end()).is_equal(door)
	_w.step()
	assert_bool(m.is_moving()).is_true()
	# The panel's "hired minus leaving" never goes below zero meanwhile.
	assert_int(_w.staff.count(CHECKIN) - _w.staff.leaving_count(CHECKIN)).is_equal(1)
	var last := _until_gone(_w, m.id)
	print("walked out from %s, last cell %s, door %s, tick %d" % [spot, last, door, _w.clock.tick])
	assert_that(last).is_equal(door)
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)


func test_a_fired_member_still_walking_to_its_station_walks_out_from_where_it_is() -> void:
	var m := _w.staff.get_member(_w.staff.hire(SECURITY))
	for i in 20:
		_w.step()
	assert_int(m.state).is_equal(StaffMember.State.TO_STATION)
	var station := m.station
	var here := m.at
	assert_bool(_w.staff.fire(SECURITY)).is_true()
	assert_int(m.state).is_equal(WALKING_OUT)
	assert_that(m.at).is_equal(here)
	assert_int(_w.staff.staff_at(station)).is_equal(0)
	assert_int(_w.staff.count(SECURITY)).is_equal(0)
	assert_that(_until_gone(_w, m.id)).is_equal(ReferenceTerminal.ENTRANCE_CELL)


func test_with_no_path_to_the_entrance_a_fired_member_goes_at_once() -> void:
	var m := _seated_agent()
	_second_entrance()
	# A wall across the hall below the desks cuts them off from the entrance.
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		(
			assert_bool(
				_w.grid.apply(BuildEdit.place_wall(Vector2i(x, 13), BuildGrid.Side.NORTH)).ok
			)
			. is_true()
		)
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_object(_w.staff.get_member(m.id)).is_null()
	assert_int(_w.staff.count(CHECKIN)).is_equal(1)


func test_a_member_gone_at_once_is_announced_once() -> void:
	var m := _seated_agent()
	_second_entrance()
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		_w.grid.apply(BuildEdit.place_wall(Vector2i(x, 13), BuildGrid.Side.NORTH))
	var changes := [0]
	_w.staff.staff_changed.connect(func() -> void: changes[0] += 1)
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_object(_w.staff.get_member(m.id)).is_null()
	var in_pool := _w.staff.hire(SECURITY)
	assert_bool(_w.staff.fire(SECURITY)).is_true()
	assert_object(_w.staff.get_member(in_pool)).is_null()
	print("staff_changed: %d for a fire with no path, a hire and a fire from the pool" % changes[0])
	assert_int(changes[0]).is_equal(3)


func test_with_no_entrance_a_fired_member_goes_at_once() -> void:
	var m := _seated_agent()
	var entrance: int = _w.sim.layout.entrances[0]
	assert_bool(_w.grid.apply(BuildEdit.remove_object(entrance)).ok).is_true()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	assert_object(_w.staff.get_member(m.id)).is_null()


func test_a_walk_out_cut_off_on_the_way_goes_at_once() -> void:
	var m := _seated_agent()
	_second_entrance()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	for i in 10:
		_w.step()
	assert_int(m.state).is_equal(WALKING_OUT)
	assert_int(m.at.y).is_less(13)
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		(
			assert_bool(
				_w.grid.apply(BuildEdit.place_wall(Vector2i(x, 15), BuildGrid.Side.NORTH)).ok
			)
			. is_true()
		)
	_w.step()
	print("after the cut: member %s" % _w.staff.get_member(m.id))
	assert_object(_w.staff.get_member(m.id)).is_null()


func test_a_walk_out_survives_a_save_and_load() -> void:
	var m := _seated_agent()
	assert_bool(_w.staff.fire(CHECKIN)).is_true()
	for i in 7:
		_w.step()
	assert_int(m.state).is_equal(WALKING_OUT)
	_b = StaffTestKit.load_world(StaffTestKit.save_text(_w))
	assert_object(_b).is_not_null()
	assert_int(_b.staff.get_member(m.id).state).is_equal(WALKING_OUT)
	assert_int(_b.staff.count(CHECKIN)).is_equal(1)
	var differing := 0
	var gone_a := -1
	var gone_b := -1
	for i in 600:
		_w.step()
		_b.step()
		differing += int(StaffTestKit.signature(_w.staff) != StaffTestKit.signature(_b.staff))
		if gone_a < 0 and _w.staff.get_member(m.id) == null:
			gone_a = _w.clock.tick
		if gone_b < 0 and _b.staff.get_member(m.id) == null:
			gone_b = _b.clock.tick
	print("walked out at tick %d saved, %d loaded" % [gone_a, gone_b])
	assert_int(differing).is_equal(0)
	assert_int(gone_a).is_greater(0)
	assert_int(gone_b).is_equal(gone_a)
