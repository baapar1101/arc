# UI Audit — Ant Design Migration, Phase 0

Project: `hesabixUI/hesabix_ui` (Flutter Web, product currently mid-rebrand from "Hesabix" to "MarkStreet"). This document is read-only research — no production code was changed to produce it. It is the evidence base for the Phase 1+ token/theme work described in `ANTD_MIGRATION.md`.

> **Path note:** the master prompt refers to paths as `hesabixUI/lib/...` and `hesabixUI/docs/...`. The actual Flutter package root is one level deeper, at `hesabixUI/hesabix_ui/`. All paths below (and all future phases) should be read relative to `hesabixUI/hesabix_ui/`, not `hesabixUI/`.

## 1. SDK & dependencies

- Version `1.1.56+23`, Dart SDK `^3.9.2`, Material 3 enabled (`uses-material-design: true`).
- `dependency_overrides`: `intl: ^0.20.2`, `desktop_drop` pinned to local path `third_party/desktop_drop`.
- Custom fonts already registered: `Roboto`, `NotoSansArabic`, `Vazirmatn` (regular+bold), `YekanBakhFaNum` (7 weights — Persian numerals), `Noto Sans`, `Noto Color Emoji`. Vazirmatn is already in the font manifest, which simplifies Phase 5.

**UI-relevant packages:**

| Category | Package(s) | Note |
|---|---|---|
| Tables | `data_table_2: ^2.5.12` | Declared but likely not the real workhorse — see §6 |
| Date/calendar | `persian_datetime_picker: ^3.2.0`, `shamsi_date: ^1.1.1` | App uses a fully custom picker on top of `shamsi_date`; `persian_datetime_picker` itself appears unused — see §5 |
| Charts | `fl_chart: ^1.1.1` | 10 files, dashboard/monitoring |
| Forms/validation | none dedicated | Hand-rolled per widget (e.g. `widgets/zohal/common/zohal_validators.dart`) |
| Icons | `cupertino_icons` only | No separate icon-font package |
| Routing | `go_router: ^17.3.0` | Single monolithic config in `lib/main.dart` |
| State management | none (plain `ChangeNotifier`) | Out of scope for restyle, but theme changes propagate via a full `setState` on `MyApp` |
| PDF/export | `pdf`, `printing`, `file_saver`, `share_plus` | Own typography/layout, won't inherit Ant tokens |
| Misc input | `mobile_scanner`, `flutter_sound`, `flutter_map`, `qr_flutter`, `barcode`, `file_picker` | Several have fixed native/third-party looks — see §6 |

## 2. Theming architecture

**A design-token layer already exists at `lib/theme/`** — this is the single most important finding for scoping Phase 1. It is a reasonable foundation, not a from-scratch build:

- `lib/theme/app_theme.dart` — `AppTheme.build({isDark, locale, seed})`, the single `ThemeData(...)` construction point, wiring ~15 component themes + 3 `ThemeExtension`s.
- `lib/theme/tokens/color_schemes.dart` — `AppColorTokens.schemeFromSeed`, a thin wrapper over `ColorScheme.fromSeed`. **No bespoke Ant-style 10-step palette yet** — purely Material tonal generation. This is what Phase 1's `ant_color_algorithm.dart` replaces.
- `lib/theme/tokens/typography.dart` — locale-aware `TextTheme` (separate FA/EN scales), a `_compactScale` helper (0.90 FA / 0.93 EN) shrinking Material's default scale for ERP density, and `AppFonts` family/fallback wiring. Deliberately uses `YekanBakhFaNum` to avoid Latin-digit substitution (inline comment) — preserve this behavior when porting Ant's font-size scale.
- `lib/theme/tokens/extensions.dart` — three `ThemeExtension`s already in place: `AppSpacing` (xs/sm/md/lg/xl = 4/8/12/16/24), `AppRadii` (sm/md/lg = 6/10/14), `AppShellColors`. Exposed via context getters (`context.appSpacing`, `context.appRadii`, `context.shellColors`). **This is structurally identical to what Phase 1 asks for (`AntTokens` via `ThemeExtension`)** — the existing extensions can likely be extended/renamed rather than replaced.
- `lib/theme/components.dart` — per-component `ThemeData` builders (button/input/card/appbar/dialog/chip/snackbar/tabbar/nav-rail themes). This is the file Phase 2 primarily rewrites.
- `lib/theme/theme_controller.dart` — `ThemeController extends ChangeNotifier`, persists `ThemeMode` + seed color to `SharedPreferences`, falls back to a backend `default_theme` setting. Hardcodes seed `Color(0xFF6B7280)` twice (`legacyBlueSeed`/`defaultSeed`) — minor cleanup candidate, not a blocker.

