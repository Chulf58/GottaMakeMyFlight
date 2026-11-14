extends SceneTree
## Windowed plate of the Offers sheet with each card's verdict and daily earnings
## (decision airline-offers-stay-accept-many-the-three-offer-cards-read-a), at UI
## scale 1.25 and 1.5. The real main.tscn boots; the airport opens on one gate,
## C, with a 10:00 contract, and the day's offers are set to one departure the
## gate cannot take (found with FlightFit) and two it can, each with its own
## passengers and fee, so the cards read "Needs another gate" and two "Fits your
## gates now". Two offers are paired with traits and one is plain (decision
## airline-offer-traits-each-offer-pairs-an-upside-with-a-downs), so each card's
## trait line shows. The cards carry the slice 2 money traits: the longest line
## (Signing bonus $300, Very heavy bags and a loyal airline's "Loyal: +10%"),
## Loyal airline with Miss fine, and a plain offer from a loyal airline. Prints
## each card's text and checks the trait lines and that the sheet is in view
## before saving.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://tests/ui/offer_cards_plate_probe.gd
##
## The plates go to tools/blender/out/offer_traits2_20261114/.

const OUT_REL := "res://../tools/blender/out/offer_traits2_20261114"
## Per card: booked, fee, traits and the loyal mark (each fee one the tier-0
## draw gives with those traits: 35 -> 39 loyal, 25 stays, 25 -> 23 plain -> 25).
const TERMS := [
	[16, 39, {"up": "signing_bonus", "down": "heavy_bags", "level": 2}, true],
	[14, 25, {"up": "loyal_airline", "down": "miss_fine", "level": 1}, false],
	[15, 25, {}, true],
]
## The game day the plate is taken on: Gotta Air became loyal on day 5.
const PLATE_DAY := 6
const TRAIT_LINES := [
	"Signing bonus $300   Very heavy bags   Loyal: +10%",
	"Loyal airline   Miss fine $10",
	"Plain terms   Loyal: +10%",
]


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
	# Day PLATE_DAY at 06:00, so Gotta Air's five Loyal days (up to the day
	# before) can have made its offers loyal (OfferBoard refuses a loyal mark its
	# count cannot explain).
	clock.tick = GameCalendar.day_start(PLATE_DAY) + 6 * 60 * GameCalendar.TICKS_PER_MINUTE
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
	for i in offers.size():
		offers[i]["booked_passengers"] = TERMS[i][0]
		offers[i]["fee_per_passenger"] = TERMS[i][1]
		offers[i]["traits"] = TERMS[i][2]
		offers[i]["loyal"] = TERMS[i][3]
		# Only Gotta Air has a Loyal count, so an offer without the mark is Sunhop's.
		offers[i]["airline"] = "Gotta Air" if TERMS[i][3] else "Sunhop"
	var board_save := TestOfferBoard.save_of(offers)
	board_save["loyalty"] = {"Gotta Air": {"days": OfferTraits.LOYAL_DAYS, "last_day": day - 1}}
	# Checked with the sheet below, before any plate is saved.
	var loaded := desk.board.from_snapshot(board_save) and day == PLATE_DAY
	print("PROBE day=%d board loaded=%s" % [day, loaded])
	var panel := panels[0] as OfferPanel
	panel.open()
	var expected := {
		"O%dN1" % PLATE_DAY: OfferPanel.NEEDS_GATE_TEXT,
		"O%dN2" % PLATE_DAY: OfferPanel.FITS_TEXT,
		"O%dN3" % PLATE_DAY: OfferPanel.FITS_TEXT,
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
			var line := _trait_line(panel.trait_row(id))
			print("PROBE %s trait line '%s' expected '%s'" % [id, line, TRAIT_LINES[shown]])
			if line != TRAIT_LINES[shown]:
				print("PROBE_INVALID card %s shows the wrong trait line" % id)
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
		if shown != 3 or not inside or not panel.sheet().visible or not loaded:
			print("PROBE_INVALID the sheet does not show three loaded cards in view")
			quit(1)
			return
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("offer_traits2_s%d.png" % int(ui_scale * 100.0))
		var saved := img.save_png(path)
		print("PLATE saved ", path, " size=", img.get_size(), " err=", saved)
		if saved != OK:
			print("PROBE_INVALID the plate could not be written")
			quit(1)
			return
	quit(0)


## The visible labels of a trait row, three spaces apart.
static func _trait_line(row: HBoxContainer) -> String:
	var parts := PackedStringArray()
	for label: Label in row.get_children():
		if label.visible:
			parts.append(label.text)
	return "   ".join(parts)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
