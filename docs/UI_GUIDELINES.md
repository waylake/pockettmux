# Native Apple UI — PocketTmux

> **Contract:** PocketTmux should feel like an iPhone and a Mac app first, and a PocketTmux app second. Product UI uses standard Apple components, semantic styling, platform navigation, and platform input conventions. Custom UI is allowed only where the product's terminal domain requires it.

Researched against Apple's current Human Interface Guidelines, SwiftUI documentation, and WWDC sessions on **2026-09-23**. Sources are listed at the end.

## 1. Product decision

PocketTmux does not maintain a separate visual theme.

- The iPhone app follows iOS conventions: `NavigationStack`, `List`, `Form`, sheets, toolbars, swipe actions, context menus, alerts, and system empty states.
- The Mac app follows macOS conventions: `MenuBarExtra`, the `Settings` scene, grouped `Form`s, `List` selection and menus, standard focus, keyboard commands, and system window chrome.
- Appearance follows the person's Light/Dark Mode and Increase Contrast settings.
- Typography follows system text styles and Dynamic Type.
- Color communicates status or emphasis through semantic system roles, not a fixed app palette.
- SF Symbols use their system rendering and adapt to appearance, contrast, and control context.

This does **not** mean every pixel must be generic. The terminal, QR code, and technical values remain intentionally specialized. The rule is that the surrounding app chrome should not make people learn a PocketTmux-specific interface.

## 2. Principles derived from Apple

### 2.1 Platform convention before brand expression

Apple's iOS and macOS guidance treats familiar platform behavior as part of quality. Standard components already include expected selection, focus, motion, accessibility, assistive-technology support, keyboard behavior, and appearance adaptation.

PocketTmux therefore prefers a system component over a visually distinctive imitation. A native `List` row is preferred to a custom card; a toolbar/menu is preferred to a custom chip strip; a Mac `Form` is preferred to a hand-built settings grid.

### 2.2 Hierarchy through content and layout

Apple separates content from controls and navigation. PocketTmux gets hierarchy from:

- navigation titles and section structure;
- system text styles (`headline`, `subheadline`, `footnote`, `caption`);
- SF Symbols and semantic foreground styles;
- spacing, safe areas, and platform-provided containers;
- one clear primary action per view.

It does not get hierarchy from fixed font sizes, all-caps labels, custom section-header views, decorative panels, or an app-wide dark palette.

### 2.3 Semantic color and appearance adaptation

Apple advises using dynamic system colors because they encode purpose and adapt to appearance, vibrancy, and increased contrast. PocketTmux uses:

- `.primary` / `Color.label` for primary content;
- `.secondary` for supporting content;
- `.green`, `.orange`, and `.red` only for connected, connecting, and error states;
- `.accentColor` / the system tint for selection and the primary action;
- system backgrounds and materials for surfaces;
- `UIColor.systemBackground`, `.label`, `.systemGreen`, and `.systemBlue` for SwiftTerm defaults.

A status is never represented by color alone: it also uses a distinct SF Symbol and an accessibility label.

### 2.4 Platform-specific interaction

The same product task may use different native patterns on iPhone and Mac.

- iPhone: push navigation, sheets, toolbars, swipe actions, context menus, and 44-point touch targets.
- Mac: a menu-bar utility window, `Settings`, selectable lists, menus, context menus, focus states, and keyboard shortcuts.

Do not force a phone metaphor onto macOS or a desktop information density onto iPhone merely to keep source visually identical.

### 2.5 Accessibility is baseline behavior

- Do not replace system text styles with fixed point sizes.
- Respect Increase Contrast and Reduce Motion through semantic styles and standard controls.
- Give icon-only controls meaningful accessibility labels.
- Combine related status text so VoiceOver reads it as one phrase.
- Keep target sizes and spacing at platform defaults wherever possible.
- Never encode state using color alone.

## 3. Component map

| Product area | Native implementation |
|---|---|
| iPhone root | `NavigationStack` with value-based `NavigationLink` destinations |
| Macs and Sessions | `List`, `Section`, native row disclosure, swipe actions, context menus, refreshable lists |
| Add/Edit Mac | Sheet containing `Form`, `Picker`, `LabeledContent`, text fields, toolbar actions |
| iPhone Settings | Sheet containing `Form`, `Stepper`, `Toggle`, `Link`, and `LabeledContent` |
| Empty states | `ContentUnavailableView` on iOS 17+/macOS 14+, with a system-aligned fallback on iOS 16 |
| Terminal navigation | Standard navigation bar and toolbar with native back, menu, and symbol buttons |
| tmux hierarchy | Standard nested `Menu`: **Window** and **Pane** remain distinct; no custom tab/chip strip |
| Mac utility panel | `MenuBarExtra(.window)` containing standard `List` sections and controls |
| Mac Pairing | Grouped `Form` with `LabeledContent`, `Picker`, standard buttons |
| Mac Settings | Native `Settings` scene, tab-style categories, and grouped `Form`s |
| Log | Standard window title/toolbar; monospaced text only for log content |
| Feedback | System alerts, confirmation dialogs, menus, and semantic status indicators |

