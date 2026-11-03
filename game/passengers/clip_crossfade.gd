class_name ClipCrossfade
extends SkeletonModifier3D
## Blends a passenger's bones from the pose it was drawn with when its clip
## changed to the new clip's pose (user ruling
## passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima), so a clip
## change never moves the body or the hands in one frame. The pose at the
## change is held still and the blend eases in with a smoothstep over
## PassengerViews.CROSSFADE_SECONDS of sim time. A change during a blend starts
## the next blend from the blended pose drawn last, which the AnimationPlayer's
## own crossfade does not do (measured 2026-11-03: a second play() 0.1 s into a
## 0.18 s blend moved a hand 0.2 m in one frame).
##
## The first modifier on the skeleton: it runs on the animation's pose, and the
## carry and recline modifiers after it bend the blended pose. The skeleton
## puts its bones back to the animation's pose after every update, so a bone's
## pose read between updates is the clip's as drawn, before any modifier.
## PassengerViews starts a blend in its tick (begin) and sets the weight from
## the sim time every frame (ease_to); stop() ends it, as a snap does.

## 0 the pose at the change, 1 the new clip alone.
var weight := 1.0
## Whether the view has been drawn since it was taken (PassengerViews sets it
## each frame), so its bones hold a clip's pose: a pooled body taken again
## holds its last passenger's pose, a new one its rest pose, and neither is
## blended from.
var drawn := false
## The pose at the change, one Transform3D per bone; empty when not blending.
var _from: Array[Transform3D] = []
## The blended pose drawn last, kept while blending.
var _out: Array[Transform3D] = []
## The sim time (ticks) the blend started at.
var _since := 0.0


## Whether a blend is under way.
func blending() -> bool:
	return not _from.is_empty()


## Starts a blend at sim time `now` (ticks) from the pose drawn now; one never
## drawn plays the new clip alone.
func begin(now: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not drawn:
		stop()
		return
	var count := skeleton.get_bone_count()
	if blending() and _out.size() == count:
		_from = _out.duplicate()
	else:
		_from.resize(count)
		for b in count:
			_from[b] = skeleton.get_bone_pose(b)
	_out = _from.duplicate()
	_since = now
	weight = 0.0


## Sets the weight for sim time `now` (ticks) on a blend of `seconds`; a
## blend that has run its time, or one started after `now` (a clock that went
## back), ends.
func ease_to(now: float, seconds: float) -> void:
	if not blending():
		return
	var t := (now - _since) / (seconds * SimClock.TICK_RATE)
	if t < 0.0 or t >= 1.0:
		stop()
		return
	weight = t


func stop() -> void:
	weight = 1.0
	_from.clear()
	_out.clear()


func _process_modification_with_delta(_delta: float) -> void:
	if not blending():
		return
	var skeleton := get_skeleton()
	if skeleton == null or skeleton.get_bone_count() != _from.size():
		stop()
		return
	var w := smoothstep(0.0, 1.0, weight)
	for b in _from.size():
		var from: Transform3D = _from[b]
		var to := skeleton.get_bone_pose(b)
		var turn := from.basis.get_rotation_quaternion().slerp(
			to.basis.get_rotation_quaternion(), w
		)
		var size := from.basis.get_scale().lerp(to.basis.get_scale(), w)
		var at := from.origin.lerp(to.origin, w)
		skeleton.set_bone_pose_position(b, at)
		skeleton.set_bone_pose_rotation(b, turn)
		skeleton.set_bone_pose_scale(b, size)
		_out[b] = Transform3D(Basis(turn) * Basis.from_scale(size), at)
