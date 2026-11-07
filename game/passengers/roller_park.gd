class_name RollerPark
extends RefCounted
## A roller laid on the floor from the pull, and taken off the floor into the
## pull, outside a toilet stall (decision roller-laid-on-the-floor-stand-it-
## up-by-the-bar-park-it-upri, board 5b0fa979). Its grip bar and its carry
## handle are 0.215 m apart even with the rods in, more than twice the probes'
## GRIP_ON reach of either, so the hand changes grip while the bag stands
## parked on its wheels beside the passenger, on the hand's side, and every
## frame a hand holds it, it holds the bar or the handle. CarryLead.plan()
## hands such a move (stamped "park", stamp()) to plan() here, which writes
## nothing but the moment the hand took a lying bag ("park_took", _taken()).
##
## pull>floor goes in four parts of TICKS_DOWN:
## - stand (to STAND_END): the hand on the bar, the rods going in, the bag rolls
##   on its axle to the park and stands up on its wheels;
## - park (to PARK_END): no hand on the bag, which stands still at the park,
##   while the empty hand goes over its top from the bar to the carry handle;
## - lay down (to LAY_END): the hand on the handle, the bag lifted out and laid
##   down ahead (CarryLead.path());
## - let go: the bag on the floor, the hand coming back.
## floor>pull (TICKS_UP) is the same backwards: the hand reaches the lying
## bag's handle (taking it from REACH_END, once there), lifts it to the park,
## lets go while the hand goes from the handle over the top to the bar
## (up_ends()), and holds the bar as the bag tips back on its axle into the
## pull, its rods running out.
## What it does not guarantee: the hand reaching its target (CarryArm's reach
## is limited; held, the bag is placed from where the grip is), or the park
## being clear of anything beside the passenger (a chair, a neighbour).

## A move that parks the roller takes this many sim ticks (not
## CarryOnProps.TRANSFER_TICKS), the parked part 3 ticks or more, so a game at
## 3x (one tick a frame) draws the bag standing alone on 3 frames.
const TICKS_DOWN := 13.0
const TICKS_UP := 16.0
## pull>floor: the ends of the stand, the park and the lay down (k).
const STAND_END := 0.37
const PARK_END := 0.6
const LAY_END := 0.83
## floor>pull: the ends of the reach, the lift and the park (k), and the lead
## (UP_LEAD_TICKS) its start once had over the end of a stand-up. No stand-up
## uses the lead now: the pick-up starts once the passenger is up, and it stands
## until the pick-up is over (ParkRecovery.UP_HOLD_TICKS, decision standing-up-
## with-a-roller-stand-up-then-pick-up-then-walk, board 2c659e42). With the
## lead the hand took the lying bag about 20 ticks into the stand-up, and the
## park ended 3 to 4 ticks into the walk off, beside the walker's way
## (UP_PARK_AHEAD_M).
const REACH_END := 0.25
const TAKE_BY := 0.4
const LIFT_END := 0.55
const UP_PARK_END := 0.74
const UP_LEAD_TICKS := 9
## The park: the axle this far out on the hand's side of the body's centre
## line and this far ahead of it, in the body's frame when the move began:
## under the hand's shoulder, so the hand reaches its bar down beside the hip
## (0.42 m out the hand stopped up to 0.3 m short as the walker sat down).
## Taken off the floor it parks further ahead (UP_PARK_AHEAD_M), where the
## walker comes past it stepping off: parked 0.45 m ahead, the walker had gone
## on and the hand was 0.16 m off the bar at 3x as it took it again.
const PARK_SIDE_M := 0.32
const PARK_AHEAD_M := 0.15
const UP_PARK_AHEAD_M := 0.7
## A roller laid across the front at a booth (round_front()) is fastest at
## this share of the lay (_across_eased()).
const ACROSS_FASTEST := 0.6
## A booth set-down that turns first (turns_first()) holds the roller still at
## its start this long while the walker turns to face out of the seat
## (PassengerTurns.TURN_TICKS), the pulling hand giving the bar to the other.
const TURN_FIRST_TICKS := float(PassengerTurns.TURN_TICKS)
## The share of that turn over which the roller stands up on its wheels and
## its rods run in (turned_round(), rods_t()).
const TURN_UP_SHARE := 0.5
## Laying it down and letting go, the stoop bends the back first and the hips
## go down only as far as that leaves the hand short, not back (CarryStoop.
## drops): with the hips going back as well, the hand of a walker sitting down
## stopped 6 to 9 cm over the handle on the floor ahead, and the bag let go
## dropped that far.
## The hips also go back (HIP_BACK_M) now the body stands while it parks the
## roller (SitHold, ActivityPoses.seat_door()): with the back capped at
## BACK_CAP the hips go lower, and without going back the knees came forward
## onto a roller lying close in front (user ruling roller-park-stoop-cap-the-
## back-at-about-45-degrees-and-push-the-hips-back, board 68c6027e).
const LAY_HIPS := Vector3(PARK_DROP, 1.0, 1.0)
## The hips' drop of a parking move, a share of CarryStoop.STOOP_DROP: with the
## back capped at BACK_CAP the hand stopped up to 6.5 cm short of a roller
## beside the feet and of its park beside the hip at 0.6.
const PARK_DROP := 1.25
const PARK_HIPS := Vector3(PARK_DROP, 1.0, 0.0)
## The back bends at most this share of CarryStoop.STOOP_DEGREES in a parking
## move (about 45 degrees; CarryStoop.bends), the hips taking the rest: at 80
## degrees the head folded under the shoulders lifting the roller.
const BACK_CAP := 45.0 / CarryStoop.STOOP_DEGREES
## A roller laid down at a gate chair lies this far out on its hand's side of
## the passenger's line (floor_spot()), beside the feet and the chair's front
## corner (a chair seat is about 0.5 m wide).
const BESIDE_FEET_M := 0.34
const FEET_AHEAD_M := 0.07
## A collecting walker's stoop goes from LAY_HIPS to HIPS_ALL over this many
## ticks from the lift's end (drops_of()).
const LOW_EASE_TICKS := 3.0
## The empty hand goes from the bar to the handle over the bag's top through
## this point (own frame, scale 1): over the top end and out past the front
## panel (0.2 m), so it comes down onto the handle from outside the shell.
const OVER_TOP := Vector3(0.0, 0.22, 0.33)
## Off the floor the hand takes the lying bag once its grip is this close to
## the handle (body["grips"]), from REACH_END on, and at TAKE_BY whatever: the
## bag waits on the floor until then. The lift then runs to LIFT_END, or for
## UP_PART of the move when it was taken late, and the park for UP_PART more
## (up_ends()): taken late at 3x, a lift squeezed into 1.8 ticks drew the hand
## 0.24 m from one frame to the next.
## Taken at REACH_END on the clock, a walker still standing up had its hand
## 0.18-0.29 m short, and the bag jumped that far into it.
const TAKE_M := 0.05
const UP_PART := 0.19
## Off the floor, the hand's reach for the lying bag is at full weight this many
## ticks before REACH_END, and the rods start out this many ticks after the park
## ends (rods_t()): at 3x (a tick a frame) the frame the hand takes the bag, or
## takes the bar again, then has the hand already on its grip and the bar where
## the hand reached for it. Taken on the last step of the reach's weight, the
## grip of a walker walking off moved 0.18 m in that frame; with the rods running
## out under the hand taking the bar of a walker sitting down again, 0.22 m.
const SETTLE_TICKS := 1.0
## Lifted off the floor to the park, the bag rises this much midway.
const LIFT_M := 0.12
## Off the floor, the walker moving this far from where it stood as the park
## began ends the park early: the empty hand goes the rest of its way over the
## top to the bar in UP_CUT_TICKS (up_ends()), there by CUT_ON of it (the last
## frame alone must not leave the hand short of the bar). Held again by the bar, the bag
## tips into the pull in the body's frame (_followed()), never left standing in
## the world as the walker goes: a late walker runs off, and its hand was 0.31
## m from one frame to the next at 1x, 1.0 m at 3x, reaching back for it. Left
## by the hand, the bag stands still in the world, never sliding on the floor
## (conductor ruling 2026-10-31 on board 5b0fa979).
const MOVED_M := 0.01
const UP_CUT_TICKS := 2.0
const CUT_ON := 0.7
## Taken again by the bar, the bag goes with the body from this share of the
## way from the last frame it stood alone to now (_followed()): the hand on the
## bar moves that share of the walker's step against the body, the bag the rest
## in the world, on top of what the hand was short of the bar.
const FOLLOW_SPLIT := 0.7
## Leaving a seat (decision leaving-a-seat-with-a-roller-roll-it-upright-
## until-clear-then-tip, board 2c659e42): a floor>pull stamped with a face
## (sit_face(): a gate chair, a cafe seat, a sofa or nap pod) whose walker has
## not moved by the park's end keeps the roller standing upright, held by the
## bar and carried with the body (_followed()), until the body is CLEAR_M from
## where it stood in the park, and only then tips it into the pull over TIP_UP.
## Measured (cafe_roller_standup_probe, the roller's box against the seat's):
## tipped at the seat, the pull's trail lay up to 0.33 m inside the sofa, pod
## or chair; tipped 0.9 m out, 0.05 m in the sofa and 0.2 m in a cafe chair the
## guest walked back past; 1.3 m out, the sofa and pod clear, the chair 0.04 m.
## A trail tested as a segment behind the body tipped too soon: the roller
## rides on the hand's side, off that line.
## The move is then ROLL_TICKS longer, and the tip starts by then whatever.
## The lift, the park and the tip keep their timing in ticks: every phase is
## read in up_k(), sim ticks over TICKS_UP. Walkers moving before the park's
## end (a collecting walker, the shower's door) tip as before.
## Decided on sim ticks, never on drawn frames (roll_step(), board c0707a22):
## a decision taken on the first frame drawing the park's end never rolled a
## pick-up first drawn 9 ticks late (past LIFT_END), and one drawn every third
## tick rolled the shower's door pick-up and tipped a sofa's a tick late. The
## walker's stood point is its tick position ROLL_FROM ticks into the move and
## it must not move from there to ROLL_TO: the tick positions drawn over the
## park's nominal span, LIFT_END to UP_PARK_END (a body is drawn between its
## last two tick positions, so a tick behind).
const CLEAR_M := 1.5
const ROLL_FROM := floorf(TICKS_UP * LIFT_END)
const ROLL_TO := floorf(TICKS_UP * UP_PARK_END)
## The ticks of tick positions kept on a roller's record (roll_step()): past
## the longest rolled move (TICKS_UP + ROLL_TICKS).
const TRACK_TICKS := 64
## A floor>pull that does not roll runs its rods out over at least this many
## ticks before it ends (rods_t()).
const RODS_OUT_TICKS := 3.0
## The share of the rods run out while it rolls upright. Measured hips while
## rolling (probe ROLL_HIPS): 0.93 to 0.96 of standing at 0.45, 0.84 to 0.89 at
## 0.3; with them in the bar was at 0.48 m, all out at 2.1 m.
const ROLL_RODS := 0.45
const ROLL_TICKS := 36.0
const TIP_UP := 1.0 - UP_PARK_END
## Standing in a queue (decision a-guest-standing-still-in-a-queue-stands-the-
## roller-up-beside-them, board 3dc86b54): a walker pulling its roller that has
## stood still STILL_TICKS in one of QUEUE_STAGES stands it upright beside it,
## held by the bar, with the pull>floor's stand (QUEUE_STAND_TICKS, the hand on
## the bar, the bag rolled on its axle to the park), and keeps it there, carried
## with the body, until it walks on (or its home or lift changes): then the bag
## tips back into the pull over QUEUE_TIP_TICKS, as a rolled roller does. One
## move from the pull to the pull ("queue", queue_stand()), its length kept
## QUEUE_AHEAD_TICKS past the tick while the walker stands. With the stand on a
## single still tick, a walker stepping up one place in a queue (its next path
## the tick after it arrives) stood the bag up and tipped it at once.
## Its rods run out (or in) so the bar stands QUEUE_BAR_M over the floor
## (queue_reach()), where the hand beside the hip reaches it standing straight
## (CarryStoop bends nothing): the body rigs' shoulders are 1.644 m (male) and
## 1.549 m (female) up, arms 0.632 and 0.645 m, so the bar at the park needs to
## be 1.09 and 0.98 m up or more. With the rods ROLL_RODS of the pull's length
## (0.83 to 1.22 m) the guests held it with their knees bent and the hips back
## for the whole stand (Opus review of 700ffaa).
## A walker standing at the gate for want of a seat (STANDING) stands it up too,
## and so does one held in a boarding file (FILE_STAGES, filed_still()), board
## 44b974cc: both had the roller in the long walking pull for the whole wait,
## one standing at the gate desk with it inside the desk for about 373 ticks
## (finding how-often-does-a-roller-in-the-walking-pull-clip-through-fur).
const QUEUE_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CAFE_QUEUE,
	Passenger.Stage.CAFE_ORDER,
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.CHECKIN,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.STANDING,
]
const FILE_STAGES: Array[Passenger.Stage] = [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]
const STILL_TICKS := 4
## A file waiter waits this long still before the stand. A file moves up in a
## ripple: the walker behind waits for a full BoardingFiles.GAP_MM of room
## (700 mm, 7 ticks at a walk), so most still spells in a file are 4 to 10 ticks.
## With STILL_TICKS, 31 of 33 stands over three full boardings (seeds 4242, 7,
## 99; 104 file waiters) tipped back within 11 ticks of the stand's start, a
## stand and a tip every few ticks; with 12, 2 stands, both held.
const FILE_STILL_TICKS := 12
## The stand's roll from the pull to the park: with the park QUEUE_SIDE_M out
## the way is longer than the pull>floor's stand (TICKS_DOWN * STAND_END, 4.8
## ticks), whose pace stepped the bag 0.150 m and more a frame against the
## body (test_roller_queue_stand JUMP_M 0.15, board 03454587).
const QUEUE_STAND_TICKS := 5.5
const QUEUE_TIP_TICKS := TICKS_UP * TIP_UP
const QUEUE_AHEAD_TICKS := 2.0
const QUEUE_BAR_M := 1.12
## A queue stand parks the roller's axle this far out on the hand's side
## (queue_park()), by the body's variant (male, then female; PassengerLooks
## BODIES), not PARK_SIDE_M: the seat parks keep theirs. At 0.32 m the stood
## roller took in the near leg of every male body (board 03454587; windowed
## BODY_IN_STOOD_BAG 6 points for male_01, 26 for male_08) and the right leg of
## the female ones by its shell's box (test_roller_stand_clearance). The idle
## legs clear the shell's box from 0.41 m (male_08, left hand) and 0.345 m
## (female_08, right hand); each has about 2 cm more.
const QUEUE_SIDE_M: Array[float] = [0.43, 0.37]
## A walker that walks off facing more than this (radians) away from its way
## (PassengerViews.walk_heading()) turns toward it as it sets off, over
## PassengerTurns.TURN_TICKS: its stood roller's tip waits that long (tip_wait()),
## the roller standing beside the body as it turns, and then tips into the pull
## behind the body facing its way. Tipped while the body turned, the pull swung
## round the body at its trail (about 1.08 m) on top of the tip's own step: a
## gate stander walking off with a turn of 0.202 rad a frame stepped the bag
## 0.218 m against the body (board 4b9d1a4e; TIP_JUMP_M 0.21 in
## test_roller_queue_stand). Under this angle the swing is a small share of the
## step, and the tip goes at once.
const TIP_TURN_RAD := 0.5


