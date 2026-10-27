class_name TestCafeViews
extends GdUnitTestSuite
## How a cafe visit looks: guests sit with the sit clips at the seat's
## Mount_SitRoot facing the table, the follow panel shows hunger, and a paid
## visit pops '+$<amount>' over the shop (ruling shops-and-food-stalls-earn-
## per-visit-toilets-and-screens-cos), in the room label's column and under it,
## which rises, fades and is reused, and never covers the room label on screen.

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


func _guest() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


func _run_to_stage(p: Passenger, stage: Passenger.Stage) -> void:
	while p.stage != stage and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(stage)


func _clip(id: int) -> String:
	return _views.node_for(id).get_meta(&"clip", "")


func test_a_seated_guest_sits_at_the_seat_root_facing_the_table() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
	assert_str(_clip(p.id)).is_equal("sit_down")
	_run_to_stage(p, Passenger.Stage.CAFE_SEATED)
	assert_str(_clip(p.id)).is_equal("sit_idle")
	var node := _views.node_for(p.id)
	var root := BuildObjectDef.seat_root_world(_world.grid, seat)
	var facing: Vector2i = seat["facing"]
	print(
		"seated at %s root %s facing %s yaw %.3f" % [node.position, root, facing, node.rotation.y]
	)
	assert_float(_world.sim.world_position(p).distance_to(root)).is_less(0.001)
	assert_float(node.rotation.y).is_equal_approx(atan2(facing.x, facing.y), 0.001)
	_views.draw()
	assert_float(node.rotation.y).is_equal_approx(atan2(facing.x, facing.y), 0.001)
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	assert_str(_clip(p.id)).is_equal("stand_up")


func test_an_ordering_guest_faces_the_counter() -> void:
	var p := _guest()
	_run_to_stage(p, Passenger.Stage.CAFE_ORDER)
	# The counters face south (+y), so the guest looks north (-z): yaw pi.
	var yaw := _views.node_for(p.id).rotation.y
	print("ordering at %s yaw %.3f" % [p.at, yaw])
	assert_bool(p.is_moving()).is_false()
	assert_float(absf(yaw)).is_equal_approx(PI, 0.001)
	_views.draw()
	assert_float(absf(_views.node_for(p.id).rotation.y)).is_equal_approx(PI, 0.001)


func test_sitting_down_moves_from_the_approach_cell_to_the_seat_root() -> void:
	var p := _guest()
	var seat := _world.sim.cafes.visit_of(p.id).seat
	_run_to_stage(p, Passenger.Stage.CAFE_SITTING_DOWN)
	var approach := _world.grid.cell_to_world(seat["approach"])
	var root := BuildObjectDef.seat_root_world(_world.grid, seat)
	assert_float(_world.sim.world_position(p).distance_to(approach)).is_less(0.001)
	for i in CafeSim.SHUFFLE_TICKS:
		_world.step()
	assert_float(_world.sim.world_position(p).distance_to(root)).is_less(0.001)


func test_the_follow_panel_shows_hunger() -> void:
	# In the tree, so the HUD's own labels are its children and freed with it.
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	hud.views = _views
	add_child(hud)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 47
	_views.selected_id = p.id
	assert_str(hud.follow_text()).contains("hunger 47")
	hud.free()


