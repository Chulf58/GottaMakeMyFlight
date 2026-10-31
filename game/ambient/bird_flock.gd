class_name BirdFlock
extends Node3D
## Ambient crows (decision ambient-birds-the-toon-farm-pack-crow-small-silent-flocks-th):
## a few small silent groups of the Toon Farm Pack crow perch on the forecourt
## (BirdPerches) and scatter to another perch when a car or passenger comes
## within BirdPerches.SCATTER_RADIUS.
##
## View-local: the flock has its own RandomNumberGenerator, keeps no sim tick
## and is not saved. A load throws every bird away and perches new groups
## (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-start-over-on-l).
##
## Time: the flock runs on the sim's time, as passengers and staff do
## (PassengerViews and StaffCharacters set speed_scale to 0 paused and to the
## clock speed otherwise). Paused, every bird holds its pose in the air or on
## the ground, with the cars and passengers that would scatter it; at 3x a
## scatter plays out three times as fast, so birds still clear a car that now
## arrives three times as fast.
##
## A flight is one smooth arch (a cubic curve, flight_point()) in the upright
## plane through both spots: the bird climbs steeply out of its gap between
## the entrance porches (Porch_7 and Porch_8, roof top 4.1 m, cut away at the
## default zoom but shown from far out), crosses above them and drops steeply
## into its new gap, under the entrance canopy (11.8 m and up). The road side
## is no way round: the canopy poles stand out there
## (test_bird_flight_clearance.gd). Clips: takeoff on leaving, fly while
## climbing, soar while gliding down, land over the last LAND_S, timed to end
## as the feet reach the perch.

const CROW := preload("res://assets/birds/tfp_crow_01.glb")
const VARIANTS: Array[String] = ["TFP_Crow_01A", "TFP_Crow_01B", "TFP_Crow_01C"]
## Groups per zone (BirdPerches.Zone), each zone keeping one perch free.
const ZONE_GROUPS: Array[int] = [3, 4, 3]
const GROUP_MIN := 3
## The most birds per group by zone: three fit a forecourt patch at 1.5x, four
## a sidewalk patch (a group must fit every patch of its zone).
const ZONE_GROUP_MAX: Array[int] = [3, 4, 4]
## The idle clips' lowest vertex sits this far below the model origin
## (tools/blender/convert_crow.py CONTACT lines), so the origin goes this far
## above the perch top for the feet to stand on it.
const FOOT_LIFT := 0.007
const TAKEOFF_S := 0.8333
const LAND_S := 1.3333
const FLIGHT_SPEED := 6.0
const MIN_FLIGHT_S := 3.0
## The arch's middle control points stand this high (x to y metres, by zone)
## over both ends; it tops out at three quarters of it. Under the canopy: high
## enough to clear the porch roofs, low enough to stay under the canopy.
const ZONE_LIFTS: Array[Vector2] = [Vector2(10.5, 11.5), Vector2(6.0, 9.0), Vector2(6.0, 9.0)]
## ... and this far out from the facade (+z), so the high crossing keeps off
## the facade's upper lights (Lights_Upper, 5.8 to 7.7 m on the wall).
const AWAY := 1.5
## Birds in a group leave up to this long after the first one.
const MAX_DELAY := 0.4
## A group that just landed sits at least this long before it can scatter.
const SETTLE_S := 0.6
## The body tilts no more than this along its flight.
const MAX_PITCH := deg_to_rad(20.0)
## idle_03 is left out: its peck takes the beak 4.3 cm below the feet (6.5 cm
## at 1.5x) into the paving (convert_crow.py CONTACT low_min).
const PERCHED_CLIPS: Array[String] = ["idle_01", "idle_02", "eat", "hop"]
const CLIP_HOLD_MIN := 2.0
const CLIP_HOLD_MAX := 6.0
const BLEND_S := 0.15

@export var clock: SimClock
@export var passenger_views: PassengerViews
@export var landside_views: LandsideViews
@export var save_game: SaveGame
## 1.0 is the vendor model, already about 1.5 times a real crow (0.56 m long
## perched, 0.46 m tall). User-ruled 2026-10-31 ("Outdoors, a bit larger"):
## drawn at 1.5 so the birds read at a landside zoom.
@export var bird_scale := 1.5

var rng := RandomNumberGenerator.new()
## Each group: {"spot": int, "target": int (-1 perched), "settle": float,
## "birds": Array[Dictionary]}. Each bird: {"node": Node3D, "player":
## AnimationPlayer, "at": Vector3 (perched origin), "from", "to", "lift",
## "t", "dur", "clip": String, "hold": float, "landed": bool}.
var groups: Array[Dictionary] = []
## LandsideSim.lots_built when the flock was last perched; a change rebuilds.
var _lots_seen: Array[bool] = []


func _ready() -> void:
	rng.randomize()
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	rebuild()


