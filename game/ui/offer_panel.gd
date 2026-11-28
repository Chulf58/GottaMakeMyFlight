# gdlint:disable = max-public-methods, max-file-lines
class_name OfferPanel
extends CanvasLayer
## Today's airline offers (Pick 1 of 3, decision
## airline-offers-pick-1-of-3-side-by-side-spin-away-discard). A button in the
## centred top row (TopRow's last slot) shows how many offers are open; it opens
## a cream sheet with the 3 daily offer cards laid out side by side in a
## horizontal row (plus any open one-off charters separated above) and a Pass
## button to decline the day's offers. Accepting 1 daily offer dismisses the
## other 2 with a spin-away discard animation while charters stay independent.
##
## Opening or closing the sheet leaves the sim clock alone. It joins
## TopRow.SHEET_GROUP so opening another top-row sheet closes it, and closes
## on Esc, when a build tool is picked, and when a save loads.

signal opened

const SHEET_W := TopRow.SHEET_W
const WIDE_SHEET_W := 960.0
const CARD_TEXT_W := 380.0
## The widths the fit and earnings lines share on the row under the title: the
## fit line may wrap in the space left of the earnings, which stay on one line.
const VERDICT_FIT_W := 200.0
const VERDICT_EARNINGS_W := 150.0
## Index of the first-flight note line in a card's lines (under the departure).
const NOTE_LINE := 2
## Rail keys, and the history titles, of the two coral notices.
const WARNING_KEY := &"offer_warning"
const ENDED_KEY := &"offer_ended"
## The English msgids of the rail card titles, the empty message and the fit line
## when the offer fits the gates now, and when another gate would take it (any
## other blocker keeps FlightFit's own words). Tests compare with these; each is
## shown through tr() of the same literal, because the POT extractor reads only
## literals.
const WARNING_TITLE := "Low airport rating"
const ENDED_TITLE := "Contract ended"
const EMPTY_TEXT := "No offers right now. New offers arrive at midnight."
const PICKED_TODAY_TEXT := "Picked today's route — new offers tomorrow."
const FITS_TEXT := "Fits your gates now"
const NEEDS_GATE_TEXT := "Needs another gate"
const CHARTER_BADGE_TEXT := "One-off charter — flies today only"
const DISCARD_DURATION_S := 0.40
const DISCARD_ROTATE_RAD := 0.72
const DISCARD_SCALE := Vector2(0.18, 0.18)
const DISCARD_OFFSET := Vector2(64.0, 44.0)
const CHOSEN_TINT := Color(1.06, 1.14, 0.96, 1.0)
const BADGE_META := &"badge_monogram"
const BADGE_BORDER := Color(0.1, 0.13, 0.26, 1.0)
const PEAK_CHIP_FILL := Color(0.98, 0.87, 0.56, 1.0)
const PEAK_CHIP_BORDER := Color(0.76, 0.54, 0.16, 1.0)
const REQ_CHIP_FILL := Color(0.99, 0.86, 0.42, 1.0)
const REQ_CHIP_BORDER := Color(0.76, 0.50, 0.10, 1.0)
const HUB_CHIP_FILL := Color(0.98, 0.85, 0.36, 1.0)
const HUB_CHIP_BORDER := Color(0.74, 0.52, 0.08, 1.0)
const PULSE_TINT := Color(1.16, 1.06, 0.72, 0.76)
const PULSE_HALF_S := 0.7
const AIRLINE_BADGES := {
	"Gotta Air": {"code": "GA", "color": Color(0.96, 0.76, 0.28, 1.0)},
	"Nordic Wing": {"code": "NW", "color": Color(0.46, 0.74, 0.94, 1.0)},
	"Blue Fjord": {"code": "BF", "color": Color(0.36, 0.78, 0.74, 1.0)},
	"Sunhop": {"code": "SH", "color": Color(0.96, 0.60, 0.34, 1.0)},
	"Polar Jet": {"code": "PJ", "color": Color(0.62, 0.84, 0.92, 1.0)},
	"Aegean Sky": {"code": "AS", "color": Color(0.48, 0.68, 0.94, 1.0)},
	"Skyline Global": {"code": "SG", "color": Color(0.76, 0.62, 0.90, 1.0)},
	"Meridian Air": {"code": "MA", "color": Color(0.52, 0.82, 0.56, 1.0)},
}
const FALLBACK_BADGE_COLORS: Array[Color] = [
	Color(0.96, 0.76, 0.28, 1.0),
	Color(0.46, 0.74, 0.94, 1.0),
	Color(0.36, 0.78, 0.74, 1.0),
	Color(0.96, 0.60, 0.34, 1.0),
	Color(0.62, 0.84, 0.92, 1.0),
	Color(0.76, 0.62, 0.90, 1.0),
	Color(0.52, 0.82, 0.56, 1.0),
	Color(0.94, 0.64, 0.62, 1.0),
]

@export var desk: OfferDesk
@export var flights: FlightSim
## Kept for scene/test wiring compatibility; OfferPanel leaves the clock alone.
@export var clock: SimClock
## Its tool changes close the sheet; null leaves the sheet to Esc and the button.
@export var build_mode: BuildMode
## A successful load replaces the world the sheet was opened over, so it closes.
@export var save_game: SaveGame
## The right rail the warning and ending notices go on; null finds the one in
## AlertStack.GROUP (the HUD builds it, so the scene does not wire it).
var alerts: AlertStack
var has_been_opened := false
var pulsing := false

var _button: Button
var _sheet: PanelContainer
var _intro_banner: PanelContainer
var _intro_label: Label
var _scroll: ScrollContainer
var _sections: VBoxContainer
var _charter_cards: VBoxContainer
var _daily_row: HBoxContainer
var _message: Label
var _pass_button: Button
var _discard_layer: Control
var _discard_spacer: Control
var _discard_tween: Tween
var _animating_discard := false
var _discard_nodes: Array[Control] = []
## The warning as the rating words it now, and as the card on the rail words it
## ("" while none is up); the ending line the tooltip adds under the warning.
var _warning_text := ""
var _warning_posted := ""
## Instance id of the rail the warning was posted to (0 before any).
var _posted_rail := 0
## The rail whose reset_done this panel listens to (only ever one).
var _watched_rail: AlertStack
var _ended_text := ""
var _offers_waiting := false
var _offers_unseen := false
var _was_airport_open := false
var _day1_auto_pop_pending := false
var _known_offer_ids: Dictionary = {}
var _pulse_tween: Tween
var _card_nodes: Dictionary = {}
var _accept_buttons: Dictionary = {}
var _decline_buttons: Dictionary = {}
var _note_labels: Dictionary = {}
var _refusal_labels: Dictionary = {}
var _fit_labels: Dictionary = {}
var _req_chips: Dictionary = {}
## Offer id -> the taxi pair of the gate its last fit found, for its note.
var _fit_taxis: Dictionary = {}
var _earnings_labels: Dictionary = {}
var _trait_rows: Dictionary = {}
var _peak_chips: Dictionary = {}
var _noted_tick := -1


## The airlines' warning once the rating is low: `low_days` day ends have
## already been low, and contracts end at RatingFormula.LOW_DAYS_TO_END.
static func warning_message(low_days: int) -> String:
	var text := (
		TranslationServer
		. translate("Airlines are warning you: the airport quality is below {percent}%.")
		. format({"percent": AirportRating.quality_percent(RatingFormula.WARN_BELOW)})
	)
	var left := RatingFormula.LOW_DAYS_TO_END - low_days
	if left > 0:
		text += (
			" "
			+ (
				TranslationServer
				. translate_plural(
					"Contracts end after {days} more low day.",
					"Contracts end after {days} more low days.",
					left
				)
				. format({"days": left})
			)
		)
	return text


