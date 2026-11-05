class_name TestRoomMoveGateSeats
extends GdUnitTestSuite
## Gate-seated passengers when their seat row moves with its room (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, part 4; board
## fee68e85, GateRelocation): a sitting or seated passenger gets up at the old
## spot beside a ghost row, a stand-up under way finishes there, a roller is
## taken into the pull on the way, the cells it needs stay clear and the exit
## is saved. A row moved by hand is removed and placed again under its id with
## its paid, as RoomMove does. The reference terminal's first row (11,3) moves
## to (18,4); its passengers use that row's first cell.

## The longest drawn step a tick may take while a passenger gets up (the
## stand-up's shuffle and its chair step each ease out over SHUFFLE_TICKS ticks).
const MAX_STEP_M := 0.15
const NEW_ANCHOR := Vector2i(18, 4)

var _world: PassengerTestWorld
var _starts: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## A passenger that claimed the reference terminal's first gate chair through
## the sim (PassengerSim._claim_seat(): the claim, the cached seat placement and
## the walk to the chair front are the production ones), a roller among its bags
## when `roller`, then in `stage` from this tick: SITTING_DOWN or SEATED as the
## sim got it there, STANDING_UP by setting the stage on a seated passenger.
func _sitter(stage: Passenger.Stage, roller := false) -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_starts = FlightSim.schedule_starts(0)
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) != roller:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_send_to_gate(p, 1 if roller else 0)
	var goal := Passenger.Stage.SEATED
	if stage == Passenger.Stage.SITTING_DOWN:
		goal = Passenger.Stage.SITTING_DOWN
	while p.stage != goal and _world.sim.tick < 600:
		_world.step()
	assert_int(p.stage).is_equal(goal)
	assert_int(p.seat_object).is_not_equal(0)
	if stage == Passenger.Stage.STANDING_UP:
		p.stage = stage
		p.stage_tick = _world.sim.tick
	return p


## Sends `p`, cleared with `bags` carry-on bags, to the gate from the first
## chair's front, so the sim claims a seat for it on the next beat.
func _send_to_gate(p: Passenger, bags: int, other: PassengerTestWorld = null) -> void:
	var world := other if other != null else _world
	ToiletTestLayout.calm(p)
	p.carry_on = bags
	p.cleared = true
	p.boarding_tick = world.sim.tick + 100000
	p.at = world.sim.layout.seats[0]["front"]
	p.clear_path()
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = world.sim.tick


## Moves the passenger's seat row to `anchor` as a room move does.
func _move_row(p: Passenger, anchor := NEW_ANCHOR) -> void:
	var record := _world.grid.get_object(p.seat_object)
	var place := BuildEdit.place_object(record["def"], anchor, record["facing"])
	place.object_id = p.seat_object
	place.paid = int(record.get("paid", 0))
	for result in _world.grid.apply_batch([BuildEdit.remove_object(p.seat_object), place]):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


## The seat key ("<row id>:<chair index>") `p` holds in `world`'s layout.
func _key_of(world: PassengerTestWorld, p: Passenger) -> String:
	for seat: Dictionary in world.sim.layout.seats:
		if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
			return seat["key"]
	return ""


## Whether another passenger can claim seat `key` in `world`: every other seat
## is held by a stand-in, a rival is sent to the gate, and it must end up with
## `key` (a claim `p` still held on it would leave the rival with nothing).
func _rival_gets(world: PassengerTestWorld, key: String) -> bool:
	for seat: Dictionary in world.sim.layout.seats:
		if seat["key"] != key:
			world.sim._seat_claims[seat["key"]] = -1
	var rival := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_send_to_gate(rival, 0, world)
	for i in 40:
		world.step()
		if rival.seat_object != 0:
			break
	return world.sim._seat_claims.get(key, 0) == rival.id


## Steps until `p` leaves STANDING_UP, failing on a tick its drawn position
## (the sim's, plus the chair step GateChairs adds) jumps more than MAX_STEP_M.
## Returns the ticks the stand-up took, counted from the tick it began.
func _get_up(p: Passenger) -> int:
	var began := p.stage_tick
	var last := _drawn(p)
	while p.stage == Passenger.Stage.STANDING_UP and _world.sim.tick < began + 400:
		_world.step()
		var now := _drawn(p)
		(
			assert_float(now.distance_to(last))
			. override_failure_message(
				"tick %d jumped to %s from %s" % [_world.sim.tick, now, last]
			)
			. is_less(MAX_STEP_M)
		)
		last = now
	return _world.sim.tick - began


