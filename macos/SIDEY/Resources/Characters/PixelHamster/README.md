# Pixel Hamster runtime asset

- Canonical character id: `pixel_hamster`
- Legacy display alias: `minty_pup`
- Sheet: `pixel_hamster.png`, 192×24 RGBA PNG
- Cell size: 24×24 px; render size: 48×48 pt
- Frame order: `idle` 2, `walk` 4, `sleep` 2
- Filtering: nearest-neighbor only
- Palette: cream, warm golden brown, cocoa, pink, periwinkle accent

The concept image is preserved at `docs/assets/pixel_hamster_concept.png`.
The deterministic runtime sheet is regenerated with:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/sidey-swift-module-cache \
  ./scripts/macos/generate_pixel_hamster.swift \
  macos/SIDEY/Resources/Characters/PixelHamster/pixel_hamster.png
```

Do not add another animal or animation state before a separate product decision.
