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
## A waiting passenger a screen stand covers (ScreenCoverage, Boredom 4/5;
## decision boredom-screens-halve-how-fast-boredom-rises-for-covered-wai)
## watches it, and its boredom rises at half the rate: RISE once every
## SCREEN_RISE_BEATS seconds, however many screens cover it. A screen never
## lowers boredom, so a long wait still ends in a kiosk visit
## (test_screen_tuning). A seated passenger watches from its chair's cell,
## everyone else from the cell it is on.
##
## A waiting passenger who looks at a prize car (PrizeCar.looks(): one in three,
## within a few cells of the podium) does not get bored while it does: its boredom
## does not rise and drops PrizeCar.LOOK_RELIEF every PrizeCar.LOOK_RELIEF_BEATS
## beats.
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
## While a screen covers a waiting passenger, boredom rises RISE only once
## every this many beats: half the rate.
const SCREEN_RISE_BEATS := 2
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
## The cells the grid's screen stands cover, followed from bind().
var screens := ScreenCoverage.new()
## The cells the grid's prize cars reach, followed from bind().
var prize := PrizeCar.new()

var _sim: PassengerSim


func bind(sim: PassengerSim) -> void:
	_sim = sim
	if sim.grid != null:
		screens.bind(sim.grid)
		prize.bind(sim.grid)


## The boredom a passenger starts with, spawned or migrated from a save
## without it: spread over the start range by its id.
static func start_of(passenger_id: int) -> int:
	var span := START_MAX - START_MIN + 1
	return START_MIN + posmod(passenger_id * 104729, span)


static func is_bored(p: Passenger) -> bool:
	return p.boredom >= BORED_AT


func entertained(p: Passenger) -> bool:
	return entertainment.is_valid() and entertainment.call(p)


## The cell `p` watches a screen from: its chair while seated, else where it is.
static func watch_cell(p: Passenger) -> Vector2i:
	if p.stage == Passenger.Stage.SEATED and p.seat_cell != Passenger.NO_CELL:
		return p.seat_cell
	return p.at


## Whether `p` watches a screen on its beat: waiting where one covers it.
func watching(p: Passenger) -> bool:
	return WAITING_STAGES.has(p.stage) and screens.covers(watch_cell(p))


## Whether `p`'s boredom rises on its beat: waiting and not entertained. While
## it watches a screen, only every SCREEN_RISE_BEATS-th beat raises it.
func rises(p: Passenger) -> bool:
	return WAITING_STAGES.has(p.stage) and not entertained(p)


## Once a simulated second per passenger: boredom rises while it waits, at half
## the rate under a screen, and a bored passenger with no visit under way loses
## mood.
func beat(p: Passenger) -> void:
	@warning_ignore("integer_division")
	var beat_number := _sim.tick / PassengerSim.BEAT_TICKS
	var slowed := watching(p) and posmod(beat_number, SCREEN_RISE_BEATS) != 0
	if prize.looks(p):
		if posmod(beat_number, PrizeCar.LOOK_RELIEF_BEATS) == 0:
			p.boredom = maxi(p.boredom - PrizeCar.LOOK_RELIEF, 0)
	elif rises(p) and not slowed:
		p.boredom = mini(p.boredom + RISE, MAX)
	if not is_bored(p) or StageKinds.visit_facility(_sim, p) != StageKinds.Facility.NONE:
		return
	if posmod(beat_number, MOOD_BEATS) == 0:
		p.mood = maxi(p.mood - 1, 0)
