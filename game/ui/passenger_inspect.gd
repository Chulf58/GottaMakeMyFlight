class_name PassengerInspect
extends PanelContainer
## The inspect card of the followed passenger (HUD 4/7, decision passenger-
## inspect-thoughts-recorded-at-sim-outcomes-saved-pin-marks-where), in the
## bottom-left place of the follow text, which PassengerHud hides while the card
## shows. Live status (stage, flight, mood, hunger, toilet need, boredom, and
## on their own line whether it runs late and what holds it up right now,
## both when both hold) is kept apart from its thoughts
## (PassengerThoughts), newest first, one button each, coral for a bad thought
## and green for a good one.
##
## Clicking a thought glides the camera to the cell where the passenger was,
## which stops the follow, and pins it (ThoughtMarker) until another thought
## is clicked, the passenger is deselected or a game is loaded; a line under
## the thoughts says the pin shows where the passenger was. The passenger's
## name follows the passenger again. A thought with no cell pins nothing.

## The card's widest, so it stays a card on a wide screen.
const MAX_W := 420.0
const MIN_W := 160.0
## The card's bottom edge, up from the bottom of the screen: one GAP above
## BuildMenu's Templates button, which docks at the left edge one bar's height
## above the category bar (TemplatesPage.attach()).
const BOTTOM := BuildMenu.MARGIN + 2.0 * BuildMenu.BAR_H + 2.0 * BuildMenu.GAP

var sim: PassengerSim
var views: PassengerViews
var camera: TycoonCamera
var flights: FlightSim
var clock: SimClock
## The pin; PassengerHud puts it in the world.
var marker := ThoughtMarker.new()
## The selected built item's rows, shown in place of the passenger's while an
## item is selected (BuiltItemCard); PassengerHud wires its selection.
var built_card := BuiltItemCard.new()
## Move and Delete under the item card (BuiltItemActions).
var actions := BuiltItemActions.new()

var _passenger_rows := VBoxContainer.new()
var _name := Button.new()
var _stage := Label.new()
var _flight := Label.new()
var _status := Label.new()
var _now := Label.new()
var _heading := Label.new()
var _rows: Array[Button] = []
var _marked := Label.new()
## The passenger the pin belongs to, 0 for none.
var _marked_id := 0
var _marked_text := ""


func _init() -> void:
	name = "PassengerInspect"
	visible = false
	theme = BuildMenu.HUD_THEME
	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(built_card)
	actions.card = built_card
	root.add_child(actions)
	var column := _passenger_rows
	column.add_theme_constant_override("separation", 2)
	root.add_child(column)
	_name.name = "PassengerName"
	_name.focus_mode = Control.FOCUS_NONE
	_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name.theme_type_variation = &"HudButtonTeal"
	_name.tooltip_text = "Follow this passenger"
	_name.pressed.connect(press_name)
	column.add_child(_name)
	for label in [_stage, _flight, _status, _now]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_now.theme_type_variation = &"HudProblemText"
	_heading.text = "Thoughts"
	_heading.theme_type_variation = &"HudSmall"
	column.add_child(_heading)
	for i in PassengerThoughts.CAP:
		var row := Button.new()
		row.name = "Thought%d" % i
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text = "Show where this happened"
		row.pressed.connect(press_thought.bind(i))
		column.add_child(row)
		_rows.append(row)
	_marked.theme_type_variation = &"HudHint"
	_marked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_marked)


func _ready() -> void:
	# Delete starts build mode through the bar's session (a sibling of PassengerHud).
	var menu := get_node_or_null("../../BuildMenu") as BuildMenu
	if menu != null and actions.session == null:
		actions.session = menu.build_session
	fit()
	get_viewport().size_changed.connect(fit)


## Bottom-left, left of BuildMenu's centre column and above its Templates
## button, growing upward.
func fit() -> void:
	var room := (get_viewport().get_visible_rect().size.x - BuildMenu.COLUMN_W) / 2.0 - 28.0
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 16.0
	offset_right = 16.0 + clampf(room, MIN_W, MAX_W)
	offset_top = -BOTTOM
	offset_bottom = -BOTTOM
	grow_vertical = Control.GROW_DIRECTION_BEGIN