func _drawn(p: Passenger) -> Vector3:
	return _world.sim.world_position(p) + GateChairs.offset(_world.sim, p)


## The saved world, through JSON.
func _save() -> Dictionary:
	var text := (
		JSON
		. stringify(
			{
				"clock": _world.clock.to_snapshot(),
				"flights": _world.flights.to_snapshot(),
				"grid": _world.grid.to_snapshot(),
				"passengers": _world.sim.to_snapshot(),
			}
		)
	)
	return JSON.parse_string(text)


## A twin world loaded from `data`, or null when the load is refused; the caller
## frees a world it gets.
func _twin(data: Dictionary) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var twin := PassengerTestWorld.make(grid, _starts, 99)
	assert_bool(twin.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(twin.flights.from_snapshot(data["flights"])).is_true()
	if twin.sim.from_snapshot(data["passengers"]):
		return twin
	twin.free_all()
	return null


## A record of a passenger that holds a seat but is not getting up from a moved
## row, with no placement saved.
func _no_placement(record: Dictionary) -> void:
	record["seat_piece"] = {}
	record["seat_exiting"] = false


## Whether `data` loads, after `change` edits passenger `id`'s record.
func _loads_with(data: Dictionary, id: int, change: Callable) -> bool:
	var edited: Dictionary = data.duplicate(true)
	for record: Dictionary in edited["passengers"]["passengers"]:
		if int(record["id"]) == id:
			change.call(record)
	var twin := _twin(edited)
	if twin == null:
		return false
	twin.free_all()
	return true


func test_a_claimed_gate_seat_caches_its_row_placement() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.cleared = true
	p.at = _world.sim.layout.seats[0]["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.sim.tick
	while p.stage != Passenger.Stage.SEATED and _world.sim.tick < 400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_dict(p.seat_piece).is_not_empty()
	assert_dict(p.seat_piece).is_equal(Relocation.placement(_world.grid, p.seat_object))
	assert_bool(p.seat_exiting).is_false()


func test_a_seated_passenger_gets_up_at_the_old_seat_beside_a_ghost_row() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var seat_cell := p.seat_cell
	var before := _drawn(p)
	var old := p.seat_piece.duplicate()
	_move_row(p)
	# Before any tick: drawn on its old chair, which a ghost row holds, and the
	# chair step is the one it had (the live row no longer has its seat cell).
	assert_float(_drawn(p).distance_to(before)).is_less(0.001)
	assert_that(GateChairs.offset(_world.sim, p)).is_not_equal(Vector3.ZERO)
	var ghosts := Relocation.ghosts(_world.sim)
	assert_int(ghosts.size()).is_equal(1)
	assert_that(ghosts[0]["anchor"]).is_equal(old["anchor"])
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(p.seat_exiting).is_true()
	assert_that(p.seat_cell).is_equal(seat_cell)
	assert_dict(p.seat_piece).is_equal(old)
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(1)
	var ticks := _get_up(p)
	assert_int(ticks).is_equal(PassengerSim.STAND_UP_TICKS)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.seat_object).is_equal(0)
	assert_bool(p.seat_exiting).is_false()
	assert_dict(p.seat_piece).is_empty()
	assert_int(Relocation.ghosts(_world.sim).size()).is_equal(0)
	# Then it takes a seat again, at the moved row or another.
	while p.stage != Passenger.Stage.SEATED and _world.sim.tick < 600:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_dict(p.seat_piece).is_equal(Relocation.placement(_world.grid, p.seat_object))


## The view asks for the chair step every frame, ticks or not. With the row
## moved and build mode paused (no tick) it must give the step of the chair the
## passenger sits on, not report the seat cell as outside the live row (which
## pushed an error a frame and drew the body off its chair).
func test_the_chair_step_is_the_old_chairs_every_frame_while_the_game_is_paused() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var step := GateChairs.offset(_world.sim, p)
	assert_that(step).is_not_equal(Vector3.ZERO)
	_move_row(p)
	for frame in 5:
		assert_that(GateChairs.offset(_world.sim, p)).is_equal(step)


func test_a_passenger_sitting_down_turns_back_and_gets_up_in_as_long_as_it_sat() -> void:
	var p := _sitter(Passenger.Stage.SITTING_DOWN)
	for i in 4:
		_world.step()
	var before := _drawn(p)
	_move_row(p)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(p.seat_exiting).is_true()
	# 5 ticks into the sit-down when it turned: 5 ticks to get up.
	var left := PassengerSim.STAND_UP_TICKS - (_world.sim.tick - p.stage_tick)
	assert_int(left).is_equal(5)
	assert_float(_drawn(p).distance_to(before)).is_less(MAX_STEP_M)
	# The stand-up clock was set back as far as the sit-down had got: 5 left of 24.
	var turned := _world.sim.tick
	assert_int(_get_up(p)).is_equal(PassengerSim.STAND_UP_TICKS)
	assert_int(_world.sim.tick - turned).is_equal(left)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_stand_up_under_way_keeps_its_seat_cell_when_the_row_moves() -> void:
	var p := _sitter(Passenger.Stage.STANDING_UP)
	# 18 ticks in: 6 left, inside the shuffle towards the chair front.
	p.stage_tick = _world.sim.tick - 18
	_world.step()
	var seat_cell := p.seat_cell
	var before := _drawn(p)
	_move_row(p)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(p.seat_exiting).is_true()
	assert_that(p.seat_cell).is_equal(seat_cell)
	assert_float(_drawn(p).distance_to(before)).is_less(MAX_STEP_M)
	_get_up(p)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.seat_object).is_equal(0)