## 4. What may remain custom

Custom presentation is justified for:

1. **SwiftTerm's terminal canvas.** It is a specialized text/ANSI surface and uses a monospaced font.
2. **QR scanning and QR rendering.** The scanner needs camera space and a recognizable reticle; the QR uses high-contrast black and white for reliable scanning.
3. **Technical values.** IPs, ports, token masks, paths, URLs, versions, and logs may use a monospaced system font or monospaced digits.
4. **Domain presentation.** A session row can include a session name, window/client counts, and a phone-attached symbol without becoming a custom card.
5. **Terminal-specific gestures.** Alternate-screen swipe scrolling remains product behavior implemented around SwiftTerm's own recognizers.

Custom presentation is not justified for app-wide backgrounds, section labels, navigation, settings, toolbars, ordinary buttons, empty states, or list rows.

## 5. Explicitly rejected patterns

Do not add:

- `.preferredColorScheme(.dark)` to the apps;
- fixed `Color(red:green:blue:)` or hex app palettes;
- fixed app-wide point sizes for ordinary text;
- custom section-header views that replace `Section` headers;
- manually drawn chevrons when `NavigationLink` can supply them;
- custom navigation bars that hide the system back button;
- custom button fills, corner radii, and shadows that replace standard button styles;
- a custom window/pane strip component where nested `Menu` or `Picker` works;
- fixed light/dark choices instead of semantic styles;
- more than one or two prominent buttons in a view;
- status communicated only by a colored dot.

## 6. Review checklist

Before merging UI work, verify:

### iPhone

- [ ] Light Mode, Dark Mode, and Increase Contrast are supported.
- [ ] Text remains usable at accessibility text sizes.
- [ ] Navigation uses the system back button and titles.
- [ ] Add/edit/settings surfaces use `Form` or another standard container.
- [ ] Destructive actions use swipe actions, context menus, and confirmations.
- [ ] Empty states use `ContentUnavailableView` when available.
- [ ] Touch controls are system controls with adequate hit areas.

### Mac

- [ ] The menu-bar extra uses one conventional status symbol.
- [ ] The panel and windows use system titles, lists, menus, and focus behavior.
- [ ] Settings opens through the `Settings` scene / standard Settings command.
- [ ] All actions are reachable by pointer and keyboard.
- [ ] Context menus and confirmation dialogs replace inline custom interaction.
- [ ] Light/Dark Mode and accent color follow System Settings.

### Both

- [ ] No hard-coded app palette or forced appearance remains.
- [ ] No fixed text scale is used outside terminal/log/technical content.
- [ ] SF Symbols use system colors and rendering.
- [ ] Information is not conveyed by color alone.
- [ ] New UI cites the relevant Apple guideline or platform convention in review notes when the choice is not obvious.

## 7. Migration sequence

1. **Contract and research** — record Apple's principles and map them to PocketTmux.
2. **iPhone structure** — replace custom hero/rows/forms/toolbars with native navigation, lists, forms, menus, and empty states.
3. **Mac chrome** — replace fixed styling and custom hover/chip behavior with system lists, forms, menus, and focus.
4. **Terminal exception** — retain SwiftTerm and QR customization, but use semantic system defaults around them.
5. **Verification** — build both apps, run unit tests, inspect light/dark/contrast/accessibility sizes, and recapture product screenshots.
6. **Guardrail** — add a lightweight source check for regressions such as forced appearance and fixed app colors.

## 8. Sources

### Human Interface Guidelines

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [Components](https://developer.apple.com/design/human-interface-guidelines/components)
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)

### SwiftUI and WWDC

- [Picking container views for your content](https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content)
- [Form](https://developer.apple.com/documentation/swiftui/form)
- [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)
- [Populating SwiftUI menus with adaptive controls](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Build a SwiftUI app with the new design — WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Bring multiple windows to your SwiftUI app — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10061/)
- [What's new in SwiftUI — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10052/)
- [Use Xcode to develop a multiplatform app — WWDC22](https://developer.apple.com/videos/play/wwdc2022/110371/)

## 9. Scope

This contract governs the product apps in `App/iOS` and `App/macOS`. It does not prohibit a distinct marketing visual identity on the public website; it does prohibit that marketing skin from becoming the interaction model inside the apps.
