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
	return models[airline.hash() % models.size()]


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
