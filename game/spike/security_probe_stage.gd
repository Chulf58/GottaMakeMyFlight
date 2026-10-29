extends RefCounted
## Two staged situations for security_visuals_plates_probe.gd, kept out of the
## probe (it sits near gdlint's file cap). Load with preload(); no class_name.
##
## lift_ends: the "lane_2_unpack" moment. Since the Security 8/8 unpack halving
## (SecurityRuntime.LANE_UNPACK_TICKS 3, LANE_UNPACK_BAG_TICKS 4) the last
## bag's move into the tray (CarryOnProps.TRANSFER_TICKS, 6) outlasts the
## UNPACK phase, so no frame of UNPACK has every bag settled, and a plate in
## the air finds no heading where the lifted bag, the tray and the carrier are
## all seen. The unpack plate is taken at the end of the lift instead: the
## first look at which every bag is down in the tray (the caller also asks for
## every move to be settled), the passenger still at the tray table, just
## walking into the arch.
##
## An instance is the sweep's sharp-turn control. A pulled roller turns sharply
## on a real walk only where a route has a corner inside the sweep window,
## which depends on the seed. The control turns the body of one real roller
## carrier a quarter turn for HOLD_FRAMES frames (step(), before the frame is
## drawn) and lets the real follower and the real snap judge see it (count(),
## after). The views set a heading only on a body that moves, sits or faces
## something, so the carrier is one that does none of these and keeps the
## turn; one where the turn is not seen is given back and another is tried.

## How far along the lane (0 unpack cell, 1 pickup cell) the passenger may have
## walked for the lift's end.
const LIFT_END_BELOW := 0.2
## The staged turn, radians: well over judge_pulled's 60 degrees.
const TURN_RAD := PI / 2.0
## The first sweep frame the control may start on (the rollers are followed
## from the frame before), the last, and the frames the turn is held.
const START_FRAME := 6
const LAST_START_FRAME := 60
const HOLD_FRAMES := 4

## The staged roller (0 none yet), the frame it started on, and the sharp
## turns the judge counted from the start to the release.
var roller := 0
var first_frame := -1
var sharp := 0
var _heading := 0.0
var _tried := {}


## Whether `p`, walking the arch for the first time and `progress` along the
## lane, has every bag in the tray.
static func lift_ends(sim: PassengerSim, p: Passenger, progress: float) -> bool:
	return (
		p.security_phase == SecurityRuntime.Phase.ARCH
		and not p.incident_resolved
		and p.carry_on > 0
		and progress > -LIFT_END_BELOW / 2.0
		and progress < LIFT_END_BELOW
		and SecurityLooks.bag_homes(sim, p).all(
			func(h: SecurityLooks.Home) -> bool: return h == SecurityLooks.Home.TRAY
		)
	)


## Before sweep frame `frame` is drawn: starts the turn on a roller carrier
## standing still among `pulled` (id -> last look), holds it, and gives the
## body back after HOLD_FRAMES.
func step(views: PassengerViews, sim: PassengerSim, pulled: Dictionary, frame: int) -> void:
	if roller == 0:
		if frame < START_FRAME or frame >= LAST_START_FRAME:
			return
		for id: int in pulled:
			var body := views.node_for(id)
			var p := sim.get_passenger(id)
			if _tried.has(id) or body == null or p == null or p.is_moving():
				continue
			if body.get_meta(&"seated", false) or body.get_meta(&"faces", false):
				continue
			roller = id
			first_frame = frame
			_heading = body.rotation.y
			break
	var staged := views.node_for(roller)
	if staged == null or frame > first_frame + HOLD_FRAMES:
		return
	var held := frame < first_frame + HOLD_FRAMES
	staged.rotation.y = wrapf(_heading + TURN_RAD, -PI, PI) if held else _heading


## After the frame: `turned` sharp turns were counted on it.
func count(views: PassengerViews, frame: int, turned: int) -> void:
	if roller == 0 or frame < first_frame or frame > first_frame + HOLD_FRAMES:
		return
	sharp += turned
	if frame == first_frame and turned == 0:
		var staged := views.node_for(roller)
		if staged != null:
			staged.rotation.y = _heading
		_tried[roller] = true
		roller = 0
		first_frame = -1
		sharp = 0
