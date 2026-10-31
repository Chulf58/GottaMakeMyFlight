class_name ShowerFoam
extends Node3D
## The foam and steam over a passenger in the shower (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, the user's
## answer "Foam and steam to cover the naked body. Icons stay"). A child of the
## passenger's node, so it stands where the body stands: a column of toon-lit
## foam balls from the shins up to the neck, built up from the feet as
## `amount` grows, and a puff of steam rising over the cubicle while the
## passenger is in. The head stays clear so the passenger is still readable,
## and the mood bubble and need icons draw over it (no depth test).
## PassengerViews sets the amount each tick from ActivityPoses.foam(); at 0
## the node is hidden.

## The foam balls in the node's frame (feet at the origin, facing +Z): [x, y,
## z, radius] in metres. A ring of four to six per height, wide enough to
## cover the arms at the sides and kept inside the cubicle's glass (|x| 0.40,
## |z| 0.37 from its middle).
const BALLS: Array[Vector4] = [
	Vector4(0.0, 0.32, 0.12, 0.13),
	Vector4(0.0, 0.32, -0.12, 0.13),
	Vector4(0.14, 0.38, 0.0, 0.13),
	Vector4(-0.14, 0.38, 0.0, 0.13),
	Vector4(0.1, 0.58, 0.13, 0.15),
	Vector4(-0.1, 0.6, 0.13, 0.15),
	Vector4(0.1, 0.6, -0.13, 0.15),
	Vector4(-0.1, 0.58, -0.13, 0.15),
	Vector4(0.0, 0.84, 0.15, 0.17),
	Vector4(0.0, 0.84, -0.15, 0.17),
	Vector4(0.17, 0.86, 0.0, 0.16),
	Vector4(-0.17, 0.86, 0.0, 0.16),
	Vector4(0.13, 1.08, 0.12, 0.17),
	Vector4(-0.13, 1.1, 0.12, 0.17),
	Vector4(0.13, 1.1, -0.12, 0.17),
	Vector4(-0.13, 1.08, -0.12, 0.17),
	Vector4(0.24, 1.0, 0.02, 0.12),
	Vector4(-0.24, 1.0, 0.02, 0.12),
	Vector4(0.0, 1.3, 0.14, 0.16),
	Vector4(0.0, 1.3, -0.14, 0.16),
	Vector4(0.19, 1.32, 0.0, 0.15),
	Vector4(-0.19, 1.32, 0.0, 0.15),
	Vector4(0.25, 1.24, 0.0, 0.11),
	Vector4(-0.25, 1.24, 0.0, 0.11),
	Vector4(0.12, 1.5, 0.08, 0.12),
	Vector4(-0.12, 1.5, 0.08, 0.12),
	Vector4(0.0, 1.5, -0.1, 0.12),
	Vector4(0.17, 1.6, 0.0, 0.11),
	Vector4(-0.17, 1.6, 0.0, 0.11),
	Vector4(0.0, 1.57, 0.1, 0.1),
]
## How far a ball swells and shrinks while the foam is up (share of its
## radius), and how fast (radians per second).
const WOBBLE := 0.07
const WOBBLE_RATE := 3.0
## The steam: soft white puffs rising from over the head, out of the
## cubicle's open 2.16 m top, growing and fading on a loop, each a share of
## the loop later than the last. They cast no shadow.
const STEAM_PUFFS := 6
const STEAM_FROM_M := 1.95
const STEAM_RISE_M := 0.8
const STEAM_LOOP_S := 2.4
const STEAM_ALPHA := 0.55

## How much foam (0 to 1) is up now.
var amount := 0.0

var _balls: Array[MeshInstance3D] = []
var _steam := Node3D.new()
var _puffs: Array[MeshInstance3D] = []
var _clock := 0.0


func _init() -> void:
	name = "ShowerFoam"
	visible = false
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color(0.96, 0.98, 1.0)
	foam.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	foam.specular_mode = BaseMaterial3D.SPECULAR_TOON
	foam.roughness = 0.35
	foam.rim_enabled = true
	foam.rim = 0.4
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = foam
	for ball in BALLS:
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(ball.x, ball.y, ball.z)
		add_child(mi)
		_balls.append(mi)
	_steam.name = "Steam"
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 10
	puff.rings = 5
	for i in STEAM_PUFFS:
		var vapour := StandardMaterial3D.new()
		vapour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vapour.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vapour.albedo_color = Color(1.0, 1.0, 1.0, STEAM_ALPHA)
		var mi := MeshInstance3D.new()
		mi.mesh = puff
		mi.material_override = vapour
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_steam.add_child(mi)
		_puffs.append(mi)
	add_child(_steam)


func _process(delta: float) -> void:
	_clock += delta
	if visible:
		_shape()


## Sets how much foam is up (0 to 1) and shows or hides the foam and steam.
func set_amount(value: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	visible = amount > 0.0
	_steam.visible = amount > 0.5
	_shape()


## The foam balls showing now (their scale above zero), for checks.
func balls_shown() -> int:
	var shown := 0
	for mi in _balls:
		if mi.visible and mi.scale.x > 0.0:
			shown += 1
	return shown


## Each ball is scaled by its share of the amount: the lower balls come first,
## so the foam builds up from the feet and rinses off from the top down.
func _shape() -> void:
	for i in _balls.size():
		var ball := BALLS[i]
		var start := ball.y / 1.6 * 0.6
		var grown := clampf((amount - start) / 0.4, 0.0, 1.0)
		var wobble := 1.0 + WOBBLE * sin(_clock * WOBBLE_RATE + i * 1.7)
		var r := ball.w * grown * wobble
		_balls[i].visible = r > 0.0
		_balls[i].scale = Vector3.ONE * maxf(r, 0.001)
	for i in _puffs.size():
		var t := fposmod(_clock / STEAM_LOOP_S + i / float(_puffs.size()), 1.0)
		var side := 0.12 * sin(i * 2.4)
		var mi := _puffs[i]
		mi.position = Vector3(side, STEAM_FROM_M + STEAM_RISE_M * t, 0.1 * cos(i * 2.4))
		mi.scale = Vector3.ONE * lerpf(0.08, 0.24, t)
		var vapour := mi.material_override as StandardMaterial3D
		vapour.albedo_color.a = STEAM_ALPHA * sin(PI * t)
