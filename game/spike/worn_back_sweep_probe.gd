extends SceneTree
## Measures CarryWorn.BACK_ON_SPINE_M (board 4af10dd0): for every body
## (PassengerLooks.BODIES) and both pack sizes (one bag, two at
## SecurityLooks.TWO_BAG_SCALE), where the top of a worn pack's panel goes so
## it rests on the back. For each height in TOPS_M over the Spine_03 bone, the
## distance behind it is bisected until the least gap from the body's own back
## to the panel (spike/worn_back_gap.gd), over the idle and walk clips at
## MOMENTS moments each, is just over CarryWorn.BACK_CLEAR_M; the height whose
## largest gap over the clips is least is kept. Each body is posed at the
## origin facing +z with its carry rig and skinned by hand, so the numbers are
## the same headless and windowed. Prints one SWEEP line per body and size and
## the table to paste. Exits 1 (PROBE_INVALID) when a size's largest gap is
## over WornBackGap.WORN_GAP_M or a pose sees too few back points.
##
## Run headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/worn_back_sweep_probe.gd

const WornBackGap := preload("res://spike/worn_back_gap.gd")
const CLIPS: Array[String] = ["idle", "walk"]
const MOMENTS := 64
const TOPS_M: Array[float] = [-0.03, 0.0, 0.03, 0.06]
const ROUNDS := 16
## Points behind the chest inside the panel outline, at the fewest.
const MIN_POINTS := 3

var _props: CarryOnProps
## [body, spine (world), back points (world)] per posed moment.
var _poses: Array = []
var _bodies: Array[Node3D] = []
var _frames := 0


func _initialize() -> void:
	_props = CarryOnProps.new()
	root.add_child(_props)
	for b in PassengerLooks.BODIES.size():
		for clip in CLIPS:
			for n in MOMENTS:
				var body := PassengerLooks.SCENES[b].instantiate() as Node3D
				body.set_meta(&"body", b)
				root.add_child(body)
				var player := body.get_node("AnimationPlayer") as AnimationPlayer
				player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				player.play(clip)
				player.seek(player.current_animation_length * n / MOMENTS, true)
				_props._rig(body)
				_bodies.append(body)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	for body in _bodies:
		var spine := _props._spine_of(body)
		# Only the points behind the chest can meet the panel (the body faces +z).
		var behind := PackedVector3Array()
		for p in WornBackGap.back_points(body):
			if p.z < spine.origin.z + 0.05:
				behind.append(p)
		_poses.append([body.get_meta(&"body"), spine, behind])
		body.free()
	var failed := false
	var table: Array[String] = []
	for b in PassengerLooks.BODIES.size():
		var per := Vector4.ZERO
		for size in 2:
			var scale_by := 1.0 if size == 0 else SecurityLooks.TWO_BAG_SCALE
			var best: Array = []
			for top_over in TOPS_M:
				var found := _settle(b, scale_by, top_over)
				if best.is_empty() or found[2] < best[2]:
					best = found
			var ok: bool = best[2] <= WornBackGap.WORN_GAP_M and best[3] >= MIN_POINTS
			failed = failed or not ok
			per[size * 2] = snappedf(best[0], 0.001)
			per[size * 2 + 1] = best[4]
			print(
				(
					"SWEEP body %d %s %s: top %.3f m behind, %.2f m over the spine, gap %.4f..%.4f, pts %d%s"
					% [
						b,
						PassengerLooks.BODIES[b],
						"one bag" if size == 0 else "two bags",
						best[0],
						best[4],
						best[1],
						best[2],
						best[3],
						"" if ok else " PROBE_INVALID"
					]
				)
			)
		table.append("\tVector4(%.3f, %.2f, %.3f, %.2f)," % [per.x, per.y, per.z, per.w])
	print("TABLE\n" + "\n".join(table))
	if failed:
		print("PROBE_INVALID a size's largest gap is over the limit or it saw too few points")
		quit(1)
	return true


## [distance behind, least gap, largest gap, fewest points, height] for body
## `b`'s pack at `scale_by` with its top `top_over` over the spine: the
## distance bisected to the least one whose least gap is BACK_CLEAR_M or more
## (the gap grows with the distance, not at one rate: near the pack's top edge
## the shoulders slope away from the panel).
func _settle(b: int, scale_by: float, top_over: float) -> Array:
	var near := 0.0
	var far := CarryWorn.BACK_FROM_SPINE_M + 0.05
	for r in ROUNDS:
		var at := (near + far) / 2.0
		if _gaps(b, scale_by, Vector2(at, top_over))[0] < CarryWorn.BACK_CLEAR_M:
			near = at
		else:
			far = at
	var got := _gaps(b, scale_by, Vector2(far, top_over))
	return [far, got[0], got[1], got[2], top_over]


## [least gap, largest gap, fewest points in the outline] of body `b`'s posed
## moments with the pack at `scale_by`, the top of its panel at `top` (x
## behind, y over the spine).
func _gaps(b: int, scale_by: float, top: Vector2) -> Array:
	var lo := INF
	var hi := -INF
	var fewest := 1 << 30
	for pose in _poses:
		if pose[0] != b:
			continue
		var xf := CarryWorn.worn_back_at(pose[1], 0.0, scale_by, top, scale_by >= 1.0)
		var got: Array = WornBackGap.panel_gap(pose[2], xf)
		lo = minf(lo, got[0])
		hi = maxf(hi, got[0])
		fewest = mini(fewest, got[2])
	return [lo, hi, fewest]
