class_name IncidentPanel
extends Node
## The panel a major incident comes in (decisions daily-incidents-small-ones-
## just-happen-with-a-card-and-a-cau and daily-incidents-technical-design-
## incidentdirector-shared-clo): the IntroDialogue's portrait and box, over the
## game, with the clock paused while it is open. Two forms:
##
## - An announcement: the words of the incident and Continue, which only closes
##   it. The director is told (acknowledge) as it opens, and keeps it as shown.
## - An offer: the words, the reward and what happens if it fails, and Accept
##   or Decline, which go to the director (answer). No key chooses.
##
## Only majors come here; a minor never pauses the game and shows as a card
## (IncidentCards). The panel takes the clock's exclusive turn
## (clock.holds.take_turn), so it opens at once when no other dialog has the
## turn, and otherwise when the unlock dialog or the Offers sheet ahead of it
## closes, in the order they asked. The hold does not give way to the player,
## as the footer says. Majors that arrive together show one after the other.
##
## A load replaces the world: the clock comes back paused at 1x and every hold
## is gone (decision loading-a-save-always-comes-back-paused-at-1x-speed-with-
## hin). The open panel ends, and whatever the director still has pending (an
## offer not answered, an announcement that never reached the screen) is shown
## again, so a player cannot save and load their way out of an offer, while an
## announcement that was up, closed or not, stays shown. Nothing is saved here:
## the director's states and its shown flag are the memory.
##
## The words come from IncidentCatalogue.panel_copy, with the numbers of the
## incident's own plan put in (IncidentCopy.fill), so a card says the counts and
## times that will happen. A major without title and body, or an offer without
## reward and failure, is not shown and a warning says so.

## The panel opened or closed. PassengerHud can hold the camera still meanwhile.
signal dialog_changed(open: bool)

## The panel's canvas layer: with the intro and the unlock dialog, over the HUD.
const LAYER := 10
const BOX_HEIGHT := 340.0
const MAX_BEAT_WORDS := 18
const ICON_COIN := preload("res://assets/ui/icons/coin.svg")
const ICON_SERVICES := preload("res://assets/ui/icons/services.svg")
## The English msgids of the two footers. Tests compare against them; the dialog
## itself says tr() of the same literals, because the POT extractor reads only literals.
const ANNOUNCE_FOOTER := "The clock goes on when you close this."
const OFFER_FOOTER := "The clock stays paused until you choose."

## body_for is static and tr() is not, so its words go through this instance.
static var _translator := RefCounted.new()

@export var director: IncidentDirector
@export var clock: SimClock
## Optional: a load ends an open panel and shows what is still pending.
@export var save_game: SaveGame

## The words of a kind: kind -> {"title", "body", "reward", "failure"}. Tests
## replace it.
var copy_for: Callable = IncidentCatalogue.panel_copy

var _layer: CanvasLayer
var _dialog: IntroDialogue
## The incident the open dialog is for.
var _shown_id := 0
## The panel's hold on the clock, from asking for the turn until it closes.
var _hold := ClockHolds.NONE
## The incidents waiting for their turn, oldest first.
var _queue: Array[int] = []


func _ready() -> void:
	name = "IncidentPanel"
	if director == null:
		push_error("IncidentPanel: no director set, so no major incident is shown")
		return
	director.major_presented.connect(_on_presented)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	_enqueue_pending()


## A panel that leaves the tree while open must not leave the game paused (the
## holds also end a hold whose owner leaves).
func _exit_tree() -> void:
	_release_clock()


func is_open() -> bool:
	return _dialog != null


## The open dialog, or null.
func dialog() -> IntroDialogue:
	return _dialog


## Closes any open or waiting incident dialog and releases its clock hold.
func close_for_modal() -> void:
	var was_open := _dialog != null
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)


## The concise 1-2 beat text, scannable Reward / Risk chips with full-sentence
## tooltips, and clock footer for one major's copy.
static func parts_for(copy: Dictionary, offer: bool) -> Dictionary:
	var raw_body := str(copy.get("body", ""))
	var beats: Array[String] = []
	var chips: Array[Dictionary] = []
	var reward := ""
	var failure := ""
	if offer:
		beats = _split_beats(raw_body)
		reward = str(copy.get("reward", ""))
		failure = str(copy.get("failure", ""))
	else:
		var lines := raw_body.split("\n", false)
		if lines.size() == 3:
			beats = _split_beats(lines[0])
			reward = lines[1]
			failure = lines[2]
		else:
			beats = _split_beats(raw_body)
	if reward != "":
		chips.append(_reward_chip(reward))
	if failure != "":
		chips.append(_failure_chip(failure))
	var footer := (
		_translator.tr("The clock stays paused until you choose.")
		if offer
		else _translator.tr("The clock goes on when you close this.")
	)
	return {"beats": beats, "chips": chips, "footer": footer}


