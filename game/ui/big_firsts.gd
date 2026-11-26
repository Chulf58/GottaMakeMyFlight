class_name BigFirsts
extends RefCounted
## The big moments that get the phone ring and the short dialog the first time
## they happen in a game, besides a new unlock tier (decisions phone-ring-and-
## help-dialog-also-on-big-firsts-first-runway-u and opening-phone-call-right-
## after-the-airport-opens-the-airline): the airline's opening call when the
## airport first opens, the first runway upgrade, and the first major incident.
## UnlockGuide shows them and BuildUnlocks keeps which have shown, in the save.

const OPENING := "opening"
const RUNWAY := "runway"
const INCIDENT := "incident"
## Every kind, in the order a dialog lists them.
const KINDS: Array[String] = [OPENING, RUNWAY, INCIDENT]
const CERTIFICATION_TOAST_SECONDS := 8.0
const CERTIFICATION_TOAST_W := 420.0
const ICON_GATES := preload("res://assets/ui/icons/gates.svg")
const ICON_COIN := preload("res://assets/ui/icons/coin.svg")
const ICON_SERVICES := preload("res://assets/ui/icons/services.svg")

## The words are built in static functions, which cannot call tr() (an Object
## method), so they go through this instance's tr().
static var _translator := RefCounted.new()


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


## The Terminal Manager's dialog title for airport-side firsts.
static func title_text() -> String:
	return _translator.tr("Big news at the airport")


## Gotta Air's nameplate subtitle for the opening call.
static func opening_title_text() -> String:
	return _translator.tr("Station manager")


## The punchy beats for the big first `kind`; `departure_time` fills OPENING's
## flight time (for example "08:13"). Each beat stays <= 18 words.
static func _beats_for_kind(kind: String, departure_time := "") -> Array[String]:
	match kind:
		OPENING:
			var beat1: String
			if departure_time != "":
				beat1 = (
					_translator
					. tr(
						# gdlint:ignore = max-line-length
						"Gotta Air here! Your airport is open, and our Oslo flight leaves at {departure_time}."
					)
					. format({"departure_time": departure_time})
				)
			else:
				beat1 = (
					_translator
					. tr(
						# gdlint:ignore = max-line-length
						"Gotta Air here! Your airport is open and passengers are heading in now."
					)
				)
			var beat2 := (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"Keep bags light for this small plane. Good luck, gotta make that flight!"
				)
			)
			return [beat1, beat2]
		RUNWAY:
			return [
				(
					_translator
					. tr(
						# gdlint:ignore = max-line-length
						"Runway works finished! Bigger planes can now land, bringing fresh airline offers."
					)
				),
			]
		INCIDENT:
			return [
				(
					_translator
					. tr(
						# gdlint:ignore = max-line-length
						"Heads up! Your first big event just came in. Check the notice for details."
					)
				),
			]
	return []


## The words for the big first `kind`; `departure_time` fills OPENING's flight
## time (for example "08:13").
static func line_for(kind: String, departure_time := "") -> String:
	return "\n".join(_beats_for_kind(kind, departure_time))


## The dialog's beats for the listed kinds, in KINDS order.
static func beats_for(kinds: Array, departure_time := "") -> Array[String]:
	var out: Array[String] = []
	for kind: String in KINDS:
		if kinds.has(kind):
			out.append_array(_beats_for_kind(kind, departure_time))
	return out


## Single-beat summary (<= 18 words) when multiple airport firsts coalesce behind
## a tier unlock so the combined dialog never exceeds two beats.
static func combined_beat_for(kinds: Array) -> String:
	if kinds.has(RUNWAY) and kinds.has(INCIDENT):
		return (
			_translator
			. tr(
				# gdlint:ignore = max-line-length
				"Bigger planes can land now, and your first big event has arrived."
			)
		)
	var beats := beats_for(kinds)
	return beats[0] if not beats.is_empty() else ""


## The dialog's text for the listed kinds, joined across its beats.
static func body_for(kinds: Array, departure_time := "") -> String:
	return "\n".join(beats_for(kinds, departure_time))


