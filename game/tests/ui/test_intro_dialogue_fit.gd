class_name TestIntroDialogueFit
extends GdUnitTestSuite
## IntroDialogue's box grows with its body text from the height the caller
## gives, up to MAX_BOX_H; past that the body scrolls (board T9). At every size
## the buttons sit below the body and inside the box, and the box and its
## nameplate stay on the screen.

## One short line, so a body of N of them is about N lines tall.
const LINE := "Passengers are on their way."
const GIVEN_HEIGHT := 400.0

var _port: SubViewport


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)


func after_test() -> void:
	_port.free()


func _open(lines: int, offer := false) -> IntroDialogue:
	var parts := PackedStringArray()
	for i in lines:
		parts.append(LINE)
	var dialog := IntroDialogue.new("A visit", "\n".join(parts), GIVEN_HEIGHT, offer)
	_port.add_child(dialog)
	# The body's scroll container sizes its text on the next sort.
	await get_tree().process_frame
	await get_tree().process_frame
	return dialog


func _rect(dialog: IntroDialogue, part: String) -> Rect2:
	return dialog.part_rects()[part]


func test_a_short_body_keeps_the_given_height() -> void:
	var dialog := await _open(1)
	print("box %s" % _rect(dialog, "box"))
	assert_float(_rect(dialog, "box").size.y).is_equal_approx(GIVEN_HEIGHT, 0.5)
	assert_bool(dialog.scrolls()).is_false()


func test_a_longer_body_grows_the_box_and_shows_every_line() -> void:
	var dialog := await _open(9)
	var box := _rect(dialog, "box")
	var body := _rect(dialog, "body")
	var text := _rect(dialog, "text")
	print("box %s body %s text %s" % [box, body, text])
	assert_float(box.size.y).is_greater(GIVEN_HEIGHT)
	assert_float(box.size.y).is_less(IntroDialogue.MAX_BOX_H)
	assert_bool(dialog.scrolls()).is_false()
	assert_bool(body.grow(0.5).encloses(text)).is_true()


func test_a_very_long_body_stops_at_the_max_height_and_scrolls() -> void:
	var dialog := await _open(40)
	var box := _rect(dialog, "box")
	var body := _rect(dialog, "body")
	var text := _rect(dialog, "text")
	print("box %s body %s text %s" % [box, body, text])
	assert_float(box.size.y).is_equal_approx(IntroDialogue.MAX_BOX_H, 0.5)
	assert_bool(dialog.scrolls()).is_true()
	assert_float(text.size.y).is_greater(body.size.y)
	assert_bool(box.encloses(body)).is_true()


func test_the_buttons_sit_below_the_body_and_inside_the_box() -> void:
	for offer in [false, true]:
		for lines in [1, 9, 40]:
			var dialog := await _open(lines, offer)
			var box := _rect(dialog, "box")
			var body := _rect(dialog, "body")
			var buttons: Array[Button] = [dialog.continue_button()]
			if offer:
				buttons = [dialog.accept_button(), dialog.decline_button()]
			for button in buttons:
				var rect := button.get_global_rect()
				var where := (
					"offer=%s lines=%d %s %s body %s" % [offer, lines, button.name, rect, body]
				)
				print(where)
				assert_bool(button.is_visible_in_tree()).override_failure_message(where).is_true()
				assert_float(rect.position.y).override_failure_message(where).is_greater_equal(
					body.end.y
				)
				assert_bool(box.encloses(rect)).override_failure_message(where).is_true()
			dialog.free()


func test_the_tallest_box_and_its_nameplate_stay_on_the_screen() -> void:
	for screen_size in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		_port.size = screen_size
		var dialog := await _open(40)
		var screen := Rect2(Vector2.ZERO, Vector2(screen_size))
		for part in ["box", "nameplate", "body", "continue"]:
			var rect := _rect(dialog, part)
			var where := "%s %s on %s" % [part, rect, screen_size]
			print(where)
			assert_bool(screen.encloses(rect)).override_failure_message(where).is_true()
		var bottom := float(screen_size.y) - IntroDialogue.BOX_BOTTOM
		assert_float(_rect(dialog, "box").end.y).is_less_equal(bottom + 0.5)
		dialog.free()


