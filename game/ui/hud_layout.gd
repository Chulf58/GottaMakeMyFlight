class_name HudLayout
extends RefCounted
## The HUD's one spacing grid, size family and type scale, in layout px
## (1536x864: a 1920x1080 window at the canvas_items stretch of 1.25). Every
## HUD window places itself from these numbers (decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra, part 1); the
## corner radius and border widths live in ui/hud_theme.tres. Constants only.

## The grid step: every margin, gap, height and width is a multiple of it.
const UNIT := 8
## Distance from every screen edge to the nearest window.
const MARGIN := 16
## Space between windows inside one group.
const GAP := 8
## Space between two groups of windows.
const GROUP_GAP := 16

## Heights.
const CHIP_H := 32
const BUTTON_H := 40
const BAR_H := 52

## Widths, by role.
## A toggle button: the top row's Build mode sign, Runway and Offers, and the
## top-left column's Mood, Departures and Hints.
const TOGGLE_W := 176
const MONEY_W := 224
## A list that opens under the top-left column, such as Departures.
const LIST_W := 304
## The right rail: the clock panel and the alert and result cards under it.
const RAIL_W := 440
const SHEET_W := 560
const TRAY_W := 640

## The type scale, in px.
const CAPTION := 14
const BODY := 16
const TITLE := 18
const PANEL_TITLE := 22
const FIGURE := 24
const TYPE_SCALE: Array[int] = [CAPTION, BODY, TITLE, PANEL_TITLE, FIGURE]
