# Cache Out — Design System

> This document describes the visual language, component patterns, and interaction principles used throughout Cache Out. It exists so contributors can build new features that feel native to the app and consistent with Apple's design language on macOS 26 Tahoe.

---

## Platform & Target

- **Platform:** macOS 26 (Tahoe) and later — no backward compatibility
- **Design language:** Apple Liquid Glass — `NavigationSplitView` with automatic sidebar glass, `.listStyle(.sidebar)`
- **Distribution:** Notarized DMG, outside Mac App Store (hardened runtime, non-sandboxed)

---

## Color

Cache Out uses **zero hardcoded hex values**. Every color is a semantic Apple color or a SwiftUI tint derivative.

| Use | Value |
|---|---|
| Primary text | `Color(.labelColor)` |
| Secondary text | `Color(.secondaryLabelColor)` |
| Tertiary text | `Color(.tertiaryLabelColor)` |
| Quaternary / muted | `Color(.quaternaryLabelColor)` |
| Separator | `Color(.separatorColor)` |
| Control background | `Color(.controlBackgroundColor)` |
| Window background | `Color(.windowBackgroundColor)` |
| Accent (interactive) | `.accentColor` — defaults to system blue, respects user override |
| Destructive | `.red` (SwiftUI semantic) |
| Success / safe | `.green` (SwiftUI semantic) |
| Warning | `.orange` (SwiftUI semantic) |

**Dark mode:** handled automatically by semantic colors. No `@Environment(\.colorScheme)` checks in views.

**Category colors** (Clean, Dev Purge, Duplicates filter pills) use named SwiftUI/NSColor system colors with opacity overlays for backgrounds:

```swift
// Background pill — never hardcoded
color.opacity(0.10)   // fill
color.opacity(0.35)   // stroke
```

---

## Typography

All text uses **SF Pro** (the system font). No custom fonts.

| Role | Swift |
|---|---|
| Section heading | `.font(.system(size: 17, weight: .semibold))` |
| Body / list row title | `.font(.system(size: 13, weight: .medium))` |
| Body regular | `.font(.system(size: 13))` |
| Secondary label | `.font(.system(size: 12))` |
| Monospaced path | `.font(.system(size: 10, design: .monospaced))` |
| Caption / hint | `.font(.system(size: 11))` |
| Tiny badge | `.font(.system(size: 9, weight: .semibold))` |

**Rule:** Sentence case throughout. Never Title Case in UI strings. Never ALL CAPS.

---

## Spacing & Layout

The app uses a consistent spacing rhythm derived from 4pt increments.

| Context | Value |
|---|---|
| View horizontal padding | `20pt` |
| Row vertical padding | `10pt` |
| Row horizontal padding | `14pt` |
| Section gap | `20pt` |
| Icon–label gap in rows | `10–12pt` |
| Pill internal padding | `10pt horizontal, 5pt vertical` |

**Corner radii:**

| Surface | Radius |
|---|---|
| List card / content block | `10pt` |
| Filter pills / badges | `Capsule()` (fully rounded) |
| Treemap cells | `5pt` |
| Metric cards (Status) | `12pt` |

---

## Animation

All animations use `.spring(response: 0.35, dampingFraction: 0.8)` unless a shorter duration is semantically appropriate (e.g. hover states at 0.1s).

```swift
// Standard transition
.animation(.spring(response: 0.35, dampingFraction: 0.8), value: someState)

// Hover / selection micro-animation
.animation(.easeInOut(duration: 0.1), value: isHovered)

// List item appear/disappear
.transition(.opacity.combined(with: .move(edge: .top)))
```

**Accessibility:** All animations respect `@Environment(\.accessibilityReduceMotion)`. When `reduceMotion` is `true`, pass `.none` instead of a spring.

---

## Component Patterns

### Filter pills
Reusable `FilterPill` view in `LargeFilesView.swift`. Parameters: `label`, `icon` (SF Symbol), `color`, `isActive`, `action`. Used in Duplicates and Large Files.

