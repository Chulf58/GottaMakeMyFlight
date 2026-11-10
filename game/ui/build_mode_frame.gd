class_name BuildModeFrame
extends Control
## What tells the player they are in build mode: a black and yellow diagonal
## hazard-stripe border round the screen edges and a roadworks-style
## "Build mode" sign in the first slot of the centred top row (TopRow), left of
## Runway and Offers. Hidden until set_building(true). Every part
## ignores the mouse, and the border is BuildMenu.MARGIN thick so it stays off
## the bottom bar, the money slot and the flight panel.

const HUD_THEME := preload("res://ui/hud_theme.tres")
const STRIPE_SHADER := preload("res://ui/build_mode_stripes.gdshader")
## BuildMenu.MARGIN (BuildMenu names this class, so it cannot be read back here;
## test_build_mode_frame.gd holds the two equal).
const THICKNESS := 8.0
const STRIPE_PERIOD := 22.0
const SIGN_TEXT := "Build mode"
const YELLOW := Color(0.99, 0.8, 0.1)
const DARK := Color(0.1, 0.1, 0.12)

var _bands: Array[ColorRect] = []
var _sign := PanelContainer.new()


func _init() -> void:
	name = "BuildModeFrame"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for i in 4:
		var band := ColorRect.new()
		band.name = ["Top", "Bottom", "Left", "Right"][i]
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = STRIPE_SHADER
		material.set_shader_parameter("period", STRIPE_PERIOD)
		material.set_shader_parameter("yellow", YELLOW)
		material.set_shader_parameter("dark", DARK)
		band.material = material
		add_child(band)
		_bands.append(band)
	_build_sign()
	add_child(_sign)


func set_building(on: bool) -> void:
	visible = on
	if on:
		_fit()


func is_showing() -> bool:
	return visible


func band(index: int) -> ColorRect:
	return _bands[index]


func sign_panel() -> Control:
	return _sign


func _process(_delta: float) -> void:
	if visible:
		_fit()


## The area the frame covers in its own units: the viewport, undone of any
## scale the HUD layer carries, so the border sits on the screen edge.
func screen_size() -> Vector2:
	var scale_xy := get_global_transform_with_canvas().get_scale()
	return get_viewport_rect().size / scale_xy


func _fit() -> void:
	var size_now := screen_size()
	position = Vector2.ZERO
	size = size_now
	var t := THICKNESS
	_place(0, Vector2.ZERO, Vector2(size_now.x, t))
	_place(1, Vector2(0.0, size_now.y - t), Vector2(size_now.x, t))
	_place(2, Vector2(0.0, t), Vector2(t, size_now.y - 2.0 * t))
	_place(3, Vector2(size_now.x - t, t), Vector2(t, size_now.y - 2.0 * t))
	_sign.size = TopRow.SLOT_SIZE
	_sign.position = Vector2(TopRow.slot_left(TopRow.SIGN_SLOT, size_now.x), TopRow.TOP)


func _place(index: int, at: Vector2, extent: Vector2) -> void:
	var rect := _bands[index]
	rect.position = at
	rect.size = extent
	# The stripes run on frame coordinates, so the four bands join up.
	var material := rect.material as ShaderMaterial
	material.set_shader_parameter("origin", at)
	material.set_shader_parameter("band_size", extent)


func _build_sign() -> void:
	_sign.name = "BuildModeSign"
	_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The theme holds the sign's look (the stripes' YELLOW and DARK).
	_sign.theme = HUD_THEME
	_sign.theme_type_variation = &"HudBuildSign"
	# The theme's 24 px text with the sign's 4 px margins would make the panel
	# 42 px tall; the row's slot is BUTTON_H. The text sits in a holder that
	# asks for no height, so the panel keeps the slot's size.
	var holder := Control.new()
	holder.name = "SignText"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.add_child(holder)
	var label := Label.new()
	label.text = SIGN_TEXT
	label.theme_type_variation = &"HudBuildSignText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
