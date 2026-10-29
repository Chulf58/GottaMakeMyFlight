extends RefCounted
## The windowed check that hand bags are placed once a frame from the hand's
## final pose (decision carry-on-bag-kinds-as-built item 6; CarryOnProps
## _on_pose and _unposed). Connected to RenderingServer.frame_pre_draw after
## CarryOnProps (so after its own pre-draw fallback), each look, just before
## the frame is drawn:
## - every bag in a hand (any kind) was placed as many times as the props were
##   drawn since the last look (once a frame; twice on a snap() frame), and
## - every settled hard case or lifted roller in a hand has its held point
##   (CarryOnProps.held_point) on the hand now (grip_of), within GRIP_TOL_M.
## Headless runs never emit frame_pre_draw, so this runs only windowed.
## Load with preload(); no class_name.

const GRIP_TOL_M := 0.001

var looks := 0
## Bag looks whose placements matched the draws, and those that did not.
var placed_ok := 0
var placed_bad := 0
## Looks where the props were drawn twice since the last look.
var double_draws := 0
## Held points compared with the hand, the farthest, and how many were off.
var grips := 0
var grip_max_m := 0.0
var grips_off := 0
## Skeleton reports that came before the props were drawn in their frame.
var early_reports := 0
var _views: PassengerViews
## Passenger id -> its props' draws at the last look.
var _draws_at_look := {}
var _sim: PassengerSim
## [id, bag index] -> [placements, draws] at the last look.
var _last := {}
var _notes: Array[String] = []


func start(views: PassengerViews, sim: PassengerSim) -> void:
	_views = views
	_sim = sim
	if not RenderingServer.frame_pre_draw.is_connected(_look):
		RenderingServer.frame_pre_draw.connect(_look)


func stop() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_look):
		RenderingServer.frame_pre_draw.disconnect(_look)


## One printable line of the counts.
func report() -> String:
	var placed := (
		"looks=%d placed_ok=%d placed_bad=%d double_draws=%d early_reports=%d"
		% [looks, placed_ok, placed_bad, double_draws, early_reports]
	)
	var held := "grips=%d grip_max_mm=%.3f grips_off=%d" % [grips, grip_max_m * 1000.0, grips_off]
	return "SWEEP grip at pre-draw: %s %s" % [placed, held]


## What failed, empty when the check passed (and was engaged).
func problems() -> Array[String]:
	var out: Array[String] = []
	if looks == 0 or placed_ok == 0 or grips == 0:
		out.append("grip watch saw no hand bag (control): %s" % report())
	if placed_bad > 0:
		out.append("a hand bag was not placed once per draw: %s %s" % [report(), _notes])
	if grips_off > 0:
		out.append("a hand bag's grip is off the final hand: %s %s" % [report(), _notes])
	return out


func _look() -> void:
	looks += 1
	var props := _views.carry_on_props()
	var seen := {}
	for id in _sim.passenger_ids():
		var body := _views.node_for(id)
		var p := _sim.get_passenger(id)
		if body == null or p == null:
			continue
		var homes := SecurityLooks.bag_homes(_sim, p)
		var drawn: Array = props.props_of(id)["bags"]
		if drawn.size() != homes.size():
			continue
		var draws := props.draws_of(id)
		_listen(body, id, draws)
		for i in homes.size():
			if homes[i] != SecurityLooks.Home.HAND:
				continue
			var key := [id, i]
			seen[key] = true
			# Every look, a snap() frame included.
			_grip(props, body, p, id, i)
			var now := [props.placements_of(id, i), draws]
			var was: Array = _last.get(key, [])
			_last[key] = now
			# Not drawn since, or a new record (a snap() starts every one over).
			if was.is_empty() or now[1] <= was[1] or now[0] < was[0]:
				continue
			double_draws += int(now[1] - was[1] > 1)
			if now[0] - was[0] == now[1] - was[1]:
				placed_ok += 1
			else:
				placed_bad += 1
				_note("id=%d i=%d placed=%d draws=%d" % [id, i, now[0] - was[0], now[1] - was[1]])
	for key in _last.keys():
		if not seen.has(key):
			_last.erase(key)


func _grip(props: CarryOnProps, body: Node3D, p: Passenger, id: int, i: int) -> void:
	if props.transfer_progress(id, i) < 1.0:
		return
	var at := props.held_point(id, i)
	if not at.is_finite():
		return
	var off := at.distance_to(props.grip_of(body, SecurityLooks.hand_of(_sim, p, i)))
	grips += 1
	grip_max_m = maxf(grip_max_m, off)
	if off > GRIP_TOL_M:
		grips_off += 1
		_note("id=%d i=%d grip_off_mm=%.2f" % [id, i, off * 1000.0])


## Counts the reports of `body`'s skeleton that come before the props are drawn
## in a frame (draws_of unchanged since the last look): the frames whose first
## report is not the final one.
func _listen(body: Node3D, id: int, draws: int) -> void:
	_draws_at_look[id] = draws
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if skeleton.has_meta(&"grip_watch"):
		skeleton.set_meta(&"grip_watch", id)
		return
	skeleton.set_meta(&"grip_watch", id)
	skeleton.skeleton_updated.connect(
		func() -> void:
			var who: int = skeleton.get_meta(&"grip_watch")
			var props := _views.carry_on_props()
			if props.draws_of(who) == int(_draws_at_look.get(who, -1)):
				early_reports += 1
	)


func _note(text: String) -> void:
	if _notes.size() < 8:
		_notes.append(text)