## Shows the selected passenger, or the selected built item (BuiltItemCard), or
## hides the card with neither (a car or taxi followed on the landside clears
## the passenger selection). A pin of a
## passenger no longer selected is cleared.
func refresh() -> void:
	var p := _selected()
	if _marked_id != 0 and (p == null or p.id != _marked_id):
		clear_marker()
	built_card.refresh()
	actions.refresh()
	_passenger_rows.visible = p != null
	visible = p != null or built_card.visible
	if p == null:
		return
	_name.text = "Passenger %d" % p.id
	_stage.text = PassengerHud.stage_text(sim, p)
	_flight.text = _flight_line(p)
	_status.text = (
		"Mood %d   Hunger %d   Toilet %d   Boredom %d"
		% [p.mood, p.hunger, p.toilet_need, p.boredom]
	)
	_now.text = now_line(sim, p)
	_now.visible = _now.text != ""
	var entries := PassengerThoughts.entries(p)
	_heading.text = "Thoughts" if not entries.is_empty() else "Thoughts: none yet"
	for i in _rows.size():
		var row := _rows[i]
		row.visible = i < entries.size()
		if not row.visible:
			continue
		var entry := entries[i]
		row.text = "%s · %s" % [entry["text"], _age(entry["tick"])]
		row.theme_type_variation = &"HudButtonGreen" if entry["positive"] else &"HudButtonCoral"
	_marked.text = _marked_text
	_marked.visible = _marked_text != ""


## A click on the `index`th thought, newest first: glides the camera to the
## cell where the passenger was, ending the follow, and pins it. False when
## there is no such thought or it has no cell.
func press_thought(index: int) -> bool:
	var p := _selected()
	if p == null:
		return false
	var entries := PassengerThoughts.entries(p)
	if index < 0 or index >= entries.size():
		return false
	var entry := entries[index]
	var cell: Vector2i = entry["cell"]
	if cell == Passenger.NO_CELL:
		return false
	var point := sim.grid.cell_to_world(cell)
	marker.show_at(point, entry["positive"])
	_marked_id = p.id
	_marked_text = "The pin shows where they were at %s" % GameCalendar.clock_text(entry["tick"])
	if camera != null:
		camera.glide_to(point, minf(camera.distance, AlertStack.JUMP_DISTANCE))
	refresh()
	return true


## A click on the passenger's name: the camera follows the passenger again.
func press_name() -> void:
	if camera != null and _selected() != null:
		camera.follow(views.follow_anchor)


func clear_marker() -> void:
	marker.clear()
	_marked_id = 0
	_marked_text = ""


## A finished load (SaveGame.loaded): a pin from before it is cleared.
func on_loaded(ok: bool) -> void:
	if ok:
		clear_marker()


## Lateness and the current obstruction, each on its own: "Running late",
## 'Stuck: "Queue full"' or both, "" for neither or once the journey ended.
## The obstruction's words are the speech bubble's (PassengerSim.bubble_text(),
## which shows the obstruction alone when both hold).
static func now_line(passenger_sim: PassengerSim, p: Passenger) -> String:
	if p.is_done():
		return ""
	var parts := PackedStringArray()
	if p.late:
		parts.append("Running late")
	if p.stuck != Passenger.Stuck.NONE:
		parts.append('Stuck: "%s"' % passenger_sim.bubble_text(p))
	return "   ".join(parts)


func now_text() -> String:
	return _now.text if _now.visible else ""


func name_text() -> String:
	return _name.text


func status_text() -> String:
	return _status.text


func flight_text() -> String:
	return _flight.text


## The thought buttons' texts, newest first, for the shown thoughts only.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _rows:
		if row.visible:
			out.append(row.text)
	return out


## What the pin is, while one is shown, else "".
func marked_text() -> String:
	return _marked_text


func _selected() -> Passenger:
	if sim == null or views == null or views.selected_id == 0:
		return null
	return sim.get_passenger(views.selected_id)


## "Flight Sunhop Lisbon, boards 10:40" (FlightResultPanel.title_for).
func _flight_line(p: Passenger) -> String:
	return (
		"Flight %s, boards %s"
		% [
			FlightResultPanel.title_for(flights, p.flight_id),
			GameCalendar.clock_text(p.boarding_tick)
		]
	)


func _age(tick: int) -> String:
	if clock == null:
		return ""
	@warning_ignore("integer_division")
	var minutes := maxi(clock.tick - tick, 0) / GameCalendar.TICKS_PER_MINUTE
	return "just now" if minutes == 0 else "%d min ago" % minutes
