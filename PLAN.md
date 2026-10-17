# FiberOps — Fiber Optic Technician Simulator (Godot 4)

## 1. Vision
First-person sim of an FTTH technician working in a building. Each building level has its
own simulated fiber network. The player installs floorboxes/BMOs (drill + screw minigame),
routes cables Satisfactory-style with a raycast, splices fibers (splicing minigame), and
checks the result with an OTDR. Losses are physically motivated: node losses (splices,
connectors, splitters) plus continuous losses (attenuation per km + macrobend loss driven
by the real curvature of the placed cable).

Core loop: **work order → install hardware → route cable → splice → test (OTDR / power
meter) → fix faults → sign off.**

---

## 2. Tech decisions (defaults, open to change)
| Topic | Default | Why |
|---|---|---|
| Engine | Godot 4.7.2 (mono build, used with GDScript) | Curve3D, typed GDScript + typed dictionaries, Resources for save data |
| Language | Typed GDScript (confirmed) | Fast iteration; hot paths (OTDR sample gen) are small |
| Tests | Built-in runner (`tests/run_tests.gd`, `run_tests.cmd`), headless | Loss model and graph tracing must be unit tested; no addon download needed |
| Art | Greybox (CSG / primitives) first | Gameplay before assets |
| Save data | Custom `Resource` classes → `.tres` | Native, inspectable, versionable |

---

## 3. Architecture

### 3.1 Folder layout
```
res://
  autoload/        Events.gd (signal bus), GameState.gd, NetworkRegistry.gd
  core/network/    FiberNetwork, NetNode, Port, Cable, Strand, Link, LossModel, Tracer
  core/otdr/       OtdrSimulator (pure data), OtdrTrace, OtdrEvent
  player/          Player (CharacterBody3D), InteractionRay, ToolBelt
  tools/           BuildTool, CableTool, DeconstructTool, OtdrTool, PowerMeterTool, VflTool
  build/           GhostPreview, Snapping, placeable definitions (PlaceableDef.tres)
  minigames/splice/  SpliceMinigame scene + steps
  minigames/mount/   DrillScrewMinigame scene
  ui/              HUD, OTDR screen, splice-tray editor, work order panel
  levels/          building_01/floor_0.tscn, floor_1.tscn ... + network .tres per floor
  tests/           GUT unit tests
```

### 3.2 Network data model (pure data, no scene dependency → testable headless)
- **FiberNetwork** (Resource, one per level): `nodes: Dictionary[id → NetNode]`, `cables: Dictionary[id → Cable]`.
- **NetNode**: id, type, transform, `ports: Array[Port]`, `links: Array[Link]`.
  - Types: `BEP/ODF` (building entry, signal source side), `RISER_STUB` (connects to the
    level above/below), `FLOORBOX/BMO`, `SPLICE_CLOSURE`, `SPLITTER (1:N)`, `OUTLET/ONT`.
  - `mounted_quality` (from the drill/screw minigame; a badly mounted box can be "loose").
- **Port**: where a cable end attaches (node id + port index + capacity).
- **Cable**: id, fiber_count (2/4/12/24, TIA-598 colour order), fiber_type
  (G.652D / G.657A1 / G.657A2), `waypoints: PackedVector3Array`, `corner_radius`,
  end_a / end_b (node, port), cached `BendProfile` and length.
- **Link** (inside a node): `(port_in, fiber_in) → (port_out, fiber_out)`, kind
  (fusion splice / mechanical splice / connector / splitter leg), `loss_db`,
  `reflectance_db`. Splice links get their loss from the splicing minigame.
- **Strand path**: tracing works per *fiber strand*, not per cable: start at
  (node, port, fiber) → walk the cable → look up the link in the next node → continue.
  Splitters branch the path into a tree.

### 3.3 Loss model (`LossModel.gd`, static functions, unit tested)
- **Attenuation**: 0.35 dB/km @1310 nm, 0.22 dB/km @1550 nm (× length).
- **Node losses**: fusion splice 0.02–0.15 dB (minigame quality), mechanical 0.1–0.5,
  connector 0.2–0.5 dB + reflectance (−45…−55 dB UPC, −60 APC), splitter
  `10·log10(N) + excess` (1:8 ≈ 10.5 dB).
- **Macrobend loss** (continuous): `α(R, λ, type) = A·exp(−B·R)` dB/m, integrated along
  the cable over every section with radius R. Parameters fitted to the ITU specs:
  - G.652D: 10 turns @ R=30 mm ≤ 0.1 dB @1625 nm
  - G.657A1: 1 turn @ R=10 mm ≤ 0.75 dB @1550 nm
  - G.657A2: 1 turn @ R=7.5 mm ≤ 0.5 dB @1550 nm
  - Bend loss is much higher at 1550 than 1310. That's how the OTDR tells a bend apart
    from a bad splice, and it makes good gameplay.
