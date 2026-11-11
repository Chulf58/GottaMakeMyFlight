extends SceneTree
## Windowed plates of the unlock guidance (board c91fac99): the new-tier dialog,
## and the tray with "New" tints and a hovered locked card. The probe opens tier 2
## by play (rating and made flights), with the guide switched on. Nothing is
## saved: what the guide shows and sees lives in the game, not in a profile file.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/unlock_guidance_plate_probe.gd
##
## Plates go to tools/blender/out/unlock-guidance/ in the main checkout.

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/unlock-guidance"
## Frames the tooltip may take to appear (its delay is wall-clock time).
const TOOLTIP_FRAMES := 240
const MARGIN := 8.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	var hud := main.find_children("*", "PassengerHud", true, false)[0] as PassengerHud
	hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	root.content_scale_factor = 1.0
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	var menu := main.find_children("*", "BuildMenu", true, false)[0] as BuildMenu
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	var guide := hud.unlock_guide()
	for i in 60:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 50:
		unlocks.note_made()
	unlocks.check()
	await _frames(8)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	print(
		"PROBE tier=%d dialog_open=%s paused=%s" % [unlocks.tier(), guide.is_open(), clock.paused]
	)
	if unlocks.tier() != 2 or not guide.is_open() or not clock.paused:
		_invalid("tier 2 did not open the dialog and pause the clock")
		return
	var box: Rect2 = guide.dialog().part_rects()["box"]
	print(
		(
			"PROBE box=%s view=%s body=%s"
			% [box, view, guide.dialog().body_text().replace("\n", " / ")]
		)
	)
	if not view.encloses(box):
		_invalid("the dialog box is out of view")
		return
	var status := menu.status_label()
	print("PROBE status_text='%s' visible=%s" % [status.text, menu.status_card().visible])
	if status.text.begins_with("Unlocked:"):
		_invalid("the Unlocked line holds the status while the dialog is open")
		return
	_save("unlock_dialog.png")
	guide.dismiss()
	await _frames(5)
	print("PROBE after dismiss dialog_open=%s paused=%s" % [guide.is_open(), clock.paused])
	await _tray_stage(menu, guide, view)


## The tray with the New tints and the hovered locked card.
func _tray_stage(menu: BuildMenu, guide: UnlockGuide, view: Rect2) -> void:
	var pair := _tray_with_new_and_locked(menu, guide)
	if pair.is_empty():
		_invalid("no tray holds both a New card and a locked card")
		return
	menu.press_category(pair["category"])
	await _frames(8)
	var locked_card := menu.card(pair["locked"])
	var new_card := menu.card(pair["new"])
	var centre := locked_card.get_global_rect().get_center()
	var new_rect := new_card.get_global_rect()
	print(
		(
			"PROBE category=%d new=%s at %s locked=%s at %s"
			% [pair["category"], pair["new"], new_rect, pair["locked"], centre]
		)
	)
	if not view.grow(-MARGIN).encloses(new_rect) or not view.grow(-MARGIN).has_point(centre):
		_invalid("a card is out of view")
		return
	var new_tinted := new_card.modulate.is_equal_approx(BuildMenu.NEW_TINT)
	print("PROBE new card modulate=%s tinted=%s" % [new_card.modulate, new_tinted])
	if not new_tinted:
		_invalid("the New card is not tinted")
		return
	var move := InputEventMouseMotion.new()
	move.position = centre
	move.global_position = centre
	root.push_input(move, true)
	var shown: Array = []
	for i in TOOLTIP_FRAMES:
		await process_frame
		shown = root.find_children("ItemInfoCard", "VBoxContainer", true, false)
		if not shown.is_empty():
			break
	if shown.is_empty():
		_invalid("the hover card never appeared")
		return
	await _frames(4)
	var requirement := shown[0].find_child("Requirement", true, false) as Label
	print("PROBE hover requirement=%s" % [requirement.text if requirement != null else "none"])
	if requirement == null or not requirement.text.begins_with("Unlocks at"):
		_invalid("the hover card has no requirement line")
		return
	_save("unlock_tray_new_and_locked_hover.png")
	_finish(0)


## A category that holds a card of the newest tier and a locked one.
func _tray_with_new_and_locked(menu: BuildMenu, guide: UnlockGuide) -> Dictionary:
	var categories := BuildMenu.categories()
	for i in categories.size():
		var fresh := BuildMode.Tool.NONE
		var locked := BuildMode.Tool.NONE
		for tool: BuildMode.Tool in categories[i]["tools"]:
			if menu.card(tool) == null:
				continue
			if guide.is_new(tool) and fresh == BuildMode.Tool.NONE:
				fresh = tool
			elif BuildUnlocks.tier_of(tool) > 2 and locked == BuildMode.Tool.NONE:
				locked = tool
		if fresh != BuildMode.Tool.NONE and locked != BuildMode.Tool.NONE:
			return {"category": i, "new": fresh, "locked": locked}
	return {}


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	var path := OUT_DIR.path_join(file)
	print("PLATE saved ", path, " err=", img.save_png(path))


func _invalid(reason: String) -> void:
	print("PROBE_INVALID ", reason)
	_finish(1)


func _finish(code: int) -> void:
	quit(code)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