func test_a_stand_up_under_way_finishes_when_its_row_is_removed() -> void:
	var p := _sitter(Passenger.Stage.STANDING_UP)
	p.stage_tick = _world.sim.tick - 18
	_world.step()
	var seat_cell := p.seat_cell
	var before := _drawn(p)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(p.seat_object)).ok).is_true()
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_that(p.seat_cell).is_equal(seat_cell)
	assert_float(_drawn(p).distance_to(before)).is_less(MAX_STEP_M)
	_get_up(p)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)


func test_a_roller_parked_at_the_chair_is_taken_into_the_pull_before_it_walks() -> void:
	var p := _sitter(Passenger.Stage.SEATED, true)
	assert_bool(ParkRecovery.has_roller(p)).is_true()
	_move_row(p)
	_world.step()
	# Not sent on at once with the bag left to collect (a lost seat's hold):
	# it gets up and picks the roller up at the old chair first.
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_int(p.collect_tick).is_equal(0)
	var front := p.at
	var up := ParkRecovery.stand_up_ticks(p)
	assert_int(up).is_greater(PassengerSim.STAND_UP_TICKS)
	assert_int(_get_up(p)).is_equal(up)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_that(p.at).is_equal(front)
	assert_int(p.collect_tick).is_equal(0)


func test_a_removed_row_still_sends_a_seated_passenger_to_the_gate() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var row := p.seat_object
	assert_bool(_world.grid.apply(BuildEdit.remove_object(row)).ok).is_true()
	_world.step()
	# Sent on at once; it may already have claimed a seat in another row.
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_int(p.seat_object).is_not_equal(row)
	assert_bool(p.seat_exiting).is_false()


func test_the_seat_cell_and_chair_front_stay_clear_while_a_passenger_gets_up() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var cells: Array[Vector2i] = [p.seat_cell, p.seat_front]
	assert_array(_world.sim.move_exit_cells()).contains(cells)
	var kept: Callable = _world.grid.get_meta(RoomMove.EXIT_CELLS_META)
	assert_array(kept.call()).contains(cells)
	_move_row(p)
	_world.step()
	assert_array(_world.sim.move_exit_cells()).contains(cells)
	_get_up(p)
	# Control: standing up done, the cells are free again.
	for cell in cells:
		assert_array(_world.sim.move_exit_cells()).not_contains([cell])