## Whether a hand-led move of `bag` (CarryOnProps' record, its "was",
## "carry_from" and "carry" stamped, going to `home`, a SecurityLooks.Home) is
## a roller's from the pull onto the floor or off the floor into the pull,
## outside a stall (`in_stall`).
static func parks(bag: Dictionary, in_stall: bool, home: int) -> bool:
	if bag["kind"] != SecurityLooks.Kind.ROLLER or in_stall or not bag.get("led", false):
		return false
	var started := CarryLead.start_of(bag)
	if bag.get("queue_still", false):
		# Stood up in a queue (queue_stand()): from the pull to the pull.
		return (
			started[0] == CarryLead.End.HELD
			and bag["carry_from"] == SecurityLooks.Carry.PULL
			and home == SecurityLooks.Home.HAND
			and bag["carry"] == SecurityLooks.Carry.PULL
		)
	if started[0] == CarryLead.End.HELD:
		return bag["carry_from"] == SecurityLooks.Carry.PULL and home == SecurityLooks.Home.FLOOR
	var was: int = bag["was"]
	var off_floor := was >= 0 and was / 4 == SecurityLooks.Home.FLOOR
	return (
		off_floor and home == SecurityLooks.Home.HAND and bag["carry"] == SecurityLooks.Carry.PULL
	)


## Whether the lift of `bag` (CarryOnProps' record, a roller, of a bag of
## `kind` now, going to `home`) is held as it is at `now` (sim tick). A walker
## turning late lifts its roller into the hand (CarryOnProps._lifted); stamped
## as a new move in the middle of a park, that move started held in the hand by
## the bar, not the carry handle the hand had or the park it stood at, and the
## bag jumped up to 0.215 m. So a parking move keeps its lift to its end (let go
## at the bar regrasp, floor>pull, the swap into the hand started from the pull's
## pose behind, not the park, and the bag jumped 0.2 m). A
## roller staying on the floor keeps it too: lying there it is carried no way
## (CarryOnProps' floor spot), and a new lift was a pick-up and set-down on the
## spot, the hand 0.36 m from one frame to the next.
static func holds_lift(bag: Dictionary, kind: SecurityLooks.Kind, home: int, now: float) -> bool:
	if kind != SecurityLooks.Kind.ROLLER or bag.get("kind", -1) != kind:
		return false
	var place: int = bag.get("place", -2)
	if home == SecurityLooks.Home.FLOOR and place >= 0 and place / 4 == home:
		return true
	if not bag.get("park", false):
		return false
	return now - float(bag.get("since", INF)) < CarryLead.ticks_of(bag)


## The home (SecurityLooks.Home) `bag` (CarryOnProps' record, a roller of a bag
## of `kind` now) is drawn going to while its walker's home is `home` at `now`
## (sim tick): the home the parking move in progress goes to, until that move
## ends ("home_held" on `bag` while that is not `home`, lay_frame()). A walker
## whose home changes in the middle of a park (its chair removed as it sits
## down; sitting down again as it stands up) stamped a new generic move there,
## which started the hand with no weight (the arm dropped to rest) or put the
## bag on the pull trail from the half-rolled stand: the bag moved up to 0.8 m
## and the grip up to 0.9 m in one frame. The change waits for the end of the
## park, as a lateness flip does (holds_lift()); the next move then starts from
## the bag laid down or in the pull, as a park does.
static func held_home(
	bag: Dictionary, kind: SecurityLooks.Kind, home: SecurityLooks.Home, now: float
) -> SecurityLooks.Home:
	bag.erase("home_held")
	if not _parking(bag, kind, now):
		return home
	var place: int = bag["place"]
	if home != place / 4:
		bag["home_held"] = true
	return (place / 4) as SecurityLooks.Home


