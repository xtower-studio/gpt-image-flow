# v0.14 — Native macOS workspace

2026-10-16. Native navigation, content, and control layers replace independently styled cards and toolbar skins.

## Design contract

- System-owned window corners, NavigationSplitView, inspector, toolbar/search and sheets. No painted sidebar or custom title bar. Related toolbar actions use native grouping.
- The inspector follows prompt → generation method → output settings. Native segmented navigation replaces a manually drawn tab control. Three generation choices remain directly visible; one description explains the selection. Output rows share one quiet group and a full-row menu target.
- Use SF Symbols in monochrome for actions. Accent color communicates selection or the primary generation action. Text uses the shared 14 pt body / 13 pt supporting hierarchy; icon targets are 32 pt.
- Content has a neutral, adaptive system color. Custom Liquid Glass belongs to image actions, preview controls, canvas navigation and status tools, not to text editors or node content.
- Images have one inset control surface containing their name, favorite and menu. A 20 pt content container and 8 pt inset provide a 12 pt inner corner baseline. `containerShape` propagates geometry; `ConcentricRectangle` makes glass corners follow their enclosing content. macOS owns window and sheet geometry.
- Nearby custom controls share `GlassEffectContainer`. Buttons use native glass or glass-prominent styles where appropriate. No custom blur stack, black gradient chrome, or perpetual decorative animation was added.
- Preview navigation and zoom are separate groups. Space/Escape and left/right navigation remain window-scoped. API connection uses a scrolling grouped Form and a fixed footer with billing disclosure and confirmation. Recipes use NavigationSplitView; task history uses native List rows.
- Scrollable content and bottom actions have separate layout space. Glass controls never overlap image-action glass at the bottom of the collection.

## Rendering and accessibility

NSCollectionView retains some offscreen hosting views. Glass render layers must be disposed in `didEndDisplaying` and rebuilt in `willDisplay`. This also stops offscreen generation placeholder animation. Explicit clip bounds prevent effects from escaping the collection. Actual mouse hit regions follow the inset bottom dock; image selection and native file dragging remain owned by NSCollectionView.

macOS 26+ uses native Liquid Glass and concentric shapes. Older supported systems fall back to standard materials and bordered buttons. Custom glass uses an opaque, outlined surface for Reduce Transparency and strengthens outlines for increased contrast. The QA appearance override is propagated into the individual AppKit-hosted image cells; no global accessibility preferences are changed.

## Reference

- [Apple: Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Verification

A separate QA app and copied, paused library were used. No generation or API charge was initiated. Visual evidence is kept locally under `.runtime/liquid-qa/`, not published with user artwork.

- Light and dark appearances; 1000×680 and 1380×900 windows.
- Gallery resize, scroll and offscreen glass disposal; native image selection and image action targets.
- Space preview, left/right navigation, Space close; grouped zoom and favorite/export controls.
- Node canvas, recipe sheet, API connection, inspector, and custom Reduce Transparency / increased-contrast surfaces.
- Core regression suite: 88 tests. Native runtime checks supplement the core tests; older macOS and Intel runtime rendering require their own devices.
