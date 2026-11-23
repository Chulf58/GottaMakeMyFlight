class_name DemoMode
extends RefCounted
## Demo build switch and content cut-line constants (decision
## demo-scope-and-cut-line-d1-cap-playable-unlocks-at-tier-2-1). Off in the full
## game unless GMMF_DEMO=1 or the "demo" export feature tag is active; tests and
## probes set _override deterministically and reset it in teardown.

const MAX_PLAYABLE_TIER := 2
const MAX_CERTIFICATION_STAR := 2
const TEASER_TIER := 3
const HIDDEN_MIN_TIER := 4
const MAX_EXTRA_LAND_PLOTS := 1
const MAX_DEMO_DAY := 5
const STEAM_STORE_URL := "https://store.steampowered.com/"
## PLACEHOLDER: the feedback page for the Send Feedback button. Empty until set.
const FEEDBACK_URL := ""

static var _override: int = -1


static func is_demo() -> bool:
	if _override != -1:
		return bool(_override)
	return OS.get_environment("GMMF_DEMO") == "1" or OS.has_feature("demo")


static func set_override_for_test(enabled: Variant) -> void:
	if enabled == null:
		_override = -1
		return
	_override = 1 if bool(enabled) else 0


static func clear_override() -> void:
	_override = -1