## Holds bag `i`'s home and hand in `homes` and `hands` (CarryOnProps.sync()'s,
## its walker's now) for the park in progress of `bag` (its record, a roller of
## a bag of `kind` now) at `now`: the home (held_home()) and the hand the park
## was stamped with. A walker whose chair goes walks off on a new route, and the
## hand for its way (SecurityLooks.hand_of()) can be the other one: a new place,
## stamped again as a generic move in the middle of the park. `collecting`:
## the walker stands collecting its roller after its seat went in the park
## (ParkRecovery), kept on `bag` ("collecting") for stamp().
static func hold_park(
	bag: Dictionary,
	kind: SecurityLooks.Kind,
	homes: Array,
	hands: Array,
	i: int,
	now: float,
	collecting := false
) -> void:
	bag["collecting"] = collecting
	homes[i] = held_home(bag, kind, homes[i], now)
	if _parking(bag, kind, now):
		hands[i] = CarryLead.hand_of(bag["place"])
	elif homes[i] == SecurityLooks.Home.HAND and _sided(bag, now):
		hands[i] = bag["queue_hand"][1]


## Whether the open side chosen for `bag` (side_first(), "queue_hand") holds
## at `now`, when it changed the hand: through the still spell it was chosen
## in, and after that spell's stand for as long as PullSide keeps a stood
## roller in its hand (PullSide.stood()), so the walk off starts on the side
## it stood on. A stand on its usual side is left to PullSide as before.
static func _sided(bag: Dictionary, now: float) -> bool:
	var mark: Array = bag.get("queue_hand", [])
	if mark.is_empty() or not mark[2]:
		return false
	return float(bag.get("still_from", NAN)) == float(mark[0]) or PullSide.stood(bag, now)


## The queue stand asked for on `bag` (restamps()) goes on the open side
## (decision a-roller-stood-in-a-queue-beside-a-wall-goes-on-the-passenge, as
## ParkSide does at a seat): `hand` is the hand it stands up with there
## (ParkSide.stand_hand()). Chosen once per still spell ("queue_hand", [its
## "still_from", the hand, whether that changed the hand]) and kept for it
## (_sided(), hold_park()), so a body turning in the spell cannot flip it. Its
## pull in the other hand, the ask is put off ("queue_still" cleared) and true
## is returned: hold_park() moves the roller to that hand in a move of its own
## (pull to pull, as PullSide does), and queue_stand() asks again once it is
## settled there, so the stand and its tip are in that hand from their start.
static func side_first(bag: Dictionary, hand: int) -> bool:
	var spell := float(bag.get("still_from", NAN))
	var mark: Array = bag.get("queue_hand", [])
	if not mark.is_empty() and float(mark[0]) == spell:
		return false
	var changes := hand != CarryLead.hand_of(bag["place"])
	bag["queue_hand"] = [spell, hand, changes]
	if not changes:
		return false
	bag.erase("queue_still")
	bag.erase("queue_asked")
	return true


## Whether `p` stands in a queue, at its counter or desk or at the gate
## (QUEUE_STAGES) with no way left to walk on this tick, waits in a boarding
## file of `sim` (filed_still()), or has just set off for the exit from its
## standing spot with no path yet (setting_off()).
static func queue_still(sim: PassengerSim, p: Passenger) -> bool:
	if p.stage in QUEUE_STAGES:
		return not p.is_moving()
	return setting_off(sim, p) or filed_still(sim, p)


## Whether gate stander `p` has turned to the exit (TO_EXIT, its standing spot
## kept until it is off the cell) and has no path yet: boarding opens with it
## still on its spot, and it plans its way on a later tick. Its roller stays
## stood, so the tip starts on the tick it walks, when its way is known and
## tip_wait() can wait for the turn (board 34a0d0aa: tipped on the boarding
## tick, every gate stander's tip went with no way and no wait).
static func setting_off(sim: PassengerSim, p: Passenger) -> bool:
	return (
		p.stage == Passenger.Stage.TO_EXIT
		and not p.is_moving()
		and sim.standing.spot_of(p.id) != StandingSpots.NO_SPOT
	)


## Whether `p` is held in a boarding file of `sim` (FILE_STAGES): in a file or
## waiting to join one, with no room to step on the next tick. Its path is still
## open, so is_moving() holds while it waits.
static func filed_still(sim: PassengerSim, p: Passenger) -> bool:
	if not p.stage in FILE_STAGES or not sim.files.holds(p.id):
		return false
	return sim.files.allowed(sim, p, PassengerSim.WALK_MM) == 0


## The ticks a queue stand's tip waits (queue_stand()'s `turn`) for a walker
## whose body is drawn facing `yaw` on the tick it walks off and whose way is
## `heading` (PassengerViews.walk_heading(), x and z): PassengerTurns.TURN_TICKS
## when it faces more than TIP_TURN_RAD away (it turns as it sets off), else 0.
static func tip_wait(yaw: float, heading: Vector2) -> float:
	if heading == Vector2.ZERO:
		return 0.0
	var off := absf(angle_difference(yaw, atan2(heading.x, heading.y)))
	return float(PassengerTurns.TURN_TICKS) if off > TIP_TURN_RAD else 0.0


## The still ticks `p` waits before its roller is stood up (queue_stand()).
static func still_wait(p: Passenger) -> int:
	return FILE_STILL_TICKS if p.stage in FILE_STAGES else STILL_TICKS


## One sim tick (`now`) of the queue stand (the header's QUEUE_STAGES) of `bag`
## (CarryOnProps' record, of a bag of `kind` now): `stands`, its walker stands
## still in a queue with the roller wanted in the pull (not lifted). Counts the
## still ticks ("still_from"); after `wait` of them (still_wait()) a roller
## settled in the pull is marked for a new move ("queue_still", restamps(), its
## "changed" now), which stamp() makes a queue stand. While that move runs its
## length is kept QUEUE_AHEAD_TICKS past `now`, and the first tick the walker no
## longer stands starts its tip ("queue_tip", ticks into the move), the move
## then ending with it. The tip waits `turn` ticks (tip_wait()) while the body
## turns toward its way.
static func queue_stand(
	bag: Dictionary,
	kind: SecurityLooks.Kind,
	stands: bool,
	now: float,
	wait := STILL_TICKS,
	turn := 0.0,
	yaw := NAN
) -> void:
	if kind != SecurityLooks.Kind.ROLLER or bag.get("kind", -1) != kind:
		bag.erase("still_from")
		return
	if not stands or float(bag.get("still_from", now)) > now:
		bag.erase("still_from")
	if stands and not bag.has("still_from"):
		bag["still_from"] = now
	var at := now - float(bag.get("since", now))
	if queued(bag) and at < CarryLead.ticks_of(bag):
		if bag.has("queue_tip"):
			return
		if stands:
			bag["ticks"] = maxf(CarryLead.ticks_of(bag), at + QUEUE_AHEAD_TICKS)
			return
		bag["queue_tip"] = at + turn
		bag["queue_tip_yaw"] = yaw
		bag["queue_tip_ticks"] = QUEUE_TIP_TICKS * (1.0 + _tip_gap(bag, yaw) / PI)
		bag["ticks"] = at + turn + tip_ticks(bag)
		return
	if not stands or now - float(bag["still_from"]) < wait or bag.has("queue_still"):
		return
	# One ask a still spell: a stand refused at its stamp (parks()) leaves a short
	# pull>pull move, after which it would ask again every TRANSFER_TICKS.
	if float(bag.get("queue_asked", -1.0)) == float(bag["still_from"]):
		return
	var place: int = bag.get("place", -1)
	# Going to the open side's hand first (side_first()): asked again from there.
	var mark: Array = bag.get("queue_hand", [])
	if not mark.is_empty() and float(mark[0]) == float(bag["still_from"]):
		if CarryLead.hand_of(place) != int(mark[1]):
			return
	var pulled: bool = (
		place >= 0
		and place / 4 == SecurityLooks.Home.HAND
		and place % 2 == 0
		and bag.get("home", -1) == place
		and bag.get("carry", -1) == SecurityLooks.Carry.PULL
		and bag.get("settled", false)
	)
	if pulled:
		bag["queue_still"] = true
		bag["queue_asked"] = bag["still_from"]
		bag["changed"] = now
		# A swap's mark outlives its move (sync() sets it only on a change of
		# place); left on a settled roller it made the stand a move not led by the
		# hand (CarryPlace.leads()), which parks() refuses.
		bag["swap"] = false


## Whether `bag` (CarryOnProps' record) waits for its queue stand to be stamped
## (queue_stand()): CarryOnProps stamps a new move though its place is the same.
static func restamps(bag: Dictionary) -> bool:
	return bag.get("queue_still", false)


## Whether the move of `bag` (CarryOnProps' record) is a queue stand (the
## header's QUEUE_STAGES): its rods start in (REACH_BUILT_M) and run out to
## the pull's length at once (rods_t()), so they are drawn as they were.
static func queued(bag: Dictionary) -> bool:
	return bag.get("park", false) and bag.get("queue", false)


## Whether `bag` (CarryOnProps' record, of a bag of `kind` now) is in a parking
## move of a roller at `now` (sim tick), its place stamped.
static func _parking(bag: Dictionary, kind: SecurityLooks.Kind, now: float) -> bool:
	if kind != SecurityLooks.Kind.ROLLER or bag.get("kind", -1) != kind:
		return false
	if int(bag.get("place", -2)) < 0 or not bag.get("park", false):
		return false
	return now - float(bag.get("since", INF)) < CarryLead.ticks_of(bag)


