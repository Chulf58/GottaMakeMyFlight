class_name BoredomSim
extends RefCounted
## The boredom need, owned by PassengerSim and run on each passenger's beat
## (decision boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh,
## point 1). Boredom is an integer from 0 to MAX. A passenger starts with
## start_of() its id, so neither a spawn nor a migrated save draws from the
## sim RNG. It rises RISE once a simulated second only while the passenger
## waits: in a queue (check-in, security, a cafe counter) or at the gate,
## seated or standing (WAITING_STAGES). Walking, being served and every
## facility visit leave it as it is, and so does being entertained
## (entertained()).
##
## From BORED_AT the passenger is bored: it gets no mood from its gate seat
## (PassengerSim's beat asks is_bored()) and loses a mood point every
## MOOD_BEATS seconds while it has no visit under way, like a high toilet
## need (decision a-passenger-with-a-high-need-detours-to-the-nearest-
## facility). A finished kiosk browse resets it (ShopSim, which NeedsPolicy
## asks after hunger). Tuned by test_boredom_tuning.

const START_MIN := 0
const START_MAX := 30
const MAX := 100
## The rise once a waiting second.
const RISE := 1
const BORED_AT := 50
## A bored passenger with no visit loses a mood point every this many beats.
const MOOD_BEATS := 5
## The stages boredom rises in, every one listed: the station and cafe queues
## and waiting at the gate.
const WAITING_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.CHECKIN_QUEUE,
	Passenger.Stage.SECURITY_QUEUE,
	Passenger.Stage.CAFE_QUEUE,
	Passenger.Stage.SEATED,
	Passenger.Stage.STANDING,
]

## What entertains a passenger, set by the facility that does (shops and
## screens, later items): called with a Passenger, true while it is
## entertained. Unset, nobody is.
var entertainment := Callable()

var _sim: PassengerSim


func bind(sim: PassengerSim) -> void:
	_sim = sim


## The boredom a passenger starts with, spawned or migrated from a save
## without it: spread over the start range by its id.
static func start_of(passenger_id: int) -> int:
	var span := START_MAX - START_MIN + 1
	return START_MIN + posmod(passenger_id * 104729, span)


static func is_bored(p: Passenger) -> bool:
	return p.boredom >= BORED_AT


func entertained(p: Passenger) -> bool:
	return entertainment.is_valid() and entertainment.call(p)


## Whether `p`'s boredom rises on its beat: waiting and not entertained.
func rises(p: Passenger) -> bool:
	return WAITING_STAGES.has(p.stage) and not entertained(p)


## Once a simulated second per passenger: boredom rises while it waits, and
## a bored passenger with no visit under way loses mood.
func beat(p: Passenger) -> void:
	if rises(p):
		p.boredom = mini(p.boredom + RISE, MAX)
	if not is_bored(p) or StageKinds.visit_facility(_sim, p) != StageKinds.Facility.NONE:
		return
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	if posmod(beat_number, MOOD_BEATS) == 0:
		p.mood = maxi(p.mood - 1, 0)
