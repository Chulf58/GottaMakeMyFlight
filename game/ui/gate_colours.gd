class_name GateColours
extends RefCounted
## One colour per gate letter (decision flight-planner-a-full-screen-day-planner-
## with-one-row-per-ga): the flight planner's row header and bars and the Gate
## button of the Departures list take it, so a gate reads the same everywhere.
## Warm, mid-light tones that keep the HUD's navy text readable and stay apart
## from each other. Gate A takes the first, B the second and so on; a gate
## past the eighth wraps round, and an id that is not a capital letter takes
## the slot its first character falls on.

const PALETTE: Array[Color] = [
	Color(0.93, 0.52, 0.45),
	Color(0.96, 0.76, 0.30),
	Color(0.40, 0.75, 0.72),
	Color(0.55, 0.78, 0.45),
	Color(0.72, 0.60, 0.85),
	Color(0.45, 0.68, 0.90),
	Color(0.90, 0.58, 0.74),
	Color(0.74, 0.58, 0.45),
]
## The HUD's navy, for text on a gate colour.
const TEXT := Color(0.1, 0.13, 0.26)


## The colour of `gate_id`.
static func of(gate_id: String) -> Color:
	return PALETTE[slot_of(gate_id)]


## Which PALETTE slot `gate_id` takes: its first letter counted from A.
static func slot_of(gate_id: String) -> int:
	if gate_id == "":
		return 0
	return posmod(gate_id.to_upper().unicode_at(0) - "A".unicode_at(0), PALETTE.size())


## Gives a themed button the colour of `gate_id` without any theme override
## (decision hud-theme-file-game-ui-hud-theme-tres-nunito-font-set-on-eac): the
## button keeps its theme variation and the theme's styleboxes, and its
## self_modulate scales the theme's normal fill to the gate colour. Hover,
## pressed and disabled keep the theme's own states, shifted by the same tint.
static func tint_themed(button: Button, gate_id: String) -> void:
	var base := of(gate_id)
	var box := button.get_theme_stylebox("normal")
	var fill := (box as StyleBoxFlat).bg_color if box is StyleBoxFlat else Color.WHITE
	button.self_modulate = Color(
		base.r / maxf(fill.r, 0.01), base.g / maxf(fill.g, 0.01), base.b / maxf(fill.b, 0.01)
	)


## Gives `button` the colour of `gate_id` in every state, keeping the theme's
## padding and outline. A disabled button is the same colour, softened.
static func tint_button(button: Button, gate_id: String) -> void:
	var base := of(gate_id)
	var shades := {
		"normal": base,
		"hover": base.lightened(0.18),
		"pressed": base.darkened(0.15),
		"focus": base,
		"disabled": base.lerp(Color(0.87, 0.85, 0.81), 0.45),
	}
	for state: String in shades:
		var box := button.get_theme_stylebox(state)
		var flat := (box.duplicate() as StyleBoxFlat) if box is StyleBoxFlat else StyleBoxFlat.new()
		flat.bg_color = shades[state]
		button.add_theme_stylebox_override(state, flat)
	for colour_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_disabled_color",
	]:
		button.add_theme_color_override(colour_name, TEXT)
