class_name BarIcons
extends RefCounted
## The category bar's icons (decision hud-look-warm-cozy-cream-cards-with-a-
## dark-outline-toon-pale): simple filled icons with a dark outline in the Toon
## palette, drawn as SVG files under game/assets/ui/icons/, not renders of the
## 3D models. A bar button shows its icon alone; its name goes in the tooltip.

const ICON_DIR := "res://assets/ui/icons/%s.svg"
## Stable bar button id (BuildMenuCatalog.category_id(), or "staff") -> icon file name.
const ICONS := {
	"building": "structure",
	"operations": "check_in",
	"facilities": "toilets",
	"food": "food",
	"shops": "shops",
	"decor": "decor",
	"landside": "landside",
	"templates": "templates",
	"remove": "remove",
	"staff": "staff",
}


## The icon file of a bar button id, or "" for an id with no icon.
static func icon_path(button_id: String) -> String:
	return ICON_DIR % ICONS[button_id] if ICONS.has(button_id) else ""


## Puts a bar button's icon on it from `button_id`. An id with no icon file is
## an error, and the button then shows `button_id` as text.
static func dress(button: Button, button_id: String) -> void:
	button.tooltip_text = button_id
	var path := icon_path(button_id)
	if path == "" or not ResourceLoader.exists(path):
		push_error("BarIcons: no icon for %s at %s" % [button_id, path])
		button.text = button_id
		return
	button.text = ""
	button.icon = load(path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