**Dark mode**: fully wired, user-configurable (`pages/profile/appearance_settings_page.dart`), branches at every token layer.

**Consistency problem**: theme-driven paths exist and are used in places, but **1,789 raw `Colors.*` references across 246 files** and **180 raw `Color(0xFF...)` literals across 12 files** coexist alongside the token layer — large parts of the page/widget layer bypass it entirely. `lib/constants/` is not a style-token store (only two unrelated domain-constants files).

## 3. Screens/routes & reusable widget inventory

**Routing**: `go_router`, entirely configured inline inside one monolithic `lib/main.dart` (3,852 lines). No separate route-config file. Two `ShellRoute`s (`ProfileShell`, `BusinessShell`) plus a `MobileLauncherShell`. A large `redirect:` callback (lines 836–913) handles auth gating + legacy-path normalization. Permission checks (`hasAppPermission(...)`) are written inline per-route rather than centralized. A `_preloadPages` method (lines 362–711) eagerly instantiates ~120 pages for bundling — a build/perf concern, not a styling one, but explains why nearly every page is imported directly into `main.dart`.

**Screens** — `lib/pages/`, 253 files:

| Directory | Files | Complexity | Notes |
|---|---|---|---|
| `pages/` (root) | 4 | S | login, home, 404, system settings |
| `pages/admin/` | 42 | M–L | Superadmin console; 3 near-duplicate monitoring-page variants (`_page`, `_page_improved`, `_page_old` — dead-code candidates) |
| `pages/business/` (top-level) | 116 | M–L | Core ERP: invoices, ~30 report pages, persons/products/warehouses, banking, tax, fiscal-year close, workflows, AI chat |
| `pages/business/crm/` | 13 | M | CRM dashboard/leads/deals/activities |
| `pages/business/repair_shop/` | 5 | M | |
| `pages/business/woocommerce/`, `basalam/`, `distribution/`, `customer_club/`, `backup/` | 3–6 each | M | Third-party integration panels |
| `pages/business/dashboard/` | 3 | **L** | `business_dashboard_page.dart` — 3,360 lines, largest single page |
| `pages/business/settings/` | 4 | S | |
| `pages/profile/` | 21 | S–M | Personal account area |
| `pages/public/` | 5 | S | Unauthenticated share-link landings |
| `pages/warehouse/` | 4 | M | |
| `pages/mobile_launcher/` | 3 | S | |
| `pages/system_settings/` | 7 | M | Settings-search infra |

**Reusable widgets** — `lib/widgets/`, 289 files:

| Directory | Files | Complexity | Notes |
|---|---|---|---|
| `widgets/` (root) | 23 | S–M | Shell chrome: splash (3 variants), menu buttons, notification bell, date field |
| `widgets/data_table/` | 6 (+2 stray) | **L** | `data_table_widget.dart` — 4,666 lines, the de facto grid for the whole app. See §6. |
| `widgets/invoice/` | 34 | L | ~10 near-duplicate combobox pickers (account/bank/customer/person/product/warehouse/price-list) — consolidation candidate |
| `widgets/ai/` | 44 | L | Full AI chat UI |
| `widgets/product/` | 22 | M–L | Sectioned form, BOM editor, platform-conditional PDF label print |
| `widgets/workflow/` | 15 | **L** | Canvas-based visual editor — see §6 |
| `widgets/warehouse/` | 8 | M | |
| `widgets/marketplace/` | 13 | M | |
| `widgets/crm/` | 7 | M | |
| `widgets/zohal/` (+ subdirs) | 27 | M | 6+ near-duplicate inquiry-result widget patterns — consolidation candidate ("shared InquiryResultCard") |
| `widgets/support/` | 6 | S–M | |
| `widgets/person/`, `banking/`, `distribution/`, `document/`, `expense_income/`, `warranty/`, `transfer/`, `project/`, `permission/`, `category/`, `barcode/` | 1–9 each | S–M | One cluster per business entity |
| `widgets/report_template/` (+`studio/`) | 6 | M | Report-template designer + embedded-PDF iframe (`_web`/`_stub`) |
| `widgets/admin/file_storage/` | 5 | S | |
| `widgets/monitoring/`, `memorial/`, `ping_pong/` | 3/1/2 | S | Ping-pong is a cosmetic Easter egg — safe to skip or delete |

## 4. Hardcoded style values

| Pattern | Occurrences | Files |
|---|---|---|
| `Colors.*` | 1,789 | 246 |
| `EdgeInsets.symmetric(` | 1,139 | 271 |
| `EdgeInsets.only(` | 926 | 274 |
| `EdgeInsets.all(` | 535 | 205 |
| `Color(0xFF` | 180 | 12 |
| `BorderRadius.circular(` | 160 | 58 |
| `TextStyle(fontSize:` | 141 | 82 |
| `Duration(milliseconds:` | 40 | 26 |

