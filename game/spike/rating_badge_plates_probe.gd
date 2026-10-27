extends SceneTree
## Windowed plate probe for Rating 2a on the real main.tscn, at 1920x1080 with
## the UI scale at 1.0 and at 1.25 (Window.content_scale_factor):
##   a_nodata   a new game: empty stars and "No flights yet" beside the money
##   b_mixed    30 made at mood 40 and 10 missed: 3.5 stars, half star drawn
##   c_low      1 made and 9 missed more: a low rating, one star and a half
##   d_full     only good days: 5 filled stars
##   e_tooltip  the real mouse rests on the badge in the 3.5 state until the
##              tooltip shows (made share, mood, days counted)
## Each state saves the whole window and a 2x crop of the top-left corner.
## Before each save it proves the subjects: the label text equals what the
## rating says, the badge rect lies inside the window and overlaps no other HUD
## piece, and the badge sits right of the money slot on the same top edge. For
## the tooltip plate the hovered control must be the badge card. Otherwise it
## prints PROBE_INVALID and exits 1. A guard thread prints PROBE_INVALID and
## calls OS.crash() past LIMIT_MS.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/.claude/worktrees/<lane>/game \
##     -s res://spike/rating_badge_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/rating_badge"
const LIMIT_MS := 180000
const WINDOW := Vector2i(1920, 1080)
const SCALES := [1.0, 1.25]
## The tooltip needs the pointer to rest this many frames (about 1.5 s at 60 fps).
const TOOLTIP_FRAMES := 90
const CROP := Rect2i(0, 0, 720, 110)

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _scale := 1.0
var _main: Node3D
var _menu: BuildMenu
var _hud: PassengerHud
var _rating: AirportRating
var _badge: RatingBadge


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		_lock.unlock()
		if stop:
			return
		if Time.get_ticks_msec() - _start_ms > LIMIT_MS:
			print("PROBE_INVALID: the probe ran past %d ms" % LIMIT_MS)
			OS.crash("rating_badge_plates_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	if root.size != WINDOW:
		_invalid("the window is %s, not %s" % [root.size, WINDOW])
	for scale: float in SCALES:
		_scale = scale
		root.content_scale_factor = scale
		await _frames(5)
		print(
			"PROBE scale=%s window=%s layout=%s" % [scale, root.size, root.get_visible_rect().size]
		)
		await _boot(world_seed)
		await _state("a_nodata", "No flights yet", 0.0)
		_feed(30, 40, 10)
		await _state("b_mixed", "3.5", 3.5)
		_reset()
		_feed(1, 10, 9)
		await _state("c_low", "", -1.0)
		_expect(_rating.stars() <= RatingFormula.WARN_BELOW, "c: the rating is not low")
		_reset()
		_feed(10, 100, 0)
		await _state("d_full", "5.0", 5.0)
		_reset()
		_feed(30, 40, 10)
		await _tooltip_state()
		_main.queue_free()
		await _frames(3)
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _boot(world_seed: int) -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	root.add_child(_main)
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_hud = _main.get_node("PassengerHud") as PassengerHud
	_rating = _main.get_node("AirportRating") as AirportRating
	_badge = _main.get_node("RatingBadge") as RatingBadge
	await _frames(8)


## Clears the rating back to a new game.
func _reset() -> void:
	var no_pending: Array[Dictionary] = []
	_rating.from_snapshot(RatingSnapshot.save(0, {}, 0, no_pending))


## Records `made` passengers at `mood`, then `missed` more who missed, on tick 0.
func _feed(made: int, mood: int, missed: int) -> void:
	for i in made:
		_rating.record_passenger(0, true, mood)
	for i in missed:
		_rating.record_passenger(0, false, 0)


## Checks the badge, then saves the window and the corner crop. `want_text` ""
## and `want_stars` below 0 skip the text and star comparison with a fixed value;
## the label must always equal what the rating says.
func _state(label: String, want_text: String, want_stars: float) -> void:
	await _frames(4)
	var name := "%s_%s" % [label, str(_scale).replace(".", "p")]
	print("PLATE %s scale=%s" % [name, _scale])
	var text := (_badge.card().find_child("RatingText", true, false) as Label).text
	print("  TEXT badge='%s' stars=%.1f has_data=%s" % [text, _rating.stars(), _rating.has_data()])
	_expect(text == _badge.summary_text(), "%s: label '%s' is not the summary" % [name, text])
	if want_text != "":
		_expect(text == want_text, "%s: label '%s', wanted '%s'" % [name, text, want_text])
	if want_stars >= 0.0:
		_expect(
			is_equal_approx(_badge.shown_stars(), want_stars),
			"%s: %.1f stars shown, wanted %.1f" % [name, _badge.shown_stars(), want_stars]
		)
	_check_layout(name)
	await _save(name)


func _tooltip_state() -> void:
	await _frames(4)
	var name := "e_tooltip_%s" % str(_scale).replace(".", "p")
	print("PLATE %s scale=%s" % [name, _scale])
	var card := _badge.card()
	var centre := card.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	root.push_input(motion, true)
	await _frames(TOOLTIP_FRAMES)
	var hit := root.gui_get_hovered_control()
	print("  HIT card at %s -> %s reached=%s" % [centre, hit, hit == card])
	_expect(hit == card, "%s: the pointer is over %s, not the badge" % [name, hit])
	print("  TOOLTIP '%s'" % card.tooltip_text.replace("\n", " | "))
	_expect(card.tooltip_text.contains("Made it: 75%"), "%s: tooltip lacks the made share" % name)
	_check_layout(name)
	await _save(name)
	root.warp_mouse(Vector2(root.get_visible_rect().size.x / 2.0, root.get_visible_rect().size.y))
	await _frames(3)


## The badge lies inside the window, right of the money slot on its top edge,
## and overlaps no other HUD piece.
func _check_layout(name: String) -> void:
	var view := root.get_visible_rect()
	var rects := {
		"rating": _badge.card().get_global_rect(),
		"money": (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect(),
		"flight": (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect(),
		"bar": _menu.bar().get_global_rect(),
		"debug": (_hud.find_child("DebugCorner", true, false) as Control).get_global_rect(),
	}
	var offers := _main.get_node("OfferPanel") as OfferPanel
	rects["offers_button"] = offers.toggle_button().get_global_rect()
	for key in rects:
		var rect: Rect2 = rects[key]
		var inside := view.grow(-2.0).encloses(rect)
		print("  RECT %s %s inside=%s" % [key, rect, inside])
		_expect(inside, "%s: %s is outside the window" % [name, key])
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				_invalid("%s: %s overlaps %s" % [name, keys[i], keys[j]])
	var rating_rect: Rect2 = rects["rating"]
	var money_rect: Rect2 = rects["money"]
	_expect(
		rating_rect.position.x >= money_rect.end.x, "%s: the badge is not right of money" % name
	)
	_expect(
		absf(rating_rect.position.y - money_rect.position.y) < 1.0,
		"%s: the badge top is not the money top" % name
	)


## Saves the window and a 2x crop of the top-left corner.
func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join(name + ".png")
	var err := image.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate was not saved (error %d)" % [name, err])
	var scale_px := root.content_scale_factor
	var crop := image.get_region(
		Rect2i(Vector2i.ZERO, Vector2i(int(CROP.size.x * scale_px), int(CROP.size.y * scale_px)))
	)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	var crop_path := _out_dir.path_join(name + "_corner.png")
	err = crop.save_png(crop_path)
	print("PLATE saved %s err=%d" % [crop_path, err])
	if err != OK:
		_invalid("%s: the corner crop was not saved (error %d)" % [name, err])


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_invalid(why)


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
