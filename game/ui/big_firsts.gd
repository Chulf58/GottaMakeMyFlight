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
const CERTIFICATION_TOAST_W := float(HudLayout.RAIL_W)
const CERTIFICATION_RAIL_KEY := &"airport_certification"
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
		var flight_tip := (
			(
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"Your starter Oslo flight leaves at {time}. Open Planner (P) to check gates and times."
				)
				. format({"time": departure_time})
			)
			if departure_time != ""
			else (
				_translator
				. tr(
					# gdlint:ignore = max-line-length
					"Your starter Oslo flight is scheduled today. Open Planner (P) to check gates and times."
				)
			)
		)
		(
			chips
			. append(
				{
					"icon": ICON_GATES,
					"label": flight_lbl,
					"tint": Color(0.24, 0.56, 0.72, 1.0),
					"tooltip": flight_tip,
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
					"tooltip":
					(
						_translator
						. tr(
							# gdlint:ignore = max-line-length
							"Airlines send new flight contracts here. Click Offers at the top to review and accept them."
						)
					),
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
					"tooltip":
					_translator.tr(
						"Your longer runway can now land bigger planes that bring more passengers."
					),
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
					"tooltip":
					_translator.tr(
						"Open Offers at the top to see new airline contracts for larger planes."
					),
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
					"tooltip":
					(
						_translator
						. tr(
							# gdlint:ignore = max-line-length
							"Major events affect terminal traffic or rewards. Read the notice and prepare your staff."
						)
					),
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
## and routes it into AlertStack when present under `host`, or top-right standalone.
static func show_certification(
	star: int, title: String, grant: int, bonus_percent: int, host: Node = null
) -> CanvasLayer:
	if host != null:
		var old := host.get_node_or_null("CertificationToastLayer")
		if old != null and is_instance_valid(old):
			host.remove_child(old)
			old.free()
	var layer := CanvasLayer.new()
	layer.name = "CertificationToastLayer"
	layer.layer = TopRow.SHEET_LAYER + 1
	var card := PanelContainer.new()
	card.name = "CertificationToast"
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudCardGreen"
	card.custom_minimum_size = Vector2(CERTIFICATION_TOAST_W, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(stars)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var close := Button.new()
	close.name = "CertificationClose"
	close.theme_type_variation = &"HudButtonCompact"
	close.text = certification_close_text()
	close.focus_mode = Control.FOCUS_NONE
	header.add_child(close)
	var heading := Label.new()
	heading.name = "CertificationTitle"
	heading.theme_type_variation = &"HudTitle"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.text = certification_title(star, title)
	box.add_child(heading)
	var body := Label.new()
	body.name = "CertificationBody"
	body.theme_type_variation = &"HudSmall"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.text = certification_body(star, title, grant, bonus_percent)
	box.add_child(body)
	var rail := _find_alert_rail(host)
	var layer_id := layer.get_instance_id()
	var card_id := card.get_instance_id()
	var rail_id := rail.get_instance_id() if rail != null else 0
	var dismiss := func() -> void:
		var r := instance_from_id(rail_id) as AlertStack
		var c := instance_from_id(card_id) as Control
		var l := instance_from_id(layer_id) as CanvasLayer
		var can_drop := (
			r != null
			and is_instance_valid(r)
			and c != null
			and r.notice_card(CERTIFICATION_RAIL_KEY) == c
		)
		if can_drop:
			r.drop_notice(CERTIFICATION_RAIL_KEY)
		if l != null and is_instance_valid(l) and not l.is_queued_for_deletion():
			l.queue_free()
	close.pressed.connect(dismiss)
	var timer := Timer.new()
	timer.wait_time = CERTIFICATION_TOAST_SECONDS
	timer.one_shot = true
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(dismiss)
	layer.add_child(timer)
	if host != null:
		host.add_child(layer)
	if rail != null:
		card.tree_exiting.connect(
			func() -> void:
				var l := instance_from_id(layer_id) as CanvasLayer
				if l != null and is_instance_valid(l) and not l.is_queued_for_deletion():
					l.queue_free()
		)
		layer.tree_exiting.connect(
			func() -> void:
				var r := instance_from_id(rail_id) as AlertStack
				var c := instance_from_id(card_id) as Control
				if (
					r != null
					and is_instance_valid(r)
					and c != null
					and r.notice_card(CERTIFICATION_RAIL_KEY) == c
				):
					r.drop_notice(CERTIFICATION_RAIL_KEY)
		)
		rail.post_notice(
			CERTIFICATION_RAIL_KEY, card, CERTIFICATION_TOAST_SECONDS, heading.text, body.text
		)
	else:
		card.anchor_left = 1.0
		card.anchor_right = 1.0
		card.anchor_top = 0.0
		card.anchor_bottom = 0.0
		card.offset_right = -float(HudLayout.MARGIN)
		card.offset_left = -float(HudLayout.MARGIN) - CERTIFICATION_TOAST_W
		card.offset_top = float(HudLayout.MARGIN)
		card.offset_bottom = float(HudLayout.MARGIN)
		card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		card.grow_vertical = Control.GROW_DIRECTION_END
		layer.add_child(card)
	return layer


static func _find_alert_rail(host: Node) -> AlertStack:
	if host == null or not host.is_inside_tree():
		return null
	var tree := host.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(AlertStack.GROUP) as AlertStack
