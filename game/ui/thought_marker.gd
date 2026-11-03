class_name ThoughtMarker
extends Node3D
## The pin a clicked thought drops where the passenger was (user ruling in
## decision passenger-inspect-thoughts-recorded-at-sim-outcomes-saved-pin-
## marks-where): a map pin in the HUD's coral for a bad thought or green for a
## good one (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-
## pale: coral red problems, green good), PIN_PX on screen at every zoom and
## drawn through walls and roof, its tip on a soft floor spot in the same
## colour that pulses gently. Its shape is not the stations' rounded-square
## signs, the need icons' circles or the selection ring. It stays until
## clear(); PassengerInspect clears it on another thought, a deselect or a
## load. A view node only: nothing about it is saved.

## The HUD theme's coral and green button fills (hud_theme.tres).
const CORAL := Color(0.92, 0.45, 0.4)
const GREEN := Color(0.5, 0.8, 0.45)
const OUTLINE := MarkerIcons.OUTLINE
const SIZE := 128
const OUTLINE_PX := 9.0
## The pin's height on screen, in output pixels.
const PIN_PX := 40.0
## Above the kept speech bubble (14): the player asked for this spot.
const PIN_PRIORITY := 15
const SPOT_RADIUS_M := 0.45
const SPOT_ALPHA := 0.45
## One pulse of the floor spot, in milliseconds of real time.
const PULSE_MS := 1200.0
## Lift of the floor spot over the floor, so it does not fight it.
const SPOT_LIFT_M := 0.03
## The head's centre and radius, and the tip, in image pixels from the centre
## (y runs down).
const HEAD := Vector2(0.0, -20.0)
const HEAD_RADIUS := 40.0
const TIP := Vector2(0.0, 62.0)
const DOT := Color(0.99, 0.97, 0.92)
const DOT_RADIUS := 13.0

static var _textures: Dictionary = {}

var _pin := Sprite3D.new()
var _spot := MeshInstance3D.new()
var _spot_material := StandardMaterial3D.new()
var _colour := CORAL


func _init() -> void:
	name = "ThoughtMarker"
	visible = false
	_pin.name = "Pin"
	_pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pin.fixed_size = true
	_pin.no_depth_test = true
	_pin.shaded = false
	_pin.render_priority = PIN_PRIORITY
	_pin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Lifted by half the image, so the tip at its bottom edge sits on the point.
	_pin.offset = Vector2(0.0, SIZE / 2.0)
	_pin.pixel_size = PIN_PX / 720.0 / SIZE
	add_child(_pin)
	var disc := CylinderMesh.new()
	disc.top_radius = SPOT_RADIUS_M
	disc.bottom_radius = SPOT_RADIUS_M
	disc.height = 0.01
	disc.radial_segments = 32
	_spot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spot.name = "Spot"
	_spot.mesh = disc
	_spot.material_override = _spot_material
	_spot.position = Vector3(0.0, SPOT_LIFT_M, 0.0)
	_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spot)


func _process(_delta: float) -> void:
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	var unit := NeedIcons.unit_of(get_viewport(), camera)
	if unit > 0.0:
		_pin.pixel_size = PIN_PX * unit / SIZE
	var phase := fmod(Time.get_ticks_msec(), PULSE_MS) / PULSE_MS
	_spot_material.albedo_color = Color(_colour, SPOT_ALPHA * (0.7 + 0.3 * cos(phase * TAU)))


## Pins `point` (its floor) in green for a good thought, coral for a bad one.
func show_at(point: Vector3, positive: bool) -> void:
	_colour = GREEN if positive else CORAL
	_pin.texture = pin_texture(_colour)
	_spot_material.albedo_color = Color(_colour, SPOT_ALPHA)
	position = point
	visible = true


func clear() -> void:
	visible = false


func is_shown() -> bool:
	return visible


func pin_colour() -> Color:
	return _colour


## The pin painted once per colour: a teardrop with the dark outline and a
## cream dot in its head, its tip at the bottom centre.
static func pin_texture(colour: Color) -> Texture2D:
	if not _textures.has(colour):
		_textures[colour] = _paint(colour)
	return _textures[colour]


static func _paint(colour: Color) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := _teardrop(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var fill := colour
			var dot := p.distance_to(HEAD) - DOT_RADIUS
			fill = fill.lerp(DOT, clampf(0.5 - dot, 0.0, 1.0))
			var pixel := OUTLINE.lerp(fill, inside)
			pixel.a = cover
			img.set_pixel(x, y, pixel)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Signed distance to the pin: the head circle joined to the tip by the two
## lines tangent to it.
static func _teardrop(p: Vector2) -> float:
	var circle := p.distance_to(HEAD) - HEAD_RADIUS
	var down := (TIP - HEAD).length()
	var angle := asin(HEAD_RADIUS / down)
	var axis := Vector2(absf(p.x), p.y - TIP.y)
	# The cone's side, from the tip upward at `angle` from the axis.
	var side := Vector2(sin(angle), -cos(angle))
	var normal := Vector2(cos(angle), sin(angle))
	var along := axis.dot(side)
	var reach := down * cos(angle)
	if along < 0.0:
		return minf(circle, axis.length())
	if along > reach:
		return circle
	return minf(circle, axis.dot(normal))
