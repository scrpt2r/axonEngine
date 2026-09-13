# axonEngine

A from-scratch graphics and game engine built in Roblox Luau — currently focused
on a CPU-side 3D software rasterizer that renders onto a 2D EditableImage canvas,
with the long-term goal of growing into a full game engine with comprehensive graphics engine.

## What this is

axonEngine implements the 3D rendering pipeline manually, without relying on
Roblox's native 3D rendering (Parts, MeshParts, etc.). Vertex transformation,
projection, backface culling, depth sorting, and polygon filling are all
computed on the CPU and drawn pixel-by-pixel onto a 2D plane
(Roblox's EditableImage), then displayed through an ImageLabel.

This is an early-stage learning project. The goal isn't to compete with
existing engines — it's to understand how the rendering pipeline actually
works by building each piece by hand: transformations, projection math,
visibility, depth ordering, and rasterization.

## Current features

- Perspective projection with configurable FOV and aspect ratio correction
- 3D rotation (Euler-based, X/Y plane rotation) driven by mouse input
- Backface culling via 2D cross product / winding order
- Painter's algorithm for depth sorting (view-space Z averaging per face)
- Scanline polygon fill (custom rasterizer, no built-in triangle/polygon draw
  calls — filled manually via edge intersection per scanline)

## Roadmap / planned

- Matrix-based transforms (replacing manual per-axis rotation functions)
- Near-plane clipping
- Z-buffer depth testing (for non-convex geometry and multiple objects)
- Move from Euler angles toward quaternions (avoiding gimbal lock)
- Expand from a single test cube into a broader scene/object system
- Eventually: input handling, basic physics, and other systems needed to
  call this a "game engine" rather than just a renderer

## Why

This project exists to learn 3D graphics programming from first principles —
projection math, visibility, rasterization — by implementing it manually in
an environment (Roblox Luau) that doesn't give you any of it for free.

## Status

Early prototype. Expect frequent breaking changes as the core math and
architecture are still being figured out.