class_name ClockHolds
extends RefCounted
## The clock's holds (decision daily-incidents-technical-design-incidentdirector-
## shared-clo): every dialog or mode that pauses the game takes a token here and
## gives it back. SimClock owns one (SimClock.holds) and is paused while the
## player paused it or any token is held, so closing one holder never starts
## the clock under another. A release restores nothing: once no token is left,
## the player's own pause and speed simply apply again.
##
## - acquire() takes a plain hold (build mode).
## - take_turn() takes a hold that also queues for the one exclusive turn
##   (the Offers sheet, the intro, the unlock dialog, later the incident
##   panel). The first such hold in line has the turn; its on_turn runs when it
##   reaches the front, at once if nobody is ahead. The line moves only when a
##   hold leaves it (a release, the owner leaving the tree, the player taking
##   over), never on a tick: a tick-driven wait would never move while paused.
## - A hold taken with yields_to_player gives way when the player resumes or
##   picks another speed (SimClock.set_paused(false), set_speed() to a new
##   value): a plain one ends, and one in line stops pausing the clock but
##   keeps its place and its turn until its owner releases it, so a dialog that
##   comes up meanwhile still waits for it (with the clock held). The others
##   keep the clock paused until their owner releases them.
## - A hold ends by itself when its owner leaves the tree.
## - clear() drops every hold and the line without running any on_turn: a load
##   replaced the world, and each holder ends its own dialog on the load.
##
## Tokens are never reused, so a token from before a clear() releases nothing.

const NONE := 0

var _next := 1
## Tokens in the order they were taken.
var _order: Array[int] = []
## token -> _Hold.
var _holds: Dictionary = {}
## How many holds pause the clock now (a hold in line that gave way does not).
var _pausing := 0


class _Hold:
	var owner: Node
	var yields: bool
	var exclusive: bool
	var pauses := true
	var on_turn: Callable
	var turn_given := false
	## Bound to the owner's tree_exiting; kept to disconnect on release.
	var on_exit: Callable


## A plain hold for `owner`, which must be in the tree. Returns its token, or
## NONE (with an error) for an owner outside the tree, whose hold could never
## end by itself.
func acquire(owner: Node, yields_to_player := false) -> int:
	return _add(owner, yields_to_player, false, Callable())


## A hold that queues for the exclusive turn. `on_turn` runs once, when this
## hold reaches the front of the line: during this call when nobody is ahead.
## The clock is held from now, waiting included. Returns the token, or NONE as
## acquire() does.
func take_turn(owner: Node, on_turn: Callable, yields_to_player := false) -> int:
	var token := _add(owner, yields_to_player, true, on_turn)
	if token != NONE:
		_give_turn()
	return token


## Ends a hold, its turn included, and moves the line on. False, and nothing
## changes, for a token that is not held (released already, ended for the
## player, cleared by a load, or NONE).
func release(token: int) -> bool:
	if not _holds.has(token):
		return false
	_drop(token)
	_give_turn()
	return true


## True while `token` is held, as a pause or only as a place in line.
func has(token: int) -> bool:
	return _holds.has(token)


## True while `token` pauses the clock (false once it gave way to the player).
func pauses(token: int) -> bool:
	return _holds.has(token) and _holds[token].pauses


## True when `token` is first in line for the exclusive turn and its on_turn ran.
func has_turn(token: int) -> bool:
	return _holds.has(token) and _first_in_line() == token and _holds[token].turn_given


## True while any hold pauses the clock.
func is_holding() -> bool:
	return _pausing > 0


## Holds of either kind, a place in line that gave way included.
func count() -> int:
	return _holds.size()


## Drops every hold and the line, running no on_turn (a load).
func clear() -> void:
	for token in _order.duplicate():
		_drop(token)


## The player resumed or picked another speed: every plain hold that gives way
## ends, and every one in line that gives way stops pausing but keeps its place
## and turn. Plain holds are never in line, so the line does not move.
func yield_to_player() -> void:
	for token in _order.duplicate():
		var hold: _Hold = _holds[token]
		if not hold.yields:
			continue
		if not hold.exclusive:
			_drop(token)
		elif hold.pauses:
			hold.pauses = false
			_pausing -= 1


func _add(owner: Node, yields: bool, exclusive: bool, on_turn: Callable) -> int:
	if owner == null or not owner.is_inside_tree():
		push_error("ClockHolds: a hold needs an owner in the tree")
		return NONE
	var token := _next
	_next += 1
	var hold := _Hold.new()
	hold.owner = owner
	hold.yields = yields
	hold.exclusive = exclusive
	hold.on_turn = on_turn
	hold.on_exit = _on_owner_exiting.bind(token)
	owner.tree_exiting.connect(hold.on_exit)
	_holds[token] = hold
	_order.append(token)
	_pausing += 1
	return token


func _on_owner_exiting(token: int) -> void:
	release(token)


func _drop(token: int) -> void:
	var hold: _Hold = _holds[token]
	_holds.erase(token)
	_order.erase(token)
	if hold.pauses:
		_pausing -= 1
	if is_instance_valid(hold.owner) and hold.owner.tree_exiting.is_connected(hold.on_exit):
		hold.owner.tree_exiting.disconnect(hold.on_exit)


func _first_in_line() -> int:
	for token in _order:
		if _holds[token].exclusive:
			return token
	return NONE


## Runs the on_turn of the hold now at the front, once. State is settled first,
## so an on_turn may itself take or release holds.
func _give_turn() -> void:
	var head := _first_in_line()
	if head == NONE:
		return
	var hold: _Hold = _holds[head]
	if hold.turn_given:
		return
	hold.turn_given = true
	if hold.on_turn.is_valid():
		hold.on_turn.call()