## The frame (world) the floor spot of `bag` (CarryOnProps' record) is laid in:
## the body's `frame` (yaw only), or while the walker's home is held off the
## floor for a park to the floor (held_home()) the frame that park is placed in
## ("park_frame", stamp()), fixed in the world from the move's start. A walker
## whose chair went as it sat down walks off, turned on the spot in one frame:
## laid in the body's frame, the bag being laid down swung round with it, 0.73 m
## in a third of a tick.
static func lay_frame(bag: Dictionary, frame: Transform3D) -> Transform3D:
	return bag["park_frame"] if bag.get("home_held", false) else frame


## Stamps a parking move on `bag` (parks()): "park", its length, and
## "park_frame", the body's frame (`body`, the frame its "from" is in; yaw only)
## the park is placed in; a floor>pull also its reach (CarryLead.reach_of(),
## for CarryLead.at_start()) and its start fixed in the world ("from_world"):
## held in the body's frame the lying bag swung round with a walker turning to
## walk off, 0.7 m in a third of a tick. A floor>pull of a walker standing to
## collect its roller ("collecting", hold_park()) is marked "park_low": its
## stoop bends the back first (LAY_HIPS) to the lift's end (drops_of()). With the hips
## going back as well, a walker standing (not standing up) stopped with its
## grip at 0.274 m over a handle at 0.225 m, and the bag jumped 6.3 cm into
## the hand at TAKE_BY.
##
## A pull>floor of a walker with a place to face as it sits or stays
## (`face`, a yaw, sit_face()) is parked in that facing, not the body's: a
## walker that sits down turns on the spot to its chair over the first 6
## ticks of the park (PassengerTurns), and parked off the way it walked in,
## the roller stood 0.7 m ahead of the seated body, which folded down to it
## with its hips 0.28 m under the seat (board 76cb23c0).
static func stamp(bag: Dictionary, body: Transform3D, face := NAN) -> void:
	bag["park"] = true
	bag["ticks"] = TICKS_DOWN
	for key in [
		"park_took",
		"park_at",
		"park_cut",
		"park_last",
		"park_rel",
		"lift_last",
		"park_tip",
		"park_low",
		"up_near",
		"park_up",
		"rolls",
		"roll_tip",
		"roll_at",
		"roll_frame",
		"queue",
		"queue_tip",
		"queue_tip_yaw",
		"queue_tip_ticks",
		"queue_walls",
		"faced",
		"turn_first",
	]:
		bag.erase(key)
	if bag.get("queue_still", false):
		bag.erase("queue_still")
		bag["queue"] = true
		bag["ticks"] = QUEUE_STAND_TICKS + QUEUE_AHEAD_TICKS
	elif CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		bag["ticks"] = TICKS_UP
		bag["park_up"] = true
		bag["reach"] = REACH_END
		bag["from_world"] = body * (bag["from"] as Transform3D)
		if bag.get("collecting", false):
			bag["park_low"] = true
		# Standing at a gate chair's front until the pick-up is over
		# (ParkRecovery.stand_up_ticks()): parked beside it, not ahead. The
		# face the walker had on the move's first tick (roll_step()'s track),
		# not on the frame that first draws it.
		bag["up_near"] = not is_nan(face)
		var first: Array = (bag.get("roll_track", {}) as Dictionary).get(_since_tick(bag), [])
		if not first.is_empty():
			bag["up_near"] = not is_nan(float(first[1]))
	bag["park_frame"] = _yawed(body)
	if not is_nan(face) and CarryLead.start_of(bag)[0] == CarryLead.End.HELD:
		bag["park_frame"] = Transform3D(Basis(Vector3.UP, face), body.origin)
	# At a seat: BoothRoller.fix_start() keeps the walls round it for plan()
	# (ParkWalls, board a40fdbaf).
	if not is_nan(face) and not queued(bag):
		bag["faced"] = true
	# First drawn after the sim could decide its roll (or its tip): as decided,
	# from the same track, on the stamp.
	_apply_roll(bag)


## The yaw `p` faces once it has turned to sit or stay where it sets its bags
## down: out of its gate chair or cafe seat, or out of the activity piece
## (PassengerViews turns the body to the same facing); NAN anywhere else.
static func sit_face(sim: PassengerSim, p: Passenger) -> float:
	var out := Vector2i.ZERO
	# Still rising from an activity piece: no face, so a pick-up parks ahead
	# (UP_PARK_AHEAD_M, stamp()). A roller visitor picks up after it is up, in
	# its hold (ActivityPoses.up_tail()), and a cafe guest stands where it sat
	# (CafeSim.up_ticks()), so both have the seat's face and roll the roller
	# upright until clear (ROLL_TICKS, board 2c659e42).
	if ActivityPoses.pose(sim, p) == StageKinds.Pose.STANDING_UP:
		return NAN
	var where := StageKinds.location(p.stage)
	if ActivityPoses.kind(sim, p) != ActivityPoses.Kind.NONE:
		out = ActivityPoses.facing(sim, p)
	elif where == StageKinds.Location.GATE_SEAT and p.seat_object != 0:
		var chair: Dictionary = sim.grid.get_object(p.seat_object)
		out = TerminalLayout.front_of(chair.get("facing", 0)) if not chair.is_empty() else out
	elif where == StageKinds.Location.FACILITY_SEAT:
		out = sim.cafes.seat_facing(p)
	return atan2(out.x, out.y) if out != Vector2i.ZERO else NAN


## Where floor bag `index` of `count` of `p` (of `kind`, in hand `hand`) lies
## in its frame: SecurityLooks.floor_spot(), but a roller lies beside the feet
## on its hand's side, along the passenger's line (user ruling
## roller-laid-down-beside-the-passenger-s-feet-not-ahead), FEET_AHEAD_M ahead;
## at a gate chair in the chair front's frame (chair_front()), where the walker
## stands to set it down and pick it up (SEAT_AHEAD_M ahead of the seated body,
## across the feet, was 7 cm from its toes). With the back bent at most BACK_CAP the
## hand could not reach it FLOOR_AHEAD_M ahead. A cafe seat's and a toilet
## stall's spots are kept: the cafe's already lie beside the chair
## (SecurityLooks.CAFE_BESIDE_M).
static func floor_spot(
	sim: PassengerSim, p: Passenger, kind: SecurityLooks.Kind, hand: int, index: int, count: int
) -> Transform3D:
	var spot := SecurityLooks.floor_spot(sim, p, index, count)
	var where := StageKinds.location(p.stage)
	if kind == SecurityLooks.Kind.ROLLER and sim.cafes.booth_roller(p):
		var front: Variant = chair_front(sim, p, kind)
		if front != null:
			spot.origin.x = BoothRoller.side(sim, front as Transform3D, hand) * PARK_SIDE_M
		return spot
	if kind != SecurityLooks.Kind.ROLLER or where == StageKinds.Location.FACILITY_SEAT:
		return spot
	var out := -1.0 if hand == 0 else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(out * BESIDE_FEET_M, 0.0, FEET_AHEAD_M))


## The frame (world, on the floor) a roller of `p` (of `kind`) lies in at a gate
## chair: the chair front's cell turned to face out of the chair, fixed in the
## world while the body moves into the seat and back out (the body's frame
## carried the bag 0.55 m with it); at a booth seat (CafeSim.booth_roller())
## the same at the seat's approach cell, where it is set down before the step
## in and picked up after the step out (board 5dc41129); null anywhere else
## (the body's frame).
static func chair_front(sim: PassengerSim, p: Passenger, kind: SecurityLooks.Kind) -> Variant:
	if kind != SecurityLooks.Kind.ROLLER:
		return null
	var where := StageKinds.location(p.stage)
	var booth := where == StageKinds.Location.FACILITY_SEAT and sim.cafes.booth_roller(p)
	if not booth and (p.seat_object == 0 or where != StageKinds.Location.GATE_SEAT):
		return null
	var face := sit_face(sim, p)
	if is_nan(face):
		return null
	var at: Variant = sim.grid.cell_to_world(p.seat_front)
	if booth:
		at = SitHold.chair_front(sim, p)
	return Transform3D(Basis(Vector3.UP, face), at as Vector3)


## `frame` turned about the vertical only (its yaw), at its origin.
static func _yawed(frame: Transform3D) -> Transform3D:
	var ahead := frame.basis.z
	return Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)), frame.origin)


## The roller parked (world) for a move led by `hand` (0 right, 1 left), in
## `frame` (stamp()'s), drawn at `scale_by`: standing on its wheels PARK_SIDE_M
## out on the hand's side and `ahead`, its front panel to the back of the body (as it
## stands up from the pull behind, turning about its axle only), upright, its
## axle the wheels' radius up: the wheels (build_carry_on_kit.py, 0.03 m past
## the shell's bottom end) on the floor. Not leaning onto its front panel's
## bottom edge: the probes' rest check reads the lowest corner of the bag's
## mesh bounds, and leaning puts that corner (under the carry handle) through
## the floor by more than its 1 cm.
static func park(
	frame: Transform3D, hand: int, scale_by: float, ahead := PARK_AHEAD_M, side := PARK_SIDE_M
) -> Transform3D:
	var out := -1.0 if hand == 0 else 1.0
	var axle := frame * Vector3(out * side, 0.0, ahead)
	axle.y = frame.origin.y + CarryOnProps.ROLLER_AXLE.y * scale_by
	var front := frame.basis * Vector3.FORWARD
	var basis := Basis(front.cross(Vector3.UP), front, Vector3.UP).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## The roller of a queue stand parked (world) beside a body drawn as `frame`
## (yaw only is used), led by `hand`, drawn at `scale_by`, the body's look
## `look` (PassengerLooks.BODIES index): park() QUEUE_SIDE_M out for its variant.
static func queue_park(frame: Transform3D, hand: int, scale_by: float, look: int) -> Transform3D:
	return park(_yawed(frame), hand, scale_by, PARK_AHEAD_M, queue_side(look))


