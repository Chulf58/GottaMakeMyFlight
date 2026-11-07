class_name PlaneClasses
extends RefCounted
## The three plane classes a flight can have (decisions three-runway-sizes-
## unlock-three-plane-classes and runway-and-taxi-technical-design-movement-
## plan-analytic-bookings-planned-pauses, point 2): small, medium and large.
## A class names the models that may draw it, how many passengers it carries
## (decision runway-upgrade-works-wait-for-a-timetable-gap-passengers-per-
## plane-class) and, from PlaneModels, the swing radius a stand reserves for it.
##
## A flight keeps only its airline and its class (the contract's "plane_size");
## the model is worked out from them each time it is needed and is never saved,
## so a re-export or a changed table needs no save change.

const SMALL := "small"
const MEDIUM := "medium"
const LARGE := "large"
## Smallest first.
const ORDER: Array[String] = [SMALL, MEDIUM, LARGE]

## The model StandPlacement is built around (its nose, tail and span), and the
## offset that placement assumes it is drawn with (NOSE_M 14.7 is its nose
## 12.99 m plus 1.7 m).
const REFERENCE_MODEL := "tp_plane_05a"
const REFERENCE_OFFSET := Vector3(0.0, 0.0, 1.7)

## Class -> {"models": the PlaneModels.PLANES names that may draw it,
## "passengers": [fewest, most] booked passengers}.
const CLASSES := {
	SMALL: {"models": ["tp_plane_03a"], "passengers": [8, 16]},
	MEDIUM: {"models": ["tp_plane_04a", "tp_plane_05a"], "passengers": [24, 48]},
	LARGE: {"models": ["tp_plane_06a", "tp_plane_07a"], "passengers": [48, 120]},
}


## True for "small", "medium" and "large".
static func is_plane_class(plane_class: String) -> bool:
	return CLASSES.has(plane_class)


## The model that draws a `plane_class` flight of `airline`: the same two always
## give the same model, and an airline keeps one model within a class. "" for an
## unknown class (with an error).
static func model_for(airline: String, plane_class: String) -> String:
	if not is_plane_class(plane_class):
		push_error("PlaneClasses.model_for: '%s' is not a plane class" % plane_class)
		return ""
	var models: Array = CLASSES[plane_class]["models"]
	return models[airline_hash(airline) % models.size()]


## FNV-1a over the airline's UTF-8 bytes, kept to 31 bits. The project owns it
## because the model is never saved: String.hash() is not promised to stay the
## same across Godot versions, and a changed hash would swap an airline's plane.
static func airline_hash(airline: String) -> int:
	var hashed := 0x811C9DC5
	for byte in airline.to_utf8_buffer():
		hashed = ((hashed ^ byte) * 0x01000193) & 0xFFFFFFFF
	return hashed & 0x7FFFFFFF


## Where a model's origin sits from the stand's plane point so that its front
## port passenger door (the first of its PlaneModels "doors") lands where model
## 05's does with the stand's own offset (REFERENCE_OFFSET). StandPlacement fixes
## the stand, the door walk and the footprint to model 05, so each model is
## moved along and across the plane to that one door rather than centred.
static func stand_offset(model: String) -> Vector3:
	var reference: Vector3 = PlaneModels.PLANES[REFERENCE_MODEL]["doors"][0] + REFERENCE_OFFSET
	var door: Vector3 = PlaneModels.PLANES[model]["doors"][0]
	return Vector3(reference.x - door.x, 0.0, reference.z - door.z)


## The class's stand radius in metres: the largest own_swing_radius among its
## models. 0.0 for an unknown class (with an error).
static func swing_radius(plane_class: String) -> float:
	if not is_plane_class(plane_class):
		push_error("PlaneClasses.swing_radius: '%s' is not a plane class" % plane_class)
		return 0.0
	var radius := 0.0
	for model: String in CLASSES[plane_class]["models"]:
		radius = maxf(radius, PlaneModels.PLANES[model]["own_swing_radius"])
	return radius


## The class's [fewest, most] booked passengers. [] for an unknown class (with
## an error).
static func passenger_range(plane_class: String) -> Array:
	if not is_plane_class(plane_class):
		push_error("PlaneClasses.passenger_range: '%s' is not a plane class" % plane_class)
		return []
	return (CLASSES[plane_class]["passengers"] as Array).duplicate()


## True when `passengers` is inside the class's range.
static func passengers_fit(plane_class: String, passengers: int) -> bool:
	if not is_plane_class(plane_class):
		return false
	var limits: Array = CLASSES[plane_class]["passengers"]
	return passengers >= limits[0] and passengers <= limits[1]