### Toolbar CTA
Each tab can push a primary action into the window toolbar via `ToolbarCTAState` (`@EnvironmentObject`). Set `cta.label`, `cta.isEnabled`, and `cta.action` in `onAppear` / `onChange`. Clear all three in `onDisappear`.

### Confirmation dialogs
Use `.confirmationDialog(title, isPresented:, titleVisibility: .visible)` for all destructive actions. Never use `Alert` for file-deletion confirmations. The primary destructive button always shows the byte size being affected: `"Move 2.4 GB to Trash"`.

### Empty states
Every tab has a distinct empty state with a large SF Symbol (size 48), a bold headline, a secondary explanation, and (where appropriate) a primary action button.

### Heuristic warning banners
Used in Leftovers and other tabs where results require user judgement. Pattern: accent-colored info icon + bold headline + secondary explanation, `RoundedRectangle` background at `accentColor.opacity(0.06)`.

---

## SF Symbols

All icons are SF Symbols. No custom artwork in the UI (app icon is the only custom graphic).

| Feature | Symbol |
|---|---|
| Clean | `sparkles` |
| Uninstall | `shippingbox` |
| Leftovers | `shippingbox.and.arrow.backward` |
| Analyze | `chart.pie` |
| Snapshots | `clock.arrow.circlepath` |
| Large Files | `doc.zipper` |
| Dev Purge | `hammer` |
| Duplicates | `doc.on.doc` |
| Startup | `power` |
| Status | `gauge.with.dots.needle.33percent` |
| Permission error | `lock.shield` |
| Success / clean | `checkmark.seal.fill` |
| Warning | `exclamationmark.triangle.fill` |

Symbol rendering mode: `.hierarchical` for large decorative icons, default for small inline icons.

---

## Window & Navigation

- **Window min size:** 700 × 500pt. Ideal: 900 × 620pt.
- **Navigation:** `NavigationSplitView` — sidebar (190–220pt wide) + detail column.
- **Sidebar:** `.listStyle(.sidebar)` — Liquid Glass applied automatically by macOS 26.
- **Detail column:** opaque `windowBackgroundColor` — no glass bleed into content area.
- **Full screen:** `.toolbarBackground(.visible, for: .windowToolbar)` keeps toolbar opaque; sidebar glass stays on sidebar only.
- **Status bar:** 22pt tall, inside the detail column, `windowBackgroundColor` — matches Finder.

---

## App Icon

Three variants for macOS 26 adaptive icon support:

| File | Use |
|---|---|
| `AppIcon.png` | Light mode (default) — 1024×1024px |
| `AppIcon-Dark.png` | Dark mode — 1024×1024px |
| `AppIcon-TintedDark.png` | Tinted / monochrome — 1024×1024px |

Design: Liquid Glass aesthetic. Blue gradient broom/sparkle motif on frosted glass background. Exported from the `AppIcon Exports/` folder at the repo root.

The `Contents.json` uses `"idiom": "universal", "platform": "ios"` for the adaptive variants (required by `actool` 26.3) alongside the traditional `"idiom": "mac"` per-size entries.

---

## Accessibility

- All interactive elements have `.accessibilityLabel` and `.accessibilityHint`
- `.accessibilityReduceMotion` respected in Onboarding and animated transitions
- Color is never the sole means of conveying information (badges always have text + icon)
- VoiceOver: treemap cells, list rows, and filter pills all have explicit accessibility actions
- Dynamic Type: not directly supported (macOS doesn't use Dynamic Type), but minimum font size of 9pt is enforced

---

## Screenshots (needed before v1.0 launch)

The following screenshots should be captured on a MacBook Pro 14" (3024×1964 native, typically shown at 1512×982) in both light and dark mode:

1. **Clean tab** — after a scan showing multiple categories with non-zero sizes
2. **Analyze tab** — treemap drilled into a large folder
3. **Dev Purge tab** — list of projects with node_modules/DerivedData selected
4. **Duplicates tab** — a few duplicate groups expanded
5. **Status tab** — live metrics showing CPU/memory/disk

Place screenshots in a `screenshots/` directory at the repo root. Reference them in `README.md` above the feature table.