## What the player is told when an airline leaves because the rating stayed low.
static func ended_message(airline: String, destination: String) -> String:
	var text := (
		TranslationServer
		. translate(
			"{airline} to {destination} has ended its contract: the airport rating stayed low."
		)
		. format({"airline": airline, "destination": destination})
	)
	return (
		text
		+ " "
		+ TranslationServer.translate("Flights already issued still fly; no new days will.")
	)


## Says when the first flight is if it is not today: "" when the sim would fly
## today's slot at a gate with taxi pair `taxi` (FlightTimetable.first_day is
## today), else "first flight tomorrow" or, past that, "first flight on Day N"
## (the HUD's day number).
static func first_flight_note(offer: Dictionary, now: int, taxi: Array, epoch: int) -> String:
	var timed := offer.duplicate()
	timed[FlightContract.TAXI_KEY] = taxi
	var first_day := FlightTimetable.first_day(timed, now, epoch)
	var ahead := first_day - GameCalendar.day_of(now, epoch)
	if ahead <= 0:
		return ""
	if ahead == 1:
		return TranslationServer.translate("first flight tomorrow")
	return TranslationServer.translate("first flight on Day {day}").format({"day": first_day + 1})


## Ticks a contract accepted while the airport is closed needs between the
## airport opening and its departure to fly the first day's slot: the issue
## lead before departure (FlightTimetable.issue_lead() and opening_day), the
## same at every gate.
static func opening_lead_ticks() -> int:
	return FlightTimetable.issue_lead()


## `ticks` as "2 h 50 min", "45 min" or "3 h", rounded up to a whole minute.
static func lead_text(ticks: int) -> String:
	var minutes := -GameCalendar.floor_div(-ticks, GameCalendar.TICKS_PER_MINUTE)
	var parts: PackedStringArray = []
	if minutes >= 60:
		parts.append(TranslationServer.translate("{hours} h").format({"hours": minutes / 60}))
	if minutes % 60 != 0:
		parts.append(TranslationServer.translate("{minutes} min").format({"minutes": minutes % 60}))
	return " ".join(parts)


## The text lines of an offer's card: who and where, when, the plane, and the
## money. `note` (first_flight_note) gets its own line under the departure when
## not empty, so no line wraps. A card without a note has 4 lines, with one 5.
static func card_lines(offer: Dictionary, note := "") -> PackedStringArray:
	var minute: int = offer["departure_minute"]
	# A daily minute as a time: the same at every epoch, so read at 0.
	var time := GameCalendar.clock_text(GameCalendar.tick_at(0, minute, 0), 0)
	var when_line := (
		TranslationServer.translate("Departs {time} today").format({"time": time})
		if FlightContract.is_charter(offer)
		else TranslationServer.translate("Departs {time} daily").format({"time": time})
	)
	var lines := PackedStringArray(
		[
			TranslationServer.translate("{airline} to {destination}").format(
				{"airline": offer["airline"], "destination": offer["destination"]}
			),
			when_line,
			_plane_line(offer["plane_size"]),
			(
				TranslationServer
				. translate_plural(
					"{count} passenger booked   ${fee} per passenger",
					"{count} passengers booked   ${fee} per passenger",
					offer["booked_passengers"]
				)
				. format({"count": offer["booked_passengers"], "fee": offer["fee_per_passenger"]})
			),
		]
	)
	if note != "":
		lines.insert(NOTE_LINE, note_line(note))
	return lines


## Peak-wave chip label for `departure_minute`, or "" for off-peak / Odd hours.
static func _peak_chip_text(departure_minute: int) -> String:
	var wave := OfferBoard.peak_wave(departure_minute)
	if wave == OfferBoard.PEAK_WAVE_MORNING:
		return TranslationServer.translate("Morning Peak +15%")
	if wave == OfferBoard.PEAK_WAVE_EVENING:
		return TranslationServer.translate("Evening Peak +15%")
	return ""


## "Small plane", "Medium plane" or "Large plane" for a plane size.
static func _plane_line(size: String) -> String:
	match size:
		PlaneClasses.SMALL:
			return TranslationServer.translate("Small plane")
		PlaneClasses.MEDIUM:
			return TranslationServer.translate("Medium plane")
		PlaneClasses.LARGE:
			return TranslationServer.translate("Large plane")
	push_error("OfferPanel._plane_line: unknown plane size '%s'" % size)
	return ""


## What an offer pays each day it flies: booked passengers times the fee.
static func daily_earnings(offer: Dictionary) -> int:
	return int(offer["booked_passengers"]) * int(offer["fee_per_passenger"])


## The earnings line on a card, the figure the offers are compared by.
static func earnings_text(offer: Dictionary) -> String:
	if FlightContract.is_charter(offer):
		return TranslationServer.translate("${amount} payout").format(
			{"amount": daily_earnings(offer)}
		)
	return TranslationServer.translate("${amount} a day").format({"amount": daily_earnings(offer)})


## The card's fit line for `assessment` of an offer with `plane_size`: the short
## fits / needs-another-gate words, else FlightFit's reason.
static func fit_line(assessment: Dictionary, plane_size: String) -> String:
	if assessment["fits"]:
		return TranslationServer.translate("Fits your gates now")
	if assessment["blocker"] == FlightSim.BLOCKER_GATE and assessment["another_gate_helps"]:
		return TranslationServer.translate("Needs another gate")
	return FlightFit.text(assessment, plane_size)


## A first-flight note as it reads on a line of its own.
static func note_line(note: String) -> String:
	return note.left(1).to_upper() + note.substr(1)


## Crisp 2-letter airline monogram for the offer card badge.
static func airline_code(airline: String) -> String:
	if AIRLINE_BADGES.has(airline):
		return String(AIRLINE_BADGES[airline]["code"])
	var words: Array[String] = []
	for part in airline.strip_edges().split(" ", false):
		words.append(part)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	if words.size() == 1:
		return words[0].left(2).to_upper()
	return "??"


## Deterministic Toon palette swatch color for `airline`.
static func airline_color(airline: String) -> Color:
	if AIRLINE_BADGES.has(airline):
		return AIRLINE_BADGES[airline]["color"]
	var index := posmod(airline.hash(), FALLBACK_BADGE_COLORS.size())
	return FALLBACK_BADGE_COLORS[index]


## One-line cozy flavor pitch tailored to charter status, traits or destination.
static func route_pitch(offer: Dictionary) -> String:
	var airline := String(offer.get("airline", ""))
	var destination := String(offer.get("destination", ""))
	var template := ""
	if FlightContract.is_charter(offer):
		template = TranslationServer.translate(
			"Last-minute charter hop to {destination} — light bags, quick turnaround."
		)
	else:
		var traits: Dictionary = offer.get(FlightContract.TRAITS_KEY, {})
		match String(traits.get("up", "")):
			OfferTraits.TOP_FARE:
				template = TranslationServer.translate(
					"Premium cabin demand to {destination} — passengers pay top fare."
				)
			OfferTraits.SHOPPERS:
				template = TranslationServer.translate(
					"Holiday crowd bound for {destination} — plenty of time to shop."
				)
			OfferTraits.BAG_COVER:
				template = TranslationServer.translate(
					"Smooth bag handling to {destination} — {airline} covers missed bags."
				)
			OfferTraits.FULL_FLIGHT:
				template = TranslationServer.translate(
					"Busy route to {destination} — almost every seat is spoken for."
				)
			OfferTraits.SIGNING_BONUS:
				template = TranslationServer.translate(
					"{airline} brings a welcome bonus on your first flight to {destination}."
				)
			OfferTraits.LOYAL_AIRLINE:
				template = TranslationServer.translate(
					"Steady partner route to {destination} — fly often for higher fares."
				)
			_:
				template = _destination_pitch(destination)
	return template.format({"airline": airline, "destination": destination})


