class_name RatingBadge
extends CanvasLayer
## The airport rating in the HUD (Rating 2a, decision airport-rating-1-5-stars-
## over-a-rolling-3-days-mostly-made-o): five stars in half steps with the
## number beside them, an optional earned certification chip, and a tooltip
## with the parts. Clicking the card toggles the Airport Certification drawer
## on TopRow.SHEET_LAYER (joining TopRow.SHEET_GROUP) showing all 5 milestones,
## criteria progress, prestige fee bonus, and DemoMode "In the full game"
## teasers for 3★-5★.

## Left edge: the money slot's margin, its width, and a gap.
const LEFT := float(HudLayout.MARGIN + HudLayout.MONEY_W + HudLayout.GAP)
const STAR_COUNT := 5
const STAR_SIZE := 16.0
const STAR_GAP := 2.0
const DRAWER_W := 408.0
const CERT_CHIP_COLOR := Color(0.56, 0.36, 0.02, 1.0)
const EARNED_COLOR := Color(0.16, 0.45, 0.2, 1.0)
const MET_COLOR := Color(0.18, 0.44, 0.22, 1.0)
const UNMET_COLOR := Color(0.32, 0.34, 0.42, 1.0)
const LOCKED_MODULATE := Color(0.55, 0.55, 0.55, 0.85)
## The English msgid of the no-data label. Tests compare against it; the label
## itself is tr("No flights yet"), because the POT extractor reads only literals.
const NO_DATA_TEXT := "No flights yet"

@export var rating: AirportRating
@export var certification: AirportCertification

var _card := PanelContainer.new()
var _star_row := StarRow.new()
var _label := Label.new()
var _cert_chip := Label.new()
var _drawer_layer := CanvasLayer.new()
var _drawer := PanelContainer.new()
var _drawer_summary := Label.new()
var _drawer_scroll := ScrollContainer.new()
var _drawer_rows := VBoxContainer.new()
var _drawer_title := Label.new()
var _close_btn := Button.new()


