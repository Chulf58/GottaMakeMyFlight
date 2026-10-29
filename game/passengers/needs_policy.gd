class_name NeedsPolicy
extends RefCounted
## Which need a passenger acts on when more than one is high (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 5:
## simultaneous needs pick by an explicit priority, not call order). On each
## passenger's beat PassengerSim first lets every facility sim raise its need
## (their beats start no visit), then calls arbitrate(): the needs are asked
## in ORDER whether the passenger wants a visit and whether one is viable now
## (the facility's plan_visit(), which commits nothing). The first viable one
## is started; each need above it that was wanted but had no viable visit is
## refused (its facility's retry cooldown starts), and the needs below it are
## not asked. With none viable, every wanted one is refused.

enum Need { NONE, TOILET, HUNGER, BROWSE, BOREDOM, SHOP_BROWSE }

## Highest priority first. TOILET before HUNGER: a high toilet need cannot be
## put off, and a stall visit is short and free, while a hungry passenger can
## wait and still eat later. BOREDOM after HUNGER (decision boredom-and-shops-
## design-boredom-need-while-waiting-kiosk-sh, points 1 and 2): a bored
## passenger detours to a kiosk. The spare-time drop-ins come last, as they
## are no need at all: BROWSE (a cafe) before SHOP_BROWSE (a kiosk), so a
## passenger passing both drops into the cafe, and cafe browsing works
## exactly as it did before kiosks.
const ORDER: Array[Need] = [Need.TOILET, Need.HUNGER, Need.BOREDOM, Need.BROWSE, Need.SHOP_BROWSE]


## The visit `p` would start now, without starting anything: {"need": the
## chosen Need or NONE, "plan": its facility's plan (empty with NONE),
## "refused": the wanted needs above it that had no viable visit}.
static func choose(sim: PassengerSim, p: Passenger) -> Dictionary:
	var refused: Array[Need] = []
	for need in ORDER:
		if not _wants(sim, p, need):
			continue
		var plan := _plan(sim, p, need)
		if not plan.is_empty():
			return {"need": need, "plan": plan, "refused": refused}
		refused.append(need)
	return {"need": Need.NONE, "plan": {}, "refused": refused}


## Starts the visit choose() picks and refuses the wanted needs above it.
## Returns the need acted on, or NONE.
static func arbitrate(sim: PassengerSim, p: Passenger) -> Need:
	var choice := choose(sim, p)
	for need: Need in choice["refused"]:
		match need:
			Need.TOILET:
				sim.toilets.refuse(p)
			Need.HUNGER:
				sim.cafes.refuse(p)
			Need.BROWSE:
				sim.cafes.refuse(p, true)
			Need.BOREDOM:
				sim.shops.refuse(p)
			Need.SHOP_BROWSE:
				sim.shops.refuse(p, true)
	match choice["need"]:
		Need.TOILET:
			sim.toilets.commit_visit(p, choice["plan"])
		Need.HUNGER, Need.BROWSE:
			sim.cafes.commit_visit(p, choice["plan"])
		Need.BOREDOM, Need.SHOP_BROWSE:
			sim.shops.commit_visit(p, choice["plan"])
	return choice["need"]


static func _wants(sim: PassengerSim, p: Passenger, need: Need) -> bool:
	match need:
		Need.TOILET:
			return sim.toilets.wants_visit(p)
		Need.HUNGER:
			return sim.cafes.wants_food(p)
		Need.BOREDOM:
			return sim.shops.wants_relief(p)
		Need.SHOP_BROWSE:
			return sim.shops.wants_browse(p)
		Need.BROWSE:
			return sim.cafes.wants_browse(p)
	return false


static func _plan(sim: PassengerSim, p: Passenger, need: Need) -> Dictionary:
	match need:
		Need.TOILET:
			return sim.toilets.plan_visit(p)
		Need.HUNGER:
			return sim.cafes.plan_visit(p)
		Need.BROWSE:
			return sim.cafes.plan_visit(p, true)
		Need.BOREDOM:
			return sim.shops.plan_visit(p)
		Need.SHOP_BROWSE:
			return sim.shops.plan_visit(p, true)
	return {}