static func _destination_pitch(destination: String) -> String:
	var text := ""
	match destination:
		"Oslo":
			text = TranslationServer.translate(
				"Crisp northern hop with {airline} — steady fjord and business flyers."
			)
		"Berlin":
			text = TranslationServer.translate(
				"Quick city-break run to Berlin — easygoing weekend flyers."
			)
		"Lisbon":
			text = TranslationServer.translate(
				"Warm coastal route to Lisbon — sunlit travelers heading south."
			)
		"Rome":
			text = TranslationServer.translate(
				"Classic Mediterranean hop to Rome — sightseeing crowds all day."
			)
		"Dublin":
			text = TranslationServer.translate(
				"Friendly island link to Dublin — reliable regional commuters."
			)
		"Athens":
			text = TranslationServer.translate(
				"Sunny Aegean flight to Athens — leisure flyers ready to board."
			)
		_:
			text = TranslationServer.translate(
				"Reliable daily link to {destination} with {airline}."
			)
	return text


func _ready() -> void:
	if desk == null or flights == null:
		push_error("OfferPanel: desk and flights must both be set, so nothing is shown")
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = TopRow.SHEET_LAYER
	add_to_group(TopRow.SHEET_GROUP)
	_build()
	get_viewport().size_changed.connect(_place_row)
	desk.board.changed.connect(_refresh)
	if desk.rating != null:
		desk.rating.changed.connect(_refresh_warning)
	desk.contract_ended.connect(_on_contract_ended)
	flights.planning_changed.connect(_refresh_fits)
	flights.snapshot_loaded.connect(_on_snapshot_loaded)
	flights.occurrence_added.connect(_on_flights_changed)
	var gate := get_node_or_null("../AirportGate") as AirportGate
	if gate != null:
		gate.opened.connect(_on_airport_opened)
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	_was_airport_open = flights.opened_tick >= 0
	_known_offer_ids = _open_offer_id_set()
	_refresh()
	_refresh_warning()
	_sync_open_state()


func _exit_tree() -> void:
	_stop_pulse()
	_animating_discard = false
	if _discard_tween != null:
		_discard_tween.kill()
		_discard_tween = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


func _retranslate() -> void:
	if _sheet != null:
		var title := _sheet.find_child("OfferTitle", true, false) as Label
		if title != null:
			title.text = tr("Airline Contracts — Accept to schedule flights")
	if _intro_label != null:
		_intro_label.text = tr(
			"Accept airlines that fit your gates. Each signed contract sends flights every day."
		)
	if _pass_button != null:
		_pass_button.text = tr("Pass today's offers")
	if desk != null and flights != null:
		_refresh()
		_refresh_warning()


func _process(_delta: float) -> void:
	if flights != null and _button != null:
		var open_now := flights.opened_tick >= 0
		if _button.visible != open_now:
			_sync_open_state()
	if _day1_auto_pop_pending:
		_try_day1_auto_pop()
	if not _sheet.visible:
		return
	var viewport := get_viewport()
	if viewport != null:
		var extent := TopRow.sheet_extent(
			viewport.get_visible_rect().size.x, TopRow.sheet_min_left(get_tree()), WIDE_SHEET_W
		)
		if (
			not is_equal_approx(_sheet.offset_left, extent.x)
			or not is_equal_approx(_sheet.custom_minimum_size.x, extent.y)
		):
			_fit_scroll_height()
	if flights.tick != _noted_tick:
		_refresh_notes()
	flights.check_planning_changed()


