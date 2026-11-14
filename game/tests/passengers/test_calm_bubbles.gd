class_name TestCalmBubbles
extends GdUnitTestSuite
## Passenger bubbles in the calm view (decision calm-cozy-default-view-quiet-
## world-detail-on-ask-soft-statio, part 3; calm-view-technical-design-shared-
## hover-target-reusing-click, part 5): the default view shows no speech and no
## wish bubble; the hovered, pinned or inspected passenger shows its own in the
## same draw; the Mood overlay's Boredom mode shows every wish and no speech;
## its Late mode shows the late bubble over exactly the late, unfinished
## passengers, whatever the sim's text puts first; and the overlap declutter
## still runs inside the modes, never hiding the focused passenger's bubble.

## Cells on the airside floor (ShopTestLayout), far enough apart that no two
## bubbles overlap on screen.
const SPOTS: Array[Vector2i] = [
	Vector2i(11, 4), Vector2i(17, 4), Vector2i(11, 7), Vector2i(17, 7), Vector2i(14, 5)
]

var _world: PassengerTestWorld
var _views: PassengerViews
var _rig: TycoonCamera
var _camera: Camera3D
var _screen: SubViewport
var _hover: HoverTarget
## Role -> passenger id: "speaker" (queue full), "late", "late_stuck" (late and
## queue full), "missed" (late, then missed its flight), "wisher" (a kiosk wish).
var _cast := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _screen != null:
		_screen.free()
		_screen = null
	if _world != null:
		_world.free_all()
		_world = null
	_views = null
	_rig = null
	_camera = null
	_hover = null
	_cast = {}


