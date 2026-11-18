class_name DebugPanelParts
extends RefCounted
## The three buttons of the HUD's dev-only Debug panel (decision
## debug-panel-is-for-dev-builds-only-the-hud-s-debug-toggle-an). Their words stay
## English and are never translated: they live here, outside game/ui/, so the
## translation guard (TranslationScan) does not see dev-only text. PassengerHud
## builds them only while its debug_tools gate is on.


## The button that spawns a debug batch of `batch` passengers.
static func spawn_button(batch: int, on_press: Callable) -> Button:
	var button := _button("Spawn %d passengers" % batch)
	button.pressed.connect(on_press)
	return button


## The button that builds or fills the starter terminal.
static func starter_button(on_press: Callable) -> Button:
	var button := _button("Starter terminal")
	button.pressed.connect(on_press)
	return button


## The "DebugToggle" that opens and closes the panel; `on_toggled` takes the new state.
static func toggle(on_toggled: Callable) -> Button:
	var button := _button("Debug")
	button.name = "DebugToggle"
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.toggled.connect(on_toggled)
	return button


static func _button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	return button