**Top files, `Colors.*`**: `widgets/document/document_details_dialog.dart` (54), `widgets/workflow/workflow_node_config_dialog.dart` (42), `pages/profile/user_notifications_page.dart` (40), `pages/admin/system_monitoring_page.dart` (39), `pages/profile/delete_business_page.dart` (37), `widgets/workflow/workflow_timeline_dialog.dart` (34), `widgets/product/sections/product_bom_section.dart` (34), `widgets/support/ticket_details_dialog.dart` (31), `pages/admin/payment_gateways_page.dart` (31), `widgets/workflow/workflow_analytics_dialog.dart` (29).

**Top files, `Color(0xFF...)`** (near-exhaustive — only 12 files use this pattern at all): `pages/system_settings/services/settings_categorization_service.dart` (47) and `pages/business/settings/business_settings_categorization_service.dart` (47) — **near-duplicate files**, same category-color-assignment logic implemented twice; `pages/business/storage_files_page.dart` (36); `pages/error_404_page.dart` (23); `pages/business/dashboard/business_dashboard_page.dart` (9); `pages/business/business_info_settings_page.dart` (6); `theme/theme_controller.dart` (3, the seed constants noted in §2); `widgets/workflow/workflow_connection_painter.dart` (2).

**`BorderRadius.circular` top files** (none route through the existing `context.appRadii`, despite it existing): `storage_files_page.dart` (32), `payment_gateways_page.dart` (28), `bom_editor_dialog.dart` (22), `transfer_form_dialog.dart` (21), `database_backup_page.dart` (19).

**Cleanup note**: `widgets/data_table/data_table_widget.dart.backup` (1,702 lines, stray) shows up repeatedly in these greps and should be deleted before migration begins, not migrated.

## 5. RTL / i18n / Jalali touchpoints

- **Localization**: `l10n.yaml` at project root, `arb-dir: lib/l10n`, locales `en`/`fa`. `app_en.arb` (5,909 lines) / `app_fa.arb` (5,953 lines) — mature, thorough coverage, not partial.
- **Directionality**: no explicit `Directionality`/`TextDirection` override anywhere in `lib/` — RTL is left entirely to Flutter's automatic `Locale` → `TextDirection` resolution via `MaterialApp.router(locale: …)`. Works today, but means no custom Row/layout code has been verified against RTL beyond what Material gives for free — every wrapper built in Phase 3 needs explicit RTL verification per rule #3 of the master prompt, since none of this was intentionally RTL-hardened.
- **Date picker**: the app does **not** use `showDatePicker` or `persian_datetime_picker`'s own widget. It has a fully custom `JalaliDatePicker` (`lib/widgets/jalali_date_picker.dart`) built directly on `shamsi_date`'s `Jalali` class — a fixed-size (350×450) custom `Dialog` that partially bypasses `appDialogTheme` (styles its background directly). `persian_datetime_picker` is declared in `pubspec.yaml` but not found used — likely dead dependency, worth confirming and removing.
- `lib/core/calendar_controller.dart` toggles Jalali vs. Gregorian app-wide. `lib/core/date_utils.dart` (`MarkStreetDateUtils`, 348 lines) centralizes Jalali↔Gregorian formatting, used from **116 files** — any `AntDatePicker` work in Phase 3 must go through this utility, not reimplement conversion.
- **Number formatting**: dual system — `intl`'s `NumberFormat` (21 files, mostly reports/tax) alongside a separate custom Persian-digit normalizer (`utils/number_normalizer.dart`, `utils/amount_to_words.dart`, used in 31 files). This seam needs checking wherever an `AntInputNumber` or table-cell renderer is introduced.
- **Font**: `AppFonts.faPrimary = 'YekanBakhFaNum'` deliberately avoids Latin-digit substitution (see §2) — preserve when porting Ant's type scale.

## 6. Top risks / resistant areas

