extends SceneTree
## Windowed plate of the Offers sheet at UI scale 1.0 with the airport closed,
## so the departure line shows the first-flight lead note (board 73e15dd7 part 4)
## and its wrapping can be judged. Prints each card's text.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/offer_card_plate_probe.gd
##
## The plate goes to tools/blender/out/offer_card/offer_card_closed.png.

const OUT_REL := "res://../tools/blender/out/offer_card"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	root.content_scale_factor = 1.0
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	var panels := main.find_children("*", "OfferPanel", true, false)
	if panels.is_empty():
		print("PROBE_INVALID no OfferPanel in main.tscn")
		quit(1)
		return
	var panel := panels[0] as OfferPanel
	panel.open()
	await _frames(8)
	print(
		"PROBE ui_scale=%s viewport=%s" % [root.content_scale_factor, root.get_visible_rect().size]
	)
	var shown := 0
	for id in panel.card_ids():
		print("CARD ", id, " | ", panel.card_text(id).replace("\n", " / "))
		shown += 1
	var sheet := panel.sheet().get_global_rect()
	var inside := Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(sheet)
	print("PROBE cards=%d sheet=%s inside_view=%s" % [shown, sheet, inside])
	if shown == 0 or not inside or not panel.sheet().visible:
		print("PROBE_INVALID the sheet is empty, hidden or out of view")
		quit(1)
		return
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("offer_card_closed.png")
	print("PLATE saved ", path, " err=", img.save_png(path))
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