## Esc closes the sheet and is not passed on, so it does not also drop a tool.
func _unhandled_input(event: InputEvent) -> void:
	if _sheet.visible and event.is_action_pressed("build_tool_none"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _sheet.visible


## The open sheet's card, or null before the panel has built itself.
func sheet() -> Control:
	return _sheet


## Shows the sheet without touching the sim clock. Hidden/refused until the
## airport opens.
func open() -> void:
	_sync_open_state()
	if flights == null or flights.opened_tick < 0 or _sheet.visible:
		return
	TopRow.close_others(self)
	_offers_unseen = false
	has_been_opened = true
	_day1_auto_pop_pending = false
	var show_intro := (
		desk != null
		and desk.board != null
		and not desk.board.is_day1_intro_shown()
		and GameCalendar.day_of(flights.opened_tick, flights.epoch) == 0
		and GameCalendar.day_of(flights.tick, flights.epoch) == 0
	)
	if show_intro:
		desk.board.mark_day1_intro_shown()
	if _intro_banner != null:
		_intro_banner.visible = show_intro
	_stop_pulse()
	_sheet.visible = true
	_refresh_notes()
	flights.check_planning_changed()
	_refresh_fits()
	TopRow.place_sheet(_sheet, self, WIDE_SHEET_W)
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()
	opened.emit()
	var rail := _rail()
	if rail != null:
		rail.refresh()


## Hides the sheet and clears transient refusals.
func close() -> void:
	var was_animating := _animating_discard
	_kill_discard_animation()
	if was_animating and desk != null and flights != null:
		_refresh()
	if not _sheet.visible:
		return
	_sheet.visible = false
	if _intro_banner != null:
		_intro_banner.visible = false
	_clear_refusals()
	_say_idle()


func toggle_button() -> Button:
	return _button


func pass_button() -> Button:
	return _pass_button


func daily_row() -> HBoxContainer:
	return _daily_row


func is_discard_animating() -> bool:
	return _animating_discard


func discard_tween() -> Tween:
	return _discard_tween


## Ids of the offers shown, in the order drawn.
func card_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _card_nodes:
		ids.append(id)
	return ids


func card(id: String) -> Control:
	return _card_nodes.get(id)


func accept_button(id: String) -> Button:
	return _accept_buttons.get(id)


func decline_button(id: String) -> Button:
	return _decline_buttons.get(id)


## All the text on one offer's card.
func card_text(id: String) -> String:
	var lines := PackedStringArray()
	for label in _card_nodes[id].find_children("*", "Label", true, false):
		var lbl := label as Label
		if lbl.visible and not lbl.has_meta(BADGE_META):
			lines.append(lbl.text)
	return "\n".join(lines)


func has_unseen_offers() -> bool:
	return _offers_unseen


## The airlines' warning, as the Offers button's tooltip says it; "" when the
## rating is fine.
func warning_text() -> String:
	return _warning_text


## The refusal shown on offer `id`'s own card (a clash, say), "" when it shows
## none.
func refusal_text(id: String) -> String:
	return (_refusal_labels[id] as Label).text


func refusal_label(id: String) -> Label:
	return _refusal_labels[id]


## The fit line on offer `id`'s card (fit_line): advice that Accept checks
## again at the click.
func fit_text(id: String) -> String:
	return (_fit_labels[id] as Label).text


func fit_label(id: String) -> Label:
	return _fit_labels[id]


## The daily earnings line on offer `id`'s card.
func earnings_text_of(id: String) -> String:
	return (_earnings_labels[id] as Label).text


func earnings_label(id: String) -> Label:
	return _earnings_labels[id]


## The trait line under the verdict row: an HFlowContainer of the Up, Down and Loyal labels.
func trait_row(id: String) -> HFlowContainer:
	return _trait_rows[id]


func requirement_chip(id: String) -> PanelContainer:
	return _req_chips.get(id)


func requirement_text(id: String) -> String:
	var chip := _req_chips.get(id) as PanelContainer
	if chip == null or not chip.visible:
		return ""
	var lbl := chip.get_node_or_null("RequirementLabel") as Label
	return lbl.text if lbl != null else ""


func intro_banner() -> PanelContainer:
	return _intro_banner


func intro_banner_text() -> String:
	if _intro_label == null or _intro_banner == null or not _intro_banner.visible:
		return ""
	return _intro_label.text


## What the sheet says under the cards: the last accept's confirmation, or
## EMPTY_TEXT when no offer is open. A refusal is on its card, not here.
func message() -> String:
	return _message.text


## Puts the button and the sheet back on the row for the viewport's layout width.
func _place_row() -> void:
	TopRow.place_in_slot(_button, TopRow.OFFERS_SLOT, self)
	TopRow.place_sheet(_sheet, self, WIDE_SHEET_W)
	_fit_scroll_height()


func _build() -> void:
	_button = Button.new()
	_sheet = PanelContainer.new()
	_scroll = ScrollContainer.new()
	_sections = VBoxContainer.new()
	_charter_cards = VBoxContainer.new()
	_daily_row = HBoxContainer.new()
	_message = Label.new()
	_pass_button = Button.new()
	_discard_layer = Control.new()
	_button.name = "OffersButton"
	_button.theme = BuildMenu.HUD_THEME
	TopRow.place_in_slot(_button, TopRow.OFFERS_SLOT, self)
	_button.focus_mode = Control.FOCUS_NONE
	_button.theme_type_variation = &"HudButtonTeal"
	_button.pressed.connect(_on_toggle)
	add_child(_button)
	_sheet.name = "OfferSheet"
	_sheet.theme = BuildMenu.HUD_THEME
	_sheet.visible = false
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	TopRow.place_sheet(_sheet, self, WIDE_SHEET_W)
	add_child(_sheet)
	var sheet_column := VBoxContainer.new()
	sheet_column.add_theme_constant_override("separation", 6)
	_sheet.add_child(sheet_column)
	var title := Label.new()
	title.name = "OfferTitle"
	title.text = tr("Airline Contracts — Accept to schedule flights")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(title, &"HudTitle")
	sheet_column.add_child(title)
	_intro_banner = PanelContainer.new()
	_intro_banner.name = "OfferIntroBanner"
	_intro_banner.theme_type_variation = &"HudTopCard"
	_intro_banner.visible = false
	_intro_label = Label.new()
	_intro_label.name = "OfferIntroLabel"
	_intro_label.text = tr(
		"Accept airlines that fit your gates. Each signed contract sends flights every day."
	)
	_intro_label.theme_type_variation = &"HudSmall"
	_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_banner.add_child(_intro_label)
	sheet_column.add_child(_intro_banner)
	_scroll.name = "OfferCardsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_column.add_child(_scroll)
	_sections.name = "OfferSections"
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 8)
	_sections.sort_children.connect(_fit_scroll_height)
	_scroll.add_child(_sections)
	_charter_cards.name = "CharterCards"
	_charter_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_charter_cards.add_theme_constant_override("separation", 6)
	_charter_cards.visible = false
	_sections.add_child(_charter_cards)
	_daily_row.name = "OfferCards"
	_daily_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_row.add_theme_constant_override("separation", 8)
	_sections.add_child(_daily_row)
	var footer := HBoxContainer.new()
	footer.name = "OfferFooter"
	footer.add_theme_constant_override("separation", 8)
	sheet_column.add_child(footer)
	_message.name = "OfferMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(_message, &"HudSmall")
	footer.add_child(_message)
	_pass_button.name = "PassButton"
	_pass_button.text = tr("Pass today's offers")
	_pass_button.custom_minimum_size = Vector2(0.0, 36.0)
	_pass_button.focus_mode = Control.FOCUS_NONE
	_pass_button.theme_type_variation = &"HudButtonCoral"
	_pass_button.pressed.connect(_on_pass)
	footer.add_child(_pass_button)
	_discard_layer.name = "OfferDiscardLayer"
	_discard_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_discard_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_layer.clip_contents = false
	_sheet.add_child(_discard_layer)


func _fit_scroll_height() -> void:
	if _sheet == null or _scroll == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_h := viewport.get_visible_rect().size.y
	if viewport_h <= 0.0:
		return
	var extent := TopRow.sheet_extent(
		viewport.get_visible_rect().size.x, TopRow.sheet_min_left(get_tree()), WIDE_SHEET_W
	)
	if not is_equal_approx(_sheet.custom_minimum_size.x, extent.y):
		_sheet.custom_minimum_size.x = extent.y
		_sheet.size.x = extent.y
		TopRow.place_sheet(_sheet, self, WIDE_SHEET_W)
	if _animating_discard:
		return
	var content_h := _sections.get_combined_minimum_size().y
	var chrome := _sheet.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var bottom_clear := float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	var max_scroll_h := maxf(0.0, viewport_h - TopRow.SHEET_TOP - bottom_clear - chrome)
	var wanted := minf(content_h, max_scroll_h)
	var size_changed := (
		not is_equal_approx(_scroll.custom_minimum_size.y, wanted)
		or not is_equal_approx(_sheet.offset_left, extent.x)
		or not is_equal_approx(_sheet.size.x, extent.y)
	)
	if size_changed:
		_scroll.custom_minimum_size.y = wanted
		TopRow.place_sheet(_sheet, self, WIDE_SHEET_W)
		_sheet.custom_minimum_size.x = extent.y
		_sheet.reset_size()


func _on_toggle() -> void:
	if _sheet.visible:
		close()
	else:
		open()


## A load replaces the world the sheet was opened over, so it closes.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	close()
	_on_snapshot_loaded()
	# The ending notice is not saved. The rail's own reset (reset_done) posts a
	# warning still due once, whichever of the two handlers runs first, so this
	# only drops the ending and lets the warning follow the loaded rating.
	var rail := _rail()
	if rail != null:
		rail.drop_notice(ENDED_KEY)
	_ended_text = ""
	_refresh_warning.call_deferred()


func _on_snapshot_loaded() -> void:
	_kill_discard_animation()
	_offers_unseen = false
	_day1_auto_pop_pending = false
	_stop_pulse()
	_was_airport_open = flights != null and flights.opened_tick >= 0
	_known_offer_ids = _open_offer_id_set()
	_sync_open_state()


func _sync_open_state() -> void:
	var open_now := flights != null and flights.opened_tick >= 0
	var became_open := open_now and not _was_airport_open
	_was_airport_open = open_now
	if _button != null:
		_button.visible = open_now
		_button.disabled = not open_now
	if not open_now:
		_offers_unseen = false
		_day1_auto_pop_pending = false
		_stop_pulse()
		if _sheet != null:
			close()
	elif (
		became_open
		and desk != null
		and not desk.board.is_loading()
		and not desk.board.open_offers().is_empty()
		and (_sheet == null or not _sheet.visible)
	):
		_known_offer_ids = _open_offer_id_set()
		_notify_fresh_offers()


