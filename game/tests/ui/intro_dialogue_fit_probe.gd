extends SceneTree
## Plates the Terminal Manager dialog (IntroDialogue) holding the three texts
## that overflowed its box in board T9: the VIP offer, the inspector's
## announcement and the unlock guide. With pseudolocalization at +40% each text
## is expanded once (the root's auto-translate is off, as in
## hud_pseudolocale_probe.gd --single); one more plate shows the longest of the
## three in English, and one more pseudolocale plate shows the unlock guide
## with both big firsts, which scrolls. Each dialog is built with the words,
## title and box height its real panel uses (IncidentPanel, UnlockGuide).
##
## Before a plate is saved it proves its subject: the box, the last body line
## and the buttons lie inside the window, the buttons' top is below the body's
## bottom, the last line lies inside the box and the visible body area, and no
## button covers it. A body that scrolls is scrolled to its end first. Any miss
## prints PROBE_INVALID and exits 1.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://tests/ui/intro_dialogue_fit_probe.gd

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/t9"
const WINDOW := Vector2i(1920, 1080)
const MARGIN := 4.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		_invalid("run windowed: the headless display draws nothing")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(WINDOW)
	root.content_scale_factor = 1.0
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var back := ColorRect.new()
	back.color = Color(0.17, 0.18, 0.2)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	await _frames(5)
	PseudoLocale.enable(0.4)
	for kind in ["vip_offer", "inspector_announce", "unlock_guide", "unlock_guide_two_firsts"]:
		await _plate("single_" + kind, _words(kind))
		if _failed:
			return
	PseudoLocale.disable()
	var longest := ""
	var longest_h := 0.0
	for kind in ["vip_offer", "inspector_announce", "unlock_guide"]:
		var height := await _text_height(_words(kind))
		print("PROBE english %s text_h=%.0f" % [kind, height])
		if height > longest_h:
			longest_h = height
			longest = kind
	await _plate("english_" + longest, _words(longest))
	if _failed:
		return
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## The title, body, box height and offer flag of one of the three dialogs, from
## the same sources its panel uses.
func _words(kind: String) -> Dictionary:
	match kind:
		"vip_offer":
			var plan := {"departs": 600 * 20, "bonus": 1500, "good_mood": 70, "miss_half_stars": 2}
			return _incident(IncidentCatalogue.VIP, plan, true)
		"inspector_announce":
			var plan := {
				"window_from": 540 * 20,
				"window_to": 720 * 20,
				"pass_money": 2000,
				"max_messes": 3,
				"max_full_queue": 2,
				"fail_half_stars": 1,
			}
			return _incident(IncidentCatalogue.INSPECTOR, plan, false)
	# A tier with both big firsts is the longest unlock text; at +40% it scrolls.
	var firsts := [BigFirsts.RUNWAY]
	if kind == "unlock_guide_two_firsts":
		firsts = BigFirsts.KINDS
	var body := "\n".join(UnlockFamilies.lines([2])) + "\n" + BigFirsts.body_for(firsts)
	return {
		"title": TranslationServer.translate("Your airport has grown"),
		"body": body,
		"height": UnlockGuide.BOX_HEIGHT,
		"offer": false,
	}


func _incident(kind: String, plan: Dictionary, offer: bool) -> Dictionary:
	var incident := {"id": 1, "kind": kind, "plan": plan, "fire_tick": 0}
	var copy := IncidentCopy.fill(IncidentCatalogue.panel_copy(kind), incident, 0, 0)
	return {
		"title": copy["title"],
		"body": IncidentPanel.body_for(copy, offer),
		"height": IncidentPanel.BOX_HEIGHT,
		"offer": offer,
	}


func _open(words: Dictionary) -> IntroDialogue:
	var dialog := IntroDialogue.new(words["title"], words["body"], words["height"], words["offer"])
	root.add_child(dialog)
	await _frames(6)
	return dialog


func _text_height(words: Dictionary) -> float:
	var dialog := await _open(words)
	var height: float = (dialog.part_rects()["text"] as Rect2).size.y
	dialog.free()
	return height


func _plate(plate: String, words: Dictionary) -> void:
	var dialog := await _open(words)
	var scroll := dialog.find_child("BodyScroll", true, false) as ScrollContainer
	var scrolls := dialog.scrolls()
	if scrolls:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _frames(3)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var rects := dialog.part_rects()
	var box: Rect2 = rects["box"]
	var body: Rect2 = rects["body"]
	var text: Rect2 = rects["text"]
	var label := dialog.find_child("Body", true, false) as Label
	var line_h := float(label.get_line_height())
	var last := Rect2(text.position.x, text.end.y - line_h, text.size.x, line_h)
	var buttons: Array[Button] = [dialog.continue_button()]
	if words["offer"]:
		buttons = [dialog.accept_button(), dialog.decline_button()]
	print(
		(
			"PROBE %s box=%s body=%s text=%s last_line=%s lines=%d scrolls=%s"
			% [plate, box, body, text, last, label.get_line_count(), scrolls]
		)
	)
	print("PROBE %s first='%s'" % [plate, dialog.body_text().left(48)])
	_expect(view.encloses(box), "%s: the box is outside the window" % plate)
	_expect(view.encloses(last), "%s: the last body line is outside the window" % plate)
	_expect(box.encloses(last), "%s: the last body line is outside the box" % plate)
	_expect(body.grow(0.5).encloses(last), "%s: the last line is outside the body area" % plate)
	for button in buttons:
		var rect := button.get_global_rect()
		print("PROBE %s button %s=%s" % [plate, button.name, rect])
		_expect(button.is_visible_in_tree(), "%s: %s is hidden" % [plate, button.name])
		_expect(view.encloses(rect), "%s: %s is outside the window" % [plate, button.name])
		_expect(box.encloses(rect), "%s: %s is outside the box" % [plate, button.name])
		_expect(
			rect.position.y >= body.end.y, "%s: %s is above the body bottom" % [plate, button.name]
		)
		_expect(not rect.intersects(last), "%s: %s covers the last line" % [plate, button.name])
	if plate.begins_with("single_"):
		_expect(dialog.body_text().begins_with("["), "%s: the body is not translated" % plate)
	if _failed:
		_invalid("%s did not prove its subject" % plate)
		return
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join(plate + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "plate %s was not saved" % plate)
	dialog.free()
	await _frames(2)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE FAIL ", why)


func _invalid(why: String) -> void:
	print("PROBE_INVALID ", why)
	quit(1)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
