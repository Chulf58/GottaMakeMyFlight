---
name: blender-asset
description: The SOP for building every 3D asset in Blender for the airport tycoon: modular, collection-based, verify-by-render, in the Toon Series look (low-poly, flat palette atlas, toon ramp and outline). Use for ANY asset authoring or major asset modification, whether through the live MCP session or headless --background --python.
---

# The Blender asset SOP

Ported from Dome Farmer, where the method was proven on a large multi-part rig. The method is kept; the art direction below is this game's.

Build the asset as MANY SMALL COMPOSABLE PIECES under a clean hierarchy, verify with your own renders at every stage, and deliver something another scene can append without surgery.

## 1. Structure: modular or it doesn't ship

- One master root empty: `<Asset>_ROOT`. Everything parents to it; the whole asset moves, rotates and scales through it alone.
- Secondary `_ROOT` empties per assembly (for example `Hangar_Door_ROOT`, `Belt_ROOT`) so each assembly lifts out, replaces or animates as a unit.
- One collection per subsystem (`STRUCTURE`, `PROPS`, `LIGHTING`, `CAMERAS`, `MOUNTS`). Descriptive object names throughout (`Terminal_Roof`, `Gate_Desk_L`); a name a grep can find beats a comment.
- Build from separate pieces with visible thickness and seams, not one smooth shell. Keep some deliberate variation (a mismatched sign, one patched panel) so props do not read as copies.
- Animation pivots (empties) for anything that will ever move: doors, barriers, belts, signs. Use object parenting and empties, not armatures, for mechanical motion.
- Mount-point empties (`Mount_*`) for every attachment the asset will ever need. Reference points only; never model the other side.

## 2. Workflow order (each step checkpoint-saves the .blend)

1. Units, real-world scale, render aspect. Apply scale BEFORE final bevel widths.
2. The judging camera and the key subject FIRST (the thing the composition is judged by).
3. Blockout of the enclosing structure.
4. Detail passes, assembly by assembly (never detail one corner to death first).
5. Materials: a SMALL NAMED reusable library built on the palette atlas. Screen and sign materials are clearly named and REPLACEABLE.
6. Decals and wear only where the art direction asks for them. Never random noise on every surface.
7. Asset lighting only if the design needs emissives (lit signs, runway lights).
8. Placeholder graphics for any screen or sign (test grid, label text); never build the world it would show.
9. Test render from the judging camera, OPEN IT, fix the biggest visible fault, repeat.
10. Clean hierarchy, pack all resources, save.

## 3. Standards that bind: Toon Series art direction

Source assets are the Toon Series packs at `/mnt/c/Users/chulf/Assets new/Toon Series/` (Unity FBX). The concept article `airport-tycoon-game` is the authority on the look; read it before a new asset family.

- Low-poly with large readable shapes. Bevelled or hard edges, flat shading or weighted normals, no subdivision-heavy modelling, no photorealism.
- Colour comes from the shared palette atlas (for example `TP_Atlas_1A_D`), not from per-object textures or vertex noise. Assign UVs into the atlas swatches; sample measured swatch positions, never eyeballed ones. A face on UV (0,0) renders black.
- Toon shading is a ramp (two to four hard steps) plus an outline. The Unity toon shaders do not carry over to Godot: they are rebuilt there as a Godot shader. Author in Blender for clean silhouettes and flat colour, and do not bake lighting into the textures.
- Keep silhouettes clear at the game camera's distance. Prioritise geometry the judging camera sees; don't model what nothing can look at.
- Cozy and bright, not industrial or military: friendly proportions, clean colour blocks, readable at a glance in a crowd of props.
- Non-destructive modifiers where practical: Bevel, Weighted Normal, Mirror, Array, Solidify. Authored asymmetry beats a Mirror that forbids it.

## 4. Verification: measured, then eyeballed, in that order

- MEASURE against the brief's dimension bands and print the numbers (widths, heights, subject distances, share of frame in px).
- Enclosure and contact claims get RAY TESTS, and density matters: a coarse first pass can miss real seams.
- Composition claims get measured off the render (px share), not asserted.
- ITERATE ON YOUR OWN RENDERS: render, open, name the biggest visible gap, fix, again. Never stop at a blockout; the final checklist in the brief is binding.
- Structure checks (vertex counts, bounding boxes, UV asserts) say nothing about appearance. Only a render does, and only a windowed Godot render answers "does it look right in the game".
- The conductor opens the deliverable renders before any claim is repeated; the user is the final eye.

## 5. Deliverables: always the same four

1. The organised, PACKED, appendable `.blend` (no external dependencies, relative paths).
2. A hero render from the judging camera.
3. A clay render (form without materials).
4. An overview render from the game's camera angle, next to a 1 m reference cube.

Plates go under `tools/blender/out/<purpose>/` (gitignored).

## 6. Execution modes

- LIVE MCP session when the user wants to watch. Checkpoint-save often; the server adds NO undo step, so the saved `.blend` is the only way back. Follow AGENTS.md "Godot and Blender conventions", MCP mechanics (the `result` dict, mode and selection before each operator, `view_layer.update()`, `.001` names, the temp-folder render path).
- Walk a scene with `get_objects_summary`, then `get_object_detail_summary` on the objects you need; never dump a whole scene. Cap window screenshots with `size_limit_in_bytes`.
- Headless `--background --python` for build, export and batch work (reproducible command lines).
- Graphics and physics work runs on the `implementor-graphic` agent (Opus 5.5 builds, Astra reviews read-only, both on high). Atlas discipline for kit assets: rebind on import, sample measured swatches, check image and material counts in the script's output.
