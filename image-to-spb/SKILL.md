---
name: image-to-spb
description: Reconstruct a supplied image, artwork, or PDF page as a semantically layered, editable Photoshop PSB and verify the saved layer structure in Photoshop. Use when the requested deliverable is a layered .psb; do not use for ordinary retouching, simple format conversion, or flattened image export.
---

# Image to Layered PSB

Create a real Photoshop Large Document Format (`.psb`) whose layers have independent editing value. Treat the skill name `image-to-spb` as the user-selected invocation name; the output format is `.psb`.

## Non-negotiable boundaries

- A PSB container does not recover the original design layers. If only a flattened image exists, call the result a semantic reconstruction and state what remains rasterized or inferred.
- Inspect every file the user explicitly supplied, including a supplied source folder, before choosing a reconstruction method. Prefer usable SVG, AI, EPS, vector PDF, PSD, font, logo, or other source assets over tracing pixels.
- Preserve the source. Write job scripts, intermediate assets, previews, and deliverables to a task workspace or user-approved output directory; never overwrite the only input.
- Use meaningful layers: editable text for text, vector or shape content when supported by evidence, masks for separable raster subjects, adjustment layers for global corrections, and raster layers only where reconstruction cannot honestly preserve structure.
- Do not upload source material, install a plugin, or use a cloud image service unless the user explicitly authorizes it.
- Do not report completion after merely saving. Reopen the PSB in Photoshop and inspect its actual layer structure.

## Workflow

1. Preflight the supplied material. Record the reference appearance, dimensions, resolution, color mode/profile, intended output use, and available editable sources. Render a reference preview when the input is a PDF or another format that is inconvenient to compare directly.
2. Choose one route:
   - **Source-backed reconstruction:** use available vector/editable source objects, preserving their canvas coordinates.
   - **Flattened-image reconstruction:** separate visible subjects, reconstruct occluded background, recreate text and regular graphics, and retain irreducible details as clearly named raster layers.
3. Write a layer manifest before building. Each planned layer must represent an object or effect a user may reasonably edit independently. Avoid arbitrary tile layers, duplicated composites, empty groups, and speculative structure.
4. Prepare full-canvas intermediate assets so every layer shares the same origin and aligns on placement. Keep a hidden `00_原始参考图` layer for flattened-source jobs; for source-backed jobs, keep a reference only when it materially helps verification.
5. Create a job-specific Photoshop script rather than hard-coding project content into this skill. It should create the document with the confirmed dimensions, resolution, bit depth, and color mode; place assets as Smart Objects or appropriate native layers; create native text and groups; assign stable semantic names; and remove Photoshop's automatic empty base layer.
6. Run the script inside the installed Photoshop. When desktop computer-use and `@Adobe Photoshop 2026` are available, use them to select the app, inspect the accessibility state, open **File > Scripts > Browse**, choose the job script, and handle dialogs. The computer-use channel starts and observes the work; the Photoshop script performs the document operations.
7. Save through Photoshop's native Large Document Format path as `.psb`, with layers retained, the color profile embedded, and compatibility enabled when supported. Export a lightweight PNG or JPEG composite preview from a duplicate, never by flattening the deliverable.
8. Reopen the saved PSB in Photoshop and run the acceptance checks below. Repair and regenerate when any required check fails.

Read [references/reconstruction-and-validation.md](references/reconstruction-and-validation.md) before implementing either reconstruction route or writing the Photoshop validation script.

## Required deliverables

- The layered `.psb`.
- A composite preview.
- A concise layer manifest naming each layer/group and its editability type.
- A validation result covering reopen success, document properties, layer structure, and visual fidelity.
- A limitations note when any element was inferred, font-substituted, background-filled, or left rasterized.

## Acceptance gate

Do not claim success unless all of these are observed:

- Photoshop reopens the `.psb` without conversion or repair errors.
- The document is not flattened and contains no unexplained empty or duplicate layers.
- Dimensions, resolution, bit depth, color mode, and profile match the confirmed target.
- Required text is native and editable when it could be reliably reconstructed; substitutions are disclosed.
- Smart Objects, masks, shape layers, adjustment layers, and raster layers are described accurately rather than all being called editable vectors.
- Hiding or editing a semantic layer affects only its intended visual component as far as the source permits.
- The composite preview matches the supplied reference closely enough for its intended use.