- **Curvature**: cable geometry = straight runs between waypoints + **fillet arcs** at
  each corner (radius = the player's chosen corner radius, clamped by segment length). So
  curvature is known exactly (1/R on arcs, 0 on straights), with no noisy numeric
  differentiation. Placing waypoints too close or pulling corners tight shrinks R and
  loss goes up. Service loops coiled in boxes use the same arc math.

### 3.4 OTDR simulation (`OtdrSimulator.gd`, pure data)
Input: start (node, port, fiber), wavelength, pulse width, range, averaging time.
1. Trace the strand path → ordered list of events with distance, loss, reflectance.
2. Generate samples: backscatter level falls with slope = attenuation; steps at
   non-reflective events (splice, bend); spike + step at reflective ones (connector);
   Fresnel spike at the fiber end, then the noise floor.
3. Realism knobs: event/attenuation dead zone ∝ pulse width, noise ∝ 1/√averaging,
   launch-cable dead zone, splitter = large step, "gainer" ghost events optional.
4. UI: custom `Control._draw()` plot, zoom/pan, A/B cursors (distance + dB delta),
   auto event table, 1310/1550 toggle, pass/fail against the work order loss budget.

### 3.5 Placement system (Satisfactory-style)
- `InteractionRay` from the camera (RayCast3D or `PhysicsDirectSpaceState3D`), range ~5 m.
- **BuildTool**: ghost mesh follows the hit point; aligns to the surface normal (floorboxes
  are wall-only); grid snap (5 cm) toggle; rotate with scroll/R; green/red validity via
  overlap check (ShapeCast3D); click places an **unmounted** box → mount minigame.
- **CableTool**: click a port to start → each click adds a waypoint on the surface (with
  a small offset off the wall so the cable sits flush) → live preview of the filleted
  path, colour-coded by bend radius (green OK / yellow near limit / red over limit) and
  showing the running length and estimated loss → click a port to finish. Scroll changes
  the corner radius. Esc cancels, Backspace removes the last waypoint.
- **Cable mesh**: generated tube `ArrayMesh` swept along the baked path (cheaper and
  more controllable than CSGPolygon3D); simple collision for deconstruct raycasts.
- **DeconstructTool**: aim + hold to remove a cable/box, and the network updates.

### 3.6 Minigames (separate scenes, opened via a camera transition / overlay)
**Splicing** (in a box or closure, per fiber pair from the tray editor):
1. Pick the right fibers by colour (a mismatch means a wrong mapping, caught later by the OTDR/VFL).
2. Strip jacket & coating (drag gesture, too fast can break the fiber).
3. Clean with alcohol (skip it and a contamination penalty applies).
4. Cleave (timing/steadiness → cleave angle, ideally < 0.5°).
5. Load into the fusion splicer, X/Y core alignment view (auto or manual nudge).
6. Arc → splicer shows an *estimated* loss; the *true* loss (which the OTDR sees) is
   `f(cleave angle, core offset, cleanliness) + noise`.
7. Heat-shrink sleeve, place in tray. Forget the sleeve and the splice is fragile.

**Drill & screw** (mounting a floorbox/BMO):
1. Hold the box, mark holes (or use a template).
2. Drill: hold to drill, keep the crosshair steady (wobble grows with depth), depth gauge,
   wall material (drywall/brick/concrete) sets speed, overheating meter, optional hammer mode.
3. Insert wall plugs.
4. Screw: rotate gesture/hold with a torque meter. Under-tightened = loose box,
   over-tightened = stripped screw.
5. The result sets `mounted_quality`; the box becomes usable once mounted.

### 3.7 Levels & persistence
- Each floor is its own scene with its own `FiberNetwork.tres`; `NetworkRegistry`
  autoload loads/saves per level.
- Cross-level continuity via `RISER_STUB` nodes with matching ids on adjacent floors; the
  tracer can hop through them, so an OTDR shot from the BEP in the basement can see a fault on floor 3.
- Save = network resources + placed-object transforms + work order progress.

### 3.8 Other tools (later)
- **Power meter + light source**: total end-to-end loss vs budget.
- **VFL (red laser)**: makes tight bends and breaks glow red in the world. A cheap visual fault finder.
- **Splice-tray editor UI**: map incoming → outgoing fibers by colour.

---

## 4. Milestones
| # | Milestone | Done when |
|---|---|---|
| M0 ✅ | Project setup | Godot project, folders, input map, autoloads, test runner, greybox test floor |
| M1 ✅ | Player & interaction | FPS controller, interaction ray, hotbar tool switching, HUD crosshair |
| M2 ✅ | Network core + loss model | Data classes, strand tracer, LossModel with unit tests passing headless |
| M3 ✅ | Build mode | Ghost preview, wall snapping, validity, place/deconstruct floorboxes, network updates |
| M4 ✅ | Cable routing | Waypoint routing, fillet geometry, tube mesh, live bend/loss preview, port connections |
| M5 ✅ | Splice tray editor | Fiber colour mapping UI creating Links |
| M6 | Splicing minigame | All steps, quality → splice loss written to Link |
| M7 ✅ | OTDR | Simulator + trace UI + event table + 1310/1550, unit tests on events |
| M8 | Drill & screw minigame | Mounting flow, mounted_quality |
| M9 | Multi-level + save/load | Per-floor networks, riser stubs, cross-level tracing, persistence |
| M10 | Work orders & polish | Job briefs, loss budgets, scoring, power meter, VFL, audio |

**Vertical slice = M0–M4 + M7 (simplified) on one floor.** That's the earliest point
where you can route a cable around a corner and see the bend on an OTDR trace.

---

## 5. Risks / notes
- Bend-loss realism vs fun: keep fitted parameters in one `.tres` so they can be tuned.
- Tube mesh regeneration while previewing: rebuild only the last segment, throttle per frame.
- Splitters in OTDR: show the splitter step and follow one selected branch (real OTDRs
  can't separate branches either).
- Godot executable: `C:\Users\Karianakis\Programming\Godot_4_7\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe` (headless tests).
- Workflow: milestone by milestone, stopping for review after each one.
