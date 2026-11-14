class_name FakeSignProvider
extends RefCounted
## A station-sign provider for HoverTarget tests and probes: it reports the signs
## it is given, as HoverTarget.hover_signs() expects ({key, rect, text}).

var signs: Array[Dictionary] = []


func add(key: Variant, rect: Rect2, text: String) -> void:
	signs.append({"key": key, "rect": rect, "text": text})


func hover_signs() -> Array[Dictionary]:
	return signs
