# Pixel Hamster runtime asset

- Canonical character id: `pixel_hamster`
- Legacy display alias: `minty_pup`
- Sheet: `pixel_hamster.png`, 240×24 RGBA PNG
- Cell size: 24×24 px; render size: 48×48 pt
- Frame order: `idle` 2, `walk` 4, standing `doze` 2, curled `offline` 2
- Lowest non-transparent foot baseline: pixel row 3 in every frame
- Filtering: nearest-neighbor only
- Palette: cream, warm golden brown, cocoa, pink, periwinkle accent

The concept image is preserved at `docs/assets/pixel_hamster_concept.png`.
The deterministic runtime sheet is regenerated with:

```sh
swift scripts/macos/generate_pixel_characters.swift
```
