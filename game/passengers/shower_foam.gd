class_name ShowerFoam
extends Node3D
## The lather and steam over a passenger in the shower (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, the user's
## answers "Foam and steam to cover the naked body. Icons stay" and "Finer
## lather"). A child of the passenger's node, so it stands where the body
## stands: many small soap bubbles hugging the legs, hips, body and arms up
## to the neck, drawn as one MultiMesh and built up from the feet as `amount`
## grows, each bubble swelling and drifting a little on its own slow loop
## (shaders/shower_lather.gdshader, on the GPU, so the motion costs no CPU
## work per frame), steam filling the cubicle around the body (Haze,
## shaders/shower_haze.gdshader: wisps drifting and rising on the inside of
## the glass, coming with the lather and going with the rinse, clear at face
## height), and thick steam rising out of the cubicle's open top. The head
## stays clear so the passenger is still readable, and the mood bubble and
## need icons draw over it (no depth test). PassengerViews adds one only to a
## showering passenger and frees it when the shower ends, so a passenger
## that is not showering carries no foam nodes and costs nothing.

## Body envelopes the bubbles cover, in the node's frame (feet at the
## origin, facing +Z), for the Toon bodies in both the idle clip (stepping in)
## and the washing clip, whose stance puts one foot forward: [centre x, centre
## z, bottom y, top y, half width, half depth]. The body is one envelope (the
## hands hang in front of the hips at idle; the arms raised to wash are bare
## skin outside it), the legs another, then a collar low enough to clear the
## chin of the shortest body. Measured 2026-10-31 over the skinned vertices of
## all 12 bodies through both clips: the legs need 0.254 by 0.274 m about
## (0.017, -0.012), the body without its arms 0.235 by 0.213 m about (0.005,
## 0.007); each envelope here is about 1 cm larger. The last two are single
## rings that close the top of the body between its envelope and the collar
## (a shoulder cap), so a view from above (the top, the game camera) does not
## look down past the collar onto the chest and back (board item bfe19c1e).
const PARTS: Array[Array] = [
	[0.0, 0.01, 0.84, 1.56, 0.26, 0.225],
	[0.017, -0.012, 0.14, 0.88, 0.265, 0.285],
	[0.0, -0.02, 1.54, 1.6, 0.12, 0.1],
	[0.0, 0.0, 1.56, 1.56, 0.215, 0.185],
	[0.0, -0.01, 1.56, 1.56, 0.17, 0.145],
]
## Bubbles stand on a grid of this spacing over each envelope (jittered by
## JITTER of it), with radii between the two below, so neighbours overlap
## and no body shows through.
const STEP_M := 0.05
const R_MIN := 0.034
const R_MAX := 0.056
const JITTER := 0.33
## Bubbles sit this share of their radius outside the envelope.
const OUT := 0.3
## Under that lather, a second layer of sparser, larger bubbles centred on the
## envelope, on a grid of its own: where two outer bubbles drift apart (by up
## to 0.7 of a radius between neighbours), it fills the gap, so the body does
## not show through from behind or the sides (board item bfe19c1e).
const INNER_STEP_M := 0.06
const INNER_R_MIN := 0.045
const INNER_JITTER := 0.15
const INNER_OUT := 0.0
const SEED := 7
## The lather's motion, as shares of a bubble's radius: how much it swells
## and how far it drifts from where it rests (the shader's uniforms).
const SWELL := 0.15
const DRIFT := 0.35
const LATHER_SHADER := preload("res://shaders/shower_lather.gdshader")
## The steam: soft white puffs rising from over the head, out of the
## cubicle's open 2.16 m top, growing and fading on a loop, each a share of
## the loop later than the last. They cast no shadow.
const STEAM_PUFFS := 10
const STEAM_FROM_M := 1.95
const STEAM_RISE_M := 0.9
const STEAM_LOOP_S := 2.2
const STEAM_ALPHA := 0.7
## The steam inside the cubicle: one box, shared by every foam, standing on
## HAZE_FLOOR_M inside the shower_cubicle's glass (the piece is 0.84 m square
## outside) and under its 2.16 m top (the foam stands on the 0.10 m tray),
## drawn by HAZE_SHADER.
const HAZE_SIZE_M := Vector3(0.62, 1.85, 0.64)
const HAZE_FLOOR_M := 0.15
const HAZE_SHADER := preload("res://shaders/shower_haze.gdshader")

static var _bubble: SphereMesh
static var _buffer := PackedFloat32Array()
static var _count := 0
static var _puff: SphereMesh
static var _haze_box: BoxMesh

## How much lather (0 to 1) is up now.
var amount := 0.0

var _lather := MultiMeshInstance3D.new()
var _steam := Node3D.new()
var _haze := MeshInstance3D.new()
var _puffs: Array[MeshInstance3D] = []
var _clock := 0.0


func _init() -> void:
	name = "ShowerFoam"
	_build_shared()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _bubble
	multi.instance_count = _count
	multi.buffer = _buffer
	multi.visible_instance_count = 0
	_lather.name = "Lather"
	_lather.multimesh = multi
	_lather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves bubbles past the instances' own bounds.
	_lather.extra_cull_margin = motion_reach_m(R_MAX)
	add_child(_lather)
	_haze.name = "Haze"
	_haze.mesh = _haze_box
	_haze.position.y = HAZE_FLOOR_M + HAZE_SIZE_M.y / 2.0
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haze.visible = false
	add_child(_haze)
	_steam.name = "Steam"
	for i in STEAM_PUFFS:
		var vapour := StandardMaterial3D.new()
		vapour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vapour.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vapour.albedo_color = Color(1.0, 1.0, 1.0, STEAM_ALPHA)
		var mi := MeshInstance3D.new()
		mi.mesh = _puff
		mi.material_override = vapour
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_steam.add_child(mi)
		_puffs.append(mi)
	_steam.visible = false
	add_child(_steam)
	set_process(false)