## The project stretches at content scale 1.25, so a 1280x720 window is a
## 1024x576 viewport to the dialog (project.godot). The box is capped by the room
## above the build bar so the group scale stays at its floor and the nameplate
## stays on the screen.
func test_a_small_logical_viewport_caps_the_box_and_scrolls_the_body() -> void:
	_port.size = Vector2i(1024, 576)
	var dialog := await _open(40)
	var screen := Rect2(Vector2.ZERO, Vector2(1024.0, 576.0))
	var box := _rect(dialog, "box")
	var body := _rect(dialog, "body")
	for part in ["box", "nameplate", "body", "continue"]:
		var rect := _rect(dialog, part)
		var where := "%s %s on %s" % [part, rect, screen]
		print(where)
		assert_bool(screen.encloses(rect)).override_failure_message(where).is_true()
	assert_bool(dialog.scrolls()).is_true()
	assert_float(_rect(dialog, "text").size.y).is_greater(body.size.y)
	assert_float(_rect(dialog, "nameplate").position.y).is_greater_equal(0.0)
	assert_float(box.end.y).is_less_equal(576.0 - IntroDialogue.BOX_BOTTOM + 0.5)
	var button := dialog.continue_button().get_global_rect()
	assert_float(button.position.y).is_greater_equal(body.end.y)
	assert_bool(box.encloses(button)).is_true()
	dialog.free()


func test_wrapped_long_chips_and_inline_tip_reserve_height_above_footer_and_buttons() -> void:
	var chips := [
		{
			"label":
			"Reward: every extra passenger pays the usual fee when they check in at the terminal.",
			"tint": Color(0.22, 0.58, 0.34, 1.0),
			"tooltip": "Full reward details for wrapped chip one.",
		},
		{
			"label":
			"If it fails: queues grow and passengers who miss their flight lower your rating.",
			"tint": Color(0.76, 0.28, 0.24, 1.0),
			"tooltip": "Full failure details for wrapped chip two.",
		},
	]
	for screen_size in [Vector2i(1280, 720), Vector2i(1536, 864)]:
		_port.size = screen_size
		var dialog := (
			IntroDialogue
			. new(
				"Holiday rush tomorrow",
				"",
				340.0,
				false,
				IntroDialogue.Speaker.TERMINAL_MANAGER,
				{
					"beats": ["Tomorrow is a holiday."],
					"chips": chips,
					"footer": "The clock goes on when you close this.",
				}
			)
		)
		_port.add_child(dialog)
		await get_tree().process_frame
		await get_tree().process_frame
		var box: Rect2 = dialog.part_rects()["box"]
		var chips_rect := dialog.chips_row().get_global_rect()
		var footer_rect := (dialog.find_child("Footer", true, false) as Label).get_global_rect()
		var btn_rect := dialog.continue_button().get_global_rect()
		assert_bool(box.grow(0.5).encloses(chips_rect)).is_true()
		assert_bool(chips_rect.intersects(footer_rect)).is_false()
		assert_bool(chips_rect.intersects(btn_rect)).is_false()
		var first_chip := dialog.chips_row().get_child(0) as Button
		first_chip.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var tip_rect := dialog.chip_tip().get_global_rect()
		chips_rect = dialog.chips_row().get_global_rect()
		footer_rect = (dialog.find_child("Footer", true, false) as Label).get_global_rect()
		btn_rect = dialog.continue_button().get_global_rect()
		assert_bool(dialog.chip_tip().visible).is_true()
		var after_box: Rect2 = dialog.part_rects()["box"]
		assert_bool(after_box.grow(0.5).encloses(tip_rect)).is_true()
		assert_bool(tip_rect.intersects(chips_rect)).is_false()
		assert_bool(tip_rect.intersects(footer_rect)).is_false()
		assert_bool(tip_rect.intersects(btn_rect)).is_false()
		dialog.free()
