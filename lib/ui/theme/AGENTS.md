# lib/ui/theme

Score 8 (distinct domain — the design-token definition site): only 2 files / 359 LOC, but `AppSpacing` alone has 563 repo-wide references and the parents (`lib/ui`, root) only say "tokens live here".

## OVERVIEW
`app_tokens.dart` defines every spacing / radius / size / semantic-colour token plus the responsive helpers; `app_theme.dart` assembles them into the single `ThemeData` (`buildAppTheme`) and the global scroll behaviour. New tokens belong here, not in pages.

## TOKENS
| Symbol | Provides |
|--------|----------|
| `AppSpacing` | `xs/sm/md/lg/xl/xxl` = 4/8/12/16/24/32, `pagePadding`, `cardPadding`, `listTilePadding` |
| `AppRadius` | `chip/input/card/panel/pill` = 8/12/18/22/999 + the matching `chipR`…`pillR` `BorderRadius` consts |
| `AppColors` | seeds only — `brandSeed` `0xFF108850`, `successSeed`, `warningSeed`; fed to `ColorScheme.fromSeed`, never used as a role colour |
| `AppSizes` | wide-screen clamps used by `home_shell.dart`: `narrowContent` 760, `listContent` 1000, `chatSplitBreakpoint` 760, `railBreakpoint` 800, `railMinWindow` 480, `chatListWidth` 320 (240–460) |
| `AppSemanticColors` | `ThemeExtension` for the roles M3 lacks (success / warning + their containers) |
| `buildAppTheme` | the only `ThemeData` builder: seed → `ColorScheme.tonalSpot`, plus appBar/card/dialog/input/button/chip/snackBar themes |
| `AppScrollBehavior` | returns the child without an overscroll indicator |
| helpers | `isCompactWidth` (shortestSide < 600), `adaptiveDensity`, `isDesktopPlatform` (linux/windows), `dialogContentWidth`, `dialogContentHeight` |

## CONVENTIONS
- `buildAppTheme` builds the scheme with `ColorScheme.fromSeed(..., dynamicSchemeVariant: tonalSpot)` and copies only `outlineVariant` (`0x1FFFFFFF` dark / `0x1F000000` light); every other role comes from the seed, which is `AppColors.brandSeed` unless the settings page passes an accent seed.
- Adding a semantic role: put its seed in `AppColors`, derive tonal values in `AppSemanticColors.fromBrightness`, and implement `copyWith` + `lerp` — the extension is `@immutable` and theme animation calls `lerp`.
- `AppSemanticColors.of(context)` must keep its fallback to `fromBrightness(theme.brightness)`: widget tests mount bare `MaterialApp`s with no extension attached, and a null here crashes them.
- `AppScrollBehavior` drops the indicator on purpose — M3's stretch overscroll distorts cards and avatars at list ends. Don't "restore" it.
- The compact-width judgement is `shortestSide < 600` so landscape phones still count as phones and keep ≥48dp touch targets.

## ANTI-PATTERNS
- No new raw `Color(0x...)` or magic spacing numbers in pages/widgets — add a token here instead. Legacy literals remain in `partner_badges.dart`, `theme_settings_page.dart`, `mail_page_widgets.dart`, `emoji_picker.dart` and `providers_settings.dart`; don't add more, and replace them when you touch those files.
- Don't add a second `ThemeData` builder or hand-pick role colours — the `fromSeed` note in `app_theme.dart` explains why saturated raw colours break the M3 tonal palette.
- Keep this directory Flutter-only: no core services, no drift, no Riverpod providers.
