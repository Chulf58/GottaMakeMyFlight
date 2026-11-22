extends SceneTree
## Plates the staff hint card (the opening checklist) above a tall inspect card
## with pseudolocalization on (expansion 0.4, one expansion: auto-translate off on
## root), board T10. The inspect card is the real PassengerInspect, shown with no
## passenger and grown to INSPECT_H, because the HUD would hide it with nobody
## followed (its processing is held off for the plate). Proves before saving that
## both cards lie inside the window and the hint card ends a GAP above the inspect
## card, otherwise PROBE_INVALID and exit 1.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://spike/inspect_hint_plate_probe.gd -- --out=<dir>

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/t10"
const WINDOW := Vector2i(1920, 1080)
const INSPECT_H := 520.0
const MARGIN := 4.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	var out_dir := _arg("--out=", OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(WINDOW)
	root.content_scale_factor = 1.0
	await _frames(5)
	PseudoLocale.enable(0.4)
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	var hud := main.find_children("*", "PassengerHud", true, false)[0] as PassengerHud
	hud.alert_settings_path = "user://inspect_hint_probe_alerts.cfg"
	hud.departures_settings_path = "user://inspect_hint_probe_departures.cfg"
	root.add_child(main)
	clock.set_paused(true)
	await _frames(8)
	hud.dismiss_intro()
	await _frames(5)
	var inspect := main.find_child("PassengerInspect", true, false) as PassengerInspect
	var hint := main.find_child("StaffHintCard", true, false) as Control
	hud.set_process(false)
	inspect.visible = true
	inspect.custom_minimum_size.y = INSPECT_H
	await _frames(10)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var card := hint.get_global_rect()
	var floor_rect := inspect.get_global_rect()
	var first := (hint.find_children("*", "Label", true, false)[0] as Label).text
	print("PLATE hint=%s inspect=%s first='%s'" % [card, floor_rect, first])
	_expect(hint.is_visible_in_tree(), "the hint card is not shown")
	_expect(view.encloses(card), "the hint card is outside the window")
	_expect(view.encloses(floor_rect), "the inspect card is outside the window")
	_expect(first.begins_with("["), "the hint card text is not bracketed: '%s'" % first)
	_expect(
		card.end.y <= floor_rect.position.y - HudLayout.GAP + 0.5,
		(
			"the hint card ends at %.0f, under the inspect card top %.0f"
			% [card.end.y, floor_rect.position.y]
		)
	)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("inspect_hint.png")
	var crop := Rect2i(0, 200, 900, 880)
	var err := root.get_texture().get_image().get_region(crop).save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "the plate was not saved")
	PseudoLocale.disable()
	for file in [
		"user://inspect_hint_probe_alerts.cfg", "user://inspect_hint_probe_departures.cfg"
	]:
		DirAccess.remove_absolute(file)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## The value of the user argument that starts with `prefix`, or `fallback`.
func _arg(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