1. **`widgets/data_table/data_table_widget.dart` (4,666 lines)** — the single highest-effort, highest-risk item in the whole migration. It's the de facto grid for the entire app (Flutter's own `DataTable`/`data_table_2` appear only 34 times across 20 files, mostly small ad-hoc report tables). Restyling this to Ant's `Table` anatomy (fixed header/columns, sort/filter, pagination, row selection, skeleton loading) is effectively its own sub-project. A `.backup` copy (1,702 lines) and a near-empty re-export shim (`data_table.dart`, 5 lines) sit next to it and should be deleted first.
2. **Canvas-based workflow editor** (`widgets/workflow/`: `workflow_canvas.dart` 712 lines, `workflow_connection_painter.dart`, `workflow_minimap.dart`, `workflow_animated_node.dart`) — a bespoke drag-and-drop automation editor with hand-drawn connector lines. Ant Design has no equivalent primitive; only the surrounding chrome (toolbar, node-config dialogs, palette) is themeable, the canvas itself stays custom.
3. **PDF/print rendering** (`pdf`, `printing`, platform-conditional embed widgets) — renders its own typography/layout independent of Flutter's widget theme; only the surrounding preview/print-options UI is themeable.
4. **Third-party fixed-look packages**: `flutter_map` (tile rendering), `mobile_scanner` (native camera preview), two competing tree-view packages (`flutter_simple_treeview` **and** `flutter_fancy_tree_view` both present) — Ant's `Tree` has a distinctive connector-line look neither replicates out of the box; worth consolidating to one package during the port rather than overriding both.
5. **`lib/main.dart` (3,852 lines)** and **`business_dashboard_page.dart` (3,360 lines)** — alongside the data-table widget, these three files total ~12,000 lines and are disproportionately large relative to the other ~540 mostly-small (100–400 line) UI files. Expect them to need dedicated sessions rather than falling into the normal "one screen per commit" cadence.
6. **Duplicated logic**: the two settings-categorization services (§4) and the ~10 near-duplicate invoice combobox pickers and ~6 near-duplicate Zohal inquiry-result widgets are consolidation opportunities *during* the port (build one themed component, retire the duplicates) rather than restyling each copy independently — but per rule #7 of the master prompt (ask before deleting), each consolidation should be confirmed rather than assumed, since some "duplicates" may encode subtly different business rules.
7. **Inconsistent token adoption** is the pervasive risk, not a localized one: `AppSpacing`/`AppRadii` extensions already exist but are barely used (0 of the top `BorderRadius.circular` offenders route through `context.appRadii`). The token layer needs both extending to Ant values *and* enforcement (Phase 1's "zero magic numbers" grep-gate) — this is a breadth problem across ~540 files, not a depth problem in any one of them.
8. **Rebrand in flight**: the codebase is concurrently being renamed from "Hesabix" to "MarkStreet" in a separate, actively-running session on `master`. Expect naming/copy churn in parallel with this migration; theme/token work should be insulated from that (no hardcoded "Hesabix" strings were found in the theme layer itself).

## 7. Recommended migration order

Lowest-risk, highest-visibility first:

1. **Phase 1 (tokens)** — extend the *existing* `lib/theme/tokens/` layer (don't replace it) with Ant seed tokens, the palette algorithm, and Ant's spacing/radius/motion scale, since `AppSpacing`/`AppRadii`/`AppShellColors` already provide the right shape of extension point.
2. **Phase 2 (ThemeData mapping)** — rewrite `lib/theme/components.dart` component-by-component; this is already isolated from page code, so it's a contained, high-leverage change.
3. **Phase 3 (component wrappers)**, screen order once we reach Phase 4:
   - `pages/public/` and `pages/mobile_launcher/` first — small, low-permission-complexity, high external visibility (share links, PWA launcher).
   - `pages/profile/` next — medium size, self-contained, good proving ground for `AntForm`/`AntFormItem` before touching ERP screens.
   - `pages/business/settings/` and `pages/admin/` (excluding monitoring) — medium complexity, consolidate the duplicate categorization service while here.
   - Core ERP (`pages/business/` invoices/reports/persons/products) last and incrementally — highest volume, highest business-rule density, most reliant on `AntTable` being ready first.
   - `business_dashboard_page.dart`, `lib/main.dart` routing chrome, and `data_table_widget.dart` treated as their own dedicated efforts, not folded into the normal per-screen cadence.
   - Workflow canvas and PDF-embed widgets restyled only at the chrome layer; canvas/PDF internals left alone.
4. **Phase 5 (Persian conformance)** can start early and run in parallel once `AntDatePicker` exists, since the Jalali infrastructure (`date_utils.dart`, `calendar_controller.dart`) is already centralized and stable — no need to wait for every screen to migrate first.

## 8. Open questions for approval

- Confirm the path correction above (`hesabixUI/hesabix_ui/` vs `hesabixUI/`) before Phase 1 begins.
- Confirm whether to delete `data_table_widget.dart.backup` and the `data_table.dart` shim now (Phase 0 cleanup) or defer to when `data_table/` is actually migrated.
- Confirm whether `persian_datetime_picker` (pubspec dependency, apparently unused) should be removed, or whether it's used somewhere not caught by this search.
- Confirm whether to consolidate the two settings-categorization services, the ~10 invoice combobox pickers, and the Zohal inquiry-result widgets during the port, or leave duplication in place and restyle each independently (master-prompt rule #7 — ask before touching anything that might encode distinct business rules).