func _process(delta: float) -> void:
	if _lots_now() != _lots_seen:
		rebuild()
	var paused := clock != null and clock.paused
	var speed := float(clock.speed) if clock != null else 1.0
	for g in groups:
		for b in g["birds"]:
			(b["player"] as AnimationPlayer).speed_scale = 0.0 if paused else speed
	step(0.0 if paused else delta * speed, threats_now())


## Drops every bird and perches new groups on distinct perches that are there
## now: ZONE_GROUPS per zone, at most one fewer than the zone's perches.
## A built or removed car park rebuilds the flock, as a load does.
func rebuild() -> void:
	for g in groups:
		for b in g["birds"]:
			(b["node"] as Node3D).queue_free()
	groups.clear()
	_lots_seen = _lots_now()
	var there := BirdPerches.available(_lots_seen)
	for zone in ZONE_GROUPS.size():
		var spots: Array[int] = []
		for i in there:
			if BirdPerches.ZONES[i] == zone:
				spots.append(i)
		for _i in mini(ZONE_GROUPS[zone], spots.size() - 1):
			var spot: int = spots.pop_at(rng.randi_range(0, spots.size() - 1))
			groups.append(_new_group(spot))


## Every perch not there now (its car park not built) plus the ones the groups
## other than `skip` hold or fly to.
func closed_spots(skip: Dictionary) -> Array[int]:
	var out := busy_spots(skip)
	var there := BirdPerches.available(_lots_seen)
	for i in BirdPerches.SPOTS.size():
		if not there.has(i):
			out.append(i)
	return out


func _lots_now() -> Array[bool]:
	if landside_views == null or landside_views.landside == null:
		return []
	return landside_views.landside.lots_built.duplicate()


## Where every drawn moving car (a parked one is still) and every drawn
## passenger stands now.
func threats_now() -> PackedVector3Array:
	var out := PackedVector3Array()
	if landside_views != null and landside_views.landside != null:
		var alpha := clock.alpha if clock != null else 1.0
		for id in landside_views.landside.vehicle_ids():
			var v := landside_views.landside.get_vehicle(id)
			if v == null or v.stage == LandsideVehicle.Stage.PARKED:
				continue
			var at := landside_views.pose_at(id, alpha).origin
			if at != Vector3.ZERO:
				out.append(at)
	if passenger_views != null and passenger_views.sim != null:
		for id in passenger_views.sim.passenger_ids():
			var node := passenger_views.node_for(id)
			if node != null and node.is_visible_in_tree():
				out.append(node.global_position)
	return out


## Advances the flock `dt` seconds of sim time with cars and passengers at
## `threats`: perched groups with a threat in range take off, flying birds
## move along their arcs, perched birds change clip now and then.
func step(dt: float, threats: PackedVector3Array) -> void:
	if dt <= 0.0:
		return
	for g in groups:
		if g["target"] < 0:
			g["settle"] = maxf(g["settle"] - dt, 0.0)
			if (
				g["settle"] <= 0.0
				and BirdPerches.scatter_due(BirdPerches.SPOTS[g["spot"]], threats)
			):
				_scatter(g, threats)
		for b in g["birds"]:
			if b["landed"]:
				_perch_tick(b, dt)
			else:
				_fly_tick(b, dt)
		if g["target"] >= 0 and g["birds"].all(func(b: Dictionary) -> bool: return b["landed"]):
			g["spot"] = g["target"]
			g["target"] = -1
			g["settle"] = SETTLE_S


## The perches the groups other than `skip` hold or fly to.
func busy_spots(skip: Dictionary) -> Array[int]:
	var busy: Array[int] = []
	for g in groups:
		if g != skip:
			busy.append(g["spot"])
			if g["target"] >= 0:
				busy.append(g["target"])
	return busy


func _new_group(spot: int) -> Dictionary:
	var g := {"spot": spot, "target": -1, "settle": 0.0, "birds": []}
	var centre: Vector3 = BirdPerches.SPOTS[spot]
	var yaw := rng.randf_range(-PI, PI)
	var size := rng.randi_range(GROUP_MIN, ZONE_GROUP_MAX[BirdPerches.ZONES[spot]])
	for off in BirdPerches.offsets(rng, size, spot, bird_scale):
		var node: Node3D = CROW.instantiate()
		var variant := VARIANTS[rng.randi_range(0, VARIANTS.size() - 1)]
		for v in VARIANTS:
			(node.find_child(v, true, false) as Node3D).visible = v == variant
		add_child(node)
		var at := centre + off + Vector3(0.0, FOOT_LIFT * bird_scale, 0.0)
		var b := {
			"node": node,
			"player": node.find_child("AnimationPlayer", true, false),
			"at": at,
			"from": at,
			"to": at,
			"lift": 0.0,
			"t": 0.0,
			"dur": 0.0,
			"clip": "",
			"hold": 0.0,
			"landed": true,
		}
		_place(node, at, Vector3.FORWARD.rotated(Vector3.UP, yaw + rng.randf_range(-0.6, 0.6)), 0.0)
		_play(b, PERCHED_CLIPS[rng.randi_range(0, PERCHED_CLIPS.size() - 1)], rng.randf())
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)
		g["birds"].append(b)
	return g