func _process(delta: float) -> void:
	_clock += delta
	_drift()


## Sets how much lather is up (0 to 1): that share of the bubbles, lowest
## first, so it builds from the feet and rinses off from the top. Steam
## shows, and moves, past half.
func set_amount(value: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	_lather.multimesh.visible_instance_count = roundi(amount * _count)
	_haze.set_instance_shader_parameter(&"amount", amount)
	_haze.visible = amount > 0.0
	var steaming := amount > 0.5
	_steam.visible = steaming
	set_process(steaming)
	if steaming:
		_drift()


## How much steam fills the cubicle now (0 to 1): as much as the lather.
func haze_shown() -> float:
	return _haze.get_instance_shader_parameter(&"amount") if _haze.visible else 0.0


## The bubbles drawn now, and in all.
func lather_shown() -> int:
	return _lather.multimesh.visible_instance_count


static func lather_count() -> int:
	_build_shared()
	return _count


## The furthest (metres) the lather's motion takes the surface of a bubble of
## radius `radius` from where it rests: the shader's swell plus its drift,
## whose offset is at most sqrt(1.25) of DRIFT long.
static func motion_reach_m(radius: float) -> float:
	return radius * (SWELL + DRIFT * sqrt(1.25))


## The bubbles' rest transforms (centre and radius each), shared by every foam.
static func bubbles() -> Array[Vector4]:
	_build_shared()
	var out: Array[Vector4] = []
	for i in _count:
		var b := _buffer.slice(i * 12, i * 12 + 12)
		out.append(Vector4(b[3], b[7], b[11], b[0]))
	return out


## The box the cubicle's steam is drawn on, shared by every foam.
static func haze_box() -> BoxMesh:
	_build_shared()
	return _haze_box


## The material the bubbles draw with.
static func soap() -> ShaderMaterial:
	_build_shared()
	return _bubble.material as ShaderMaterial


func _drift() -> void:
	for i in _puffs.size():
		var t := fposmod(_clock / STEAM_LOOP_S + i / float(_puffs.size()), 1.0)
		var mi := _puffs[i]
		var x := 0.18 * sin(i * 2.4)
		mi.position = Vector3(x, STEAM_FROM_M + STEAM_RISE_M * t, 0.13 * cos(i * 2.4))
		mi.scale = Vector3.ONE * lerpf(0.12, 0.34, t)
		(mi.material_override as StandardMaterial3D).albedo_color.a = STEAM_ALPHA * sin(PI * t)


## The bubble and puff meshes and the bubbles' transforms, built once and
## shared by every foam: the bubbles in height order, from a fixed seed.
static func _build_shared() -> void:
	if _bubble != null:
		return
	var lather := ShaderMaterial.new()
	lather.shader = LATHER_SHADER
	lather.set_shader_parameter("swell", SWELL)
	lather.set_shader_parameter("drift", DRIFT)
	_bubble = SphereMesh.new()
	_bubble.radius = 1.0
	_bubble.height = 2.0
	_bubble.radial_segments = 8
	_bubble.rings = 4
	_bubble.material = lather
	var haze := ShaderMaterial.new()
	haze.shader = HAZE_SHADER
	haze.set_shader_parameter("centre_y", HAZE_FLOOR_M + HAZE_SIZE_M.y / 2.0)
	_haze_box = BoxMesh.new()
	_haze_box.size = HAZE_SIZE_M
	_haze_box.material = haze
	_puff = SphereMesh.new()
	_puff.radius = 1.0
	_puff.height = 2.0
	_puff.radial_segments = 10
	_puff.rings = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bubbles: Array[Vector4] = []
	for part in PARTS:
		_shell(bubbles, rng, part, [STEP_M, R_MIN, R_MAX, JITTER, OUT])
		_shell(bubbles, rng, part, [INNER_STEP_M, INNER_R_MIN, R_MAX, INNER_JITTER, INNER_OUT])
	bubbles.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
	_count = bubbles.size()
	_buffer.resize(_count * 12)
	for i in _count:
		var b := bubbles[i]
		var row := [b.w, 0.0, 0.0, b.x, 0.0, b.w, 0.0, b.y, 0.0, 0.0, b.w, b.z]
		for k in 12:
			_buffer[i * 12 + k] = row[k]


## Adds one layer of bubbles over envelope `part` (PARTS) to `bubbles`:
## `grid` is [step, smallest radius, largest radius, jitter as a share of the
## step, share of the radius out of the envelope].
static func _shell(
	bubbles: Array[Vector4], rng: RandomNumberGenerator, part: Array, grid: Array
) -> void:
	var step: float = grid[0]
	var jitter: float = grid[3]
	var rx: float = part[4]
	var rz: float = part[5]
	# Ramanujan's ellipse perimeter, for the number of bubbles around.
	var around := PI * (3.0 * (rx + rz) - sqrt((3.0 * rx + rz) * (rx + 3.0 * rz)))
	var cols := ceili(around / step)
	var rows := ceili((part[3] - part[2]) / step) + 1
	for row in rows:
		for col in cols:
			var r := rng.randf_range(grid[1], grid[2])
			var turn := (col + rng.randf_range(-jitter, jitter) + 0.5 * (row % 2)) * TAU / cols
			var y := clampf(
				part[2] + (row + rng.randf_range(-jitter, jitter)) * step, part[2], part[3]
			)
			var out := Vector2(cos(turn) * rx, sin(turn) * rz)
			out += out.normalized() * r * grid[4]
			bubbles.append(Vector4(part[0] + out.x, y, part[1] + out.y, r))
