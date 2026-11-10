class_name AlertBoard
extends RefCounted
## The rule behind the alert cards (HUD 1/7, decision hud-steal-list-self-
## clearing-alert-cards-money-hover-departu): which cards are up, and the
## history of every card that came up. It holds no UI and reads no sim; it is
## told, on each update, every cause that is true right now.
##
## A cause is a Dictionary: key (StringName, one card per key), title, detail,
## targets (Array of world points the card's click goes to), show_after and
## clear_after (ticks). A card comes up once its cause has been true for
## show_after ticks in a row and clears itself once the cause has been gone for
## clear_after ticks in a row, so a cause that flickers (a queue one short for a
## tick) neither blinks the card nor fills the history. While a card is up its
## detail and targets follow the cause. Alerts are never saved: a load or a new
## world calls reset().

## How many history entries are kept, newest first.
const HISTORY_CAP := 30

## Goes up by one whenever an update changed what a card or the history shows.
var revision := 0

## Key -> the card's alert (the cause's fields, raised_tick and its history entry).
var _active: Dictionary = {}
## Keys of the cards up, in the order they came up.
var _order: Array[StringName] = []
## Key -> the first tick of the current unbroken run its cause was true, for a
## cause waiting out show_after.
var _pending: Dictionary = {}
## Key -> the first tick its card's cause was gone, while the card waits out
## clear_after.
var _missing: Dictionary = {}
## Oldest first.
var _history: Array[Dictionary] = []


## Takes the causes true at `tick` and raises, updates and clears cards. A key
## named twice keeps its first cause. True when anything shown changed.
func update(causes: Array[Dictionary], tick: int) -> bool:
	var changed := false
	var seen := {}
	for cause in causes:
		var key: StringName = cause["key"]
		if seen.has(key):
			continue
		seen[key] = true
		_missing.erase(key)
		if _active.has(key):
			changed = _follow(key, cause) or changed
			continue
		var since: int = _pending.get(key, tick)
		_pending[key] = since
		if tick - since >= int(cause.get("show_after", 0)):
			_raise(cause, tick)
			changed = true
	for key: StringName in _pending.keys():
		if not seen.has(key) or _active.has(key):
			_pending.erase(key)
	for key in _order.duplicate():
		if seen.has(key):
			continue
		var gone: int = _missing.get(key, tick)
		_missing[key] = gone
		if tick - gone >= int(_active[key].get("clear_after", 0)):
			_clear(key, tick)
			changed = true
	if changed:
		revision += 1
	return changed


## The cards up, in the order they came up.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in _order:
		out.append(_active[key])
	return out


## The alert of the card up for `key`, or an empty Dictionary.
func alert(key: StringName) -> Dictionary:
	return _active.get(key, {})


## Every card that came up and every notice (note()), newest first: key,
## title, detail (as it read when it came up), raised_tick and cleared_tick (-1
## while it is still up, and for a notice). Copies.
func history() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_history.size() - 1, -1, -1):
		out.append(_history[i].duplicate())
	return out


## Puts a notice in the history at `tick`: a card the rail holds itself (the
## flight result), which has no cause and no clear tick. Its entry has
## "notice" true and cleared_tick -1.
func note(key: StringName, title: String, detail: String, tick: int) -> void:
	_add_history(
		{
			"key": key,
			"title": title,
			"detail": detail,
			"raised_tick": tick,
			"cleared_tick": -1,
			"notice": true,
		}
	)
	revision += 1


## Drops every card, wait and history entry.
func reset() -> void:
	_active.clear()
	_order.clear()
	_pending.clear()
	_missing.clear()
	_history.clear()
	revision += 1


func _raise(cause: Dictionary, tick: int) -> void:
	var key: StringName = cause["key"]
	var entry := {
		"key": key,
		"title": cause["title"],
		"detail": cause["detail"],
		"raised_tick": tick,
		"cleared_tick": -1,
	}
	_add_history(entry)
	var alert := cause.duplicate()
	alert["raised_tick"] = tick
	alert["entry"] = entry
	_active[key] = alert
	_order.append(key)
	_pending.erase(key)


func _add_history(entry: Dictionary) -> void:
	_history.append(entry)
	if _history.size() > HISTORY_CAP:
		_history.pop_front()


## Takes the cause's current words and targets for the card up; true when its
## words changed.
func _follow(key: StringName, cause: Dictionary) -> bool:
	var alert: Dictionary = _active[key]
	var changed: bool = alert["title"] != cause["title"] or alert["detail"] != cause["detail"]
	for field in ["title", "detail", "targets", "clear_after"]:
		if cause.has(field):
			alert[field] = cause[field]
	return changed


func _clear(key: StringName, tick: int) -> void:
	var entry: Dictionary = _active[key]["entry"]
	entry["cleared_tick"] = tick
	_active.erase(key)
	_order.erase(key)
	_missing.erase(key)
