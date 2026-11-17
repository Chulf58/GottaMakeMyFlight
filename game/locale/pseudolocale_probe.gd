extends SceneTree
## Probe for the translation foundation. Run it headless to print the loaded
## locales and the translated and pseudolocalized example strings; run it
## windowed to plate the migrated RatingBadge on the real main.tscn with
## pseudolocalization on (PseudoLocale, expansion 0.4):
##   a_nodata   the badge label "No flights yet" shows its brackets and padding
##   b_tooltip  the real pointer rests on the badge with data fed in, so the
##              tooltip shows the tr() and tr_n() lines
## Before each save it proves the subject: the badge card lies inside the window,
## the label starts with "[", and for the tooltip plate the hovered control is
## the card. Otherwise it prints PROBE_INVALID and exits 1. A guard thread
## prints PROBE_INVALID and calls OS.crash() past LIMIT_MS.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe [--headless | --display-driver windows \
##     --rendering-driver vulkan] --audio-driver Dummy --path <worktree>/game \
##     -s res://locale/pseudolocale_probe.gd

const OUT_REL := "res://../tools/blender/out/locale"
const LIMIT_MS := 120000
const WINDOW := Vector2i(1920, 1080)
const TOOLTIP_FRAMES := 90
const CROP := Rect2i(0, 0, 720, 190)
const PLURAL_ONE := "Made it: {share}% ({made} of {count} passenger)"
const PLURAL_MANY := "Made it: {share}% ({made} of {count} passengers)"

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _guard := Thread.new()
var _lock := Mutex.new()
var _stop := false
var _main: Node3D
var _rating: AirportRating
var _badge: RatingBadge


func _initialize() -> void:
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
			OS.crash("pseudolocale_probe: no finish within %d ms" % LIMIT_MS)


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	_print_translation_state()
	PseudoLocale.enable()
	print("PROBE pseudo on ratio=%s" % PseudoLocale.EXPANSION)
	print("  PSEUDO tr('No flights yet') -> '%s'" % tr("No flights yet"))
	print("  PSEUDO tr_n(1) -> '%s'" % tr_n(PLURAL_ONE, PLURAL_MANY, 1))
	print("  PSEUDO tr_n(7) -> '%s'" % tr_n(PLURAL_ONE, PLURAL_MANY, 7))
	if DisplayServer.get_name() != "headless":
		await _plates(world_seed)
	PseudoLocale.disable()
	print("PROBE pseudo off tr('No flights yet') -> '%s'" % tr("No flights yet"))
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


func _print_translation_state() -> void:
	print(
		(
			"PROBE loaded_locales=%s fallback=%s"
			% [
				TranslationServer.get_loaded_locales(),
				ProjectSettings.get_setting("internationalization/locale/fallback")
			]
		)
	)
	print("PROBE locale=%s" % TranslationServer.get_locale())
	print("  TR tr('No flights yet') -> '%s'" % tr("No flights yet"))
	print("  TR tr('Mood: {mood} of {max}') -> '%s'" % tr("Mood: {mood} of {max}"))


func _plates(world_seed: int) -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	DisplayServer.window_set_size(WINDOW)
	await _frames(5)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(world_seed)
	root.add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_rating = _main.get_node("AirportRating") as AirportRating
	_badge = _main.get_node("RatingBadge") as RatingBadge
	await _frames(8)
	var label := _badge.card().find_child("RatingText", true, false) as Label
	print("  PLATE a_nodata label='%s' card=%s" % [label.text, _badge.card().get_global_rect()])
	_expect(label.text.begins_with("["), "the badge label is not bracketed: '%s'" % label.text)
	_expect(
		root.get_visible_rect().grow(-2.0).encloses(_badge.card().get_global_rect()),
		"card outside window"
	)
	await _save("a_nodata")
	for i in 30:
		_rating.record_passenger(0, true, 40)
	for i in 10:
		_rating.record_passenger(0, false, 0)
	await _frames(4)
	var card := _badge.card()
	var centre := card.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	root.warp_mouse(centre)
	root.push_input(motion, true)
	await _frames(TOOLTIP_FRAMES)
	var hit := root.gui_get_hovered_control()
	print("  HIT card at %s -> %s reached=%s" % [centre, hit, hit == card])
	_expect(hit == card, "the pointer is over %s, not the badge" % hit)
	print("  TOOLTIP '%s'" % card.tooltip_text.replace("\n", " | "))
	await _save("b_tooltip")
	_main.queue_free()
	await _frames(3)


func _save(plate: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var crop := image.get_region(
		Rect2i(
			Vector2i.ZERO,
			Vector2i(
				int(CROP.size.x * root.content_scale_factor),
				int(CROP.size.y * root.content_scale_factor)
			)
		)
	)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	var path := _out_dir.path_join(plate + "_corner.png")
	var err := crop.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "the plate %s was not saved" % plate)
	image.save_png(_out_dir.path_join(plate + ".png"))


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
