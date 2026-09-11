# Reconstruction and validation workflow

Project-specific dimensions, content, and layer counts belong in the task inventory and scripts.

## Element inventory

Create `work/element-inventory.md` before generating assets or building the PSB. Use one row per independently editable visual element:

| Field | Required content |
|---|---|
| ID | Stable stacking-order identifier |
| Element | Visible content and role |
| Bounds | Source-pixel `x, y, width, height` |
| Layer order | Position relative to neighboring elements |
| Alignment | Left, center, right, baseline, grid, or visual anchor |
| Spacing | Margins, gaps, leading, tracking, and padding that apply |
| Category | Photoshop, Source asset, ImageGen, or Protected element |
| Target layer | Intended Photoshop layer type and semantic name |
| Fidelity | Exact content, exact geometry, or visual-match requirement |
| Acceptance | Observable check for this element |

Also record the authoritative reference, canvas dimensions, resolution, bit depth, color mode, profile, and intended use. Inspect supplied SVG, AI, EPS, PDF, PSD, fonts, marks, and images before assigning categories.

## Category decisions

### Photoshop

Use Photoshop-native layers for content with measurable geometry or typography:

- native text for exact copy;
- shape layers for regular geometry and color fields;
- masks for separable raster subjects;
- adjustment layers for global tonal changes;
- native effects when their appearance can be matched reliably.

Verify text content visually. Measure font size, baseline, line height, tracking, alignment, wrapping width, and distance to neighboring elements. Record font substitutions.

### Source asset

Prefer supplied editable or authoritative content. Preserve its coordinate system, proportions, transparency, and color behavior. Place reusable vectors as Smart Objects or native shapes.

### ImageGen

Use `$imagegen` for complex raster visuals that cannot be reproduced faithfully with deterministic Photoshop drawing. Treat the reference as an edit target when its visual structure must be preserved.

Build a concise edit specification:

```text
Use case: precise-object-edit
Asset type: layered PSB component
Primary request: create the routed raster element for reconstruction
Input images: Image 1 is the edit target and composition reference
Scene/backdrop: describe only the required visual field
Composition/framing: preserve viewpoint, crop, perspective, anchors, and negative space
Lighting/mood: preserve light direction, contrast, atmosphere, and palette
Constraints: change only the routed element; preserve the listed invariants
Avoid: text, QR codes, barcodes, logos, seals, signatures, watermarks, and extra objects
```

Repeat the invariants on every iteration. Inspect composition, subject placement, perspective, lighting, palette, texture, and negative space. Move or copy the accepted project asset into the task workspace before referencing it from Photoshop scripts.

### Protected element

Use reliable source material for content whose machine readability, identity, branding, legal meaning, or factual accuracy must remain intact. Preserve it by extraction, masking, or direct placement. Confirm QR codes and barcodes remain decodable when tools are available. If the source is insufficient, identify the required source.

## Coordinate and layout fidelity

Use the reference's native pixel canvas as the coordinate system and build at that size from the start.

1. Measure element bounds and shared alignment axes.
2. Record outer margins, internal padding, inter-group gaps, text baselines, leading, tracking, and wrapping widths.
3. Prepare full-canvas intermediates or record explicit placement coordinates for cropped assets.
4. Align generated backgrounds by aspect ratio, horizon or vanishing point, dominant subjects, light sources, and reserved negative space.
5. Apply one deterministic scale-and-crop operation before placement; keep later positioning numeric.
6. Compare the Photoshop composite and reference at identical dimensions using aligned opacity overlays, rapid visibility toggling, or Difference blending.
7. Correct every visible mismatch in deterministic elements. For generated elements, require the same visual hierarchy and spatial relationships throughout the canvas.

Preserve the reference composition and spacing unless the user requests a redesign.

## Photoshop build

Generate a task-specific script in the workspace with explicit paths. It should:

- create or open the document with the inventoried properties;
- place layers in deterministic stacking order;
- create native text, shapes, masks, and adjustments specified by the inventory;
- place source and generated raster assets at measured coordinates;
- use semantic layer and group names;
- retain the untouched reference as hidden `00_原始参考图`;
- save a new `.psb` with layers and profile preserved;
- export the preview from a duplicate;
- stop and surface errors.

When desktop computer-use is available, select the installed Photoshop app, read the current accessibility state, and use **File > Scripts > Browse** to run the task script. Prefer labeled controls and accessibility identifiers over fixed screen coordinates.

## Validation

Use a separate Photoshop validation script for non-trivial jobs. Reopen the output and record:

- width, height, resolution, bit depth, color mode, and profile;
- groups, hierarchy, layer names, types, visibility, and opacity;
- native text, shapes, Smart Objects, masks, adjustments, and raster layers;
- hidden reference state;
- empty, unknown, duplicate, or missing layers.

Validate every inventory row against the real layer tree. Toggle major layers to confirm isolation and inspect text, edges, transparency, glow, shadows, and occluded-background continuity. Compare the final preview with the reference at identical dimensions.

Confirm PSB format by reopening it in Photoshop. A binary header check may supplement this: Photoshop files begin with `8BPS`, and PSB uses document version `2`.

## Final surfaces

Derive layer names, filenames, metadata, manifests, and reports from the accepted visual structure. Keep working assets in `work/` and user-facing deliverables in the output directory. State observed document properties, actual editability, and authenticity-relevant generation or substitution facts. Re-read every final surface after the last change and remove text that does not affect use, verification, or truthful handoff.