func _on_airport_opened(tick: int) -> void:
	_sync_open_state()
	_refresh()
	if (
		flights != null
		and desk != null
		and desk.board != null
		and not desk.board.is_loading()
		and GameCalendar.day_of(tick, flights.epoch) == 0
		and GameCalendar.day_of(flights.tick, flights.epoch) == 0
		and not desk.board.is_day1_intro_shown()
		and not has_been_opened
	):
		_day1_auto_pop_pending = true
		_try_day1_auto_pop()


func _try_day1_auto_pop() -> void:
	if not _day1_auto_pop_pending or flights == null or desk == null or desk.board == null:
		_day1_auto_pop_pending = false
		return
	if (
		desk.board.is_day1_intro_shown()
		or has_been_opened
		or flights.opened_tick < 0
		or GameCalendar.day_of(flights.tick, flights.epoch) != 0
	):
		_day1_auto_pop_pending = false
		return
	if desk.board.open_offers().is_empty() or _any_modal_open():
		return
	_day1_auto_pop_pending = false
	open()


func _any_modal_open() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var blocked := false
	var hud := parent.get_node_or_null("PassengerHud") as PassengerHud
	if hud != null:
		var planner := hud.find_child("FlightPlanner", false, false) as FlightPlanner
		blocked = (
			hud.intro() != null
			or (hud.unlock_guide() != null and hud.unlock_guide().is_open())
			or (hud.demo_end_card != null and hud.demo_end_card.is_open())
			or (planner != null and planner.is_open())
		)
	var menu := parent.get_node_or_null("GameMenu") as GameMenu
	var incident := parent.get_node_or_null("IncidentPanel") as IncidentPanel
	var runway := parent.get_node_or_null("RunwayCard") as RunwayCard
	return (
		blocked
		or (menu != null and (menu.is_open() or menu.is_question_open()))
		or (incident != null and incident.is_open())
		or (runway != null and runway.is_open())
	)


func _on_flights_changed(_id: String) -> void:
	_sync_open_state()


func _on_tool_changed(_tool: BuildMode.Tool) -> void:
	close()


## Rebuilds the cards and the button text from the board's open offers.
func _refresh() -> void:
	var charters := desk.board.open_charters()
	var offers := desk.board.open_offers()
	if _animating_discard and offers.is_empty():
		_sync_button_and_cues(charters, offers)
		return
	_kill_discard_animation()
	for node in _card_nodes.values():
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_card_nodes.clear()
	_accept_buttons.clear()
	_decline_buttons.clear()
	_note_labels.clear()
	_refusal_labels.clear()
	_fit_labels.clear()
	_req_chips.clear()
	_fit_taxis.clear()
	_earnings_labels.clear()
	_trait_rows.clear()
	_peak_chips.clear()
	_charter_cards.visible = not charters.is_empty()
	_daily_row.visible = not offers.is_empty()
	for charter in charters:
		_add_card(charter, true)
	for offer in offers:
		_add_card(offer, false)
	if _pass_button != null:
		_pass_button.visible = not offers.is_empty()
		_pass_button.disabled = false
	_sync_button_and_cues(charters, offers)
	_say_idle()
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()
	_noted_tick = flights.tick


func _sync_button_and_cues(charters: Array[Dictionary], offers: Array[Dictionary]) -> void:
	var total := charters.size() + offers.size()
	_button.text = tr("Offers ({count})").format({"count": total})
	_offers_waiting = total > 0
	_style_button()
	_sync_fresh_offer_cue(offers)


func _open_offer_id_set() -> Dictionary:
	var ids := {}
	if desk == null or desk.board == null:
		return ids
	for offer in desk.board.open_offers():
		ids[String(offer["id"])] = true
	return ids


func _sync_fresh_offer_cue(offers: Array[Dictionary]) -> void:
	var current_ids := {}
	var has_new := false
	for offer in offers:
		var id := String(offer["id"])
		current_ids[id] = true
		if not _known_offer_ids.has(id):
			has_new = true
	_known_offer_ids = current_ids
	if desk.board.is_loading() or flights == null or flights.opened_tick < 0:
		return
	if current_ids.is_empty():
		_offers_unseen = false
		_stop_pulse()
	elif has_new and (_sheet == null or not _sheet.visible):
		_notify_fresh_offers()


func _notify_fresh_offers() -> void:
	_offers_unseen = true
	_start_pulse()
	_play_offer_chime()