func test_a_save_mid_exit_loads_and_the_twin_finishes_the_exit() -> void:
	var p := _sitter(Passenger.Stage.SEATED, true)
	_move_row(p)
	for i in 5:
		_world.step()
	assert_bool(p.seat_exiting).is_true()
	var data := _save()
	var twin := _twin(data)
	assert_object(twin).is_not_null()
	var q := twin.passenger(p.id)
	assert_int(q.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_bool(q.seat_exiting).is_true()
	assert_that(q.seat_cell).is_equal(p.seat_cell)
	assert_dict(q.seat_piece).is_equal(p.seat_piece)
	assert_int(Relocation.ghosts(twin.sim).size()).is_equal(1)
	assert_str(twin.signature()).is_equal(_world.signature())
	for i in 80:
		_world.step()
		twin.step()
	print("twin stage %d original %d" % [q.stage, p.stage])
	assert_int(p.stage).is_not_equal(Passenger.Stage.STANDING_UP)
	assert_str(twin.signature()).is_equal(_world.signature())
	assert_int(q.seat_object).is_equal(p.seat_object)
	twin.free_all()


func test_a_save_with_inconsistent_seat_state_is_refused() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	_move_row(p)
	for i in 5:
		_world.step()
	var data := _save()
	assert_bool(_loads_with(data, p.id, func(_r: Dictionary) -> void: pass)).is_true()
	var cases := {
		"exiting but sitting": func(r: Dictionary) -> void: r["stage"] = Passenger.Stage.SEATED,
		"exiting with no placement": func(r: Dictionary) -> void: r["seat_piece"] = {},
		"unknown piece": func(r: Dictionary) -> void: r["seat_piece"]["def"] = "no_such_piece",
		"facing out of range": func(r: Dictionary) -> void: r["seat_piece"]["facing"] = 4,
		"no seat but a placement": func(r: Dictionary) -> void: r["seat_object"] = 0,
		"not a placement": func(r: Dictionary) -> void: r["seat_piece"] = "x",
		"exiting not a bool": func(r: Dictionary) -> void: r["seat_exiting"] = 1,
		"not a seat row": func(r: Dictionary) -> void: r["seat_piece"]["def"] = "checkin_desk",
		"an unused relocation field": func(r: Dictionary) -> void: r["seat_piece"]["left"] = -1,
		"seat cell outside the row": func(r: Dictionary) -> void: r["seat_cell"] = [5, 5],
		"chair front not the row's": func(r: Dictionary) -> void: r["seat_front"] = [5, 5],
		"row anchored away from the seat":
		func(r: Dictionary) -> void: r["seat_piece"]["anchor"] = [30, 3],
		"a seat and no placement": _no_placement,
	}
	for label: String in cases:
		(
			assert_bool(_loads_with(data, p.id, cases[label]))
			. override_failure_message("loaded: " + label)
			. is_false()
		)


func test_a_version_20_save_is_refused() -> void:
	_sitter(Passenger.Stage.SEATED)
	var data := _save()
	assert_int(int(data["passengers"]["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	data["passengers"]["save_version"] = PassengerSim.SAVE_VERSION - 1
	assert_object(_twin(data)).is_null()


## The seat a passenger gets up from is free for another from the tick it turned
## back, in the world that ran on and in the one loaded from its save.
func test_the_seat_a_passenger_gets_up_from_can_be_claimed_also_after_a_load() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var key := _key_of(_world, p)
	_move_row(p)
	_world.step()
	assert_bool(p.seat_exiting).is_true()
	assert_str(key).is_not_empty()
	var twin := _twin(_save())
	assert_object(twin).is_not_null()
	assert_bool(twin.passenger(p.id).seat_exiting).is_true()
	assert_bool(_rival_gets(_world, key)).override_failure_message("running world").is_true()
	assert_bool(_rival_gets(twin, key)).override_failure_message("loaded world").is_true()
	twin.free_all()


## A row moved away and back while its passenger gets up: the seat is at the
## cell it held again, but the passenger gave up its claim, so a load must not
## give it back.
func test_a_row_moved_away_and_back_leaves_the_seat_free_after_a_load() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var key := _key_of(_world, p)
	var home: Vector2i = p.seat_piece["anchor"]
	_move_row(p)
	for i in 3:
		_world.step()
	_move_row(p, home)
	_world.step()
	assert_bool(p.seat_exiting).is_true()
	assert_int(p.stage).is_equal(Passenger.Stage.STANDING_UP)
	var twin := _twin(_save())
	assert_object(twin).is_not_null()
	assert_bool(_rival_gets(_world, key)).override_failure_message("running world").is_true()
	assert_bool(_rival_gets(twin, key)).override_failure_message("loaded world").is_true()
	twin.free_all()


## A passenger still walking to its chair when the row moves has not sat down:
## it is released and chooses again, and ends seated on a chair the layout has.
func test_a_passenger_walking_to_a_row_that_moves_chooses_again() -> void:
	_world = PassengerTestWorld.reference_world()
	_starts = FlightSim.schedule_starts(0)
	_world.run_to(10)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_send_to_gate(p, 0)
	p.at = Vector2i(15, 5)
	p.clear_path()
	var tries := 0
	while p.seat_object == 0 and tries < 40:
		_world.step()
		tries += 1
	assert_int(p.seat_object).is_not_equal(0)
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	assert_dict(p.seat_piece).is_not_empty()
	_move_row(p)
	_world.step()
	assert_bool(p.seat_exiting).is_false()
	var stages: Array[int] = []
	while p.stage != Passenger.Stage.SEATED and _world.sim.tick < 800:
		_world.step()
		stages.append(p.stage)
	assert_int(p.stage).is_equal(Passenger.Stage.SEATED)
	assert_array(stages).not_contains([Passenger.Stage.STANDING_UP])
	assert_str(_key_of(_world, p)).is_not_empty()
	assert_dict(p.seat_piece).is_equal(Relocation.placement(_world.grid, p.seat_object))


## A version 10 save has no seat placement or exit flag: a passenger standing up
## from a chair gets the grid's placement of its row, and finishes standing up.
func test_a_version_10_save_with_a_standing_up_passenger_gets_its_placement() -> void:
	var p := _sitter(Passenger.Stage.STANDING_UP)
	var placement := p.seat_piece.duplicate()
	var data := _save()
	var block: Dictionary = data["passengers"]
	block["save_version"] = 10
	block.erase("shop")
	for record: Dictionary in block["passengers"]:
		record.erase("boredom")
		record.erase("shop_cooldown")
		record.erase("seat_piece")
		record.erase("seat_exiting")
	var twin := _twin(data)
	assert_object(twin).is_not_null()
	var q := twin.passenger(p.id)
	assert_int(q.stage).is_equal(Passenger.Stage.STANDING_UP)
	assert_dict(q.seat_piece).is_equal(placement)
	assert_bool(q.seat_exiting).is_false()
	for i in PassengerSim.STAND_UP_TICKS + 2:
		twin.step()
	assert_int(q.stage).is_equal(Passenger.Stage.TO_GATE)
	twin.free_all()


## An old save derives the placement from the grid without the parser, so a seat
## that names a desk (or any object that is not a seat row) must be refused: here
## the seat cell and chair front are the desk's own, so only its def gives it away.
func test_a_version_10_save_whose_seat_is_not_a_seat_row_is_refused() -> void:
	var p := _sitter(Passenger.Stage.SEATED)
	var data := _save()
	var block: Dictionary = data["passengers"]
	block["save_version"] = 10
	block.erase("shop")
	for record: Dictionary in block["passengers"]:
		record.erase("boredom")
		record.erase("shop_cooldown")
		record.erase("seat_piece")
		record.erase("seat_exiting")
	var other := 0
	for id in range(1, 60):
		var held := _world.grid.get_object(id)
		if not held.is_empty() and held["def"] != &"seat_row":
			other = id
			break
	assert_int(other).is_not_equal(0)
	var twin := _twin(data)
	assert_object(twin).override_failure_message("control: the old save loads").is_not_null()
	twin.free_all()
	var desk := _world.grid.get_object(other)
	var cell: Vector2i = (
		BuildCatalog.get_def(desk["def"]).footprint(desk["anchor"], desk["facing"])[0]
	)
	var front := cell + TerminalLayout.front_of(desk["facing"])
	for record: Dictionary in block["passengers"]:
		if int(record["id"]) == p.id:
			record["seat_object"] = other
			record["seat_cell"] = [cell.x, cell.y]
			record["seat_front"] = [front.x, front.y]
	assert_object(_twin(data)).is_null()
