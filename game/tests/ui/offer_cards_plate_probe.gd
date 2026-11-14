extends SceneTree
## Windowed plate of the Offers sheet with each card's verdict and daily earnings
## (decision airline-offers-stay-accept-many-the-three-offer-cards-read-a), at UI
## scale 1.25 and 1.5. The real main.tscn boots; the airport opens on one gate,
## C, with a 10:00 contract, and the day's offers are set to one departure the
## gate cannot take (found with FlightFit) and two it can, each with its own
## passengers and fee, so the cards read "Needs another gate" and two "Fits your
## gates now". Prints each card's text and checks the sheet is in view before
## saving.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/offer_cards_plate_probe.gd
##
## The plates go to tools/blender/out/offer_cards_20261114/.

const OUT_REL := "res://../tools/blender/out/offer_cards_20261114"


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
	var day := GameCalendar.day_of(clock.tick)
	var needs_gate := -1
	var fits: Array[int] = []
	for minute in range(0, 1440, 30):
		var probe := TestOfferBoard.record("P", day, minute)
		var verdict := OfferPanel.fit_line(
			FlightFit.assess(flights, OfferBoard.terms_of(probe)), probe["plane_size"]
		)
		if verdict == OfferPanel.NEEDS_GATE_TEXT and needs_gate < 0:
			needs_gate = minute
		elif verdict == OfferPanel.FITS_TEXT and fits.size() < 2 and minute > 12 * 60:
			fits.append(minute)
	if needs_gate < 0 or fits.size() < 2:
		print(
			"PROBE_INVALID no needs-gate minute (%d) or fewer than 2 fits (%s)" % [needs_gate, fits]
		)
		quit(1)
		return
	var offers := TestOfferBoard.day_records(day, [needs_gate, fits[0], fits[1]])
	var terms := [[16, 32], [12, 25], [15, 32]]
	for i in offers.size():
		offers[i]["booked_passengers"] = terms[i][0]
		offers[i]["fee_per_passenger"] = terms[i][1]
	print("PROBE board loaded=", desk.board.from_snapshot(TestOfferBoard.save_of(offers)))
	var panel := panels[0] as OfferPanel
	panel.open()
	var expected := {
		"O0N1": OfferPanel.NEEDS_GATE_TEXT,
		"O0N2": OfferPanel.FITS_TEXT,
		"O0N3": OfferPanel.FITS_TEXT,
	}
	for ui_scale: float in [1.25, 1.5]:
		root.content_scale_factor = ui_scale
		await _frames(8)
		var shown := 0
		for id in panel.card_ids():
			print("CARD ", id, " | ", panel.card_text(id).replace("\n", " / "))
			if panel.fit_text(id) != expected.get(id, ""):
				print("PROBE_INVALID card %s says '%s'" % [id, panel.fit_text(id)])
				quit(1)
				return
			shown += 1
		var sheet := panel.sheet().get_global_rect()
		var view := root.get_visible_rect()
		var inside := view.grow(-4.0).encloses(sheet)
		print(
			(
				"PROBE scale=%.2f cards=%d sheet=%s view=%s inside=%s"
				% [ui_scale, shown, sheet, view, inside]
			)
		)
		if shown != 3 or not inside or not panel.sheet().visible:
			print("PROBE_INVALID the sheet does not show three cards in view")
			quit(1)
			return
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("offer_cards_s%d.png" % int(ui_scale * 100.0))
		var saved := img.save_png(path)
		print("PLATE saved ", path, " size=", img.get_size(), " err=", saved)
		if saved != OK:
			print("PROBE_INVALID the plate could not be written")
			quit(1)
			return
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