func _ready() -> void:
	_build()
	add_to_group(TopRow.SHEET_GROUP)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_place_drawer):
		vp.size_changed.connect(_place_drawer)
	if get_parent() != null:
		var save_node := get_parent().get_node_or_null("SaveGame") as SaveGame
		if save_node != null:
			if certification == null:
				certification = save_node.ensure_certification()
			if not save_node.loaded.is_connected(_on_save_loaded):
				save_node.loaded.connect(_on_save_loaded)
		if certification == null:
			certification = (
				get_parent().get_node_or_null("AirportCertification") as AirportCertification
			)
	if rating == null:
		push_error("RatingBadge: no AirportRating is set")
		if certification != null:
			watch_certification(certification)
		return
	watch(rating)
	if certification != null:
		watch_certification(certification)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_place_drawer):
		vp.size_changed.disconnect(_place_drawer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()
		if rating != null or certification != null:
			refresh()


func _input(event: InputEvent) -> void:
	if not _drawer.visible:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if (
		_global_rect(_card).has_point(click.position)
		or _global_rect(_drawer).has_point(click.position)
	):
		return
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not _drawer.visible:
		return
	var key := event as InputEventKey
	var is_esc_key := key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	if event.is_action_pressed("build_tool_none") or is_esc_key:
		close()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Follows `with_rating` and shows it at once; a rating followed before is let
## go, and following the same one again does nothing.
func watch(with_rating: AirportRating) -> void:
	if rating != null and rating != with_rating and rating.changed.is_connected(refresh):
		rating.changed.disconnect(refresh)
	rating = with_rating
	if rating != null and not rating.changed.is_connected(refresh):
		rating.changed.connect(refresh)
	refresh()


## Follows `with_certification` and updates the badge chip and drawer live.
func watch_certification(with_cert: AirportCertification) -> void:
	if (
		certification != null
		and certification != with_cert
		and certification.changed.is_connected(refresh)
	):
		certification.changed.disconnect(refresh)
	certification = with_cert
	if certification != null and not certification.changed.is_connected(refresh):
		certification.changed.connect(refresh)
	refresh()


func card() -> PanelContainer:
	return _card


## The drawn stars; its `fills` are what the card shows.
func star_row() -> StarRow:
	return _star_row


## The label beside the stars (named RatingText).
func label() -> Label:
	return _label


## The compact certification chip beside RatingText (named CertChip).
func cert_chip() -> Label:
	return _cert_chip


## The certification progress drawer panel (named CertificationDrawer).
func drawer() -> PanelContainer:
	return _drawer


## TopRow.SHEET_GROUP interface: returns the drawer Control.
func sheet() -> Control:
	return _drawer


func is_open() -> bool:
	return _drawer.visible


func is_drawer_open() -> bool:
	return _drawer.visible


func open() -> void:
	TopRow.close_others(self)
	_refresh_drawer()
	_drawer.visible = true
	_place_drawer()
	_fit_drawer_height.call_deferred()


func _process(_delta: float) -> void:
	if _drawer.visible:
		_place_drawer()


func close() -> void:
	_drawer.visible = false


func toggle_drawer() -> void:
	if _drawer.visible:
		close()
	else:
		open()


## Simulates clicking the rating badge card to toggle the certification drawer.
func press() -> void:
	toggle_drawer()


## The stars drawn: the rating's, or 0 while it has no data.
func shown_stars() -> float:
	if rating == null:
		return 0.0
	return rating.stars() if rating.has_data() else 0.0


## The number beside the stars, or "No flights yet".
func summary_text() -> String:
	if rating == null or not rating.has_data():
		return tr("No flights yet")
	return "%.1f" % rating.stars()


## The card's tooltip: made share, mood, the incident adjustment (only while it
## is not zero), days counted over the window, and earned certification summary.
func tooltip_text() -> String:
	if rating == null or not rating.has_data():
		var empty_tip := tr(
			"No flights yet: the rating starts when passengers make or miss a flight."
		)
		if certification != null:
			if certification.earned_star() > 0:
				empty_tip += (
					"\n"
					+ (
						tr("Certification: {star}★ {title} (+{bonus}% contract fees)")
						. format(
							{
								"star": certification.earned_star(),
								"title": tr(certification.earned_title()),
								"bonus": certification.prestige_fee_bonus_percent(),
							}
						)
					)
				)
			empty_tip += "\n" + tr("Click for airport certification progress.")
		return empty_tip
	var parts := rating.parts()
	var made_line := tr_n(
		"Made it: {share}% ({made} of {count} passenger)",
		"Made it: {share}% ({made} of {count} passengers)",
		parts["passengers"]
	)
	made_line = (
		made_line
		. format(
			{
				"share": roundi(parts["made_share"] * 100.0),
				"made": parts["made"],
				"count": parts["passengers"],
			}
		)
	)
	var lines: Array[String] = [
		tr("Airport rating: {stars} of {max}").format(
			{"stars": "%.1f" % parts["stars"], "max": STAR_COUNT}
		),
		made_line,
		tr("Mood: {mood} of {max}").format(
			{"mood": roundi(parts["mood_avg"]), "max": PassengerSim.MOOD_MAX}
		),
	]
	if parts["adjustment"] != 0.0:
		lines.append(
			tr("Incident adjustment: {amount} stars").format(
				{"amount": "%+.1f" % parts["adjustment"]}
			)
		)
	lines.append(
		tr("Days counted: {days} of {window}").format(
			{"days": parts["days"], "window": RatingFormula.WINDOW_DAYS}
		)
	)
	if certification != null:
		if certification.earned_star() > 0:
			(
				lines
				. append(
					(
						tr("Certification: {star}★ {title} (+{bonus}% contract fees)")
						. format(
							{
								"star": certification.earned_star(),
								"title": tr(certification.earned_title()),
								"bonus": certification.prestige_fee_bonus_percent(),
							}
						)
					)
				)
			)
		lines.append(tr("Click for airport certification progress."))
	return "\n".join(lines)


func refresh() -> void:
	_star_row.fills = star_fills(shown_stars())
	_star_row.queue_redraw()
	_label.text = summary_text()
	_refresh_cert_chip()
	_card.tooltip_text = tooltip_text()
	if _drawer.visible:
		_refresh_drawer()
		_place_drawer()


## How full each of the five stars is for `value` stars: 1.0, 0.5 or 0.0.
static func star_fills(value: float) -> Array[float]:
	var fills: Array[float] = []
	for i in STAR_COUNT:
		fills.append(clampf(value - i, 0.0, 1.0))
	return fills


func _refresh_cert_chip() -> void:
	if certification == null or certification.earned_star() <= 0:
		_cert_chip.visible = false
		return
	# "No flights yet" already fills ~197 px of TopRow.RATING_W (200 px);
	# omit the chip there while keeping certification in the tooltip and drawer.
	if rating == null or not rating.has_data():
		_cert_chip.visible = false
		return
	_cert_chip.text = tr("{star}★").format({"star": certification.earned_star()})
	_cert_chip.visible = true


func _retranslate() -> void:
	_drawer_title.text = tr("Airport Certification")
	_close_btn.text = tr("Close")


func _on_card_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		toggle_drawer()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _on_save_loaded(ok: bool) -> void:
	if ok:
		close()
		refresh()


func _live_metrics() -> Dictionary:
	var metrics := certification.current_metrics() if certification != null else {}
	if rating != null and (certification == null or certification.rating == null):
		metrics["rating_stars"] = rating.stars()
		if rating.has_data():
			metrics["made_ratio"] = float(rating.parts().get("made_share", -1.0))
	return metrics


func _refresh_drawer() -> void:
	for child in _drawer_rows.get_children():
		_drawer_rows.remove_child(child)
		child.queue_free()
	if certification == null:
		_drawer_summary.text = tr("Certification tracking is not active.")
		return
	var earned := certification.earned_star()
	var level_label := (
		tr("{star}★ {title}").format({"star": earned, "title": tr(certification.earned_title())})
		if earned > 0
		else tr("Unrated")
	)
	_drawer_summary.text = tr("Current: {level} • Permanent contract fee bonus: +{bonus}%").format(
		{"level": level_label, "bonus": certification.prestige_fee_bonus_percent()}
	)
	var rows := certification.progress_rows(_live_metrics(), DemoMode.is_demo())
	for row in rows:
		_drawer_rows.add_child(_build_drawer_row(row))


func _build_drawer_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudCardGreen" if bool(row["earned"]) else &"HudTopCard"
	if bool(row["demo_locked"]):
		panel.modulate = LOCKED_MODULATE
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var title := Label.new()
	title.theme_type_variation = &"HudCardName"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(row["earned"]):
		title.text = tr("✓ {star}★ {title}").format(
			{"star": int(row["star"]), "title": tr(str(row["title"]))}
		)
		title.add_theme_color_override(&"font_color", EARNED_COLOR)
	else:
		title.text = tr("{star}★ {title}").format(
			{"star": int(row["star"]), "title": tr(str(row["title"]))}
		)
	top.add_child(title)
	var reward := Label.new()
	reward.theme_type_variation = &"HudSmall"
	reward.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	if bool(row["demo_locked"]):
		reward.text = tr(BuildUnlocks.IN_FULL_GAME_TEXT)
	elif bool(row["earned"]):
		reward.text = _reward_summary(int(row["grant"]), int(row["bonus_percent"]), true)
		reward.add_theme_color_override(&"font_color", EARNED_COLOR)
	else:
		reward.text = _reward_summary(int(row["grant"]), int(row["bonus_percent"]), false)
	top.add_child(reward)
	if not bool(row["demo_locked"]) and not bool(row["earned"]):
		for criterion: Dictionary in row["criteria"]:
			var item := Label.new()
			item.theme_type_variation = &"HudSmall"
			item.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
			var met := bool(criterion["met"])
			var mark := "[✓]" if met else "[ ]"
			item.text = "%s %s" % [mark, _criterion_text(criterion)]
			item.add_theme_color_override(&"font_color", MET_COLOR if met else UNMET_COLOR)
			vbox.add_child(item)
	return panel


func _reward_summary(grant: int, bonus_percent: int, is_done: bool) -> String:
	if is_done:
		if bonus_percent > 0:
			return tr("Earned • +${grant} • +{bonus}% fees").format(
				{"grant": grant, "bonus": bonus_percent}
			)
		return tr("Earned • +${grant}").format({"grant": grant})
	if bonus_percent > 0:
		return tr("+${grant} • +{bonus}% fees").format({"grant": grant, "bonus": bonus_percent})
	return tr("+${grant}").format({"grant": grant})


func _criterion_text(criterion: Dictionary) -> String:
	var label_key := str(criterion["label"])
	var current: Variant = criterion["current"]
	var target: Variant = criterion["target"]
	var out := tr(label_key)
	match label_key:
		"Airport opened":
			out = tr("Airport opened")
		"Airport rating":
			out = tr("Rating: {current} / {target}★").format(
				{"current": "%.1f" % float(current), "target": "%.1f" % float(target)}
			)
		"Passengers made":
			out = tr("Passengers made: {current} / {target}").format(
				{"current": int(current), "target": int(target)}
			)
		"Security lane built":
			out = tr("Operational security lane built")
		"Bag room built":
			out = tr("Operational bag room built")
		"Medium+ plane departed":
			out = tr("Medium+ planes departed: {current} / {target}").format(
				{"current": int(current), "target": int(target)}
			)
		"Large plane departed":
			out = tr("Large planes departed: {current} / {target}").format(
				{"current": int(current), "target": int(target)}
			)
		"Made / on-time rate":
			var tgt_pct := roundi(float(target) * 100.0)
			if float(current) < 0.0:
				out = tr("Made rate: -- / {target}%").format({"target": tgt_pct})
			else:
				out = tr("Made rate: {current}% / {target}%").format(
					{"current": roundi(float(current) * 100.0), "target": tgt_pct}
				)
	return out


func _place_drawer() -> void:
	if not _drawer.visible:
		return
	var vp := get_viewport()
	var view := vp.get_visible_rect().size if vp != null else Vector2(1536.0, 864.0)
	var min_left := TopRow.sheet_min_left(get_tree()) if is_inside_tree() else TopRow.SHEET_MIN_LEFT
	var right := view.x - float(HudLayout.MARGIN + HudLayout.RAIL_W + HudLayout.GAP)
	var max_w := maxf(240.0, right - min_left)
	var width := minf(DRAWER_W, minf(max_w, view.x - 2.0 * float(HudLayout.MARGIN)))
	var max_x := maxf(float(HudLayout.MARGIN), view.x - width - float(HudLayout.MARGIN))
	var x := clampf(min_left, float(HudLayout.MARGIN), max_x)
	var target_pos := Vector2(x, TopRow.SHEET_TOP)
	var size_changed := not is_equal_approx(_drawer.custom_minimum_size.x, width)
	if size_changed:
		_drawer.custom_minimum_size = Vector2(width, 0.0)
	if not _drawer.position.is_equal_approx(target_pos):
		_drawer.position = target_pos
	_fit_drawer_height()
	if size_changed:
		_drawer.reset_size()


func _fit_drawer_height() -> void:
	if _drawer == null or _drawer_scroll == null or not _drawer.visible:
		return
	var vp := get_viewport()
	var viewport_h := vp.get_visible_rect().size.y if vp != null else 864.0
	if viewport_h <= 0.0:
		return
	var content_h := _drawer_rows.get_combined_minimum_size().y
	var chrome := (
		_drawer.get_combined_minimum_size().y - _drawer_scroll.get_combined_minimum_size().y
	)
	var bottom_clear := float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	var max_scroll_h := maxf(0.0, viewport_h - TopRow.SHEET_TOP - bottom_clear - chrome)
	var wanted := minf(content_h, max_scroll_h)
	var need_reset := false
	if not is_equal_approx(_drawer_scroll.custom_minimum_size.y, wanted):
		_drawer_scroll.custom_minimum_size.y = wanted
		need_reset = true
	if need_reset or _drawer.size.y > _drawer.get_combined_minimum_size().y + 1.0:
		_drawer.reset_size()


static func _global_rect(ctrl: Control) -> Rect2:
	return ctrl.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ctrl.size)


