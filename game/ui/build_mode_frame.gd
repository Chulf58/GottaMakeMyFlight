class_name BuildModeFrame
extends Control
## What tells the player they are in build mode: a black and yellow diagonal
## hazard-stripe border round the screen edges and a roadworks-style
## "Build mode" sign at top centre. Hidden until set_building(true). Every part
## ignores the mouse, and the border is BuildMenu.MARGIN thick so it stays off
## the bottom bar, the money slot and the flight panel.

const HUD_THEME := preload("res://ui/hud_theme.tres")
const STRIPE_SHADER := preload("res://ui/build_mode_stripes.gdshader")
## BuildMenu.MARGIN (BuildMenu names this class, so it cannot be read back here;
## test_build_mode_frame.gd holds the two equal).
const THICKNESS := 8.0
const STRIPE_PERIOD := 22.0
const SIGN_TEXT := "Build mode"
const SIGN_TOP := THICKNESS + 6.0
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
	_sign.size = _sign.get_combined_minimum_size()
	_sign.position = Vector2((size_now.x - _sign.size.x) / 2.0, SIGN_TOP)


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
	var style := StyleBoxFlat.new()
	style.bg_color = YELLOW
	style.border_color = DARK
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_sign.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = SIGN_TEXT
	label.theme = HUD_THEME
	label.add_theme_color_override("font_color", DARK)
	label.add_theme_font_size_override("font_size", 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.add_child(label)
