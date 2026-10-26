class_name FlightResultPanel
extends PanelContainer
## The result of one flight, shown by PassengerHud when its doors close: made,
## missed and the main reasons passengers missed. Hidden until shown and
## dismissed with its button.

## The most reasons listed; the rest are summed into one "Other" row, so the
## rows add up to every reason.
const MAX_REASONS := 3
const WIDTH := 440.0

var _label := Label.new()


func _init() -> void:
	name = "FlightResultPanel"
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0.0)
	add_theme_stylebox_override("panel", BuildMenu.panel_style())
	var column := VBoxContainer.new()
	add_child(column)
	_label.add_theme_font_size_override("font_size", 18)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	var dismiss := Button.new()
	dismiss.name = "DismissResult"
	dismiss.text = "Dismiss"
	dismiss.size_flags_horizontal = Control.SIZE_SHRINK_END
	BuildMenu.style_button(dismiss)
	dismiss.pressed.connect(dismiss_result)
	column.add_child(dismiss)


## The panel's text for a FlightResult.summarize() dictionary.
static func text_for(summary: Dictionary) -> String:
	var lines := PackedStringArray(
		[
			"%s result" % summary["flight"],
			"Made %d   Missed %d" % [summary["made"], summary["missed"]],
		]
	)
	var reasons: Array = summary["reasons"]
	for i in mini(reasons.size(), MAX_REASONS):
		lines.append("%d  %s" % [reasons[i]["count"], reasons[i]["text"]])
	var other := 0
	for i in range(MAX_REASONS, reasons.size()):
		other += reasons[i]["count"]
	if other > 0:
		lines.append("%d  Other" % other)
	return "\n".join(lines)


func show_result(summary: Dictionary) -> void:
	_label.text = text_for(summary)
	visible = true


func dismiss_result() -> void:
	visible = false


func result_text() -> String:
	return _label.text
