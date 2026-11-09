class_name TestQueueWalkAround
extends GdUnitTestSuite
## A walker heading to line[index] of a station's line never walks over the
## line's cells ahead of it, line[0..index-1] (decision queue-walkers-route-
## around-their-own-line-a-walker-heading-t): every StationQueue.approach()
## branch routes round them, a walker standing on one leaves them on its first
## step, and with no way round it takes the plain route.

## An L-shaped line on an open 8x8 floor: a lane down column 2 from its front
## at (2, 1), then hold cells along row 4.
const LINE: Array[Vector2i] = [
	Vector2i(2, 1),
	Vector2i(2, 2),
	Vector2i(2, 3),
	Vector2i(2, 4),
	Vector2i(3, 4),
	Vector2i(4, 4),
	Vector2i(5, 4),
]

var _grid: BuildGrid


func before() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(8, 8))


## The cells of `path` after its first that lie on LINE ahead of `index`.
static func _over(path: Array[Vector2i], index: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(1, path.size()):
		var at := LINE.find(path[i])
		if at >= 0 and at < index:
			out.append(path[i])
	return out


## Whether the last step of `path` onto LINE[index] faces the front of the
## line or across it.
static func _faces_front(path: Array[Vector2i], index: int) -> bool:
	var step: Vector2i = path[path.size() - 1] - path[path.size() - 2]
	var front: Vector2i = LINE[index - 1] - LINE[index]
	return step.x * front.x + step.y * front.y >= 0


func _check_round(from: Vector2i, index: int) -> Array[Vector2i]:
	var path := StationQueue.approach(_grid, LINE, from, index)
	print("from %s to %s: %s" % [from, LINE[index], path])
	assert_that(path[0]).is_equal(from)
	assert_that(path[path.size() - 1]).is_equal(LINE[index])
	assert_array(_over(path, index)).is_empty()
	assert_bool(_faces_front(path, index)).is_true()
	return path


func test_a_walker_on_the_front_side_goes_round_the_line() -> void:
	var from := Vector2i(1, 2)
	# Control: every shortest way to the hold cells crosses the lane.
	var plain := _grid.find_path(from, LINE[5])
	assert_array(_over(plain, 5)).is_not_empty()
	var path := _check_round(from, 5)
	assert_int(path.size()).is_greater(plain.size())


func test_a_walker_standing_on_the_line_ahead_leaves_it_on_its_first_step() -> void:
	var from: Vector2i = LINE[1]
	# Control: along the line it would walk over line[2..4].
	assert_array(_over(StationQueue.path_to(_grid, LINE, from, 5), 5)).is_not_empty()
	var path := _check_round(from, 5)
	assert_int(LINE.find(path[1])).is_equal(-1)


func test_the_round_behind_the_target_keeps_off_the_line_too() -> void:
	# Coming at line[5] from (3, 5) would face away from line[4]: it comes
	# round by line[6], never over line[5] itself on the way.
	var path := _check_round(Vector2i(3, 5), 5)
	assert_that(path[path.size() - 2]).is_equal(LINE[6])
	assert_int(path.count(LINE[5])).is_equal(1)


func test_the_round_by_a_neighbour_of_the_last_cell_keeps_off_the_line() -> void:
	var path := _check_round(Vector2i(1, 2), 6)
	assert_int(path.count(LINE[6])).is_equal(1)


func test_behind_the_target_on_the_line_it_walks_the_line_as_before() -> void:
	var path := StationQueue.approach(_grid, LINE, LINE[6], 4)
	assert_array(path).is_equal([LINE[6], LINE[5], LINE[4]])


func test_with_no_way_round_it_takes_the_plain_route() -> void:
	# A corridor one cell wide: the line fills it from (0, 1) down.
	var corridor := PassengerTestWorld.floored(Vector2i(1, 6))
	var line: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5)
	]
	var path := StationQueue.approach(corridor, line, Vector2i(0, 0), 2)
	print("corridor: %s" % [path])
	# It comes round by line[3] to face the front, as before the shut.
	assert_array(path).is_equal([Vector2i(0, 0), line[0], line[1], line[2], line[3], line[2]])


## The live line pass: a claimant on the front side of a line with members on
## line[0..3] walks to the tail without stepping onto or brushing a member,
## and joins there.
func test_the_claimant_walks_round_the_members_and_joins() -> void:
	var by_id := {}
	var lane: Array = []
	for i in 4:
		var member := Passenger.new()
		member.id = 100 + i
		member.at = LINE[i]
		member.clear_path()
		by_id[member.id] = member
		lane.append(member.id)
	var w := Passenger.new()
	w.id = 7
	w.station = 1
	w.stage = Passenger.Stage.TO_CHECKIN
	w.at = Vector2i(1, 3)
	w.clear_path()
	by_id[7] = w
	var queues := {1: {"lane": lane, "holding": [], "serving": 0}}
	var lanes := {1: LINE.slice(0, 5)}
	var lines := {1: LINE}
	var claims := {}
	var least := INF
	var cells := {}
	var joined := false
	for tick in range(1, 400):
		joined = not (
			StationQueue
			. arrive(_grid, queues, lanes, lines, [w], by_id, tick, [], claims)
			. is_empty()
		)
		if joined:
			break
		w.walk(w.pace_mm())
		cells[w.at] = true
		for id: int in lane:
			least = minf(
				least, w.grid_position().distance_to((by_id[id] as Passenger).grid_position())
			)
	print("walked %d cells, least to a member %.3f m, at %s" % [cells.size(), least, w.at])
	assert_bool(joined).is_true()
	assert_array(queues[1]["lane"]).is_equal([100, 101, 102, 103, 7])
	assert_that(w.at).is_equal(LINE[4])
	assert_int(cells.size()).is_greater_equal(4)
	assert_float(least).is_greater_equal(0.70)


## Members standing on LINE[from_index..] onward, `count` of them, as a queue
## and its id map.
static func _members(from_index: int, count: int) -> Array:
	var by_id := {}
	var lane: Array = []
	for i in count:
		var member := Passenger.new()
		member.id = 100 + i
		member.at = LINE[from_index + i]
		member.clear_path()
		by_id[member.id] = member
		lane.append(member.id)
	return [{"lane": lane, "holding": [], "serving": 0}, by_id]


## A walker setting off for a slot past the members' block (StationQueue.
## set_off()) keeps off the members' cells only: the empty cells between them
## and its slot, kept for walkers still on their way, do not send it round.
func test_set_off_keeps_off_the_members_block_but_not_the_empty_cells_past_it() -> void:
	var got := _members(0, 2)
	var from := Vector2i(1, 3)
	var whole := StationQueue.approach(_grid, LINE, from, 5)
	var path := StationQueue.set_off(_grid, got[0], LINE, got[1], from, 5)
	print("whole line shut %s, members' block shut %s" % [whole, path])
	assert_that(path[path.size() - 1]).is_equal(LINE[5])
	assert_array(_over(path, 2)).is_empty()
	assert_bool(_faces_front(path, 5)).is_true()
	assert_int(Passenger.path_mm(path)).is_less(Passenger.path_mm(whole))


## A slot inside the members' block (members standing further back than
## their places) is raised to the free index.
func test_set_off_heads_past_members_standing_behind_the_slot() -> void:
	var got := _members(2, 2)
	var path := StationQueue.set_off(_grid, got[0], LINE, got[1], Vector2i(1, 2), 2)
	print("past the members: %s" % [path])
	assert_that(path[path.size() - 1]).is_equal(LINE[4])
	assert_array(_over(path, 4)).is_empty()