func _start_pulse() -> void:
	if _button == null or not is_inside_tree():
		return
	pulsing = true
	if _pulse_tween != null and _pulse_tween.is_valid():
		return
	_button.modulate = Color.WHITE
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	(
		_pulse_tween
		. tween_property(_button, "modulate", PULSE_TINT, PULSE_HALF_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_pulse_tween
		. tween_property(_button, "modulate", Color.WHITE, PULSE_HALF_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _stop_pulse() -> void:
	pulsing = false
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	if _button != null:
		_button.modulate = Color.WHITE


func _play_offer_chime() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("GameAudio")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"offer_chime")


## The first-flight note for an offer card right now. While the airport is
## closed a contract accepted starts at the opening, which is not known yet, so
## the note names the lead its slot needs after the opening.
func _note_for(offer: Dictionary) -> String:
	if FlightContract.is_charter(offer):
		return ""
	if flights.opened_tick < 0:
		return tr("first flight {lead} after opening").format(
			{"lead": lead_text(opening_lead_ticks())}
		)
	var taxi: Array = _fit_taxis.get(offer["id"], TaxiTimes.BASE)
	return first_flight_note(offer, flights.tick, taxi, flights.epoch)


## Rewrites each card's note line for the sim's current tick, hiding it while
## there is no note.
func _refresh_notes() -> void:
	_noted_tick = flights.tick
	for id in _note_labels:
		_set_note(_note_labels[id], _note_for(desk.board.any_offer_of(id)))


func _set_note(label: Label, note: String) -> void:
	label.text = note_line(note)
	label.visible = note != ""


## Rewrites each card's fit line for the sim as it is now.
func _refresh_fits() -> void:
	_sync_open_state()
	if _animating_discard:
		return
	for id: String in _fit_labels:
		_set_fit(_fit_labels[id], desk.board.any_offer_of(id))


func _set_fit(label: Label, offer: Dictionary) -> void:
	var id := String(offer["id"])
	var assessment := FlightFit.assess(flights, OfferBoard.terms_of(offer))
	var fits := bool(assessment["fits"])
	var stand_key := String(assessment.get("stand", assessment["gate"]))
	var taxi: Array = flights.gate_taxi(stand_key) if fits else []
	_fit_taxis[id] = taxi if not taxi.is_empty() else TaxiTimes.BASE
	if _note_labels.has(id):
		_set_note(_note_labels[id], _note_for(offer))
	var reason := fit_line(assessment, offer["plane_size"])
	label.text = reason
	label.theme_type_variation = &"HudGoodText" if fits else &"HudProblemText"
	# HudGoodText is larger than the card's other small lines; both looks keep
	# the HudSmall size.
	label.add_theme_font_size_override(
		"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
	)
	var chip := _req_chips.get(id) as PanelContainer
	if chip != null:
		chip.visible = not fits
		var chip_lbl := chip.get_node_or_null("RequirementLabel") as Label
		if chip_lbl != null:
			chip_lbl.text = reason
	var accept := _accept_buttons.get(id) as Button
	if accept != null:
		accept.disabled = not fits
		accept.tooltip_text = "" if fits else reason


## Posts or drops the airlines' warning card from the rating, and words the
## button's tooltip. A card is posted again only when its words change, so a
## card the player clicked away stays away until the low-day count moves on.
func _refresh_warning() -> void:
	var rating := desk.rating
	_warning_text = ""
	if rating != null and rating.warning():
		_warning_text = warning_message(rating.low_days())
	var rail := _rail()
	if _warning_text == "":
		_ended_text = ""
		_button.tooltip_text = ""
		_warning_posted = ""
		if rail != null:
			rail.drop_notice(WARNING_KEY)
	else:
		_button.tooltip_text = (
			_warning_text if _ended_text == "" else "%s\n%s" % [_warning_text, _ended_text]
		)
		if rail != null and _warning_text != _warning_posted:
			_warning_posted = _warning_text
			_post(rail, WARNING_KEY, tr("Low airport rating"), _warning_text)
	_style_button()


func _on_contract_ended(contract: Dictionary) -> void:
	_ended_text = ended_message(contract["airline"], contract["destination"])
	var rail := _rail()
	if rail == null:
		push_warning("OfferPanel: no alert rail to tell the player: %s" % _ended_text)
	else:
		_post(rail, ENDED_KEY, tr("Contract ended"), _ended_text)
	_refresh_warning()
	_refresh_fits()


## The right rail, found through its group the first time it is needed. A rail
## other than the one the warning was posted to starts the warning again: it has
## no card, and the old rail's click dismissal does not carry over.
func _rail() -> AlertStack:
	if not is_instance_valid(alerts):
		alerts = get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack
	if alerts != null and alerts.get_instance_id() != _posted_rail:
		if (
			is_instance_valid(_watched_rail)
			and _watched_rail.reset_done.is_connected(_on_rail_reset)
		):
			_watched_rail.reset_done.disconnect(_on_rail_reset)
		_watched_rail = alerts
		_posted_rail = alerts.get_instance_id()
		_warning_posted = ""
		alerts.reset_done.connect(_on_rail_reset)
	return alerts


## The rail dropped every card (a load or a new world): the warning, if the
## rating still calls for one, goes up again.
func _on_rail_reset() -> void:
	_warning_posted = ""
	_refresh_warning()


## A coral notice that stays on the rail until clicked, with its history line.
static func _post(rail: AlertStack, key: StringName, title: String, detail: String) -> void:
	rail.post_notice(key, coral_card(key, title, detail), 0.0, title, detail)


## A rail card in the theme's HudCardCoral look (coral means a problem, decision
## 0b50e074): a title over the words, RAIL_W wide like the other cards.
static func coral_card(key: StringName, title: String, detail: String) -> PanelContainer:
	return _rail_card(&"HudCardCoral", key, title, detail)


## The same card in the theme's HudCardGreen look, the flight result card's
## (green means good news, decision 0b50e074).
static func green_card(key: StringName, title: String, detail: String) -> PanelContainer:
	return _rail_card(&"HudCardGreen", key, title, detail)


static func _rail_card(
	variation: StringName, key: StringName, title: String, detail: String
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "OfferNotice_%s" % key
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = variation
	card.custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	for part in [[title, &"HudCardName"], [detail, &"HudSmall"]]:
		var label := Label.new()
		label.text = part[0]
		label.theme_type_variation = part[1]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	return card


## Coral while the airlines warn, yellow while offers wait, else teal.
func _style_button() -> void:
	if _warning_text != "":
		_button.theme_type_variation = &"HudButtonCoral"
	elif _offers_waiting:
		_button.theme_type_variation = &"HudButtonYellow"
	else:
		_button.theme_type_variation = &"HudButtonTeal"


func _add_card(offer: Dictionary, is_charter: bool) -> void:
	var id: String = offer["id"]
	var card_box := PanelContainer.new()
	card_box.name = "Offer_%s" % id
	card_box.theme_type_variation = &"HudSubCard"
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_charter:
		card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_charter_cards if is_charter else _daily_row).add_child(card_box)
	_card_nodes[id] = card_box
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_charter:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card_box.add_child(row)
		row.add_child(texts)
		var badge := _card_label(tr("One-off charter — flies today only"), &"HudGoodText")
		badge.name = "CharterBadge_%s" % id
		badge.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		texts.add_child(badge)
	else:
		texts.add_theme_constant_override("separation", 4)
		texts.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_box.add_child(texts)
	var lines := card_lines(offer)
	texts.add_child(_card_header(offer, lines[0], not is_charter))
	texts.add_child(_card_verdict(id, offer, is_charter))
	var traits := _trait_row(offer)
	texts.add_child(traits)
	_trait_rows[id] = traits
	if is_charter:
		var when := HFlowContainer.new()
		when.name = "When_%s" % id
		when.add_theme_constant_override("h_separation", 12)
		when.add_theme_constant_override("v_separation", 2)
		texts.add_child(when)
		for i in [1, 2]:
			var part := _card_label(lines[i], &"HudSmall")
			part.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			part.autowrap_mode = TextServer.AUTOWRAP_OFF
			when.add_child(part)
		texts.add_child(_card_label(lines[3], &"HudSmall"))
	else:
		for i in range(1, lines.size()):
			texts.add_child(_card_label(lines[i], &"HudSmall"))
	var note := _card_label("", &"HudSmall")
	note.name = "Note_%s" % id
	_set_note(note, _note_for(offer))
	texts.add_child(note)
	texts.move_child(note, texts.get_child_count() - 2)
	_note_labels[id] = note
	if not is_charter:
		_add_offer_chips(texts, id, offer)
	var pitch := _card_label(route_pitch(offer), &"HudHint")
	pitch.name = "Pitch_%s" % id
	texts.add_child(pitch)
	var req_chip := _requirement_chip(id)
	texts.add_child(req_chip)
	_req_chips[id] = req_chip
	texts.add_child(_card_refusal(id))
	var accept := _card_button(tr("Accept", "button: accept an offer"), &"HudButtonGreen", id)
	accept.pressed.connect(_on_accept.bind(id))
	_accept_buttons[id] = accept
	if is_charter:
		var buttons := VBoxContainer.new()
		card_box.get_child(0).add_child(buttons)
		buttons.add_child(accept)
		var decline := _card_button(
			tr("Decline", "button: decline an offer"), &"HudButtonCoral", id
		)
		decline.pressed.connect(_on_decline.bind(id))
		buttons.add_child(decline)
		_decline_buttons[id] = decline
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(spacer)
		accept.custom_minimum_size = Vector2(0.0, 36.0)
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_child(accept)
	_set_fit(_fit_labels[id], offer)


func _add_offer_chips(texts: VBoxContainer, id: String, offer: Dictionary) -> void:
	var is_hub := bool(offer.get(OfferBoard.HUB_KEY, false))
	var is_peak := OfferBoard.is_peak_minute(int(offer["departure_minute"]))
	if not is_hub and not is_peak:
		return
	var chips := HFlowContainer.new()
	chips.name = "Chips_%s" % id
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	if is_hub:
		chips.add_child(_hub_badge(offer))
	if is_peak:
		var chip := _peak_chip(offer)
		chips.add_child(chip)
		_peak_chips[id] = chip
	texts.add_child(chips)


func _card_header(offer: Dictionary, title_text: String, compact: bool) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header_%s" % offer["id"]
	header.add_theme_constant_override("separation", 6 if compact else 8)
	header.add_child(_airline_badge(offer))
	var title_label := _card_label(title_text, &"HudTitle")
	if compact:
		title_label.add_theme_font_size_override("font_size", HudLayout.TITLE)
	header.add_child(title_label)
	return header


func _card_verdict(id: String, offer: Dictionary, is_charter: bool) -> Container:
	var verdict: Container = HBoxContainer.new() if is_charter else VBoxContainer.new()
	verdict.name = "Verdict_%s" % id
	if not is_charter:
		verdict.add_theme_constant_override("separation", 2)
	var fit := _card_label("", &"HudSmall")
	fit.name = "Fit_%s" % id
	verdict.add_child(fit)
	_fit_labels[id] = fit
	var earnings := _card_label(earnings_text(offer), &"HudSmall")
	earnings.name = "Earnings_%s" % id
	if is_charter:
		earnings.size_flags_horizontal = Control.SIZE_SHRINK_END
		earnings.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	verdict.add_child(earnings)
	_earnings_labels[id] = earnings
	return verdict


func _card_refusal(id: String) -> Label:
	var refusal := Label.new()
	refusal.name = "Refusal_%s" % id
	refusal.visible = false
	refusal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(refusal, &"HudProblemText")
	_refusal_labels[id] = refusal
	return refusal


## The trait line under the verdict row (OfferTraits.card_labels): the upside in
## HudGoodText and the downside in HudProblemText, each with its numbers as a
## tooltip; a plain offer shows PLAIN_LABEL in HudHint and no downside. An offer
## from a Bronze/Silver/Gold airline ends the line with its tier badge in HudGoodText.
func _trait_row(offer: Dictionary) -> HFlowContainer:
	if FlightContract.is_charter(offer):
		var charter_row := HFlowContainer.new()
		charter_row.name = "Traits_%s" % offer["id"]
		var badge := Label.new()
		badge.name = "CharterTerms"
		badge.text = tr("No exit fee")
		badge.tooltip_text = tr("Flies once today only; no exit fee or daily commitment.")
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		badge.theme_type_variation = &"HudGoodText"
		badge.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		charter_row.add_child(badge)
		return charter_row
	var traits: Dictionary = offer[FlightContract.TRAITS_KEY]
	var plain := OfferTraits.is_plain(traits)
	var tier := int(
		offer.get(OfferBoard.LOYAL_TIER_KEY, 1 if offer.get(OfferBoard.LOYAL_KEY, false) else 0)
	)
	var loyal_text := ""
	var loyal_tip := ""
	match tier:
		OfferBoard.LOYALTY_TIER_BRONZE:
			loyal_text = tr("Bronze +5%")
			loyal_tip = tr("Bronze loyalty: this airline's offers pay 5% more.")
		OfferBoard.LOYALTY_TIER_SILVER:
			loyal_text = tr("Silver +10%")
			loyal_tip = tr("Silver loyalty: this airline's offers pay 10% more.")
		OfferBoard.LOYALTY_TIER_GOLD:
			loyal_text = tr("Gold +15%")
			loyal_tip = (
				tr(
					# gdlint:ignore = max-line-length
					"Gold loyalty: this airline's offers pay 15% more and unlock Hub Contracts at {percent}%+ quality."
				)
				. format({"percent": AirportRating.quality_percent(OfferBoard.HUB_MIN_STARS)})
			)
	var labels := Array(OfferTraits.card_labels(traits)) + [loyal_text]
	var tips := Array(OfferTraits.card_tips(traits)) + [loyal_tip]
	var shown: Array[bool] = [true, labels[1] != "", tier > OfferBoard.LOYALTY_TIER_NONE]
	var row := HFlowContainer.new()
	row.name = "Traits_%s" % offer["id"]
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 2)
	var variations: Array[StringName] = [
		&"HudHint" if plain else &"HudGoodText", &"HudProblemText", &"HudGoodText"
	]
	for i in 3:
		var label := Label.new()
		label.name = ["Up", "Down", "Loyal"][i]
		label.text = labels[i]
		label.tooltip_text = tips[i]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.visible = shown[i]
		label.theme_type_variation = variations[i]
		label.add_theme_font_size_override(
			"font_size", BuildMenu.HUD_THEME.get_font_size("font_size", &"HudSmall")
		)
		row.add_child(label)
	return row


func _airline_badge(offer: Dictionary) -> PanelContainer:
	var airline := String(offer.get("airline", ""))
	var badge := PanelContainer.new()
	badge.name = "AirlineBadge_%s" % offer["id"]
	badge.custom_minimum_size = Vector2(36.0, 26.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = airline_color(airline)
	style.border_color = BADGE_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("panel", style)
	var code := Label.new()
	code.name = "Monogram"
	code.text = airline_code(airline)
	code.set_meta(BADGE_META, true)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(code, &"HudCardName")
	badge.add_child(code)
	return badge


func _hub_badge(offer: Dictionary) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "HubBadge_%s" % offer["id"]
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	badge.tooltip_text = tr(
		"Gold Hub Contract: +10% prestige fee bonus and +1 low-rating grace day."
	)
	var style := StyleBoxFlat.new()
	style.bg_color = HUB_CHIP_FILL
	style.border_color = HUB_CHIP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "HubLabel"
	label.text = tr("Hub Contract")
	label.theme_type_variation = &"HudSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BADGE_BORDER)
	badge.add_child(label)
	return badge


func _peak_chip(offer: Dictionary) -> PanelContainer:
	var minute := int(offer["departure_minute"])
	var chip := PanelContainer.new()
	chip.name = "PeakChip_%s" % offer["id"]
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = tr("Peak rush wave: +15% passenger fee included.")
	var style := StyleBoxFlat.new()
	style.bg_color = PEAK_CHIP_FILL
	style.border_color = PEAK_CHIP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "PeakLabel"
	label.text = _peak_chip_text(minute)
	label.theme_type_variation = &"HudSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BADGE_BORDER)
	chip.add_child(label)
	return chip


func _requirement_chip(id: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "RequirementChip_%s" % id
	chip.visible = false
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = REQ_CHIP_FILL
	style.border_color = REQ_CHIP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "RequirementLabel"
	label.set_meta(BADGE_META, true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = &"HudSmall"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", BADGE_BORDER)
	chip.add_child(label)
	return chip


func _card_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(label, variation)
	return label


func _card_button(text: String, variation: StringName, id: String) -> Button:
	var button := Button.new()
	button.name = "%s_%s" % [text, id]
	button.text = text
	button.custom_minimum_size = Vector2(110.0, 36.0)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = variation
	return button


func _on_accept(id: String) -> void:
	if _animating_discard:
		return
	var offer := desk.board.any_offer_of(id)
	if offer.is_empty():
		return
	var problem := flights.accept_problem(OfferBoard.terms_of(offer))
	if problem != "":
		_refuse(
			id,
			tr("Can't accept {airline} to {destination}: {reason}").format(
				{
					"airline": offer["airline"],
					"destination": offer["destination"],
					"reason": _in_words(problem)
				}
			)
		)
		return
	var is_charter := FlightContract.is_charter(offer)
	var daily_ids := _current_daily_ids() if not is_charter else ([] as Array[String])
	var should_animate := (
		not is_charter
		and _sheet != null
		and _sheet.visible
		and is_inside_tree()
		and daily_ids.has(id)
	)
	var note := _note_for(offer)
	if should_animate:
		_prepare_discard_animation(daily_ids)
	if desk.board.accept(id, flights):
		var named := {"airline": offer["airline"], "destination": offer["destination"]}
		if note == "":
			_say(tr("Accepted {airline} to {destination}").format(named))
		else:
			named["note"] = note
			_say(tr("Accepted {airline} to {destination}, {note}").format(named))
		if should_animate:
			_run_discard_animation(daily_ids, id)
	elif should_animate:
		_kill_discard_animation()
		_refresh()


func _on_pass() -> void:
	if _animating_discard:
		return
	var daily_ids := _current_daily_ids()
	if daily_ids.is_empty():
		return
	var should_animate := _sheet != null and _sheet.visible and is_inside_tree()
	if should_animate:
		_prepare_discard_animation(daily_ids)
	if desk.board.pass_open_offers():
		_say(tr("Passed today's offers. New offers arrive at midnight."))
		if should_animate:
			_run_discard_animation(daily_ids, "")
	elif should_animate:
		_kill_discard_animation()
		_refresh()


func _current_daily_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _card_nodes:
		var card_node := _card_nodes[id] as Control
		if card_node != null and card_node.get_parent() == _daily_row:
			ids.append(id)
	return ids


func _prepare_discard_animation(daily_ids: Array[String]) -> void:
	_kill_discard_animation()
	_animating_discard = true
	if _pass_button != null:
		_pass_button.disabled = true
	for id: String in daily_ids:
		var btn := _accept_buttons.get(id) as Button
		if btn != null:
			btn.disabled = true


func _run_discard_animation(daily_ids: Array[String], chosen_id: String) -> void:
	var row_size := _daily_row.size
	if row_size.x <= 0.0 or row_size.y <= 0.0:
		row_size = _daily_row.get_combined_minimum_size()
	var rects: Array[Rect2] = []
	for id: String in daily_ids:
		var card_node := _card_nodes[id] as Control
		var csize := card_node.size
		if csize.x <= 0.0 or csize.y <= 0.0:
			csize = card_node.get_combined_minimum_size()
		rects.append(Rect2(card_node.global_position - _sheet.global_position, csize))
	for i in daily_ids.size():
		var card_node := _card_nodes[daily_ids[i]] as Control
		_daily_row.remove_child(card_node)
		_discard_layer.add_child(card_node)
		card_node.position = rects[i].position
		card_node.size = rects[i].size
		card_node.pivot_offset = rects[i].size * 0.5
		card_node.z_index = 11 if daily_ids[i] == chosen_id else 10
		_discard_nodes.append(card_node)
	_discard_spacer = Control.new()
	_discard_spacer.custom_minimum_size = row_size
	_discard_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_row.add_child(_discard_spacer)
	_discard_tween = create_tween()
	_discard_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_discard_tween.set_parallel(true)
	var chosen_idx := daily_ids.find(chosen_id)
	for i in daily_ids.size():
		var card_node := _card_nodes[daily_ids[i]] as Control
		if daily_ids[i] == chosen_id:
			(
				_discard_tween
				. tween_property(card_node, "scale", Vector2(1.05, 1.05), 0.14)
				. set_trans(Tween.TRANS_BACK)
				. set_ease(Tween.EASE_OUT)
			)
			_discard_tween.tween_property(card_node, "modulate", CHOSEN_TINT, 0.14)
			_discard_tween.tween_property(card_node, "scale", Vector2(0.95, 0.95), 0.14).set_delay(
				0.26
			)
			_discard_tween.tween_property(card_node, "modulate:a", 0.0, 0.14).set_delay(0.26)
			continue
		var dir := -1.0 if i < chosen_idx else 1.0
		if chosen_idx < 0:
			dir = -1.0 if i == 0 else (1.0 if i >= daily_ids.size() - 1 else 0.55)
		(
			_discard_tween
			. tween_property(card_node, "rotation", dir * DISCARD_ROTATE_RAD, DISCARD_DURATION_S)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
		(
			_discard_tween
			. tween_property(card_node, "scale", DISCARD_SCALE, DISCARD_DURATION_S)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
		(
			_discard_tween
			. tween_property(
				card_node,
				"position",
				card_node.position + Vector2(dir * DISCARD_OFFSET.x, DISCARD_OFFSET.y),
				DISCARD_DURATION_S
			)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN)
		)
		(
			_discard_tween
			. tween_property(card_node, "modulate:a", 0.0, DISCARD_DURATION_S * 0.95)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
	_discard_tween.finished.connect(_on_discard_animation_finished)


func _on_discard_animation_finished() -> void:
	_kill_discard_animation()
	if desk != null and flights != null:
		_refresh()


func _kill_discard_animation() -> void:
	_animating_discard = false
	if _discard_tween != null:
		_discard_tween.kill()
		_discard_tween = null
	if _discard_spacer != null:
		if is_instance_valid(_discard_spacer):
			if _discard_spacer.get_parent() != null:
				_discard_spacer.get_parent().remove_child(_discard_spacer)
			_discard_spacer.queue_free()
		_discard_spacer = null
	for node in _discard_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_discard_nodes.clear()


func _has_accepted_today() -> bool:
	if desk == null or desk.board == null or flights == null:
		return false
	var day := GameCalendar.day_of(flights.tick, flights.epoch)
	return desk.board.has_accepted_on_day(day)


## FlightSim's refusal `problem` for the player: a clash names what it ran
## into by time, airline and destination, not by id. A clash in a shape
## FlightLabel cannot read is warned about and shown without ids. Any other
## refusal is shown as the sim wrote it.
func _in_words(problem: String) -> String:
	var clash := FlightLabel.clash_sentence(flights, problem)
	if clash != "":
		return clash
	if problem.begins_with("contract ") and problem.contains(" clashes with "):
		push_warning("OfferPanel: unreadable clash refusal from FlightSim: %s" % problem)
		return tr("it clashes with another flight")
	return problem


## What the sheet says when nothing was just done: PICKED_TODAY_TEXT after
## picking today's route, EMPTY_TEXT otherwise when no offer is open, else "".
func _say_idle() -> void:
	if not desk.board.open_offers().is_empty() or not desk.board.open_charters().is_empty():
		_say("")
	elif _has_accepted_today():
		_say(tr("Picked today's route — new offers tomorrow."))
	else:
		_say(tr("No offers right now. New offers arrive at midnight."))


## Shows `text` under the cards, hiding the line when it is empty.
func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""
	_fit_scroll_height()


## Shows a refusal on the offer's own card, in place of any refusal on another.
func _refuse(id: String, text: String) -> void:
	_say("")
	_clear_refusals()
	var label: Label = _refusal_labels[id]
	label.text = text
	label.visible = true
	_fit_scroll_height()
	_fit_scroll_height.call_deferred()


## Empties every card's refusal line.
func _clear_refusals() -> void:
	for id: String in _refusal_labels:
		(_refusal_labels[id] as Label).text = ""
		(_refusal_labels[id] as Label).visible = false


func _on_decline(id: String) -> void:
	if _animating_discard:
		return
	desk.board.decline(id)


func _style_label(label: Label, variation: StringName) -> void:
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
