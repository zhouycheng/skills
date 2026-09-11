# Reconstruction and validation workflow

Use only the sections required by the selected route. Project-specific dimensions, layer counts, text, and names belong in the job manifest and scripts, not in the skill.

## 1. Evidence and route selection

Create a short source inventory before editing:

- supplied file paths and formats;
- whether each source is flattened, layered, or vector;
- canvas or physical dimensions;
- resolution, bit depth, color mode, and embedded profile when readable;
- visible text, likely fonts, logos, repeated motifs, effects, and occlusions;
- output purpose and fidelity risks.

Prefer the richest supplied source. A vector PDF or SVG can contain directly reusable paths even when a rendered page looks like a single image. Do not assume that a PDF is either vector or flattened without inspecting it.

If sources disagree, use the user's designated reference for appearance and the richer source only for reusable structure. Report material discrepancies instead of silently choosing one.

## 2. Source-backed reconstruction

Use this route when supplied SVG, AI, EPS, vector PDF, PSD, or equivalent material exposes reusable objects.

1. Render the authoritative reference to a preview at a useful comparison resolution.
2. Inspect the editable source structure. Identify text separately from non-text graphics.
3. Group source objects by semantic editing responsibility, not merely by tag type. Typical groups include background, texture/grid, decorative waves, circuitry, separator lines, hero graphic, logo, and footer ornament.
4. Export each group on the original full-size canvas. Preserve the view box, coordinate system, definitions, gradients, clipping paths, and transparency required by that group.
5. Test one representative asset in Photoshop before batch placement. If Photoshop drops an unsupported SVG filter, mask, or blend construct, simplify only that construct and visually compare the result.
6. Place vector groups as independent Smart Objects or native shape layers. Name them in stacking order with a stable numeric prefix.
7. Recreate text as native Photoshop text layers using verified content, position, font, size, color, alignment, tracking, and line spacing. Put related text in a clearly named group.

Do not rasterize a usable vector source just to make placement easier.

## 3. Flattened-image reconstruction

Use this route when no richer supplied source exists. The goal is useful semantic editability, not fictional recovery of hidden data.

1. Place the untouched image as a hidden `00_原始参考图` Smart Object.
2. Describe the layer manifest from back to front. Separate only components that have independent editing value.
3. Reconstruct the background before extracting foreground objects when the foreground hides areas that must remain usable after movement. Use Photoshop masks, Content-Aware Fill, Generative Fill only if locally available and authorized, cloning, gradients, or manual repainting as appropriate. Disclose inferred regions.
4. Separate major subjects with non-destructive masks. Inspect hair, translucent materials, glow, motion blur, and soft shadows at useful zoom levels.
5. Recreate legible text as native text layers. Confirm OCR visually; never trust OCR for names, dates, legal text, or small display copy without comparison. If the original font is unavailable, use the closest installed substitute and report it.
6. Rebuild simple geometry, icons, lines, and solid-color ornaments as shape layers or vector Smart Objects when the visible evidence supports them.
7. Keep photographic detail, complex texture, and effects that cannot be reconstructed reliably as individually named raster Smart Objects or raster layers. Use masks instead of destructive erasure where practical.
8. Put global color and tonal corrections in adjustment layers rather than baking them into every content layer.

A stack of duplicate copies with different masks is acceptable when each copy represents a genuine editable component. A stack of arbitrary slices is not semantic layering.

## 4. Job-specific Photoshop script

Generate the script in the task workspace and keep all paths explicit. The script should:

- target the installed Photoshop version through its supported scripting interface;
- suppress only dialogs the script can handle safely;
- use the confirmed units and document properties;
- place prepared assets in deterministic stacking order;
- create native text, groups, masks, or adjustments required by the manifest;
- remove only the automatically created empty layer after another valid layer exists;
- save to a new `.psb` path using Photoshop's Large Document Format support;
- create the preview from a duplicate document;
- close generated documents only after save succeeds;
- surface failures instead of continuing to a false success message.

Use computer-use for Photoshop UI actions when available:

1. Select `@Adobe Photoshop 2026` or the installed Photoshop app.
2. Read the current accessibility state before acting.
3. Use labeled menu items and accessibility element identifiers in preference to fixed screen coordinates.
4. Open **File > Scripts > Browse** and select the job script.
5. Observe completion or error dialogs and verify output files separately.

Computer-use is an interaction channel, not proof that Photoshop completed the internal operation.

## 5. Validation script and report

Use a separate Photoshop validation script for non-trivial jobs. It should reopen the output and recursively record:

- document width and height;
- resolution and bit depth;
- color mode and profile when exposed;
- groups and nested hierarchy;
- native text layers;
- Smart Objects;
- shape, adjustment, mask, and raster layers;
- hidden reference layers;
- empty, unknown, or duplicate layers;
- layer names and visibility.

Validate against the job manifest rather than a universal fixed layer count. The validation fails when a required semantic layer is absent, a supposedly editable text item is rasterized without disclosure, an unexplained layer is present, or the file cannot be reopened.

Also perform visual checks:

- compare the output composite with the authoritative reference at the same aspect ratio;
- inspect text baselines, spacing, clipping, edges, transparency, glow, and shadows;
- toggle major layers to confirm isolation and background completion;
- confirm there are no missing objects caused by unsupported SVG/PDF features;
- inspect the preview at normal viewing size and critical edges at higher zoom.

For a PSB-specific container check, prefer Photoshop reopen as the authoritative test. When a binary header check is used, Photoshop documents begin with `8BPS`; PSB uses document version `2`. An extension alone is not proof that the file is actually a PSB.

## 6. Completion report

State only observed facts:

- output path and file size;
- verified document properties;
- layer/group counts by actual type;
- whether text, vectors, masks, and effects are independently editable;
- visual comparison result;
- known inferred or raster-only portions.

Do not equate a generated preview, a successful save call, or a passing filesystem check with a verified layered PSB.
