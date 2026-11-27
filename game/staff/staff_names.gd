class_name StaffNames
extends RefCounted
## Deterministic real names, lightweight cozy quirks, activity summaries, and
## contextual live thoughts for hired staff members (decision 94ec8fbe).
## Names are plain international strings (never translated); quirks, role
## labels, activities, and thoughts go through TranslationServer with a Words
## inner class holding tr() literals for POT extraction.

const SALT_NAME := 0x4F1BBCDC
const SALT_QUIRK := 0x6A09E667

## 47 first names x 43 last names (coprime sizes -> 2,021 unique names before
## repeating any pair, and no repeated first or last name across early hires).
const FIRST: Array[String] = [
	"Maya",
	"Leo",
	"Priya",
	"Mateo",
	"Hana",
	"Omar",
	"Clara",
	"Tariq",
	"Nora",
	"Felix",
	"Sofia",
	"Chidi",
	"Elena",
	"Jonas",
	"Amara",
	"Kenji",
	"Rosa",
	"Henrik",
	"Mei",
	"Lucas",
	"Farah",
	"Emil",
	"Lucia",
	"Jamal",
	"Tessa",
	"Ravi",
	"Astrid",
	"Diego",
	"Yuki",
	"Sam",
	"Nadia",
	"Bruno",
	"Kasia",
	"Kofi",
	"Ilse",
	"Rafael",
	"Gita",
	"Ivan",
	"Camila",
	"Anders",
	"Zara",
	"Tomas",
	"Dara",
	"Marco",
	"Anika",
	"Owen",
	"Linh",
]
const LAST: Array[String] = [
	"Lin",
	"Garcia",
	"Patel",
	"Andersen",
	"Tanaka",
	"Okafor",
	"Rossi",
	"Silva",
	"Novak",
	"Haddad",
	"Kim",
	"Dubois",
	"Costa",
	"Murphy",
	"Petrov",
	"Chen",
	"Morales",
	"Fischer",
	"Adeyemi",
	"Jensen",
	"Torres",
	"Singh",
	"Bianchi",
	"Santos",
	"Schmidt",
	"Lopez",
	"Mori",
	"Wagner",
	"Larsen",
	"Vargas",
	"Becker",
	"Sato",
	"Lindqvist",
	"Kaya",
	"Mensah",
	"Kowalski",
	"Ortiz",
	"Quinn",
	"Romero",
	"Berg",
	"Nair",
	"Alvarez",
	"Zhang",
]

const QUIRKS: Array[String] = [
	"Coffee enthusiast",
	"Always humming",
	"Triple-checks tags",
	"Early bird",
	"Neat freak",
	"Window watcher",
	"Friendly waver",
	"Fast walker",
	"Keeps spare pens",
	"Polishes badges",
	"Loves rainy days",
	"Names the baggage carts",
	"Counts steps",
	"Smooth announcer",
	"Snack sharer",
	"Calm in a rush",
]

static var _words := Words.new()


## Deterministic real full name from `(member_id, world_seed)`, avoiding
## duplicates across early hires.
static func display_name_for(member_id: int, world_seed: int = 0) -> String:
	var idx := maxi(1, member_id) - 1
	var h0 := _mix(world_seed ^ SALT_NAME)
	var h1 := _mix(h0 ^ 0x9E3779B9)
	var first_stride := 1 + posmod(h0, FIRST.size() - 1)
	var last_stride := 1 + posmod(h1, LAST.size() - 1)
	var first_idx := posmod(posmod(h0 >> 6, FIRST.size()) + idx * first_stride, FIRST.size())
	var last_idx := posmod(posmod(h1 >> 6, LAST.size()) + idx * last_stride, LAST.size())
	return "%s %s" % [FIRST[first_idx], LAST[last_idx]]


## Deterministic canonical English quirk keys (1-2 quirks) stored on StaffMember.
static func quirk_keys_for(member_id: int, world_seed: int = 0) -> Array[String]:
	var h := _mix(_mix(maxi(1, member_id)) ^ _mix(world_seed ^ SALT_QUIRK))
	var first_idx := posmod(h, QUIRKS.size())
	var out: Array[String] = [QUIRKS[first_idx]]
	if (h & 1) == 1 or (h & 4) == 4:
		var step := 1 + posmod(h >> 8, QUIRKS.size() - 1)
		var second_idx := posmod(first_idx + step, QUIRKS.size())
		out.append(QUIRKS[second_idx])
	return out


## Translated 1-2 cozy quirks for `(member_id, world_seed)`.
static func quirks_for(member_id: int, world_seed: int = 0) -> Array[String]:
	var out: Array[String] = []
	for key in quirk_keys_for(member_id, world_seed):
		out.append(TranslationServer.translate(key))
	return out


