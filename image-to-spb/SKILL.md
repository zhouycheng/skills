---
name: image-to-spb
description: Reconstructs a supplied image, artwork, or PDF page as a high-fidelity, semantically layered Photoshop PSB. Use when the deliverable must preserve editable content, measured layout, and verified layer structure.
---

# Image to Layered PSB

Create a Photoshop Large Document Format (`.psb`) with useful, independently editable layers and a composite that closely matches the reference.

## Required workflow

1. Inspect every supplied file and identify the richest reliable source for each visible element.
2. Before editing, complete the element inventory defined in [references/reconstruction-and-validation.md](references/reconstruction-and-validation.md). Record each element's bounds, stacking order, alignment anchors, spacing, processing category, target layer type and name, fidelity requirement, and acceptance check.
3. Assign every element to exactly one category:
   - **Photoshop:** native text, regular shapes, color fields, lines, masks, gradients, and deterministic effects.
   - **Source asset:** supplied vectors, photos, marks, machine-readable codes, and other reliable originals.
   - **ImageGen:** complex photography, illustration, texture, environmental lighting, and backgrounds that Photoshop cannot reconstruct faithfully with deterministic drawing.
   - **Protected element:** QR codes, barcodes, logos, seals, signatures, exact data graphics, identity-sensitive people, and other content whose correctness or identity must be preserved. Use a reliable source asset; if none exists, report the unresolved element.
4. Use full-canvas assets and the reference image's pixel coordinate system. Preserve measured positions, scale, baselines, margins, gaps, alignment axes, perspective, and stacking order.
5. When the inventory contains an ImageGen element, load and follow `$imagegen`:
   - Use the built-in edit mode by default. Inspect a local edit target with `view_image` first.
   - Lock viewpoint, composition, perspective, subject placement, lighting, palette, crop, and negative space.
   - Request only the routed visual content. Keep text, machine-readable codes, brand marks, watermarks, and extra objects out of the generated asset.
   - Inspect every result and iterate with one targeted change at a time.
   - Copy the accepted project asset from the generated-images location into the task workspace.
   - If the built-in tool is unavailable, explain that CLI fallback requires explicit user confirmation; do not switch automatically.
6. Build the document in Photoshop with a task-specific script. Create native text and shape layers, place source and generated assets at measured coordinates, use stable semantic layer names, retain a hidden `00_原始参考图`, and remove unexplained empty layers.
7. Compare the composite against the reference using aligned overlays, rapid visibility toggling, or Difference blending. Correct visible drift in dimensions, placement, spacing, wrapping, perspective, color, and effects.
8. Save through Photoshop as a layered `.psb`, embed the intended color profile, and export a preview from a duplicate document.
9. Reopen the PSB in Photoshop and validate document properties, the complete layer tree, element isolation, reference visibility, and composite fidelity against the inventory.
10. Before delivery, load and follow `$no-negative-echo`. Final names, metadata, previews, manifests, and reports describe the accepted visual structure and observed facts. Keep method provenance only where it is needed to understand authenticity or editability.

## Required deliverables

- The layered `.psb`.
- A composite preview.
- Semantic layer manifest.
- Validation report tied to the element inventory.
- Concise disclosure of generated, substituted, inferred, or raster-only content when relevant to authenticity or editing.

## Acceptance gate

Completion requires all of the following:

- Photoshop reopens the `.psb` without conversion or repair errors.
- Dimensions, resolution, bit depth, color mode, and profile match the target.
- Every inventoried element has the intended content, layer type, position, visibility, and editability.
- Deterministic elements match the reference in content, alignment, and spacing.
- Generated elements preserve the required composition, proportions, perspective, lighting, palette, and negative space.
- Protected elements come from reliable source assets and remain valid.
- The document contains no unexplained empty, duplicate, or flattened replacement layers.