static func _reward_chip(reward: String) -> Dictionary:
	return {
		"icon": ICON_COIN,
		"label": _short_reward_label(reward),
		"tint": Color(0.22, 0.58, 0.34, 1.0),
		"tooltip": reward,
	}


static func _failure_chip(failure: String) -> Dictionary:
	return {
		"icon": ICON_SERVICES,
		"label": _short_failure_label(failure),
		"tint": Color(0.76, 0.28, 0.24, 1.0),
		"tooltip": failure,
	}


static func _short_reward_label(sentence: String) -> String:
	var money_re := RegEx.create_from_string("(\\d[\\d,]*)\\s+money")
	var money_match := money_re.search(sentence)
	if money_match != null:
		return _translator.tr("Reward: +{amount} money").format(
			{"amount": money_match.get_string(1)}
		)
	var lower := sentence.to_lower()
	if lower.find("usual fee") != -1 or lower.find("extra passenger") != -1:
		return _translator.tr("Reward: Extra fees")
	var body := _strip_prefix(sentence, "reward:")
	return _translator.tr("Reward: {summary}").format({"summary": _head_words(body, 2)})


static func _short_failure_label(sentence: String) -> String:
	var lower := sentence.to_lower()
	if lower.find("half a star") != -1:
		return _translator.tr("Risk: -0.5 star")
	var star_re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s+(stars?)")
	var star_match := star_re.search(sentence)
	if star_match != null:
		return _translator.tr("Risk: -{amount} {unit}").format(
			{"amount": star_match.get_string(1), "unit": star_match.get_string(2)}
		)
	if lower.find("queues grow") != -1:
		return _translator.tr("Risk: Longer queues")
	if lower.find("check-in") != -1 or lower.find("extra passengers") != -1:
		return _translator.tr("Risk: Extra queues")
	var body := _strip_prefix(sentence, "if it fails:")
	return _translator.tr("Risk: {summary}").format({"summary": _head_words(body, 2)})


static func _strip_prefix(sentence: String, prefix_lower: String) -> String:
	var clean := sentence.strip_edges()
	if clean.to_lower().begins_with(prefix_lower):
		clean = clean.substr(prefix_lower.length()).strip_edges()
	return clean


static func _head_words(text: String, max_words: int) -> String:
	var words := text.strip_edges().split(" ", false)
	var picked: Array[String] = []
	for i in mini(max_words, words.size()):
		picked.append(words[i].trim_suffix(".").trim_suffix(",").trim_suffix(";"))
	return " ".join(PackedStringArray(picked))


static func _word_count(text: String) -> int:
	return text.strip_edges().split(" ", false).size()


static func _split_sentences(text: String) -> Array[String]:
	var out: Array[String] = []
	var start := 0
	var n := text.length()
	var i := 0
	while i < n - 1:
		var ch := text[i]
		if (ch == "." or ch == "!" or ch == "?") and text[i + 1] == " ":
			out.append(text.substr(start, i - start + 1).strip_edges())
			i += 2
			start = i
			continue
		i += 1
	var tail := text.substr(start).strip_edges()
	if tail != "":
		out.append(tail)
	return out


static func _split_beats(text: String) -> Array[String]:
	var clean := text.strip_edges()
	if clean == "":
		return []
	var sentences := _split_sentences(clean)
	if sentences.size() <= 1:
		if _word_count(clean) > MAX_BEAT_WORDS and clean.find(": ") != -1:
			var colon := clean.find(": ")
			return [clean.substr(0, colon + 1).strip_edges(), clean.substr(colon + 2).strip_edges()]
		return [clean]
	if sentences.size() == 2:
		if _word_count(clean) <= MAX_BEAT_WORDS:
			return [clean]
		if _word_count(sentences[1]) > MAX_BEAT_WORDS and sentences[1].find(": ") != -1:
			var colon := sentences[1].find(": ")
			var lead := sentences[0] + " " + sentences[1].substr(0, colon + 1)
			if _word_count(lead) <= MAX_BEAT_WORDS:
				return [lead, sentences[1].substr(colon + 2).strip_edges()]
		return [sentences[0], sentences[1]]
	@warning_ignore("integer_division")
	var mid := (sentences.size() + 1) / 2
	var first := " ".join(PackedStringArray(sentences.slice(0, mid)))
	var second := " ".join(PackedStringArray(sentences.slice(mid)))
	return [first, second]


## The panel's text for one major's copy.
static func body_for(copy: Dictionary, offer: bool) -> String:
	var lines: Array[String] = [copy["body"]]
	if offer:
		lines.append(copy["reward"])
		lines.append(copy["failure"])
		lines.append(_translator.tr("The clock stays paused until you choose."))
	else:
		lines.append(_translator.tr("The clock goes on when you close this."))
	return "\n".join(lines)


