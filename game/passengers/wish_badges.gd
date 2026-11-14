class_name WishBadges
extends RefCounted
## The wish bubbles' side of the count clusters (board c8b16621; user ruling
## 'Merge wishes into badges' in decision calm-cozy-default-view-quiet-world-
## detail-on-ask-soft-statio): in the Mood overlay's Boredom mode, close wish
## bubbles of one shop kind merge into one bubble with a count, whatever state
## each wish is in (wanted, fulfilled or substituted), by the same mechanism as
## the need icons (NeedCluster; decision need-icon-count-clusters-technical-
## design-screen-space-clust). The badge shows the plain wish bubble of the
## kind; a tick or a cross shows only on a focused passenger's own bubble.
## PassengerViews runs a second NeedCluster over the wishes and places both
## kinds of badge together. This file maps a shop kind to the integer a
## NeedCluster calls its kind, and back.


## The cluster kind of shop kind `kind` (a WishTable.CANDIDATES entry): its
## index there.
static func code_of(kind: StringName) -> int:
	var code := WishTable.CANDIDATES.find(kind)
	assert(code >= 0, "wish kind %s is not a WishTable candidate" % kind)
	return code


## The wish icon key (WishIconView.key_of()) of a cluster kind's badge: the
## plain wanted wish of its shop kind.
static func key_of_code(code: int) -> String:
	return WishIconView.key_of(WishTable.CANDIDATES[code], WishTable.State.WANTED)


## The bubble a wish badge shows: the wanted wish icon of its shop kind.
static func texture_of_code(code: int) -> Texture2D:
	return WishIconView.texture(WishTable.CANDIDATES[code], WishTable.State.WANTED)
