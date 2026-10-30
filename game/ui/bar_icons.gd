class_name BarIcons
extends RefCounted
## The category bar's icons (decision hud-look-warm-cozy-cream-cards-with-a-
## dark-outline-toon-pale): simple filled icons with a dark outline in the Toon
## palette, drawn as SVG files under game/assets/ui/icons/, not renders of the
## 3D models. A bar button shows its icon alone; its name goes in the tooltip.

const ICON_DIR := "res://assets/ui/icons/%s.svg"
## Bar button name (BuildMenu.bar_name(), or Staff) -> icon file name.
const ICONS := {
	"Structure": "structure",
	"Doors": "doors",
	"Check-in": "check_in",
	"Security": "security",
	"Lane": "lane",
	"Gates": "gates",
	"Cafe": "cafe",
	"Toilets": "toilets",
	"Kiosk": "kiosk",
	"Landside": "landside",
	"Baggage": "baggage",
	"Decor": "decor",
	"Food": "food",
	"Services": "services",
	"Leisure": "leisure",
	"Shops": "shops",
	"Remove": "remove",
	"Staff": "staff",
}


## The icon file of a bar button, or "" for a name with no icon.
static func icon_path(button_name: String) -> String:
	return ICON_DIR % ICONS[button_name] if ICONS.has(button_name) else ""


## Puts a bar button's icon on it and its name in the tooltip. A name with no
## icon file is an error, and the button then shows the name as text.
static func dress(button: Button, button_name: String) -> void:
	button.tooltip_text = button_name
	var path := icon_path(button_name)
	if path == "" or not ResourceLoader.exists(path):
		push_error("BarIcons: no icon for %s at %s" % [button_name, path])
		button.text = button_name
		return
	button.text = ""
	button.icon = load(path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
