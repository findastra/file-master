# File Master companion revision

Prepared with the built-in image generation tool by OpenAI Codex (GPT-6), 2026-10-11. Desktop artwork draft for Astra. Preserves existing runtime size; no website changes.

## Exact generation prompt

Use case: precise-object-edit.
Asset type: production transparent pixel-art desktop-pet 3-by-3 nine-mood sprite sheet.
Image 1 is the existing File Master sheet, the edit target. Image 2 is its idle frame for shape and face reference.
Primary request: make File Master look more like a master, more commanding and intimidating, while remaining a recognizable cute golden manila folder desktop mascot.
Preserve the squat golden/manila folder body, left folder tab, white stacked papers above the top edge, little golden arms and feet, frontal view and overall proportions from the references. Preserve the reference's small vertical black rectangular eyes with tiny square white highlights (no large round or anime eyes). Add strong stern angled eyebrows and a confident straight mouth in the default idle pose. Add a compact angular dark-gold three-point crown resting on the folder's upper edge, centered so the left folder tab and white papers remain visible. The crown is integral to the same sprite, the same in all nine poses. No cape, weapons, extra objects or new limbs.
Pixel-art medium: chunky crisp pixel geometry, consistent black outline, simple warm gold colors, limited flat pixel shading. Tiny readable authoritative face; less blush. Overall cute but formidable ruler, suitable for a sprite displayed about 42 pixels high.
Layout: EXACTLY nine same-size bodies, arranged evenly in an exact 3x3 grid with substantial empty gutters and margins. Uniform scale and registration in every cell, full body and crown visible, no overlap. Read left to right top to bottom: idle stern; blink; happy confident slight smile; curious; worried; sad; sick; alarmed; asleep. Facial changes only, same folder/crown/arms/feet throughout. Only facial expressions, no mood stickers or symbols.
Critical background: actual transparent alpha everywhere outside each character. Remove the reference's dark rectangular backdrops, warm glows and ambient haze completely. No shadow, no floor, no rectangle or vignette behind any pose. All gaps between poses and margins fully transparent.
No text of any kind, no labels, no punctuation symbols, no watermark, no checkerboard drawing.

## Exact background cleanup prompt

Use case: background-extraction and production sprite layout correction.
Edit target is the provided File Master nine-mood sheet. Preserve the pixel-art folder character, face expressions, gold three-point crown, white papers, golden limbs, all pixel details and black outlines. No redesign.
Remove ALL dark and gold background glow and haze. The ONLY visible pixels should be the nine folder characters including their black outlines and crowns. Every pixel outside each character's actual outline must be truly alpha=0, with NO gray/gold glowing rectangle, no shadow and no ambient halo.
Correct the production layout: make a SQUARE canvas with EXACTLY 3 rows and EXACTLY 3 columns of EQUAL-SIZE cells. Move the nine sprites to the EXACT CENTER of their corresponding cells. Scale every whole sprite uniformly to at most 68% of its cell width and height, with generous fully transparent padding around ALL sides. No character may touch or cross any cell boundary. Identical body/crown scale and aligned pose registration all nine. Preserve existing mood order.
This is a strictly mechanical background cleanup and recentering. Do not change character design. Fully transparent RGBA background, not a colored/checkerboard depiction. No labels/text/mood symbols.