## The frame (world) the queue stand of `bag` (CarryOnProps' record) is drawn
## in (plan()): the one ParkSide.choose_stand() chose its side in from the sim
## ("queue_frame", kept to the move's end), else the body as drawn, `frame`
## (no way to face known).
static func queue_frame_of(bag: Dictionary, frame: Transform3D) -> Transform3D:
	var kept: Array = bag.get("queue_frame", [])
	return kept[1] if not kept.is_empty() else frame


## What carries a stood roller with the body once its queue stand's tip has
## started (queue_stand()'s "queue_tip"): from `chosen` (queue_frame_of()) to
## the body as drawn, `frame`, both yaw only: the body's step from where it
## stood and its turn from `chosen`, less the part of that turn it already had
## when the tip started (`start_yaw`, the body's drawn yaw on that sync tick,
## "queue_tip_yaw"; NAN for none), which comes in with the tip's own `share`
## (tip_share()). The walker is walking off: held where it stood in the world,
## the roller stayed behind the body walking away and the tip swung it in from
## there, 0.2 to 0.55 m a frame against the body (test_roller_queue_stand,
## test_roller_file_gate_stand); carried, it goes with the body. A body drawn a
## quarter or half turn away from `chosen` when it walked off, carried in full
## at once, swung the stood roller round it 0.53 and 0.70 m in one tick (0.36
## not turned; test_queue_stand_side_sim); its turn eased in by the share
## alone, the roller lagged a cafe guest turning as it walked off by 0.150 m a
## frame against the body (test_roller_queue_stand). The identity while the
## body is drawn where and as the sim has it stand.
static func tip_carried(
	chosen: Transform3D, frame: Transform3D, share: float, start_yaw := NAN
) -> Transform3D:
	var from := _yawed(chosen)
	var to := _yawed(frame)
	var turn := angle_difference(_yaw_of(from), _yaw_of(to))
	if not is_nan(start_yaw):
		turn -= angle_difference(_yaw_of(from), start_yaw) * (1.0 - share)
	return Transform3D(Basis(Vector3.UP, turn), to.origin) * Transform3D(Basis(), -from.origin)


## What carries the stood roller of the queue stand of `bag` at `k` with the
## body drawn as `frame` (plan()): tip_carried() once its tip has started, from
## the stand's frame (queue_frame_of()) and the yaw the tip started at; the
## identity before. Drawn in the body's frame (no "queue_frame" kept), the
## stand already goes with the body, so no start yaw is eased in: one was, and
## a tip started at yaw 0 then drawn at PI / 2 swung the roller a quarter turn
## round the body at no share of the tip (Sol re-check).
static func tip_carry_of(bag: Dictionary, frame: Transform3D, k: float) -> Transform3D:
	if not bag.has("queue_tip"):
		return Transform3D.IDENTITY
	var at_tip: float = bag.get("queue_tip_yaw", NAN) if bag.has("queue_frame") else NAN
	return tip_carried(queue_frame_of(bag, frame), frame, tip_share(bag, k), at_tip)


## The yaw (about +y, 0 facing +z) of a frame's ahead (+z) axis.
static func _yaw_of(frame: Transform3D) -> float:
	return atan2(frame.basis.z.x, frame.basis.z.z)


## How far the tip of a queue stand of `bag` has run at `k` of its move, 0 to 1
## (eased; "queue_tip", tip_ticks()): 0 before it starts and while it waits
## for the body's turn (tip_wait()).
static func tip_share(bag: Dictionary, k: float) -> float:
	var tip: float = bag.get("queue_tip", INF)
	return smoothstep(0.0, 1.0, (k * CarryLead.ticks_of(bag) - tip) / tip_ticks(bag))


## How many ticks the tip of a queue stand of `bag` runs: QUEUE_TIP_TICKS, and
## up to twice that for a body drawn turned from the stand's frame when it
## starts ("queue_tip_ticks", _tip_gap(), a half turn doubling it): turned a
## half turn, the stood roller crossed behind the body to the pull in the
## usual tip's time at 0.57 m a tick (0.36 not turned; test_queue_stand_side_sim).
static func tip_ticks(bag: Dictionary) -> float:
	return bag.get("queue_tip_ticks", QUEUE_TIP_TICKS)


## How far (radians, 0 to PI) a body drawn at `yaw` is turned from the frame
## the queue stand of `bag` was placed in (queue_frame_of()); 0 with no frame
## kept or no yaw (NAN).
static func _tip_gap(bag: Dictionary, yaw: float) -> float:
	var kept: Array = bag.get("queue_frame", [])
	if kept.is_empty() or is_nan(yaw):
		return 0.0
	return absf(angle_difference(_yaw_of(kept[1]), yaw))


## How far out (QUEUE_SIDE_M) a queue stand parks the axle of a body of look
## `look` (PassengerLooks.BODIES index).
static func queue_side(look: int) -> float:
	var variant := clampi(look / PassengerLooks.PER_VARIANT, 0, QUEUE_SIDE_M.size() - 1)
	return QUEUE_SIDE_M[variant]


## How far a parking move of `bag` has run its rods from their old length to
## their new one at `k`: in while it stands up, out while it tips into the pull
## (a roller rolled upright, rolls(), runs them out ROLL_RODS of the way after
## its park, so its bar is at the standing hand, and the rest over its tip,
## "roll_tip": run out upright, the bar rose to 2.1 m with the hand on it; left
## in, the walker crouched to a bar at 0.48 m, its hips 0.33 m low).
static func rods_t(k: float, bag: Dictionary) -> float:
	if queued(bag):
		# Its length is queue_reach()'s, not a blend from its start.
		return queue_share(bag, k)
	if CarryLead.start_of(bag)[0] == CarryLead.End.REST:
		var park := up_ends(bag).y
		var settle := SETTLE_TICKS / TICKS_UP
		var up := up_k(bag, k)
		if not rolls(bag):
			# Out over RODS_OUT_TICKS at least before the move ends: one taken
			# late ends its park past k 1, and run from the park's end the
			# smoothstep had its edges the wrong way round (all out at once).
			return smoothstep(minf(park + settle, 1.0 - RODS_OUT_TICKS / TICKS_UP), 1.0, up)
		var part := ROLL_RODS * smoothstep(park + settle, park + TIP_UP, up)
		if not bag.has("roll_tip"):
			return part
		var tip: float = bag["roll_tip"]
		return lerpf(part, 1.0, smoothstep(tip + settle, tip + TIP_UP, up))
	if turns_first(bag):
		# In while it stands up and turns round (_turning()), in from then on.
		return smoothstep(0.0, TURN_UP_SHARE * TURN_FIRST_TICKS, k * CarryLead.ticks_of(bag))
	return smoothstep(0.0, STAND_END, k)


## How far a queue stand of `bag` (queued()) at `k` has gone from the pull to
## standing: 0 to 1 over QUEUE_STAND_TICKS, and from where it was at
## "queue_tip" back to 0 over its tip (tip_ticks()).
static func queue_share(bag: Dictionary, k: float) -> float:
	var at := k * CarryLead.ticks_of(bag)
	var tip: float = bag.get("queue_tip", INF)
	var share := smoothstep(0.0, QUEUE_STAND_TICKS, minf(at, tip))
	if at <= tip:
		return share
	return lerpf(share, 0.0, smoothstep(tip, tip + tip_ticks(bag), at))


## The rods' length (the bag's units) of a queue stand of `bag` at `k`: from
## `pull` (the pull's length now) to the length that stands the bar QUEUE_BAR_M
## over the floor upright (park()), and back. `bar_in` is the bar's own z with
## no rods out, less REACH_BUILT_M (CarryHand.bar_z()), `scale_by` the
## bag's scale. The bar of a roller on its wheels is
## (ROLLER_AXLE.y + bar_z - ROLLER_AXLE.z) * scale_by up.
static func queue_reach(
	bag: Dictionary, k: float, pull: float, bar_in: float, scale_by: float
) -> float:
	var axle := CarryOnProps.ROLLER_AXLE
	var bar_z := QUEUE_BAR_M / scale_by - axle.y + axle.z
	var stood := maxf(CarryOnProps.REACH_BUILT_M, bar_z - bar_in)
	return lerpf(pull, stood, queue_share(bag, k))


## `k` (the move's share of its length) of a floor>pull move of `bag` in units of
## TICKS_UP: the same as `k` until the move is made longer to roll its roller
## upright (rolls()), so its phases keep their length in ticks.
static func up_k(bag: Dictionary, k: float) -> float:
	return k * CarryLead.ticks_of(bag) / TICKS_UP


## Whether the floor>pull of `bag` rolls its roller upright until clear (the
## header's CLEAR_M), decided on a sim tick (roll_step()).
static func rolls(bag: Dictionary) -> bool:
	return bag.get("rolls", false)


## 0 to 1 over `t` (0 to 1), still at both ends (smootherstep): a stand that
## eased out with smoothstep still moved 0.19 m on the last tick before the park.
static func _eased(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## Where the lift and the park of a floor>pull move of `bag` end (k): LIFT_END
## and UP_PARK_END, later when its bag was taken late ("park_took", _taken()),
## the park sooner when the walker moved during it ("park_cut", MOVED_M).
static func up_ends(bag: Dictionary) -> Vector2:
	var lift := maxf(LIFT_END, float(bag.get("park_took", 0.0)) + UP_PART)
	var park := maxf(UP_PARK_END, lift + UP_PART)
	if bag.has("park_cut"):
		park = minf(park, (bag["park_cut"] as Vector2).x + UP_CUT_TICKS / TICKS_UP)
	return Vector2(lift, park)


## The roller turning on its axle from `from` to `to` (world, both on their
## wheels) at `u`: its axle rolls straight across the floor between theirs.
static func rolled(from: Transform3D, to: Transform3D, u: float) -> Transform3D:
	var axle := (from * CarryOnProps.ROLLER_AXLE).lerp(to * CarryOnProps.ROLLER_AXLE, u)
	var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), u)
	var basis := Basis(q).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), u))
	return Transform3D(basis, axle - basis * CarryOnProps.ROLLER_AXLE)


