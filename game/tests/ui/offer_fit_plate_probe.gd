extends SceneTree
## Windowed plate of the Offers sheet with each card's fit line (decision
## airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more, point 6). The
## real main.tscn boots; the airport opens on one gate, C, with a 10:00
## contract, and the day's offers are set to 10:00, 12:00 and 20:00, so the
## three cards read "No gate free, and the taxi lane is busy then", "No gate
## free at this time: build another gate" and "Fits a free gate at this time".
## Prints each card's text and checks the sheet is in view before saving.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/offer_fit_plate_probe.gd
##
## The plate goes to tools/blender/out/offers-fit/offer_fit_cards.png.

const OUT_REL := "res://../tools/blender/out/offers-fit"


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
	var flights := main.get_node("FlightSim") as FlightSim
	var desk := main.get_node("OfferDesk") as OfferDesk
	var panels := main.find_children("*", "OfferPanel", true, false)
	if panels.is_empty():
		print("PROBE_INVALID no OfferPanel in main.tscn")
		quit(1)
		return
	flights.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	flights.stand_source = Callable()
	if flights.opened_tick < 0:
		flights.open_airport()
	var taken := TestFlightFit.terms("K10", 600)
	print("PROBE contract K10 at 10:00 accepted=", flights.accept_contract(taken))
	var offers := TestOfferBoard.day_records(GameCalendar.day_of(clock.tick), [600, 720, 1200])
	print("PROBE board loaded=", desk.board.from_snapshot(TestOfferBoard.save_of(offers)))
	var panel := panels[0] as OfferPanel
	panel.open()
	await _frames(8)
	var shown := 0
	for id in panel.card_ids():
		print("CARD ", id, " | ", panel.card_text(id).replace("\n", " / "))
		shown += 1
	var sheet := panel.sheet().get_global_rect()
	var inside := Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(sheet)
	print("PROBE cards=%d sheet=%s inside_view=%s" % [shown, sheet, inside])
	if shown != 3 or not inside or not panel.sheet().visible:
		print("PROBE_INVALID the sheet does not show three cards in view")
		quit(1)
		return
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("offer_fit_cards.png")
	print("PLATE saved ", path, " err=", img.save_png(path))
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
