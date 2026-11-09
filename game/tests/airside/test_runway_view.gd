class_name TestRunwayView
extends GdUnitTestSuite
## The drawn runway follows FlightSim.runway.size (Runway R9; board 48f9bf52,
## the R8 review residual that main.tscn drew a fixed small runway): it is drawn
## at scene start, redrawn when the size changes (the works end, a load) and
## the scene holds no hand-placed runway pieces any more.


func _view(sim: FlightSim) -> RunwayView:
	var view := auto_free(RunwayView.new()) as RunwayView
	view.flights = sim
	add_child(view)
	return view


func _pieces(view: RunwayView) -> Array[Node]:
	return view.get_child(0).get_children()


func test_it_draws_the_size_at_start_and_follows_a_change() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.runway.size = PlaneClasses.SMALL
	var view := _view(sim)
	assert_str(view.shown_size()).is_equal(PlaneClasses.SMALL)
	assert_int(view.get_child_count()).is_equal(1)
	assert_int(_pieces(view).size()).is_equal(Runway.pieces(PlaneClasses.SMALL).size())
	for size in [PlaneClasses.MEDIUM, PlaneClasses.LARGE, PlaneClasses.SMALL]:
		sim.runway.size = size
		print("%s runway drawn with %d pieces" % [size, _pieces(view).size()])
		assert_str(view.shown_size()).is_equal(size)
		assert_int(_pieces(view).size()).is_equal(Runway.pieces(size).size())
		assert_str(view.get_child(0).name).is_equal("Runway%s" % size.capitalize())
	# Control: the sizes differ, so a view that never redrew would fail above.
	assert_int(Runway.pieces(PlaneClasses.LARGE).size()).is_greater(
		Runway.pieces(PlaneClasses.SMALL).size()
	)


func test_a_load_redraws_the_runway() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.runway.size = PlaneClasses.SMALL
	var view := _view(sim)
	var saved := Runway.new(PlaneClasses.LARGE)
	assert_bool(sim.runway.from_snapshot(saved.to_snapshot())).is_true()
	assert_str(view.shown_size()).is_equal(PlaneClasses.LARGE)
	assert_int(_pieces(view).size()).is_equal(Runway.pieces(PlaneClasses.LARGE).size())


func test_the_scene_draws_the_runway_through_the_view_alone() -> void:
	var state := (load("res://main/main.tscn") as PackedScene).get_state()
	var names := []
	for node in state.get_node_count():
		names.append(String(state.get_node_name(node)))
	assert_array(names).contains(["RunwayView"])
	for gone in ["RunwayEndWest", "RunwayWest", "RunwayMid", "RunwayEast", "RunwayEndEast"]:
		assert_array(names).not_contains([gone])