## The empty hand's point (own frame) at `v` of its way from `from` (the bar or
## the handle) to `to` over the bag's top (OVER_TOP).
static func over_top(from: Vector3, to: Vector3, v: float) -> Vector3:
	return from.lerp(OVER_TOP, v).lerp(OVER_TOP.lerp(to, v), v)


## A parking move of `bag` at `k`, as CarryLead.plan() returns it (same
## arguments; `body` gives "bar_z", the bar as the rods are drawn now, and
## "scale").
static func plan(
	bag: Dictionary,
	k: float,
	start: Transform3D,
	want: Transform3D,
	frame: Transform3D,
	flags: Dictionary,
	body: Dictionary
) -> Dictionary:
	var started := CarryLead.start_of(bag)
	var off_floor: bool = started[0] == CarryLead.End.REST
	var lead: int = CarryLead.hand_of(bag["home"]) if off_floor else started[1]
	# The whole move's share, for the walls' ease at its start (BoothRoller.drawn()).
	var move_k := k
	if turns_first(bag):
		lead = CarryLead.hand_of(bag["home"])
		k = down_k(bag, k)
	var ahead := UP_PARK_AHEAD_M if off_floor and not bag.get("up_near", false) else PARK_AHEAD_M
	var parked := park(bag["park_frame"], lead, body["scale"], ahead)
	# Out of the walls beside a seat (BoothRoller.fix_start(), ParkWalls).
	if bag.has("wall_boxes"):
		parked.origin += ParkWalls.shift(parked, bag["wall_boxes"])
	var bar := Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, body["bar_z"])
	var handle := CarryOnProps.ROLLER_HANDLE
	var go := flags.duplicate()
	go["hand"] = lead
	# [holder (-1 none), the bag, the point held, the hand's target (own frame of
	# the bag), the hand's weight]. The stoop is kept on through
	# the whole move (CarryStoop bends only as far as the reach needs): with the
	# height fade alone the hand reaching the bar 0.6 m up beside a walker sitting
	# down stopped 0.3 m short, the bag rising off its wheels with it.
	var at: Array
	var turning := move_k * CarryLead.ticks_of(bag)
	if turns_first(bag) and turning < TURN_FIRST_TICKS:
		return _turning(bag, move_k, turning, start, parked, bar, started[1], lead)
	if queued(bag):
		# Stood in the frame its side was chosen in (queue_frame_of()), held by the
		# bar throughout: the body drawn another way, or turning, does not take the
		# stood roller across to the side the choice was not made for. Once its
		# tip starts it is carried with the body (tip_carried()).
		assert(body.has("look") and int(body["look"]) >= 0, "RollerPark: queued with no body look")
		var chosen := queue_frame_of(bag, frame)
		parked = queue_park(chosen, lead, body["scale"], body["look"])
		parked = tip_carry_of(bag, frame, k) * parked
		# Walled on both sides, or a two-bag guest's (ParkSide.choose_stand() kept
		# its side): out of the walls kept at the stamp (CarryPlace, ParkWalls),
		# the tip rolled from there.
		if bag.has("queue_walls"):
			parked.origin += ParkWalls.shift(parked, bag["queue_walls"])
		at = _queued(bag, k, start, want, parked, bar)
	elif not off_floor:
		# At a booth seat (BoothRoller.fix_start()'s "wall_faces") a roller pulled
		# on the walled side is laid on the open side, round the front (across()).
		if bag.has("wall_faces") and across(bag["park_frame"], parked, want):
			go["across"] = bag["park_frame"]
		# Turned first, the roller came in to the park through the turn (turned_round()).
		var from := parked if turns_first(bag) else start
		at = _onto_floor(k, from, want, parked, frame, go, bar, handle)
	else:
		var up := up_k(bag, k)
		_taken(bag, up, start * handle, body, lead)
		at = _off_floor(up, bag, start, want, parked, _yawed(frame), bar, handle)
	# Out of any wall at a booth seat (BoothRoller.fix_start()).
	var xf := BoothRoller.drawn(at[1], bag, move_k, bar)
	# Every frame out of the walls one way per wall, chosen from the park
	# (ParkWalls.held_out()): the roll and the tip carried with the body.
	if bag.has("wall_boxes"):
		xf.origin += ParkWalls.held_out(xf, bag["wall_boxes"], parked)
	var targets := [Vector3.ZERO, Vector3.ZERO]
	var weights := [0.0, 0.0]
	var keeps := [0.0, 0.0]
	targets[lead] = xf * (at[3] as Vector3)
	weights[lead] = at[4]
	keeps[lead] = 1.0
	return {
		"holder": lead if at[0] else -1,
		"xf": xf,
		"anchor": at[2],
		"targets": targets,
		"weights": weights,
		"keeps": keeps,
		"drops": [drops_of(bag, k), drops_of(bag, k)],
		"bends": [BACK_CAP, BACK_CAP],
	}


## How the stoop of a parking move of `bag` at `k` moves the hips (CarryStoop's
## drops): LAY_HIPS laying it down; for a floor>pull marked "park_low"
## (stamp()) LAY_HIPS while the hand takes the bag off the floor and lifts it,
## eased into HIPS_ALL over LOW_EASE_TICKS from the lift's end (up_ends().x,
## from the stamp and "park_took"); else HIPS_ALL. Kept on past the lift, a
## walker setting off from the park bent about 90 degrees at the waist on
## straight legs, its free arm thrown up behind its back; switched in one
## frame, its back came up from about 60 degrees and its head 0.3 m in two
## frames (CarryStoop.solved() blends the two).
static func drops_of(bag: Dictionary, k: float) -> Vector3:
	if queued(bag):
		return PARK_HIPS
	if CarryLead.start_of(bag)[0] != CarryLead.End.REST:
		return LAY_HIPS if k >= PARK_END else PARK_HIPS
	if not bag.get("park_low", false):
		return PARK_HIPS
	var lift_end := up_ends(bag).x
	var eased := smoothstep(lift_end, lift_end + LOW_EASE_TICKS / TICKS_UP, up_k(bag, k))
	return LAY_HIPS.lerp(PARK_HIPS, eased)


## pull>floor at `k` (plan()): [held, xf, anchor, target, weight].
static func _onto_floor(
	k: float,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	frame: Transform3D,
	go: Dictionary,
	bar: Vector3,
	handle: Vector3
) -> Array:
	if k < STAND_END:
		var u := _eased(k / STAND_END)
		# Aimed at the bar from the start, where the pull put it: eased in from the
		# pull's arm pose, the bag placed from the hand rose off its wheels with it.
		return [true, rolled(start, parked, u), bar, bar, 1.0]
	if k < PARK_END:
		var v := smoothstep(0.0, 1.0, (k - STAND_END) / (PARK_END - STAND_END))
		return [false, parked, handle, over_top(bar, handle, v), 1.0]
	if k <= LAY_END:
		# Still at both ends: path()'s set-down comes down fastest at its end, and
		# the bag reached the floor 8 cm a third of a tick.
		var u := (k - PARK_END) / (LAY_END - PARK_END)
		if go.has("across"):
			# Across the front: no push from the body (path()'s keep_out()), its
			# way and height eased with _across_eased(): with _eased(), its step
			# grew 0.064 m a frame on the way round.
			var share := _across_eased(u)
			var flat := go.duplicate()
			flat["clear"] = 0.0
			var swung := CarryLead.path(
				parked, want, share, frame, frame.affine_inverse() * parked, flat
			)
			var way := round_front(go["across"], parked.origin, want.origin, share)
			swung.origin = Vector3(way.x, swung.origin.y, way.z)
			return [true, swung, handle, handle, 1.0]
		var t := _eased(u)
		var laid := CarryLead.path(parked, want, t, frame, frame.affine_inverse() * parked, go)
		return [true, laid, handle, handle, 1.0]
	var back := smoothstep(0.0, 1.0, (1.0 - k) / (1.0 - LAY_END))
	return [false, want, handle, handle, back]


## Marks a booth set-down from the pull (`bag`, BoothRoller.fix_start(), its
## start fixed in the world, "from_world") to turn first when the walker's turn
## to face out of the seat ("park_frame") puts its pulling hand on the walled
## side: the floor place's hand (ParkSide's, the open side) is not the pulling
## one and the pull left the roller on the floor place's side of that facing.
## A guest that walks in along the booth's wall pulls on the side away from it
## (PullSide) and turns round at the approach cell. Set down from the pulling
## hand while it turned, the roller was parked on the walled side and laid back
## across in front of the legs (food_seats_probe booth_alt_13-1: a 0.43 m jump,
## then 60-76 body points in the roller round the front). User ruling of
## 2026-11-07 (board 2eaa9bc4): turn, then set down with the hand now on the
## open side. The move is TURN_FIRST_TICKS longer; CafeSim.STEP_IN_HOLD_TICKS
## has room for it.
static func mark_turn_first(bag: Dictionary) -> void:
	var held: int = CarryLead.start_of(bag)[1]
	# The new place: CarryPlace makes it the bag's "home" just after fix_start().
	var home := CarryLead.hand_of(bag["place"])
	if home == held or not bag.has("from_world") or not bag.has("park_frame"):
		return
	var park_frame: Transform3D = bag["park_frame"]
	var x := (park_frame.affine_inverse() * (bag["from_world"] as Transform3D).origin).x
	if (x < 0.0) == (home == 0):
		bag["turn_first"] = true
		bag["ticks"] = TICKS_DOWN + TURN_FIRST_TICKS