## Was "..._over_the_counter_then_fades": the pop moved from over the counter
## to the room label's column (board item seated-passengers-are-drawn-standing-
## in-the-passenger-plates: the pop covered the 'Cafe Ready' label). The amount,
## rise, fade and reuse checks are kept; the rise is RISE_M (0.4 m), so the
## half-way check is RISE_M * 0.4 instead of 0.3 m.
func test_a_paid_visit_pops_its_amount_under_the_room_label_then_fades() -> void:
	var rooms := RoomView.new()
	add_child(rooms)
	rooms.watch(_world.grid)
	var p := _guest()
	var pops := _views.cafe_pops()
	assert_int(pops.live_count()).is_equal(0)
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	var visit := _world.sim.cafes.visit_of(p.id)
	var amount := visit.amount
	assert_int(amount).is_greater(0)
	assert_int(pops.live_count()).is_equal(1)
	var label := pops.live_labels()[0]
	var room_label := rooms.label_of(visit.room)
	assert_object(room_label).is_not_null()
	var at := room_label.position
	print("pop '%s' at %s, room label at %s" % [label.text, label.position, at])
	assert_str(label.text).is_equal("+$%d" % amount)
	(
		assert_float(Vector2(label.position.x, label.position.z).distance_to(Vector2(at.x, at.z)))
		. is_less(0.01)
	)
	assert_int(label.vertical_alignment).is_equal(VERTICAL_ALIGNMENT_TOP)
	assert_float(label.position.y).is_equal_approx(at.y - CafePops.GAP_M - CafePops.RISE_M, 0.001)
	var start_y := label.position.y
	pops.advance(CafePops.POP_SECONDS * 0.5)
	assert_float(label.position.y).is_greater(start_y + CafePops.RISE_M * 0.4)
	assert_float(label.modulate.a).is_less(0.75)
	pops.advance(CafePops.POP_SECONDS * 0.49)
	assert_float(label.position.y).is_less_equal(at.y - CafePops.GAP_M + 0.001)
	pops.advance(CafePops.POP_SECONDS)
	assert_int(pops.live_count()).is_equal(0)
	assert_bool(label.visible).is_false()
	rooms.free()


## A Label3D's text box in its own plane (metres, y up from the label's
## position), from the font's line metrics and the vertical alignment, grown by
## the whole outline. Label3D.get_aabb() is no help: for a billboard it is a
## cube that covers every turn.
func _text_box(label: Label3D) -> Rect2:
	var font := label.font if label.font != null else ThemeDB.fallback_font
	var px := font.get_multiline_string_size(
		label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size
	)
	var size := px * label.pixel_size
	var bottom := 0.0
	match label.vertical_alignment:
		VERTICAL_ALIGNMENT_TOP:
			bottom = -size.y
		VERTICAL_ALIGNMENT_CENTER:
			bottom = -size.y / 2.0
	var box := Rect2(Vector2(-size.x / 2.0 + label.offset.x * label.pixel_size, bottom), size)
	return box.grow(label.outline_size * label.pixel_size)


## The screen box of a camera-facing Label3D: its text box laid on the
## camera's right and up axes, then projected.
func _screen_box(cam: Camera3D, label: Label3D) -> Rect2:
	var box := _text_box(label)
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var points := PackedVector2Array()
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			points.append(cam.unproject_position(label.global_position + right * x + up * y))
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


func test_the_pop_never_covers_the_room_label_on_screen() -> void:
	var rooms := RoomView.new()
	add_child(rooms)
	rooms.watch(_world.grid)
	var cam := Camera3D.new()
	add_child(cam)
	var p := _guest()
	var pops := _views.cafe_pops()
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	var label := pops.live_labels()[0]
	var room_label := rooms.label_of(_world.sim.cafes.visit_of(p.id).room)
	await get_tree().process_frame
	# Laid-out text boxes, or the overlap check below would pass on empty boxes.
	print("text boxes pop=%s label=%s" % [_text_box(label), _text_box(room_label)])
	assert_float(_text_box(label).size.y).is_greater(0.3)
	assert_float(_text_box(room_label).size.y).is_greater(0.8)
	# Every centred view (84 of 168) and most off-centre ones show both.
	assert_int(_views_seen(cam, label, room_label, pops)).is_greater(100)
	cam.free()
	rooms.free()