func _build() -> void:
	_card.name = "RatingCard"
	_card.theme = BuildMenu.HUD_THEME
	_card.theme_type_variation = &"HudTopCard"
	_card.position = Vector2(LEFT, HudLayout.MARGIN)
	_card.custom_minimum_size = Vector2(0.0, HudLayout.BUTTON_H)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_card.gui_input.connect(_on_card_gui_input)
	add_child(_card)
	# The card is BUTTON_H tall like the rest of the top row and ends before the
	# centred top row: 16 px stars and a CAPTION label keep it inside 200 px.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_star_row.fills = star_fills(0.0)
	_star_row.custom_minimum_size = Vector2(
		STAR_COUNT * STAR_SIZE + (STAR_COUNT - 1) * STAR_GAP, STAR_SIZE
	)
	_star_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_star_row)
	_label.name = "RatingText"
	_label.theme_type_variation = &"HudSmall"
	_label.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	_cert_chip.name = "CertChip"
	_cert_chip.theme_type_variation = &"HudSmall"
	_cert_chip.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	_cert_chip.add_theme_color_override(&"font_color", CERT_CHIP_COLOR)
	_cert_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cert_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cert_chip.visible = false
	row.add_child(_cert_chip)
	_build_drawer()


func _build_drawer() -> void:
	_drawer_layer.name = "CertificationDrawerLayer"
	_drawer_layer.layer = TopRow.SHEET_LAYER
	add_child(_drawer_layer)
	_drawer.name = "CertificationDrawer"
	_drawer.theme = BuildMenu.HUD_THEME
	_drawer.theme_type_variation = &"HudTopCard"
	_drawer.visible = false
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer.position = Vector2(TopRow.SHEET_MIN_LEFT, TopRow.SHEET_TOP)
	_drawer.custom_minimum_size = Vector2(DRAWER_W, 0.0)
	_drawer_layer.add_child(_drawer)
	var root_box := VBoxContainer.new()
	root_box.sort_children.connect(_fit_drawer_height)
	_drawer.add_child(root_box)
	var header := HBoxContainer.new()
	root_box.add_child(header)
	_drawer_title.name = "CertDrawerTitle"
	_drawer_title.theme_type_variation = &"HudTitle"
	_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_drawer_title)
	_close_btn.name = "CloseCertDrawer"
	_close_btn.theme_type_variation = &"HudButtonCompact"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)
	_drawer_summary.name = "CertSummary"
	_drawer_summary.theme_type_variation = &"HudSmall"
	_drawer_summary.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	_drawer_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(_drawer_summary)
	root_box.add_child(HSeparator.new())
	_drawer_scroll.name = "CertRowsScroll"
	_drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(_drawer_scroll)
	_drawer_rows.name = "CertRows"
	_drawer_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_rows.sort_children.connect(_fit_drawer_height)
	_drawer_scroll.add_child(_drawer_rows)
	_retranslate()


