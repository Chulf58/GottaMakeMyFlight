class_name TestGateSeatChairs
extends GdUnitTestSuite
## A gate seat_row has three cells and four chairs. A seated passenger is drawn
## on a chair pan of the drawn seat_row.glb by the view (GateChairs), while
## the sim keeps seating by cell, at every facing and grid origin.

const SEAT_ROW := "res://assets/interior/seat_row.glb"
## The pans' top faces: tools/blender/interior/build_interior_kit.py puts the
## pan top at SEAT_LIFT + 0.46 = 0.53 m; the front half (z > 0.05) leaves out
## the backrests, whose bottom edge is at the same height.
const PAN_TOP_M := 0.53
const PAN_FRONT_Z := 0.05
const MATCH_M := 0.02

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## The x centre of each chair pan in the .glb's own frame, left to right.
func _pan_centres() -> Array[float]:
	var scene := (load(SEAT_ROW) as PackedScene).instantiate() as Node3D
	var xs: Array[float] = []
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var to_root := Transform3D.IDENTITY
		var at: Node = mesh_node
		while at != scene:
			to_root = (at as Node3D).transform * to_root
			at = at.get_parent()
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var p := to_root * v
				if absf(p.y - PAN_TOP_M) < 0.005 and p.z > PAN_FRONT_Z:
					xs.append(p.x)
	scene.free()
	xs.sort()
	# The top faces' vertices sit only on each pan's two side edges.
	var edges: Array[float] = []
	for x in xs:
		if edges.is_empty() or x - edges.back() > 0.01:
			edges.append(x)
	var centres: Array[float] = []
	for i in range(0, edges.size() - 1, 2):
		assert_float(edges[i + 1] - edges[i]).is_equal_approx(0.53, 0.02)
		centres.append((edges[i] + edges[i + 1]) / 2.0)
	assert_int(edges.size() % 2).is_equal(0)
	return centres


func test_the_seat_row_mesh_has_four_pans_and_each_cell_maps_to_its_own() -> void:
	var pans := _pan_centres()
	print("pan centres %s" % [pans])
	assert_int(pans.size()).is_equal(4)
	var used := {}
	for i in GateChairs.CHAIR_OFFSET_M.size():
		var chair: float = (i - 1) + GateChairs.CHAIR_OFFSET_M[i]
		var nearest := -1
		for j in pans.size():
			if absf(pans[j] - chair) < MATCH_M:
				nearest = j
		assert_int(nearest).is_not_equal(-1)
		used[nearest] = true
	assert_int(used.size()).is_equal(3)


func test_a_seated_passenger_is_drawn_on_a_chair_at_every_facing() -> void:
	var pans := _pan_centres()
	var grid := BuildGrid.new(Vector2i(10, 10), Vector3(3.25, 0.3, -7.5))
	for y in 10:
		for x in 10:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var anchors := [Vector2i(2, 1), Vector2i(8, 2), Vector2i(7, 8), Vector2i(1, 7)]
	for facing in 4:
		PassengerTestWorld.place(grid, &"seat_row", anchors[facing], facing)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var sim := _world.sim
	var views := PassengerViews.new()
	views.sim = sim
	# In the tree, so freeing it frees the nodes it builds in _ready.
	add_child(views)
	var checked := 0
	for seat: Dictionary in sim.layout.seats:
		var record := grid.get_object(seat["object_id"])
		var def := BuildCatalog.get_def(&"seat_row")
		var cells := def.footprint(record["anchor"], record["facing"])
		var index := cells.find(seat["cell"])
		var p := Passenger.new()
		p.id = 1000 + checked
		p.stage = Passenger.Stage.SEATED
		p.seat_object = seat["object_id"]
		p.seat_cell = seat["cell"]
		p.seat_front = seat["front"]
		var front := grid.cell_to_world(seat["front"])
		var cell := grid.cell_to_world(seat["cell"])
		# The sim seats by cell: SIT_FORWARD_M in front of the cell's centre.
		var in_sim := sim.world_position(p)
		assert_vector(in_sim).is_equal_approx(
			cell + (front - cell) * PassengerSim.SIT_FORWARD_M, Vector3.ONE * 0.001
		)
		var drawn := views.draw_position(p)
		# The pan this cell maps to, through the transform the build view draws with.
		var frame := BuildView.object_transform(grid, cells, record["facing"])
		var chair: float = (index - 1) + GateChairs.CHAIR_OFFSET_M[index]
		var nearest := pans[0]
		for x in pans:
			if absf(x - chair) < absf(nearest - chair):
				nearest = x
		var pan := frame * Vector3(nearest, 0.0, 0.0)
		var sideways := (drawn - pan).dot(frame.basis.x)
		var forward := (drawn - pan).dot(frame.basis.z)
		print(
			(
				"facing=%d cell=%s index=%d sim=%s drawn=%s pan=%s sideways=%.3f forward=%.3f"
				% [record["facing"], seat["cell"], index, in_sim, drawn, pan, sideways, forward]
			)
		)
		assert_float(absf(sideways)).is_less(MATCH_M)
		assert_float(forward).is_equal_approx(PassengerSim.SIT_FORWARD_M, 0.001)
		assert_float(drawn.y).is_equal_approx(grid.origin.y, 0.001)
		# Sitting down ends on the chair, starts at the front cell and is half
		# way sideways half way through the shuffle.
		p.stage = Passenger.Stage.SITTING_DOWN
		p.stage_tick = sim.tick - PassengerSim.SHUFFLE_TICKS
		assert_vector(views.draw_position(p)).is_equal_approx(drawn, Vector3.ONE * 0.001)
		p.stage_tick = sim.tick
		assert_vector(views.draw_position(p)).is_equal_approx(front, Vector3.ONE * 0.001)
		p.stage_tick = sim.tick - PassengerSim.SHUFFLE_TICKS / 2
		var half := views.draw_position(p) - sim.world_position(p)
		assert_vector(half).is_equal_approx((drawn - in_sim) * 0.5, Vector3.ONE * 0.001)
		# Standing up starts on the chair and ends at the front cell.
		p.stage = Passenger.Stage.STANDING_UP
		p.stage_tick = sim.tick
		assert_vector(views.draw_position(p)).is_equal_approx(drawn, Vector3.ONE * 0.001)
		p.stage_tick = sim.tick - PassengerSim.STAND_UP_TICKS
		assert_vector(views.draw_position(p)).is_equal_approx(front, Vector3.ONE * 0.001)
		checked += 1
	views.free()
	assert_int(checked).is_equal(12)