## Translates a stored canonical quirk string.
static func translate_quirk(quirk: String) -> String:
	return TranslationServer.translate(quirk)


## Translated singular role label.
static func role_label(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return TranslationServer.translate("Check-in agent")
		StaffMember.Role.SECURITY:
			return TranslationServer.translate("Security officer")
		StaffMember.Role.GATE:
			return TranslationServer.translate("Gate agent")
		StaffMember.Role.SHOP:
			return TranslationServer.translate("Shop server")
		StaffMember.Role.CLEANER:
			return TranslationServer.translate("Cleaner")
		StaffMember.Role.RAMP:
			return TranslationServer.translate("Ramp agent")
	return TranslationServer.translate("Staff")


## Short hover caption showing real name + role for HoverTarget tooltips.
static func hover_caption(_sim: Object, member: StaffMember) -> String:
	if member == null:
		return ""
	var staff_name := (
		member.display_name if member.display_name != "" else display_name_for(member.id)
	)
	return TranslationServer.translate("{name} · {role}").format(
		{"name": staff_name, "role": role_label(member.role)}
	)


## Live translated activity line for StaffInspect.
static func activity_text(sim: Object, member: StaffMember) -> String:
	if member == null:
		return ""
	var resolved := _resolve_sims(sim)
	var pax_sim: PassengerSim = resolved[0]
	var station_name := _station_label(pax_sim, member)
	var out := ""
	match member.state:
		StaffMember.State.WALKING_OUT:
			out = TranslationServer.translate("Walking out")
		StaffMember.State.LEAVING_SHIFT:
			out = TranslationServer.translate("Heading off shift")
		StaffMember.State.OFF_SHIFT:
			out = TranslationServer.translate("Off shift")
		StaffMember.State.TO_BREAK:
			out = TranslationServer.translate("Heading to Break Room")
		StaffMember.State.ON_BREAK:
			out = TranslationServer.translate("Resting in Break Room")
		_:
			out = _active_activity_text(member, station_name)
	return out


static func _active_activity_text(member: StaffMember, station_name: String) -> String:
	if member.role == StaffMember.Role.RAMP:
		match member.ramp_job:
			StaffMember.RampJob.SHUTTLE:
				return TranslationServer.translate("Driving baggage cart")
			StaffMember.RampJob.PUSHBACK:
				return TranslationServer.translate("Operating pushback tug")
			StaffMember.RampJob.MARSHAL:
				return TranslationServer.translate("Marshalling aircraft")
			_:
				return TranslationServer.translate("Patrolling apron")
	if member.role == StaffMember.Role.CLEANER:
		if member.state == StaffMember.State.ON_DUTY:
			return (
				TranslationServer.translate("Emptying bin")
				if member.job_bin
				else TranslationServer.translate("Cleaning mess")
			)
		if member.state == StaffMember.State.TO_STATION:
			return (
				TranslationServer.translate("Walking to full bin")
				if member.job_bin
				else TranslationServer.translate("Walking to mess")
			)
		return (
			TranslationServer.translate("Patrolling terminal")
			if member.is_moving()
			else TranslationServer.translate("On standby")
		)
	if member.state == StaffMember.State.TO_STATION:
		return TranslationServer.translate("Walking to {station}").format({"station": station_name})
	if member.state == StaffMember.State.ON_DUTY:
		if member.is_helper():
			return TranslationServer.translate("Helping at Security lane")
		return TranslationServer.translate("On duty at {station}").format({"station": station_name})
	return TranslationServer.translate("Waiting for assignment")


## Short, charming contextual thought matching the member's real current state.
static func live_thought(sim: Object, member: StaffMember) -> String:
	if member == null:
		return ""
	var resolved := _resolve_sims(sim)
	var pax_sim: PassengerSim = resolved[0]
	var staff_sim: StaffSim = resolved[1]
	var msg := _lifecycle_thought(member)
	if msg == "":
		msg = _role_thought(pax_sim, staff_sim, member)
	return TranslationServer.translate(msg)


static func _lifecycle_thought(member: StaffMember) -> String:
	if member.leaving:
		return "Finishing up this last one before I head out."
	match member.state:
		StaffMember.State.WALKING_OUT:
			return "Heading for the exit. Good luck, team!"
		StaffMember.State.LEAVING_SHIFT:
			return "Heading home for the night."
		StaffMember.State.OFF_SHIFT:
			return "Off shift, resting up for tomorrow."
		StaffMember.State.TO_BREAK:
			return "Could really use a coffee in the Break Room."
		StaffMember.State.ON_BREAK:
			if member.energy >= 80:
				return "Feeling recharged and ready to head back."
			return "Putting my feet up for a minute."
	if member.is_tired():
		return "Running low on steam, hoping for a break soon."
	return ""


static func _role_thought(
	pax_sim: PassengerSim, staff_sim: StaffSim, member: StaffMember
) -> String:
	if member.role == StaffMember.Role.RAMP:
		return _ramp_thought(member)
	if member.role == StaffMember.Role.CLEANER:
		return _cleaner_thought(member)
	if member.state == StaffMember.State.TO_STATION:
		return _walking_thought(member.role)
	if member.state == StaffMember.State.ON_DUTY:
		return _on_duty_thought(pax_sim, staff_sim, member)
	if member.level >= 2:
		return _trained_thought(member.level)
	return "Ready and waiting for a station assignment."


static func _ramp_thought(member: StaffMember) -> String:
	match member.ramp_job:
		StaffMember.RampJob.SHUTTLE:
			return "Cart's loaded, heading across the apron."
		StaffMember.RampJob.PUSHBACK:
			return "Pushback clear, guiding the nose out."
		StaffMember.RampJob.MARSHAL:
			return "Wands up, bringing this bird in smoothly."
	return "Patrolling the apron, checking stands and cones."


static func _cleaner_thought(member: StaffMember) -> String:
	if member.state == StaffMember.State.ON_DUTY:
		if member.job_bin:
			return "Emptying this full bin before it overflows."
		return "Cleaning up this mess, spotless in a jiffy."
	if member.state == StaffMember.State.TO_STATION:
		if member.job_bin:
			return "On my way to empty a full bin."
		return "Spotted a mess, heading over with the mop."
	if member.is_moving():
		return "Doing the terminal rounds, keeping an eye out."
	if member.level >= 2:
		return _trained_thought(member.level)
	return "Terminal looks tidy for now."


static func _walking_thought(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return "Heading over to my check-in desk."
		StaffMember.Role.SECURITY:
			return "Walking to my security post."
		StaffMember.Role.GATE:
			return "Making my way to the gate desk."
		StaffMember.Role.SHOP:
			return "Heading to the counter to open up."
	return "On my way to post."


static func _on_duty_thought(
	pax_sim: PassengerSim, staff_sim: StaffSim, member: StaffMember
) -> String:
	if staff_sim != null and member.station != 0:
		if staff_sim.faults.is_faulted(member.station):
			return "Scanner's acting up, waiting on the reset."
		if staff_sim.closures.is_closed(member.station):
			return "Closing down the lane once this clears."
	var serving := (
		pax_sim != null and member.station != 0 and StaffPosts.in_service(pax_sim, member.station)
	)
	if serving:
		return _serving_thought(member)
	if member.level >= 2:
		return _trained_thought(member.level)
	return _waiting_thought(member.role)


static func _serving_thought(member: StaffMember) -> String:
	match member.role:
		StaffMember.Role.CHECKIN:
			return "Printing boarding passes and tagging bags."
		StaffMember.Role.SECURITY:
			if member.is_helper():
				return "Helping repack carry-ons at the berth."
			return "Keeping an eye on the X-ray belt."
		StaffMember.Role.GATE:
			return "Scanning boarding passes, welcome aboard!"
		StaffMember.Role.SHOP:
			return "Serving a customer at the counter."
	return "Happy to help!"


static func _waiting_thought(role: StaffMember.Role) -> String:
	match role:
		StaffMember.Role.CHECKIN:
			return "Desk is open, ready for the next flyer."
		StaffMember.Role.SECURITY:
			return "Security belt is clear and ready."
		StaffMember.Role.GATE:
			return "Gate desk is ready for boarding."
		StaffMember.Role.SHOP:
			return "Counter is stocked and ready."
	return "Ready and waiting for a station assignment."


static func _trained_thought(level: int) -> String:
	if level >= 3:
		return "Mastered the station, Level 3 feels effortless."
	return "Loving the new skills from Level 2 training."


static func _station_label(pax_sim: PassengerSim, member: StaffMember) -> String:
	if member.role == StaffMember.Role.CHECKIN:
		return TranslationServer.translate("Check-in desk")
	if member.role == StaffMember.Role.GATE:
		return TranslationServer.translate("Gate desk")
	if member.role == StaffMember.Role.SECURITY:
		if (
			pax_sim != null
			and member.station != 0
			and pax_sim.layout.security_lanes.is_complete(member.station)
		):
			return TranslationServer.translate("Security lane")
		return TranslationServer.translate("Security scanner")
	if member.role == StaffMember.Role.SHOP:
		if pax_sim != null and pax_sim.grid != null and member.station != 0:
			var rec := pax_sim.grid.get_object(member.station)
			if rec.get("def", &"") == &"info_desk":
				return TranslationServer.translate("Info desk")
		return TranslationServer.translate("Counter")
	return TranslationServer.translate("station")


static func _resolve_sims(sim: Object) -> Array:
	if sim is PassengerSim:
		var pax := sim as PassengerSim
		return [pax, pax.staff]
	if sim is StaffSim:
		var staff := sim as StaffSim
		return [staff.sim, staff]
	return [null, null]


static func _mix(x: int) -> int:
	x = (x ^ (x >> 16)) * 0x45D9F3B
	x = (x ^ (x >> 16)) * 0x45D9F3B
	return (x ^ (x >> 16)) & 0x7FFFFFFF


## Holds tr() literals for POT extraction.
class Words:
	extends RefCounted

	func msgids() -> PackedStringArray:
		return PackedStringArray(
			[
				tr("Coffee enthusiast"),
				tr("Always humming"),
				tr("Triple-checks tags"),
				tr("Early bird"),
				tr("Neat freak"),
				tr("Window watcher"),
				tr("Friendly waver"),
				tr("Fast walker"),
				tr("Keeps spare pens"),
				tr("Polishes badges"),
				tr("Loves rainy days"),
				tr("Names the baggage carts"),
				tr("Counts steps"),
				tr("Smooth announcer"),
				tr("Snack sharer"),
				tr("Calm in a rush"),
				tr("Check-in agent"),
				tr("Security officer"),
				tr("Gate agent"),
				tr("Shop server"),
				tr("Cleaner"),
				tr("Ramp agent"),
				tr("Staff"),
				tr("{name} · {role}"),
				tr("Walking out"),
				tr("Heading off shift"),
				tr("Off shift"),
				tr("Heading to Break Room"),
				tr("Resting in Break Room"),
				tr("Driving baggage cart"),
				tr("Operating pushback tug"),
				tr("Marshalling aircraft"),
				tr("Patrolling apron"),
				tr("Emptying bin"),
				tr("Cleaning mess"),
				tr("Walking to full bin"),
				tr("Walking to mess"),
				tr("Patrolling terminal"),
				tr("On standby"),
				tr("Walking to {station}"),
				tr("Helping at Security lane"),
				tr("On duty at {station}"),
				tr("Waiting for assignment"),
				tr("Check-in desk"),
				tr("Gate desk"),
				tr("Security lane"),
				tr("Security scanner"),
				tr("Info desk"),
				tr("Counter"),
				tr("station"),
				tr("Finishing up this last one before I head out."),
				tr("Heading for the exit. Good luck, team!"),
				tr("Heading home for the night."),
				tr("Off shift, resting up for tomorrow."),
				tr("Could really use a coffee in the Break Room."),
				tr("Feeling recharged and ready to head back."),
				tr("Putting my feet up for a minute."),
				tr("Running low on steam, hoping for a break soon."),
				tr("Ready and waiting for a station assignment."),
				tr("Cart's loaded, heading across the apron."),
				tr("Pushback clear, guiding the nose out."),
				tr("Wands up, bringing this bird in smoothly."),
				tr("Patrolling the apron, checking stands and cones."),
				tr("Emptying this full bin before it overflows."),
				tr("Cleaning up this mess, spotless in a jiffy."),
				tr("On my way to empty a full bin."),
				tr("Spotted a mess, heading over with the mop."),
				tr("Doing the terminal rounds, keeping an eye out."),
				tr("Terminal looks tidy for now."),
				tr("Heading over to my check-in desk."),
				tr("Walking to my security post."),
				tr("Making my way to the gate desk."),
				tr("Heading to the counter to open up."),
				tr("On my way to post."),
				tr("Scanner's acting up, waiting on the reset."),
				tr("Closing down the lane once this clears."),
				tr("Printing boarding passes and tagging bags."),
				tr("Helping repack carry-ons at the berth."),
				tr("Keeping an eye on the X-ray belt."),
				tr("Scanning boarding passes, welcome aboard!"),
				tr("Serving a customer at the counter."),
				tr("Happy to help!"),
				tr("Desk is open, ready for the next flyer."),
				tr("Security belt is clear and ready."),
				tr("Gate desk is ready for boarding."),
				tr("Counter is stocked and ready."),
				tr("Mastered the station, Level 3 feels effortless."),
				tr("Loving the new skills from Level 2 training."),
			]
		)
