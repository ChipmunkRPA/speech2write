# Speech2Write design specification

Speech2Write is a private, on-device macOS dictation app invented by Ray Sang. The brand should feel focused, trustworthy, fast, and native to macOS.

## Product name and copy

- Product name: `Speech2Write` (capital S and W, numeral 2, no spaces).
- Use the full product name in every user-facing reference.
- Use sentence case for headings and buttons.
- State privacy plainly: speech recognition runs on the Mac by default and vendor telemetry has been removed.
- The onboarding attribution is: “Invented by Ray Sang.”

## App icon

The source master is `speech2write-appicon-master.png` at 1024×1024. It is generated artwork and is the source for all ten PNGs in `AppIcon.appiconset`.

The mark combines three flowing speech waves, a restrained fountain-pen-nib transition, and three straight writing lines. It contains no text, monogram, microphone, animal, watermark, or surrounding mockup. The full square is an edge-to-edge deep ink-navy gradient. The mark moves from cyan to violet with a cool-white highlight.

The symbol must remain readable at 16 px. Do not add an outer frame, white padding, or a second background.

## Menu bar icon

The menu bar mark uses the same “waves become lines” concept in a simplified monochrome form. It is a template image so macOS controls its tint in light, dark, selected, and recording states.

- Canvas: 22×22 points.
- Stroke: black, 1.8 points, round caps and joins.
- Keep all three strokes inside the 2-point safe area.
- Export at 22, 44, and 66 pixels.

## Color

- Ink navy: `#050A2A`
- Luminous cyan: `#16DFF2`
- Transition blue: `#3187FF`
- Vivid violet: `#C230FF`
- Cool white highlight: `#F4F7FF`
- Recording red remains a semantic state color and is not part of the brand gradient.

## Packaging and compatibility

- App bundle and executable: `Speech2Write.app` / `Speech2Write`
- Release archive: `Speech2Write-<version>.zip`
- Export prefixes: `Speech2Write_Backup_`, `Speech2Write_Dictionary_`, `Speech2Write_Audio_`, and `Speech2Write_Pair_`
- The existing bundle identifier remains unchanged to preserve macOS privacy approvals and user settings during the rename.
- The installer removes the previous app-name path only after the replacement bundle has passed checksum and signature verification.

## Generated-image prompt

> Use case: logo-brand. Asset type: production-ready 1024×1024 macOS application icon master for “Speech2Write,” an on-device voice dictation app that turns spoken words into written text. Primary mark: a single bold, instantly readable symbol where three flowing speech-wave strokes transition smoothly into three crisp horizontal writing lines, with a subtle fountain-pen-nib point integrated at the transition. The concept should communicate “speech becomes writing” without needing any words. Style: premium contemporary macOS icon; polished vector-like geometry with restrained depth, soft material lighting, and an exceptionally clean silhouette. Friendly, focused, trustworthy, and productive—not playful or mascot-like. Composition: centered and optically balanced, large enough to read at 16 px, generous safe margins around the mark. Fill the entire square canvas edge-to-edge with a deep ink-navy gradient background. Do not depict an app icon sitting on another background, device, card, or mockup. Do not add transparent or white outer padding. Do not bake a separate outer rounded-square frame; the artwork itself must reach all four canvas edges. Palette: deep navy/near-black background, with the central mark transitioning from luminous cyan on the speech-wave side to vivid violet on the writing side; a small cool-white highlight for clarity. Strong contrast, restrained glow, no visual clutter. Text: none—no words, letters, monograms, numbers, or typography. Hard constraints: no animal, no microphone cliché, no human face, no watermark, no signature, no duplicate icons, no UI screenshot, no tiny decorative details. One square icon only.
