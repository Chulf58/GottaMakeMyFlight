class_name WishBadges
extends RefCounted
## The wish bubbles' side of the count clusters (board c8b16621; user ruling
## 'Merge wishes into badges' in decision calm-cozy-default-view-quiet-world-
## detail-on-ask-soft-statio): in the Mood overlay's Boredom mode, close wish
## bubbles that look alike (one shop kind in one state: wanted, fulfilled or
## substituted, so a tick or a cross is never merged into a plain wish) merge
## into one bubble with a count, by the same mechanism as the need icons
## (NeedCluster; decision need-icon-count-clusters-technical-design-screen-
## space-clust). PassengerViews runs a second NeedCluster over the wishes and
## places both kinds of badge together. This file maps a wish icon to the
## integer a NeedCluster calls its kind, and back.

## Wish icons per shop kind: WishIconView.Badge's NONE, TICK and CROSS.
const PER_KIND := 3


## The cluster kind of wish icon `key` (WishIconView.key_of(): "kiosk/0").
static func code_of(key: String) -> int:
	var parts := key.split("/")
	var kind := WishTable.CANDIDATES.find(StringName(parts[0]))
	assert(kind >= 0, "wish kind %s is not a WishTable candidate" % parts[0])
	return kind * PER_KIND + int(parts[1])


## The wish icon key a cluster kind stands for.
static func key_of_code(code: int) -> String:
	return "%s/%d" % [WishTable.CANDIDATES[code / PER_KIND], code % PER_KIND]


## The bubble a wish badge shows: the wish icon of its kind and state.
static func texture_of_code(code: int) -> Texture2D:
	return WishIconView.texture_for(WishTable.CANDIDATES[code / PER_KIND], code % PER_KIND)
