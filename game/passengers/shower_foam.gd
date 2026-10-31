class_name ShowerFoam
extends Node3D
## The lather and steam over a passenger in the shower (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, the user's
## answers "Foam and steam to cover the naked body. Icons stay" and "Finer
## lather"). A child of the passenger's node, so it stands where the body
## stands: many small soap bubbles hugging the legs, hips, body and arms up
## to the neck, drawn as one MultiMesh and built up from the feet as `amount`
## grows, and thick steam rising out of the cubicle's open top. The head
## stays clear so the passenger is still readable, and the mood bubble and
## need icons draw over it (no depth test). PassengerViews adds one only to a
## showering passenger and frees it when the shower ends, so a passenger
## that is not showering carries no foam nodes and costs nothing.

## Body envelopes the bubbles cover, in the node's frame (feet at the
## origin, facing +Z), for the Toon bodies standing in the idle clip: [centre
## x, centre z, bottom y, top y, half width, half depth]. The body and arms
## are one envelope (the hands hang in front of the hips), the legs another,
## then a collar low enough to clear the chin of the shortest body.
const PARTS: Array[Array] = [
	[0.0, 0.0, 0.84, 1.56, 0.26, 0.17],
	[0.0, 0.0, 0.14, 0.88, 0.2, 0.12],
	[0.0, -0.02, 1.54, 1.6, 0.12, 0.1],
]
## Bubbles stand on a grid of this spacing over each envelope (jittered by
## a third of it), with radii between the two below, so neighbours overlap
## and no body shows through.
const STEP_M := 0.05
const R_MIN := 0.034
const R_MAX := 0.056
## Bubbles sit this share of their radius outside the envelope.
const OUT := 0.3
const SEED := 7
## The steam: soft white puffs rising from over the head, out of the
## cubicle's open 2.16 m top, growing and fading on a loop, each a share of
## the loop later than the last. They cast no shadow.
const STEAM_PUFFS := 10
const STEAM_FROM_M := 1.95
const STEAM_RISE_M := 0.9
const STEAM_LOOP_S := 2.2
const STEAM_ALPHA := 0.7

static var _bubble: SphereMesh
static var _buffer := PackedFloat32Array()
static var _count := 0
static var _puff: SphereMesh

## How much lather (0 to 1) is up now.
var amount := 0.0

var _lather := MultiMeshInstance3D.new()
var _steam := Node3D.new()
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
	add_child(_lather)
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
	var steaming := amount > 0.5
	_steam.visible = steaming
	set_process(steaming)
	if steaming:
		_drift()


## The bubbles drawn now, and in all.
func lather_shown() -> int:
	return _lather.multimesh.visible_instance_count


static func lather_count() -> int:
	_build_shared()
	return _count


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
	var soap := StandardMaterial3D.new()
	soap.albedo_color = Color(0.97, 0.98, 1.0)
	soap.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	soap.specular_mode = BaseMaterial3D.SPECULAR_TOON
	soap.roughness = 0.3
	soap.rim_enabled = true
	soap.rim = 0.35
	_bubble = SphereMesh.new()
	_bubble.radius = 1.0
	_bubble.height = 2.0
	_bubble.radial_segments = 8
	_bubble.rings = 4
	_bubble.material = soap
	_puff = SphereMesh.new()
	_puff.radius = 1.0
	_puff.height = 2.0
	_puff.radial_segments = 10
	_puff.rings = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bubbles: Array[Vector4] = []
	for part in PARTS:
		var rx: float = part[4]
		var rz: float = part[5]
		# Ramanujan's ellipse perimeter, for the number of bubbles around.
		var around := PI * (3.0 * (rx + rz) - sqrt((3.0 * rx + rz) * (rx + 3.0 * rz)))
		var cols := ceili(around / STEP_M)
		var rows := ceili((part[3] - part[2]) / STEP_M) + 1
		for row in rows:
			for col in cols:
				var r := rng.randf_range(R_MIN, R_MAX)
				var turn := (col + rng.randf_range(-0.33, 0.33) + 0.5 * (row % 2)) * TAU / cols
				var y := clampf(
					part[2] + (row + rng.randf_range(-0.33, 0.33)) * STEP_M, part[2], part[3]
				)
				var out := Vector2(cos(turn) * rx, sin(turn) * rz)
				out += out.normalized() * r * OUT
				bubbles.append(Vector4(part[0] + out.x, y, part[1] + out.y, r))
	bubbles.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y < b.y)
	_count = bubbles.size()
	_buffer.resize(_count * 12)
	for i in _count:
		var b := bubbles[i]
		var row := [b.w, 0.0, 0.0, b.x, 0.0, b.w, 0.0, b.y, 0.0, 0.0, b.w, b.z]
		for k in 12:
			_buffer[i * 12 + k] = row[k]