## The cast drawn in a 1600 x 900 viewport, closer than the home zoom, with a
## HoverTarget the views resolve in draw() and a Mood overlay that is off.
func _open() -> void:
	var grid := BuildGrid.new()
	WishTestLayout.build(grid, [&"kiosk"])
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return &"kiosk"
	_screen = SubViewport.new()
	_screen.size = Vector2i(1600, 900)
	add_child(_screen)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_hover = HoverTarget.new()
	_hover.views = _views
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_views.hover_target = _hover
	_screen.add_child(_views)
	_screen.add_child(_hover)
	_hover.set_process(false)
	_rig = TycoonCamera.new()
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_rig.add_child(_camera)
	_screen.add_child(_rig)
	_rig.set_process(false)
	_rig.home_distance = 40.0
	_rig.distance = 12.0
	_camera.make_current()
	PassengerTestWorld.ensure_overlay(_views)
	_cast["speaker"] = _stand(SPOTS[0], false, Passenger.Stuck.QUEUE_FULL).id
	_cast["late"] = _stand(SPOTS[1], true, Passenger.Stuck.NONE).id
	_cast["late_stuck"] = _stand(SPOTS[2], true, Passenger.Stuck.QUEUE_FULL).id
	var missed := _stand(SPOTS[3], true, Passenger.Stuck.NONE)
	missed.stage = Passenger.Stage.MISSED
	missed.outcome_tick = _world.sim.tick
	_cast["missed"] = missed.id
	_cast["wisher"] = ShopTestLayout.airside_guest(_world, BoredomSim.MAX, SPOTS[4]).id
	_views.sync()
	var centre := _world.sim.grid.cell_to_world(Vector2i(14, 6))
	_camera.global_position = centre + Vector3(0.0, 12.0, 9.0)
	_camera.look_at(centre + Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	_views.draw()


## A calm passenger standing on `cell`, `late` and `stuck` as given.
func _stand(cell: Vector2i, late: bool, stuck: Passenger.Stuck) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.at = cell
	p.clear_path()
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _world.sim.tick
	p.late = late
	p.stuck = stuck
	return p


func _bubble(id: int) -> Label3D:
	return _views.node_for(id).get_node("Bubble") as Label3D


func _wish(id: int) -> Sprite3D:
	return _views.node_for(id).get_node(WishIconView.SPRITE) as Sprite3D


## Passenger id -> the text of every bubble drawn now (text set and visible).
func _shown_bubbles() -> Dictionary:
	var out := {}
	for id: int in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var bubble := node.get_node("Bubble") as Label3D
		if bubble.visible and bubble.text != "":
			out[id] = bubble.text
	return out


## The ids whose wish bubble is drawn now.
func _shown_wishes() -> Array[int]:
	var out: Array[int] = []
	for id: int in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and _wish(id).visible:
			out.append(id)
	return out


func _mode(mode: MoodTint.Mode, shown := true) -> void:
	_views.mood_overlay.set_mode(mode)
	_views.mood_overlay.set_shown(shown)
	_views.draw()


## The screen point over `id`'s head that a hover there resolves to it.
func _over(id: int) -> Vector2:
	var node := _views.node_for(id)
	return _camera.unproject_position(node.global_position + Vector3(0.0, 1.0, 0.0))


func test_the_default_view_shows_no_speech_and_no_wish_bubble() -> void:
	_open()
	var speech := {}
	for role: String in _cast:
		speech[role] = _views.node_for(_cast[role]).get_meta(&"speech", "")
	print("speech per role %s; shown %s, wishes %s" % [speech, _shown_bubbles(), _shown_wishes()])
	# The controls: the cast has words to say and a wish to show.
	assert_str(speech["speaker"]).is_equal("Queue full")
	assert_str(speech["late"]).is_equal(BubbleDeclutter.LATE_TEXT)
	assert_str(_views.node_for(_cast["wisher"]).get_meta(&"wish", "")).is_not_empty()
	assert_bool(_views.mood_overlay.is_shown()).is_false()
	assert_dict(_shown_bubbles()).is_empty()
	assert_array(_shown_wishes()).is_empty()
	# With every bubble on (the seam), the same cast does draw them.
	_views.all_bubbles = true
	_views.draw()
	# Everyone but the wisher, who has no words, speaks.
	assert_int(_shown_bubbles().size()).is_equal(4)
	assert_bool(_shown_bubbles().has(_cast["wisher"])).is_false()
	assert_array(_shown_wishes()).contains([_cast["wisher"]])


func test_a_hovered_passenger_shows_its_bubble_in_the_same_draw() -> void:
	_open()
	var speaker: int = _cast["speaker"]
	_hover.pointer_override = _over(speaker)
	var seen := {}
	var record := func() -> void: seen["hovered"] = _hover.hovered_passenger()
	_views.layout_started.connect(record)
	# One draw: it resolves the hover, then lays out the bubbles.
	_views.draw()
	_views.layout_started.disconnect(record)
	print("hover at %s: at layout %s, shown %s" % [_hover.pointer_override, seen, _shown_bubbles()])
	assert_that(seen.get("hovered")).is_equal(speaker)
	assert_dict(_shown_bubbles()).is_equal({speaker: "Queue full"})
	# The hover moves to the wisher: its wish shows, the speaker's bubble goes.
	var wisher: int = _cast["wisher"]
	_hover.pointer_override = _over(wisher)
	_views.draw()
	print("hover on the wisher: shown %s, wishes %s" % [_shown_bubbles(), _shown_wishes()])
	assert_dict(_shown_bubbles()).is_empty()
	assert_array(_shown_wishes()).is_equal([wisher])
	# Off every passenger, nothing shows.
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_views.draw()
	assert_dict(_shown_bubbles()).is_empty()
	assert_array(_shown_wishes()).is_empty()


func test_a_pinned_or_inspected_passenger_shows_its_bubble_while_another_is_hovered() -> void:
	_open()
	var late: int = _cast["late"]
	var speaker: int = _cast["speaker"]
	# A click selects the passenger PassengerHud inspects, which a pin follows.
	_views.selected_id = late
	_hover.pointer_override = _over(speaker)
	_views.draw()
	print("selected %d, hovered %d: shown %s" % [late, speaker, _shown_bubbles()])
	assert_dict(_shown_bubbles()).is_equal({late: BubbleDeclutter.LATE_TEXT, speaker: "Queue full"})
	_views.selected_id = 0
	_views.draw()
	assert_dict(_shown_bubbles()).is_equal({speaker: "Queue full"})


func test_boredom_mode_shows_the_wishes_and_no_speech() -> void:
	_open()
	_mode(MoodTint.Mode.BOREDOM)
	print("boredom mode: shown %s, wishes %s" % [_shown_bubbles(), _shown_wishes()])
	assert_array(_shown_wishes()).is_equal([_cast["wisher"]])
	assert_dict(_shown_bubbles()).is_empty()
	# Hunger mode shows no wish; closing the overlay shows none either.
	_mode(MoodTint.Mode.HUNGER)
	assert_array(_shown_wishes()).is_empty()
	_mode(MoodTint.Mode.BOREDOM, false)
	assert_array(_shown_wishes()).is_empty()


func test_late_mode_shows_the_late_bubble_over_exactly_the_late_unfinished_passengers() -> void:
	_open()
	_mode(MoodTint.Mode.LATE)
	var shown := _shown_bubbles()
	print("late mode: shown %s, wishes %s" % [shown, _shown_wishes()])
	# Late and late-but-stuck show it (the sim's text puts "Queue full" first
	# for the second); the missed one, the speaker and the wisher do not.
	assert_dict(shown).is_equal(
		{_cast["late"]: BubbleDeclutter.LATE_TEXT, _cast["late_stuck"]: BubbleDeclutter.LATE_TEXT}
	)
	assert_str(_views.node_for(_cast["late_stuck"]).get_meta(&"speech", "")).is_equal("Queue full")
	assert_bool(_world.passenger(_cast["missed"]).late).is_true()
	assert_array(_shown_wishes()).is_empty()
	# One soft disc per late passenger. Where they lie is for the windowed plate:
	# the headless rendering server keeps no instance transforms to read back.
	var marks := (_views.get_node("LateMarks") as MultiMeshInstance3D).multimesh
	print("late marks %d" % marks.visible_instance_count)
	assert_int(marks.visible_instance_count).is_equal(2)
	# Mood mode shows none of them, and no disc.
	_mode(MoodTint.Mode.MOOD)
	assert_dict(_shown_bubbles()).is_empty()
	assert_int(marks.visible_instance_count).is_equal(0)


func test_the_declutter_still_runs_in_late_mode_and_keeps_the_focused_bubble() -> void:
	_open()
	# Every late passenger stands on one spot, so their bubbles overlap.
	var late: Array[int] = []
	for i in 4:
		late.append(_stand(SPOTS[1], true, Passenger.Stuck.NONE).id)
	_views.sync()
	_mode(MoodTint.Mode.LATE)
	var shown := _shown_bubbles()
	var on_spot := late.filter(func(id: int) -> bool: return shown.has(id))
	print("late mode, four on one spot: shown %s, on the spot %s" % [shown, on_spot])
	assert_int(on_spot.size() + (1 if shown.has(_cast["late"]) else 0)).is_equal(1)
	# The hovered one of them is kept, whatever the late order would keep.
	var focus: int = late[3]
	_views.selected_id = focus
	_views.draw()
	shown = _shown_bubbles()
	print("selected %d: shown %s" % [focus, shown])
	assert_bool(shown.has(focus)).is_true()
	assert_bool(shown.has(late[0])).is_false()
	assert_bool(shown.has(_cast["late"])).is_false()


func test_a_focused_speaker_shows_its_speech_in_every_mode_and_an_unfocused_one_does_not() -> void:
	_open()
	var speaker: int = _cast["speaker"]
	var modes := {
		"off": null,
		"mood": MoodTint.Mode.MOOD,
		"hunger": MoodTint.Mode.HUNGER,
		"toilet": MoodTint.Mode.TOILET,
		"boredom": MoodTint.Mode.BOREDOM,
		"late": MoodTint.Mode.LATE,
	}
	for label: String in modes:
		# Unfocused: the speaker (not late) shows nothing in any mode.
		_hover.pointer_override = Vector2(-1.0, -1.0)
		_views.selected_id = 0
		if modes[label] == null:
			_mode(MoodTint.Mode.MOOD, false)
		else:
			_mode(modes[label])
		var unfocused := _shown_bubbles()
		# Focused (hovered): the same passenger shows its own speech.
		_hover.pointer_override = _over(speaker)
		_views.draw()
		var focused := _shown_bubbles()
		print("%s mode: unfocused %s, hovered %s" % [label, unfocused, focused])
		assert_bool(unfocused.has(speaker)).override_failure_message(label).is_false()
		assert_str(focused.get(speaker, "")).override_failure_message(label).is_equal("Queue full")
		# Pinned or inspected shows it the same way.
		_hover.pointer_override = Vector2(-1.0, -1.0)
		_views.selected_id = speaker
		_views.draw()
		assert_str(_shown_bubbles().get(speaker, "")).override_failure_message(label).is_equal(
			"Queue full"
		)
		# Only Late mode shows anyone else's bubble: the late passengers.
		var others := focused.keys().filter(func(id: int) -> bool: return id != speaker)
		if label == "late":
			assert_array(others).contains_exactly_in_any_order([_cast["late"], _cast["late_stuck"]])
		else:
			assert_array(others).is_empty()


func test_the_shown_text_rules() -> void:
	var late := BubbleDeclutter.LATE_TEXT
	assert_str(BubbleDeclutter.shown_text("Queue full", true, false, false)).is_empty()
	assert_str(BubbleDeclutter.shown_text("Queue full", true, true, false)).is_equal("Queue full")
	assert_str(BubbleDeclutter.shown_text("Queue full", true, false, true)).is_equal(late)
	assert_str(BubbleDeclutter.shown_text("Queue full", false, false, true)).is_empty()
	assert_str(BubbleDeclutter.shown_text("Queue full", false, true, true)).is_equal("Queue full")
	assert_str(BubbleDeclutter.shown_text("Queue full", false, false, false, true)).is_equal(
		"Queue full"
	)
	var entry := BubbleDeclutter.entry(1, "Queue full", 3, Rect2(), true)
	assert_int(entry["tier"]).is_less(BubbleDeclutter.tier_of(late))