## Scannable icon chips for the listed big-first kinds.
static func chips_for(kinds: Array, departure_time := "") -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if kinds.has(OPENING):
		var flight_lbl := (
			_translator.tr("1st Flight · {time}").format({"time": departure_time})
			if departure_time != ""
			else _translator.tr("1st Flight")
		)
		(
			chips
			. append(
				{
					"icon": ICON_GATES,
					"label": flight_lbl,
					"tint": Color(0.24, 0.56, 0.72, 1.0),
				}
			)
		)
		(
			chips
			. append(
				{
					"icon": ICON_COIN,
					"label": _translator.tr("Offers"),
					"tint": Color(0.84, 0.58, 0.16, 1.0),
				}
			)
		)
	if kinds.has(RUNWAY):
		(
			chips
			. append(
				{
					"icon": ICON_GATES,
					"label": _translator.tr("Larger planes"),
					"tint": Color(0.24, 0.56, 0.72, 1.0),
				}
			)
		)
		(
			chips
			. append(
				{
					"icon": ICON_COIN,
					"label": _translator.tr("New offers"),
					"tint": Color(0.84, 0.58, 0.16, 1.0),
				}
			)
		)
	if kinds.has(INCIDENT):
		(
			chips
			. append(
				{
					"icon": ICON_SERVICES,
					"label": _translator.tr("Major event"),
					"tint": Color(0.78, 0.36, 0.24, 1.0),
				}
			)
		)
	return chips


## Heading for an airport certification celebration card.
static func certification_title(star: int, title: String) -> String:
	return _translator.tr("Certified {star}★: {title}").format(
		{"star": star, "title": _translator.tr(title)}
	)


## Close button text for the certification celebration card.
static func certification_close_text() -> String:
	return _translator.tr("Close")


## Body lines for an airport certification celebration card.
static func certification_body(star: int, title: String, grant: int, bonus_percent: int) -> String:
	var lines: Array[String] = [
		_translator.tr("Your airport earned {star}★ {title} certification!").format(
			{"star": star, "title": _translator.tr(title)}
		),
		_translator.tr("One-time cash grant: +${grant}").format({"grant": grant}),
	]
	if bonus_percent > 0:
		lines.append(
			_translator.tr("Permanent contract fee prestige bonus: +{percent}%").format(
				{"percent": bonus_percent}
			)
		)
	else:
		lines.append(
			_translator.tr("Reach 2★ Regional Terminal to unlock permanent contract fee bonuses.")
		)
	return "\n".join(lines)


## Shows a non-blocking celebration toast for a newly earned certification milestone
## and returns the CanvasLayer (attached under `host` when provided).
static func show_certification(
	star: int, title: String, grant: int, bonus_percent: int, host: Node = null
) -> CanvasLayer:
	if host != null:
		var old := host.get_node_or_null("CertificationToastLayer")
		if old != null and is_instance_valid(old):
			host.remove_child(old)
			old.queue_free()
	var layer := CanvasLayer.new()
	layer.name = "CertificationToastLayer"
	layer.layer = TopRow.SHEET_LAYER + 1
	var card := PanelContainer.new()
	card.name = "CertificationToast"
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudCardGreen"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	card.offset_left = -CERTIFICATION_TOAST_W * 0.5
	card.offset_right = CERTIFICATION_TOAST_W * 0.5
	card.offset_top = TopRow.SHEET_TOP
	card.offset_bottom = TopRow.SHEET_TOP
	card.grow_vertical = Control.GROW_DIRECTION_END
	layer.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var stars := RatingBadge.StarRow.new()
	stars.fills = RatingBadge.star_fills(float(star))
	stars.custom_minimum_size = Vector2(
		(
			RatingBadge.STAR_COUNT * RatingBadge.STAR_SIZE
			+ (RatingBadge.STAR_COUNT - 1) * RatingBadge.STAR_GAP
		),
		RatingBadge.STAR_SIZE
	)
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(stars)
	var heading := Label.new()
	heading.name = "CertificationTitle"
	heading.theme_type_variation = &"HudTitle"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text = certification_title(star, title)
	header.add_child(heading)
	var close := Button.new()
	close.name = "CertificationClose"
	close.theme_type_variation = &"HudButtonCompact"
	close.text = certification_close_text()
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(layer.queue_free)
	header.add_child(close)
	var body := Label.new()
	body.name = "CertificationBody"
	body.theme_type_variation = &"HudSmall"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = certification_body(star, title, grant, bonus_percent)
	box.add_child(body)
	var timer := Timer.new()
	timer.wait_time = CERTIFICATION_TOAST_SECONDS
	timer.one_shot = true
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(layer.queue_free)
	layer.add_child(timer)
	if host != null:
		host.add_child(layer)
	return layer