## Whether the set-down of `bag` turns first (mark_turn_first()).
static func turns_first(bag: Dictionary) -> bool:
	return bag.get("turn_first", false)


## `k` (the share of a move of `bag`) as the share of its set-down proper: past
## the turn of one that turns first (turns_first()), 0 through the turn; `k`
## for any other move.
static func down_k(bag: Dictionary, k: float) -> float:
	if not turns_first(bag):
		return k
	var at := k * CarryLead.ticks_of(bag) - TURN_FIRST_TICKS
	return clampf(at / TICKS_DOWN, 0.0, 1.0)


## The turn of a set-down that turns first (turns_first()), `at` ticks into the
## move of `bag` (`k` its share): the roller held still at its start (world,
## out of the walls as plan() draws it, `parked` plan()'s park), the hand
## that pulled it (`from_hand`) letting go of the bar over the middle third of
## the turn as the other (`to_hand`, the hand now on its side) takes it, so
## each frame a hand is on it. Placed by its start, not by a grip: held, it
## swung round with the turning body.
static func _turning(
	bag: Dictionary,
	k: float,
	at: float,
	start: Transform3D,
	parked: Transform3D,
	bar: Vector3,
	from_hand: int,
	to_hand: int
) -> Dictionary:
	var xf := BoothRoller.drawn(turned_round(bag, start, parked, at), bag, k, bar)
	if bag.has("wall_boxes"):
		xf.origin += ParkWalls.held_out(xf, bag["wall_boxes"], parked)
	var given := smoothstep(TURN_FIRST_TICKS / 3.0, TURN_FIRST_TICKS * 2.0 / 3.0, at)
	var targets := [Vector3.ZERO, Vector3.ZERO]
	var weights := [0.0, 0.0]
	targets[from_hand] = xf * bar
	targets[to_hand] = xf * bar
	weights[from_hand] = 1.0 - given
	weights[to_hand] = given
	return {
		"holder": -1,
		"xf": xf,
		"anchor": bar,
		"targets": targets,
		"weights": weights,
		"keeps": [1.0, 1.0],
		"drops": [PARK_HIPS, PARK_HIPS],
		"bends": [BACK_CAP, BACK_CAP],
	}


## The roller of a set-down that turns first (`bag`), `at` ticks into its turn
## (_turning()): from `start` (the pull, world) to `parked` (plan()'s park,
## world) while the walker turns, so the set-down after the turn starts at the
## park. It stands up on its wheels over the first TURN_UP_SHARE of the turn,
## turns round about its own middle (its box's centre) over the middle of it,
## and comes in to the park over the whole of it, late (the ease squared: on
## the plain ease a knee of the walker still turning met it, 6 body points at
## k4.67). Rolled on its axle with the
## turn as one slerp (rolled()), its top swept through the booth's end panel
## and the hand on its bar took the body in after it (food_seats_probe
## booth_alt_13-1: BAG_INSIDE up to 18 and SIT_INSIDE up to 352 points). Its
## turn goes the way that keeps its front facing the walker midway, so it
## swings on the walker's side, not out towards the panel.
static func turned_round(
	bag: Dictionary, start: Transform3D, parked: Transform3D, at: float
) -> Transform3D:
	var middle := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER).get_center()
	var b0 := Basis(Vector3.LEFT, Vector3.BACK, Vector3.UP)
	var yaw_from := _heading(start.basis)
	var yaw_to := _heading(parked.basis)
	var lean_basis := (Basis(Vector3.UP, yaw_from) * b0).inverse() * start.basis.orthonormalized()
	var lean := atan2(lean_basis.y.z, lean_basis.y.y)
	var turn := angle_difference(yaw_from, yaw_to)
	var other := turn - signf(turn) * TAU
	var from_mid := start * middle
	var to_mid := parked * middle
	var walker: Vector3 = (bag["park_frame"] as Transform3D).origin
	var towards := walker - from_mid.lerp(to_mid, 0.5)
	# Of the two ways round, the one whose front faces the walker midway.
	var front_a := Basis(Vector3.UP, yaw_from + turn / 2.0) * Vector3.BACK
	var front_b := Basis(Vector3.UP, yaw_from + other / 2.0) * Vector3.BACK
	if front_b.dot(towards) > front_a.dot(towards):
		turn = other
	var up_u := smoothstep(0.0, TURN_UP_SHARE * TURN_FIRST_TICKS, at)
	var turn_u := smoothstep(0.25 * TURN_FIRST_TICKS, 0.75 * TURN_FIRST_TICKS, at)
	var in_u := pow(smoothstep(0.0, TURN_FIRST_TICKS, at), 2.0)
	var scale := start.basis.get_scale().lerp(parked.basis.get_scale(), in_u)
	var basis := Basis(Vector3.UP, yaw_from + turn * turn_u) * b0
	basis = (basis * Basis(Vector3.RIGHT, lean * (1.0 - up_u))).scaled(scale)
	var mid := from_mid.lerp(to_mid, in_u)
	return Transform3D(basis, mid - basis * middle)


## The way (yaw) a roller drawn with `basis` faces: its front (+y) on the floor.
static func _heading(basis: Basis) -> float:
	var front := basis.y
	return atan2(front.x, front.z)


## Whether a set-down parked at `parked` lays its roller at `want` (both world)
## on the other side of the centre line of `park_frame` (stamp()'s): pulled in
## the hand on a booth's walled side, it lies on the open side
## (BoothRoller.side()).
static func across(park_frame: Transform3D, parked: Transform3D, want: Transform3D) -> bool:
	var a := park_frame.affine_inverse() * parked.origin
	var b := park_frame.affine_inverse() * want.origin
	return a.x * b.x < 0.0


## 0 to 1 over `t` (0 to 1), still at both ends: speeding up at one rate to
## ACROSS_FASTEST, then slowing down at another as it comes to the floor. Its
## step a frame grows by no more than 2 / (ACROSS_FASTEST n^2) of the way over
## n frames. Sped up and slowed down alike (at 0.5), the 1.0 m round the front
## in the lay's 9 frames grew 0.052 m in a frame.
static func _across_eased(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x < ACROSS_FASTEST:
		return x * x / ACROSS_FASTEST
	return 1.0 - (1.0 - x) * (1.0 - x) / (1.0 - ACROSS_FASTEST)


## Where (world, its height that of `from`) a roller laid across goes at `t`
## from `from` to `to` (world): round the front of `park_frame` (fixed in the
## world from the move's start), its angle about the frame's origin turning
## from the one to the other through straight ahead and its distance from it
## from the one's to the other's (0.32-0.35 m at a booth), as
## CarryLead.swap_axle() swings a roller round the hand's side. Pushed out to
## TRANSFER_CLEAR_M midway as well, a longer way, its step grew 0.056 m in a
## frame (eased alike at both ends). On a straight line pushed out from the
## body's centre (CarryLead.keep_out()) the push turned from one side to the other as
## the line passed 0.08 m ahead of the centre, and the roller jumped 0.43 m in
## a third of a tick (food_seats_probe booth_alt_13-1 k9, board 2eaa9bc4).
static func round_front(park_frame: Transform3D, from: Vector3, to: Vector3, t: float) -> Vector3:
	var a := park_frame.affine_inverse() * from
	var b := park_frame.affine_inverse() * to
	var angle := lerpf(atan2(a.x, a.z), atan2(b.x, b.z), t)
	var r := lerpf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length(), t)
	return park_frame * Vector3(r * sin(angle), a.y, r * cos(angle))


## A queue stand of `bag` at `k` (plan()): [held, xf, anchor, target, weight].
## Held by the bar throughout: rolled on its axle from the pull (`start`) to the
## park beside the body (`parked`) over QUEUE_STAND_TICKS, standing there, and
## from where it stood at "queue_tip" rolled back into the pull (`want`) over
## its tip (tip_ticks()), the arm easing back into its pull pose as it goes.
static func _queued(
	bag: Dictionary,
	k: float,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	bar: Vector3
) -> Array:
	var at := k * CarryLead.ticks_of(bag)
	var tip: float = bag.get("queue_tip", INF)
	var stood := rolled(start, parked, _eased(minf(at, tip) / QUEUE_STAND_TICKS))
	if at < tip:
		return [true, stood, bar, bar, 1.0]
	var u := tip_share(bag, k)
	return [true, rolled(stood, want, u), bar, bar, 1.0 - u]


## The k a floor>pull move of `bag` took the lying bag at (TAKE_M, TAKE_BY), the
## hand `lead` of `body` (plan()'s) and the handle at `at` (world) as drawn now;
## -1 while it has not. Kept on the move's record ("park_took"): the hand
## reaching it is a pose, not a time.
static func _taken(bag: Dictionary, k: float, at: Vector3, body: Dictionary, lead: int) -> float:
	if bag.has("park_took"):
		return bag["park_took"]
	var grip: Vector3 = body["grips"][lead]
	if k >= TAKE_BY or (k >= REACH_END and grip.distance_to(at) <= TAKE_M):
		bag["park_took"] = k
		return k
	return -1.0