func _on_presented(incident: Dictionary) -> void:
	_enqueue(incident["id"])


func _enqueue_pending() -> void:
	for incident in director.pending_presentation():
		_enqueue(incident["id"])


func _enqueue(id: int) -> void:
	if id == _shown_id or _queue.has(id):
		return
	_queue.append(id)
	_request_turn()


## Asks the clock for the exclusive turn unless the panel already holds a place
## in the line or has a dialog open. Without a clock the dialog shows at once.
func _request_turn() -> void:
	if _dialog != null or _queue.is_empty():
		return
	if clock == null:
		_on_turn()
		return
	if clock.holds.has(_hold):
		return
	_hold = clock.holds.take_turn(self, _on_turn)
	# The turn may have run inside take_turn, before _hold was set.
	_settle()


## The turn has come: shows the first queued major that is still pending.
func _on_turn() -> void:
	while not _queue.is_empty():
		var incident := _pending(_queue.pop_front())
		if not incident.is_empty() and _show(incident):
			return
	_settle()


## Gives the turn back when nothing is open and nothing waits.
func _settle() -> void:
	if _dialog == null and _queue.is_empty():
		_release_clock()


## The director's pending record of incident `id`, or {} when it was dealt with.
func _pending(id: int) -> Dictionary:
	for incident in director.pending_presentation():
		if incident["id"] == id:
			return incident
	return {}


func _show(incident: Dictionary) -> bool:
	var offer: bool = incident["state"] == IncidentCatalogue.OFFERED
	# Worded by the clock as the dialog opens: a queued offer may open after midnight.
	var now: int = clock.tick if clock != null else incident["fire_tick"]
	var copy := IncidentCopy.fill(
		copy_for.call(incident["kind"]), incident, now, SimClock.epoch_of(clock)
	)
	if not _copy_ok(copy, offer):
		push_warning(
			"IncidentPanel: no words for %s incident %d" % [incident["kind"], incident["id"]]
		)
		return false
	_shown_id = incident["id"]
	_layer = CanvasLayer.new()
	_layer.name = "IncidentLayer"
	_layer.layer = LAYER
	var parts := parts_for(copy, offer)
	_dialog = IntroDialogue.new(
		copy["title"],
		"\n".join(parts["beats"]),
		BOX_HEIGHT,
		offer,
		IntroDialogue.Speaker.TERMINAL_MANAGER,
		{"beats": parts["beats"], "chips": parts["chips"], "footer": parts["footer"]}
	)
	_layer.add_child(_dialog)
	add_child(_layer)
	if offer:
		_dialog.chosen.connect(_on_chosen.bind(_shown_id))
	else:
		# Shown from the moment it is up, not when Continue closes it: a save
		# taken meanwhile must not show it again (the ruling: an announcement
		# already shown is dropped on a load).
		director.acknowledge(_shown_id)
	# Each close names its own layer, so a replaced dialog's layer leaving the
	# tree a frame later cannot close the dialog that replaced it.
	var close := _close.bind(_layer)
	_dialog.dismissed.connect(close)
	_dialog.tree_exiting.connect(close)
	_layer.tree_exiting.connect(close)
	dialog_changed.emit(true)
	return true


static func _copy_ok(copy: Dictionary, offer: bool) -> bool:
	var keys: Array[String] = ["title", "body"]
	if offer:
		keys.append_array(["reward", "failure"])
	for key in keys:
		if str(copy.get(key, "")) == "":
			return false
	return true


func _on_chosen(accepted: bool, id: int) -> void:
	director.answer(id, accepted)


## Closes the dialog shown on `layer`; a layer that is no longer the current
## one (replaced, or already closed) closes nothing. The next major, if any,
## asks for a turn behind whatever is already waiting.
func _close(layer: CanvasLayer) -> void:
	if _dialog == null or layer != _layer:
		return
	_free_dialog()
	var token := _hold
	_hold = ClockHolds.NONE
	if is_instance_valid(clock):
		clock.holds.release(token)
	dialog_changed.emit(false)
	_request_turn()


## A load replaced the world, clock included: SaveGame.load_world() leaves it
## paused at 1x before it emits `loaded`, and installing the clock dropped every
## hold. The panel ends and what is still pending shows again.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	var was_open := _dialog != null
	_free_dialog()
	_release_clock()
	if was_open:
		dialog_changed.emit(false)
	_enqueue_pending()


func _free_dialog() -> void:
	var layer := _layer
	_layer = null
	_dialog = null
	_shown_id = 0
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


## Ends the panel's hold, waiting or shown, and forgets the queue. Nothing is
## restored: with no hold left, the player's own pause and speed apply.
func _release_clock() -> void:
	_queue.clear()
	if is_instance_valid(clock):
		clock.holds.release(_hold)
	_hold = ClockHolds.NONE
