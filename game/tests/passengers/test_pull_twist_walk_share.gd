class_name TestPullTwistWalkShare
extends GdUnitTestSuite
## The pulling arm's set twist follows the walk clip's share of the drawn pose
## (CarryArmPose.walk_share()) through ClipCrossfade blends, with no jump when
## a blend is cut short by another clip change: ClipCrossfade.begin() starts
## the new blend from the pose drawn last, so the share must start from the
## share drawn last. Idle to walk is cut at half way by run, and by idle; the
## crossfade weight goes up STEP a frame. On 0c03eec the cut started the new
## blend from the share before the first blend (0), and the share fell from
## 0.5 to 0 in one frame.

const STEP := 0.05
## smoothstep's steepest slope is 1.5, so STEP moves the share at most 0.075.
const MAX_CHANGE := 0.1

var _body: Node3D
var _fade: ClipCrossfade


func before_test() -> void:
	_body = auto_free(Node3D.new())
	_fade = auto_free(ClipCrossfade.new())
	_body.set_meta(&"crossfade", _fade)
	_body.set_meta(&"clip", "idle")


## A blend to `clip` starts now, as PassengerViews starts one (ClipCrossfade
## begin(): weight 0, a pose held to blend from).
func _begin(clip: String) -> void:
	_body.set_meta(&"clip", clip)
	_fade._from = [Transform3D()]
	_fade.weight = 0.0


## The shares drawn while the blend's weight goes from 0 to `to`, STEP a frame.
func _ease(held: Dictionary, to: float) -> Array[float]:
	var shares: Array[float] = []
	var w := 0.0
	while w <= to + 0.0001:
		_fade.weight = w
		shares.append(CarryArmPose.walk_share(held, _body))
		w += STEP
	return shares


func _cut_short_by(then: String) -> Array[float]:
	var held := {}
	var shares: Array[float] = [CarryArmPose.walk_share(held, _body)]
	_begin("walk")
	shares.append_array(_ease(held, 0.5))
	_begin(then)
	shares.append_array(_ease(held, 1.0))
	_fade.stop()
	shares.append(CarryArmPose.walk_share(held, _body))
	return shares


func test_a_walk_blend_cut_short_by_run_eases_the_twist_out() -> void:
	_check(_cut_short_by("run"), 0.0)


func test_a_walk_blend_cut_short_by_idle_eases_the_twist_out() -> void:
	_check(_cut_short_by("idle"), 0.0)


func _check(shares: Array[float], last: float) -> void:
	var worst := 0.0
	var top := 0.0
	for i in range(1, shares.size()):
		worst = maxf(worst, absf(shares[i] - shares[i - 1]))
		top = maxf(top, shares[i])
	print("shares %s, largest change a frame %.3f" % [shares, worst])
	# Control: the walk blend got the share up to half way before the cut.
	assert_float(top).is_equal_approx(0.5, 0.01)
	assert_float(worst).is_less(MAX_CHANGE)
	assert_float(shares[shares.size() - 1]).is_equal(last)
