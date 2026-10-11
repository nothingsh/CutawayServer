# CutawayServer README header

A transparent header for the CutawayServer README, based on the layer mark and blue/cyan palette
of the Cutaway macOS app icon. The detail in the top layer is a pair of capture brackets; the
caption reads "Capture iOS layers, images and attributes."

The header has light and dark variants. Both have transparent backgrounds; only the foreground
colors change. SVGs are 1280 × 360, with lettering outlined so no font installation is needed.

Use `<picture>` to select the foreground palette; the light variant is the fallback. The fragment
goes before the README introduction:

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/readme/cutaway-server-dark.svg">
    <img src="Resources/readme/cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850">
  </picture>
</p>
```

The translations in this directory reference the same files by name, without the
`Resources/readme/` prefix.
