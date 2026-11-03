class_name TestBubbleDeclutter
extends GdUnitTestSuite
## Overlapping passenger speech bubbles (decision passenger-speech-bubbles-that-
## overlap-on-screen-keep-the-one): the one nearest the front of the queue
## stays, the ones it overlaps are hidden, "I'm late!" wins over the others,
## ties go to the lower passenger id, and bubbles that clear each other all stay.

const SIZE := Vector2(100.0, 30.0)


func _entry(id: int, text: String, rank: int, at: Vector2) -> Dictionary:
	return BubbleDeclutter.entry(id, text, rank, Rect2(at, SIZE))


func test_the_bubble_nearest_the_front_of_the_queue_stays() -> void:
	var entries: Array[Dictionary] = [
		_entry(1, "Queue full", 5, Vector2(0.0, 0.0)),
		_entry(2, "Queue full", 0, Vector2(10.0, 0.0)),
		_entry(3, "Queue full", 3, Vector2(20.0, 0.0)),
	]
	var hidden := BubbleDeclutter.hidden(entries)
	hidden.sort()
	assert_array(hidden).is_equal([1, 3])


func test_late_wins_over_queue_full_even_further_back() -> void:
	var entries: Array[Dictionary] = [
		_entry(1, "Queue full", 0, Vector2(0.0, 0.0)),
		_entry(2, BubbleDeclutter.LATE_TEXT, 9, Vector2(10.0, 0.0)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([1])


func test_late_bubbles_keep_the_front_of_queue_order_among_themselves() -> void:
	var entries: Array[Dictionary] = [
		_entry(1, BubbleDeclutter.LATE_TEXT, 4, Vector2(0.0, 0.0)),
		_entry(2, BubbleDeclutter.LATE_TEXT, 2, Vector2(10.0, 0.0)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([1])


func test_equal_rank_and_text_goes_to_the_lower_passenger_id() -> void:
	var entries: Array[Dictionary] = [
		_entry(7, "Queue full", 2, Vector2(0.0, 0.0)),
		_entry(4, "Queue full", 2, Vector2(10.0, 0.0)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([7])
	entries.reverse()
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([7])


func test_bubbles_that_clear_each_other_all_stay() -> void:
	var entries: Array[Dictionary] = [
		_entry(1, "Queue full", 0, Vector2(0.0, 0.0)),
		_entry(2, "Queue full", 1, Vector2(SIZE.x + BubbleDeclutter.MARGIN_PX + 1.0, 0.0)),
		_entry(3, "Queue full", 2, Vector2(0.0, SIZE.y + BubbleDeclutter.MARGIN_PX + 1.0)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_empty()


func test_bubbles_closer_than_the_margin_count_as_overlapping() -> void:
	var entries: Array[Dictionary] = [
		_entry(1, "Queue full", 0, Vector2(0.0, 0.0)),
		_entry(2, "Queue full", 1, Vector2(SIZE.x + BubbleDeclutter.MARGIN_PX - 1.0, 0.0)),
	]
	assert_array(BubbleDeclutter.hidden(entries)).is_equal([2])


func test_a_hidden_bubble_does_not_hide_the_one_behind_it() -> void:
	# 1 and 3 overlap 2 but not each other: 2 is hidden by 1, so 3 stays.
	var entries: Array[Dictionary] = [
		_entry(1, "Queue full", 0, Vector2(0.0, 0.0)),
		_entry(2, "Queue full", 1, Vector2(60.0, 0.0)),
		_entry(3, "Queue full", 2, Vector2(120.0, 0.0)),
	]
	var hidden := BubbleDeclutter.hidden(entries)
	hidden.sort()
	assert_array(hidden).is_equal([2])


func test_a_walker_outside_every_queue_ranks_behind_a_queued_passenger() -> void:
	var lane: Array[int] = [11, 12]
	var holding: Array[int] = [13]
	assert_int(BubbleDeclutter.rank_in(lane, holding, 11)).is_equal(0)
	assert_int(BubbleDeclutter.rank_in(lane, holding, 12)).is_equal(1)
	assert_int(BubbleDeclutter.rank_in(lane, holding, 13)).is_equal(2)
	assert_int(BubbleDeclutter.rank_in(lane, holding, 99)).is_equal(BubbleDeclutter.NO_QUEUE)


func test_the_late_text_is_the_one_the_sim_says() -> void:
	PassengerTestWorld.tracker = self
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.late = true
	p.stuck = Passenger.Stuck.NONE
	assert_str(world.sim.bubble_text(p)).is_equal(BubbleDeclutter.LATE_TEXT)
	assert_int(BubbleDeclutter.tier_of(world.sim.bubble_text(p))).is_equal(0)
	assert_int(BubbleDeclutter.tier_of("Queue full")).is_equal(1)
	world.free_all()
	PassengerTestWorld.tracker = null


func _views_with_camera(world: PassengerTestWorld, ids: Array[int]) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	auto_free(views)
	var camera := Camera3D.new()
	add_child(camera)
	auto_free(camera)
	camera.current = true
	camera.global_position = world.sim.world_position(world.passenger(ids[0])) + Vector3(0, 8, 8)
	camera.look_at(world.sim.world_position(world.passenger(ids[0])) + Vector3(0, 2, 0))
	views.sync()
	return views


func _bubble(views: PassengerViews, id: int) -> Label3D:
	return views.node_for(id).get_node("Bubble") as Label3D


func test_views_hide_the_overlapping_bubble_of_the_passenger_further_back() -> void:
	PassengerTestWorld.tracker = self
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var early := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var full := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var late := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.passenger(early).stuck = Passenger.Stuck.QUEUE_FULL
	world.passenger(full).stuck = Passenger.Stuck.QUEUE_FULL
	world.passenger(late).late = true
	var views := _views_with_camera(world, [early, full, late])
	views.draw()
	assert_str(_bubble(views, early).text).is_equal("Queue full")
	assert_str(_bubble(views, late).text).is_equal(BubbleDeclutter.LATE_TEXT)
	# All three stand on one spot: the late bubble wins, the rest are hidden.
	assert_bool(_bubble(views, late).visible).is_true()
	assert_bool(_bubble(views, early).visible).is_false()
	assert_bool(_bubble(views, full).visible).is_false()
	world.passenger(late).late = false
	views.sync()
	views.draw()
	# With no late bubble the lower id of the equal ranks is kept.
	assert_bool(_bubble(views, early).visible).is_true()
	assert_bool(_bubble(views, full).visible).is_false()
	world.free_all()
	PassengerTestWorld.tracker = null