## Checks the pop against the room label from the game camera's own views:
## its field of view, its tilt for each zoom distance (35 degrees close, 65 far)
## from the closest to the farthest zoom, four turns, aimed at the ground under
## the label and 5 m beside it, at three ages of the pop. Only the on-screen
## parts of the boxes count. Returns how many views had both on screen.
func _views_seen(cam: Camera3D, label: Label3D, room_label: Label3D, pops: CafePops) -> int:
	cam.fov = 55.0  # game/camera/tycoon_camera.tscn
	var screen := get_viewport().get_visible_rect()
	var rig := TycoonCamera.new()
	var ground := room_label.global_position
	ground.y = _world.grid.origin.y
	var checked := 0
	for age in [0.0, 0.5, 0.98]:
		pops.advance(CafePops.POP_SECONDS * age - float(label.get_meta(&"age")))
		for distance in [rig.min_distance, 12.0, 20.0, 40.0, 80.0, 150.0, rig.max_distance]:
			var pitch := deg_to_rad(rig.pitch_for_distance(distance))
			for yaw_step in 4:
				for aside in [Vector3.ZERO, Vector3(4.0, 0.0, 3.0)]:
					var yaw := yaw_step * PI / 2.0
					var target: Vector3 = ground + aside
					var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
					cam.look_at_from_position(target + back * distance, target)
					if cam.is_position_behind(label.global_position):
						continue
					var pop_box := _screen_box(cam, label).intersection(screen)
					var label_box := _screen_box(cam, room_label).intersection(screen)
					if not (pop_box.has_area() and label_box.has_area()):
						continue
					if pop_box.intersects(label_box):
						print(
							(
								"OVERLAP age=%.2f d=%.0f yaw=%d aside=%s pop=%s label=%s"
								% [age, distance, yaw_step, aside, pop_box, label_box]
							)
						)
					assert_bool(pop_box.intersects(label_box)).is_false()
					checked += 1
	print("pop/label screen boxes checked=%d of 168" % checked)
	rig.free()
	return checked


func test_pops_paid_together_in_one_room_step_aside_from_each_other() -> void:
	var p := _guest()
	var pops := _views.cafe_pops()
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	var room := _world.sim.cafes.visit_of(p.id).room
	_world.sim.cafes.paid.emit(p.id, room, 7)
	_world.sim.cafes.paid.emit(p.id, room, 9)
	var labels := pops.live_labels()
	assert_int(labels.size()).is_equal(3)
	var sides: Array[float] = []
	for label in labels:
		sides.append(label.offset.x * label.pixel_size)
		assert_float(label.position.distance_to(labels[0].position)).is_less(0.001)
	print("pop sides %s" % [sides])
	assert_float(sides[0]).is_equal_approx(0.0, 0.001)
	assert_float(sides[1]).is_equal_approx(CafePops.SIDE_STEP_M, 0.001)
	assert_float(sides[2]).is_equal_approx(-CafePops.SIDE_STEP_M, 0.001)
	# Side by side, none covers another: a step is wider than any pop's text.
	for label in labels:
		var width := _text_box(label).size.x - label.outline_size * label.pixel_size
		assert_float(CafePops.SIDE_STEP_M).is_greater(width)


## The middle pop expires while the side ones are still up: the next payment
## takes the freed middle slot, not a side slot another pop is in.
func test_a_new_pop_takes_the_slot_an_expired_pop_freed() -> void:
	var p := _guest()
	var pops := _views.cafe_pops()
	_run_to_stage(p, Passenger.Stage.CAFE_STANDING_UP)
	var room := _world.sim.cafes.visit_of(p.id).room
	var oldest := pops.live_labels()[0]
	assert_float(oldest.offset.x).is_equal_approx(0.0, 0.001)
	pops.advance(CafePops.POP_SECONDS * 0.6)
	_world.sim.cafes.paid.emit(p.id, room, 7)
	_world.sim.cafes.paid.emit(p.id, room, 9)
	pops.advance(CafePops.POP_SECONDS * 0.5)
	assert_int(pops.live_count()).is_equal(2)
	assert_bool(pops.live_labels().has(oldest)).is_false()
	_world.sim.cafes.paid.emit(p.id, room, 11)
	var sides := {}
	for label in pops.live_labels():
		sides[label.text] = snappedf(label.offset.x * label.pixel_size, 0.001)
	print("pop sides after expiry %s" % [sides])
	assert_float(sides["+$7"]).is_equal_approx(CafePops.SIDE_STEP_M, 0.001)
	assert_float(sides["+$9"]).is_equal_approx(-CafePops.SIDE_STEP_M, 0.001)
	assert_float(sides["+$11"]).is_equal_approx(0.0, 0.001)