func _scatter(g: Dictionary, threats: PackedVector3Array) -> void:
	var target := BirdPerches.pick(rng, g["spot"], closed_spots(g), threats)
	if target < 0:
		return
	var offs := BirdPerches.offsets(rng, g["birds"].size(), target, bird_scale)
	if offs.size() < g["birds"].size():
		return  # no room drawn this time; the group tries again next step
	g["target"] = target
	var centre: Vector3 = BirdPerches.SPOTS[target]
	var lifts: Vector2 = ZONE_LIFTS[BirdPerches.ZONES[target]]
	for i in g["birds"].size():
		var b: Dictionary = g["birds"][i]
		b["from"] = b["at"]
		b["to"] = centre + offs[i] + Vector3(0.0, FOOT_LIFT * bird_scale, 0.0)
		b["lift"] = rng.randf_range(lifts.x, lifts.y)
		b["dur"] = maxf(MIN_FLIGHT_S, flight_length(b["from"], b["to"], b["lift"]) / FLIGHT_SPEED)
		b["t"] = -rng.randf_range(0.0, MAX_DELAY)
		b["landed"] = false


func _perch_tick(b: Dictionary, dt: float) -> void:
	b["hold"] -= dt
	if b["hold"] <= 0.0:
		_play(b, PERCHED_CLIPS[rng.randi_range(0, PERCHED_CLIPS.size() - 1)], 0.0)
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)


func _fly_tick(b: Dictionary, dt: float) -> void:
	b["t"] += dt
	var t: float = b["t"]
	if t < 0.0:
		return
	var dur: float = b["dur"]
	if t >= dur:
		var last := flight_point(b["from"], b["to"], b["lift"], 1.0)
		last -= flight_point(b["from"], b["to"], b["lift"], 0.98)
		b["at"] = b["to"]
		b["landed"] = true
		_place(b["node"], b["to"], _flat(last, b["node"]), 0.0)
		_play(b, PERCHED_CLIPS[rng.randi_range(0, 1)], 0.0)
		b["hold"] = rng.randf_range(CLIP_HOLD_MIN, CLIP_HOLD_MAX)
		return
	var u := smoothstep(0.0, 1.0, t / dur)
	var at := flight_point(b["from"], b["to"], b["lift"], u)
	var ahead := flight_point(b["from"], b["to"], b["lift"], minf(u + 0.01, 1.0)) - at
	if u + 0.01 > 1.0:
		ahead = at - flight_point(b["from"], b["to"], b["lift"], u - 0.01)
	var clip := "fly"
	if t < TAKEOFF_S:
		clip = "takeoff"
	elif t >= dur - LAND_S:
		clip = "land"
	elif ahead.y < 0.0:
		clip = "soar"
	if clip != b["clip"]:
		_play(b, clip, 0.0)
	var pitch := 0.0
	if clip != "land" and clip != "takeoff":
		pitch = atan2(ahead.y, Vector2(ahead.x, ahead.z).length())
		pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)
	_place(b["node"], at, _flat(ahead, b["node"]), pitch)


## The point `u` (0 to 1) along a flight from `from` to `to`: a cubic curve
## whose middle control points stand `lift` metres above both ends and AWAY
## metres out from the facade, so the bird leaves and lands steeply and does
## its crossing high.
## It tops out at 0.75 * `lift` above the ends.
static func flight_point(from: Vector3, to: Vector3, lift: float, u: float) -> Vector3:
	var p1 := from + Vector3(0.0, lift, AWAY)
	var p2 := to + Vector3(0.0, lift, AWAY)
	var v := 1.0 - u
	return from * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + to * (u * u * u)


## The length of a flight, summed over 32 straight pieces.
static func flight_length(from: Vector3, to: Vector3, lift: float) -> float:
	var total := 0.0
	var prev := from
	for i in range(1, 33):
		var p := flight_point(from, to, lift, i / 32.0)
		total += prev.distance_to(p)
		prev = p
	return total


## `dir` flattened onto the ground, or the node's own heading when it has none.
static func _flat(dir: Vector3, node: Node3D) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 1e-4:
		return node.basis.z.normalized()
	return flat.normalized()


## Puts the crow (its head along the model's +Z) at `at`, heading `forward`
## (flat), nose tilted up by `pitch` radians.
func _place(node: Node3D, at: Vector3, forward: Vector3, pitch: float) -> void:
	var basis := Basis.looking_at(forward, Vector3.UP, true)
	basis = basis * Basis(Vector3.RIGHT, -pitch)
	node.transform = Transform3D(basis.scaled(Vector3.ONE * bird_scale), at)


func _play(b: Dictionary, clip: String, start_frac: float) -> void:
	var player: AnimationPlayer = b["player"]
	b["clip"] = clip
	player.play(clip, BLEND_S)
	if start_frac > 0.0:
		player.seek(player.current_animation_length * start_frac, true)


func _on_loaded(ok: bool) -> void:
	if ok:
		rebuild()
