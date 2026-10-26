class_name PlaytestAnomalies
extends RefCounted
## The open anomalies of a playtest, keyed "<kind>:<subject>". Each check pass
## hands update() every anomaly that is true right now; one that was not open
## before is raised, one that is open but missing from the pass is cleared. So
## an anomaly is reported once per subject until it clears, however many
## passes see it.

## Key -> {"kind", "subject", "detail", "since_tick"}.
var _open: Dictionary = {}


static func key_of(kind: String, subject: String) -> String:
	return "%s:%s" % [kind, subject]


## `found` maps key_of(kind, subject) to {"kind", "subject", "detail"}. Returns
## {"raised": [...], "cleared": [...]}, each an array of anomaly records; a
## raised record has "since_tick", a cleared one also "cleared_tick".
func update(found: Dictionary, tick: int) -> Dictionary:
	var raised: Array[Dictionary] = []
	var cleared: Array[Dictionary] = []
	for key in found:
		if _open.has(key):
			continue
		var record: Dictionary = (found[key] as Dictionary).duplicate(true)
		record["since_tick"] = tick
		_open[key] = record
		raised.append(record)
	for key in _open.keys():
		if found.has(key):
			continue
		var record: Dictionary = _open[key].duplicate(true)
		record["cleared_tick"] = tick
		_open.erase(key)
		cleared.append(record)
	return {"raised": raised, "cleared": cleared}


## The open anomalies, in key order.
func open() -> Array[Dictionary]:
	var keys := _open.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for key in keys:
		out.append(_open[key].duplicate(true))
	return out


func is_open(kind: String, subject: String) -> bool:
	return _open.has(key_of(kind, subject))
