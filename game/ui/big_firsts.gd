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


## The words for the big first `kind`; `departure_time` fills OPENING's flight
## time (for example "08:13").
static func line_for(kind: String, departure_time := "") -> String:
	match kind:
		OPENING:
			return (
				"\n"
				. join(
					PackedStringArray(
						[
							(
								_translator
								. tr(
									# gdlint:ignore = max-line-length
									"Gotta Air here. Welcome, your airport is open, and I hear it is the only one with a dent in the carpet."
								)
							),
							(
								_translator
								. tr(
									# gdlint:ignore = max-line-length
									"Our first flight to Oslo leaves at {departure_time}. It is a small plane, so please keep the luggage small too."
								)
								. format({"departure_time": departure_time})
							),
							_translator.tr("Your first passengers are on their way in now."),
							_translator.tr("Good luck. Gotta make that flight!"),
						]
					)
				)
			)
		RUNWAY:
			return (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"The runway works are done. Bigger planes can land now, so Offers can bring them flights."
				)
			)
		INCIDENT:
			return (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"A big event has come up. Its notice says what it is and what you can do about it."
				)
			)
	return ""


## The dialog's text for the listed kinds: each kind's lines, then the note
## about the clock.
static func body_for(kinds: Array, departure_time := "") -> String:
	var lines: Array[String] = []
	for kind: String in KINDS:
		if kinds.has(kind):
			lines.append(line_for(kind, departure_time))
	return "\n".join(lines) + "\n" + _translator.tr("The clock goes on when you close this.")


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