## floor>pull of `bag` at `k` (plan()), the bag taken off the floor at its
## "park_took" (_taken()), the body at `body` (yaw only): [held, xf, anchor,
## target, weight].
static func _off_floor(
	k: float,
	bag: Dictionary,
	start: Transform3D,
	want: Transform3D,
	parked: Transform3D,
	body: Transform3D,
	bar: Vector3,
	handle: Vector3
) -> Array:
	var took: float = bag.get("park_took", -1.0)
	if took < 0.0 or k < took:
		var reach := smoothstep(0.0, REACH_END - SETTLE_TICKS / TICKS_UP, k)
		return [false, start, handle, handle, reach]
	var ends := up_ends(bag)
	if k < ends.x:
		var t := (k - took) / (ends.x - took)
		var lifted := start.interpolate_with(parked, _eased(t))
		lifted.origin.y += LIFT_M * 4.0 * t * (1.0 - t)
		bag["lift_last"] = body
		return [true, lifted, handle, handle, 1.0]
	if k < ends.y:
		var v := smoothstep(0.0, 1.0, (k - ends.x) / (ends.y - ends.x))
		if not bag.has("park_at"):
			bag["park_at"] = body.origin
		if not bag.has("park_cut") and body.origin.distance_to(bag["park_at"]) > MOVED_M:
			bag["park_cut"] = Vector2(k, v)
		if bag.has("park_cut"):
			var cut: Vector2 = bag["park_cut"]
			ends = up_ends(bag)
			v = lerpf(cut.y, 1.0, smoothstep(cut.x, lerpf(cut.x, ends.y, CUT_ON), k))
		if k < ends.y and rolls(bag):
			# Rolled: carried with the body from its park on (_carried()), so a
			# park drawn late, running into the step off, rides with the body.
			return [false, _carried(bag, parked, body), bar, over_top(handle, bar, v), 1.0]
		if k < ends.y:
			bag["park_last"] = body
			# The empty hand let go goes on with the walker by half its last step,
			# less as it comes to the bar: a hand still in the world as a walker
			# running on lets go moved 0.175 m against the body at 3x.
			var last: Transform3D = bag.get("lift_last", body)
			var hand := parked * over_top(handle, bar, v)
			hand += (body.origin - last.origin) * 0.5 * (1.0 - v)
			return [false, parked, bar, parked.affine_inverse() * hand, 1.0]
	if rolls(bag):
		var carried := _carried(bag, parked, body)
		if _rolling(bag, k):
			return [true, carried, bar, bar, 1.0]
		var tip := smoothstep(0.0, 1.0, (k - float(bag["roll_tip"])) / TIP_UP)
		return [true, rolled(carried, want, tip), bar, bar, 1.0 - smoothstep(0.0, 1.0, tip)]
	var tipped := _followed(bag, parked, body, k)
	var from: float = bag.get("park_tip", ends.y)
	var u := smoothstep(0.0, 1.0, (k - from) / (1.0 - from))
	# Into the pull's arm pose as the bag comes onto the trail, from the frame
	# the hand took it ("park_tip"; between two frames at 3x it had rolled
	# 0.2 m toward the trail by the first).
	tipped = rolled(tipped, want, u)
	return [true, tipped, bar, bar, 1.0 - smoothstep(0.0, 1.0, u)]


## Whether the floor>pull of `bag` at `k` (up_k()), its park over, still rolls
## its roller upright: rolls() and not yet at its tip ("roll_tip"). Read only:
## both are set on sim ticks (roll_step()), never on a drawn frame. Not decided
## yet, it tips as before (only a walker drawn moving early in its park, its
## park cut short, gets here before roll_step() decides).
static func _rolling(bag: Dictionary, k: float) -> bool:
	return rolls(bag) and k < float(bag.get("roll_tip", INF))


## Records on `bag` (CarryOnProps' record of a bag of `kind`), on every sim
## tick `now` (CarryOnProps.sync(), drawn or not), its walker's tick position
## `at` (PassengerViews.tick_position()) and the yaw `face` it faced
## (sit_face()), by tick ("roll_track", the last TRACK_TICKS ticks), then
## applies them to its move (_apply_roll()). The track is the sim's alone, and
## read against the move's own "since", so a move stamped again while its hand
## still reaches (it keeps its "since") reads the same ticks, and a first draw
## coming late (a frame running several ticks) decides the same.
static func roll_step(
	bag: Dictionary, kind: SecurityLooks.Kind, now: float, at: Vector3, face: float
) -> void:
	if kind != SecurityLooks.Kind.ROLLER:
		return
	if not bag.has("roll_track"):
		bag["roll_track"] = {}
	var track: Dictionary = bag["roll_track"]
	track[int(now)] = [at, face]
	track.erase(int(now) - TRACK_TICKS)
	bag["roll_now"] = int(now)
	_apply_roll(bag)


## The sim tick the move of `bag` started on (its "since"), -1 with none.
static func _since_tick(bag: Dictionary) -> int:
	return int(bag.get("since", -1.0))


## Applies the sim's track (roll_step()) to the floor>pull of `bag` (stamped
## "park_up", stamp()) as of the last tick seen ("roll_now"), on that tick or
## on the stamp of a move first drawn late. Once its park's nominal span is
## seen (ROLL_TO ticks in), it decides once whether it rolls: stamped with a
## face (the face on its first tick, stamp()) and not moved more than MOVED_M,
## ROLL_FROM to ROLL_TO, from where it stood ROLL_FROM ticks in ("roll_at"; with
## its first tick's face, "roll_frame", what _carried() carries it in). A
## rolled move is ROLL_TICKS longer. It stops rolling, for good ("roll_tip", the
## move then ending with the tip), once the drawn body is CLEAR_M from where it
## stood (drawn a tick behind its tick position, so a tick on), once its
## walker's home is no longer the hand ("home_held", held_home(): one sitting
## down again tipped at the forced end, 30 ticks on, before it could set the
## roller down again), or so late that the tip only just ends with the move.
## Each set on the tick it falls due, so a tip seen sooner still comes first.
## A track missing a tick it reads (a record made since the move began, as
## after a load) decides no roll.
static func _apply_roll(bag: Dictionary) -> void:
	if not bag.get("park", false) or not bag.get("park_up", false):
		return
	if bag.has("rolls") and (not rolls(bag) or bag.has("roll_tip")):
		return
	var track: Dictionary = bag.get("roll_track", {})
	var since := _since_tick(bag)
	var n := int(bag.get("roll_now", -1)) - since
	if not bag.has("rolls"):
		if n < ROLL_TO:
			return
		var first: Array = track.get(since, [])
		var stood: Array = track.get(since + int(ROLL_FROM), [])
		var moved := first.is_empty() or stood.is_empty()
		for t in range(int(ROLL_FROM), int(ROLL_TO) + 1):
			var row: Array = track.get(since + t, [])
			moved = moved or row.is_empty()
			moved = moved or (row[0] as Vector3).distance_to(stood[0]) > MOVED_M
		bag["rolls"] = bag.get("up_near", false) and not moved
		if not bag["rolls"]:
			return
		bag["ticks"] = TICKS_UP + ROLL_TICKS
		bag["roll_at"] = stood[0]
		bag["roll_frame"] = Transform3D(Basis(Vector3.UP, float(first[1])), stood[0])
	var last := (TICKS_UP + ROLL_TICKS) / TICKS_UP - TIP_UP
	var tip := INF
	for t in range(int(ROLL_TO) + 1, n + 1):
		var row: Array = track.get(since + t, [])
		if not row.is_empty() and (row[0] as Vector3).distance_to(bag["roll_at"]) >= CLEAR_M:
			tip = (t + 1.0) / TICKS_UP
			break
	if bag.get("home_held", false):
		tip = minf(tip, n / TICKS_UP)
	if (n + 1.0) / TICKS_UP < minf(tip, last):
		return
	tip = minf(tip, last)
	bag["roll_tip"] = tip
	# The move ends with the tip, not ROLL_TICKS on: its home and hand are held
	# only while it runs (hold_park()).
	bag["ticks"] = (tip + TIP_UP) * TICKS_UP


## The parked bag `parked` (world, placed in the move's "park_frame") of a
## rolled floor>pull of `bag` carried with the body at `body` (yaw only): held
## where it stands against the walker as it stood on the sim's ticks
## ("roll_frame", _apply_roll()), never against a drawn frame, so every draw
## cadence carries it the same way.
static func _carried(bag: Dictionary, parked: Transform3D, body: Transform3D) -> Transform3D:
	return body * ((bag["roll_frame"] as Transform3D).affine_inverse() * parked)


## The parked bag `parked` (world) carried with the body at `body` (yaw only)
## from where the hand took it again at `k` ("park_tip"): kept on `bag`
## ("park_rel") in the body's frame FOLLOW_SPLIT of the way from the last frame
## it stood alone ("park_last") to now, so a walker going on moves the hand on
## the bar and the bag each part of its step across that frame, not one of them
## all of it (0.058 m a third of a tick for a walker running off, more than the
## 5 cm a change of grip may move; split in halves, the hand short of the bar
## by 2.6 cm put the bag 5.5 cm on).
static func _followed(
	bag: Dictionary, parked: Transform3D, body: Transform3D, k: float
) -> Transform3D:
	if not bag.has("park_rel"):
		# The step only: the last frame at the body's yaw now. A body turning as it
		# goes (PassengerTurns eases a turn over 0.3 s) swung the bag the rest of
		# its turn about the body that frame, 0.15 m in a frame at 3x.
		var last := Transform3D(body.basis, (bag.get("park_last", body) as Transform3D).origin)
		var now := body.affine_inverse() * parked
		bag["park_rel"] = (last.affine_inverse() * parked).interpolate_with(now, FOLLOW_SPLIT)
		bag["park_tip"] = k
	return body * (bag["park_rel"] as Transform3D)
