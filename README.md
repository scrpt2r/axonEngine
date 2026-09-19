# axonEngine

A from-scratch graphics and game engine built in Roblox Luau — currently focused
on a CPU-side 3D software rasterizer that renders onto a 2D EditableImage canvas,
with the long-term goal of growing into a full game engine.

## What this is

axonEngine implements the 3D rendering pipeline manually, without relying on
Roblox's native 3D rendering (Parts, MeshParts, etc.). Vertex transformation,
projection, backface culling, depth sorting, clipping, and polygon filling are
all computed on the CPU and drawn pixel-by-pixel onto a 2D plane (Roblox's
EditableImage), then displayed through an ImageLabel.

This is an early-stage learning project. The goal isn't to compete with
existing engines — it's to understand how the rendering pipeline actually
works by building each piece by hand: transformations, projection math,
visibility, depth ordering, clipping, and rasterization.

## Current features

- Perspective projection with configurable FOV and aspect ratio correction
- Matrix-based rotation (3x3, X/Y axis composition via matrix multiplication),
  replacing the original manual per-axis trig functions
- Backface culling via 2D cross product / winding order
- Painter's algorithm for depth sorting (view-space Z averaging per face)
- Scanline polygon fill (custom rasterizer, no built-in triangle/polygon draw
  calls — filled manually via edge intersection per scanline), generalized to
  support any number of vertices per face (not hardcoded to quads)
- Near-plane clipping (Sutherland-Hodgman style, edge-based, produces a
  variable-length vertex list per clipped face)
- Basic Lambertian lighting (face normal via cross product, dot product
  against a fixed light direction, with an ambient floor)
- 2D line clipping for debug overlays (Cohen-Sutherland), used for surface
  normal visualization

## Known issues / actively debugging

These are open problems, not yet fixed. Listed here so the state of the
project is honest about what still breaks.

- **Grazing-angle faces sometimes fail to render.** Faces that are nearly
  edge-on to the camera (steep angle, close to parallel with the view
  direction) are inconsistently culled or skipped. Reproduced in at least two
  places: the inner wall of a torus (donut) mesh, and some legs of a table
  mesh — in both cases the missing geometry is at a shallow/grazing angle
  relative to the camera, not random. Suspected cause: the backface cull
  (`isBack`, a 2D cross product / winding-order check) becomes unreliable
  right at the boundary, where the cross product result is close to zero and
  floating-point noise can flip which side of the `<= 0` threshold it lands
  on. Not yet confirmed — needs targeted logging of the cross-product value
  for the specific faces that disappear, across a few camera angles, to see
  if the value is hovering near zero right where the geometry drops out.
- **Screen-space clipping is not implemented yet.** Right now only near-plane
  (Z-axis) clipping exists. When projected screen coordinates fall outside
  the EditableImage bounds (e.g. a very oblique face near the edge of the
  view), `DrawRectangle` can be asked for a width/height that exceeds the
  API's limits and the draw call silently fails for that scanline, leaving a
  gap. This is a known, expected gap in coverage — the plan is to add
  screen-space polygon clipping (Sutherland-Hodgman:
  https://en.wikipedia.org/wiki/Sutherland–Hodgman_algorithm) against the
  viewport rectangle, the same way near-plane clipping already clips against
  the Z plane. Not a priority until the grazing-angle issue above is
  understood, since some of what looks like a clipping gap may actually be a
  culling gap.

## Roadmap / planned

- Z-buffer depth testing (replacing painter's algorithm — needed for
  non-convex geometry and multiple objects; painter's algorithm's sorting
  approach doesn't generalize to overlapping/intersecting geometry)
- Screen-space (viewport) clipping via Sutherland-Hodgman, to close the gap
  described above
- Move from Euler angles toward quaternions (avoiding gimbal lock, which
  Euler-based free camera rotation is prone to)
- Expand from loading a single test mesh into a broader scene/object system
  (multiple objects, each with its own transform)
- Eventually: input handling, basic physics, and other systems needed to
  call this a "game engine" rather than just a renderer
- Move from `DrawRectangle` to `WritePixelsBuffer` for scanline fills, using
  pre-allocated buffers instead of allocating a new buffer per scanline —
  attempted once already (implementation still present but commented out),
  parked in favor of finishing correctness first, revisit once the renderer
  is stable

## Troubleshooting notes (for future me)

Patterns that have shown up more than once while debugging this project,
worth checking first before assuming something new is broken:

- **If a face disappears intermittently or only at certain angles**, check
  whether it's a grazing-angle / near-parallel-to-camera case before assuming
  the fill or clipping logic is wrong. This has been the actual cause more
  than once (see Known issues above).
- **If `isBack` gives inconsistent results for the same geometry across
  frames**, check what vertices it's being called with. It must be called
  with original, unclipped, consistently-wound vertices — calling it with
  post-clip vertices (where near-plane clipping has inserted new intersection
  points) can distort the winding order and produce frame-to-frame
  inconsistent results, even though the face itself hasn't moved. The fix
  that worked: run backface culling first, against the original vertices,
  before ever clipping. Only clip faces that already passed the cull.
- **If `DrawRectangle` throws a bounds/size error**, check for degenerate
  scanline math before assuming it's a one-off: a horizontal edge (`A.Y ==
  B.Y`) causes division by zero in the intersection formula, and near-zero
  denominators can produce huge but finite widths that still exceed the
  API's limits. Guard both: skip near-horizontal edges explicitly, and clamp
  or reject scanline widths that exceed the canvas bounds rather than passing
  them straight to `DrawRectangle`.
- **When adding any new per-face computation (depth, color, etc.)**, remember
  that clipping can change the vertex count per face. Anything that assumes
  a fixed count (e.g. dividing a sum by a hardcoded 4) will silently misfire
  or crash once a face gets clipped down to 3 vertices. Sum and divide by the
  actual count, always.

## Why

This project exists to learn 3D graphics programming from first principles —
projection math, visibility, clipping, rasterization — by implementing it
manually in an environment (Roblox Luau) that doesn't give you any of it for
free.

## Status

Early prototype. Core pipeline (transform → cull → clip → project → fill →
sort → draw) is working end to end on both primitive shapes, with basic lighting. Known correctness gaps remain around
grazing-angle geometry and screen-space bounds (see Known issues). Expect
frequent breaking changes as the architecture evolves — the plan is Z-buffer
next, which will remove the painter's-algorithm sorting step entirely.
