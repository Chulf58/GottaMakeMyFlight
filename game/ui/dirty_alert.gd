class_name DirtyAlert
extends PanelContainer
## The dirty-terminal alert card (decision cleaner-staff-and-messes-visits-
## leave-messes-bins-fill-pooled-cleaners-nearest-mess, point 6; card form from
## decision hud-steal-list-self-clearing-alert-cards-money-hover-departu): a
## small card at the top of the screen that appears when the terminal's mess
## builds up and clears itself when it is clean again. It reads the summed dirt
## of every mess (MessSim.total_dirt()) and tells the player what to do: hire a
## cleaner when none is hired, otherwise place bins or hire more cleaners.
##
## The dirt has a band so the card does not flicker as cleaners work: it
## shows once the dirt reaches SHOW_AT and stays until it falls below
## CLEAR_BELOW. One fresh mess costs MessSim.DIRT, an aged one AGED_DIRT and a
## grown one GROWN_DIRT, so SHOW_AT is about eight fresh messes or three
## grown ones, and the card clears when about three fresh ones are left.

const SHOW_AT := 8
const CLEAR_BELOW := 4
const HIRE_TEXT := "The terminal is getting dirty. Hire a cleaner on the Staff card."
const BINS_TEXT := (
	"The terminal is getting dirty. Place bins near the bar and toilets, "
	+ "or hire more cleaners."
)
## Below the top row (money, rating, offers, day panel), right edge a gap left
## of the flight panel (which spans the right 460 px less its 20 px margin), so
## the card sits in the free space beside it. It is WIDTH wide, or narrower
## (the text wraps) when the viewport leaves less than that, down to MIN_WIDTH.
const TOP := 76.0
const WIDTH := 420.0
const MIN_WIDTH := 240.0
const RIGHT_GAP := 480.0
const LEFT_MARGIN := 16.0

## The passenger sim whose messes and staff the card reads. A different sim is
## a different world, so the card starts again (reset()).
@export var sim: PassengerSim:
	set(value):
		sim = value
		reset()
## True while something covers the card's place (the open offer sheet); the card
## stays down then and comes back when it is false.
var covered := Callable()

var _shown := false
var _label := Label.new()


func _ready() -> void:
	name = "DirtyAlert"
	theme = BuildMenu.HUD_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_top = TOP
	grow_vertical = Control.GROW_DIRECTION_END
	_fit()
	get_viewport().size_changed.connect(_fit)
	_label.name = "DirtyAlertText"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


## The card's width for a viewport `viewport_w` wide: WIDTH, or what is left of
## it between LEFT_MARGIN and the flight panel, never under MIN_WIDTH.
static func width_for(viewport_w: float) -> float:
	return clampf(viewport_w - RIGHT_GAP - LEFT_MARGIN, MIN_WIDTH, WIDTH)


## Whether the card is up when the dirt is `dirt` and it is `was_shown` now:
## shown at SHOW_AT, kept while at or above CLEAR_BELOW, cleared below it.
static func shown_next(was_shown: bool, dirt: int) -> bool:
	if was_shown:
		return dirt >= CLEAR_BELOW
	return dirt >= SHOW_AT


## What the card says for `cleaners` hired.
static func text_for(cleaners: int) -> String:
	return HIRE_TEXT if cleaners <= 0 else BINS_TEXT


## Puts the card back as at the start: down, with its dirt read afresh at the
## next refresh(). A card that was up does not carry over to another world or a
## load; the dirt then has to reach SHOW_AT again.
func reset() -> void:
	_shown = false
	visible = false
	_label.text = ""


## True while the card is up (it can be up but covered, and then not drawn).
func is_shown() -> bool:
	return _shown


## The card's text: empty while it is down.
func card_text() -> String:
	return _label.text if _shown else ""


## Reads the sim's dirt and hired cleaners and updates the card. Does nothing
## without a sim.
func refresh() -> void:
	if sim == null:
		return
	# A sim with no staff pool has hired nobody.
	var cleaners := 0 if sim.staff == null else sim.staff.count(StaffMember.Role.CLEANER)
	refresh_with(sim.messes.total_dirt(), cleaners)


## Updates the card for `dirt` and `cleaners` hired: the visibility follows
## shown_next(), the text follows the hired count.
func refresh_with(dirt: int, cleaners: int) -> void:
	_shown = shown_next(_shown, dirt)
	visible = _shown and not (covered.is_valid() and covered.call())
	_label.text = text_for(cleaners) if _shown else ""


func _fit() -> void:
	var width := width_for(get_viewport().get_visible_rect().size.x)
	offset_right = -RIGHT_GAP
	offset_left = -RIGHT_GAP - width