## Draws the five stars from `fills`: an empty star under, the filled part
## clipped to its left half for a half step, the outline on top. Colours come
## from the HUD theme, type RatingStars: star_fill, star_empty, star_outline.
class StarRow:
	extends Control

	var fills: Array[float] = []

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			queue_redraw()

	func _draw() -> void:
		var fill := get_theme_color(&"star_fill", &"RatingStars")
		var empty := get_theme_color(&"star_empty", &"RatingStars")
		var outline_colour := get_theme_color(&"star_outline", &"RatingStars")
		for i in fills.size():
			var shape := _star(Vector2(i * (STAR_SIZE + STAR_GAP) + STAR_SIZE / 2.0, size.y / 2.0))
			var outline := shape.duplicate()
			outline.append(shape[0])
			# Draw the 2 px outline behind the polygon fills so only its outer 1 px
			# frames the 16 px star without swallowing the arms and gold interior.
			draw_polyline(outline, outline_colour, 2.0, true)
			draw_colored_polygon(shape, empty)
			if fills[i] >= 1.0:
				draw_colored_polygon(shape, fill)
			elif fills[i] > 0.0:
				var half := PackedVector2Array(
					[
						Vector2(shape[0].x - STAR_SIZE, -STAR_SIZE),
						Vector2(shape[0].x, -STAR_SIZE),
						Vector2(shape[0].x, size.y + STAR_SIZE),
						Vector2(shape[0].x - STAR_SIZE, size.y + STAR_SIZE),
					]
				)
				for piece in Geometry2D.intersect_polygons(shape, half):
					draw_colored_polygon(piece, fill)

	## A five-point star around `centre`, point up, starting at the top point.
	static func _star(centre: Vector2) -> PackedVector2Array:
		var outer := STAR_SIZE / 2.0 - 1.0
		var inner := outer * 0.48
		var points := PackedVector2Array()
		for k in 10:
			var radius := outer if k % 2 == 0 else inner
			var angle := -PI / 2.0 + k * PI / 5.0
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		return points
