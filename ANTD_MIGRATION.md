# Master Prompt — Migrate `hesabixUI` to the Ant Design language

> **Read this first (important):** `antd` is a **React** component library. Your frontend (`hesabixUI`) is **Flutter Web / Material**. You cannot `npm install antd` into it. What you *can* do — and what this prompt does — is port the **Ant Design specification** (tokens, typography, spacing, radii, shadows, motion, component anatomy) into a native Flutter theme + component layer, so the app *looks and behaves* like Ant Design while keeping 487 commits of working code.
>
> If you actually want the real React `antd` library, use **Appendix C** instead — that is a frontend rewrite, not a restyle.

---

## How to use this in VS Code

1. Save this file at the repo root as `ANTD_MIGRATION.md` and commit it.
2. Open a terminal in VS Code at the repo root and run `claude`.
3. Create a safety branch first: `git checkout -b feat/antd-design-language`
4. Enter **Plan Mode** (`Shift+Tab` twice) and paste the prompt below.
5. Let it finish Phase 0 and **read the audit before approving any code**.
6. After Phase 0, ask it to write the agreed rules into `hesabixUI/CLAUDE.md` so every future session inherits them.

---

## THE MASTER PROMPT (copy everything below this line)

---

You are a senior Flutter engineer and design-systems specialist. Your job is to migrate the UI of this project from Material Design to the **Ant Design language**, without breaking anything.

### 1. Project context

- Monorepo `arc` / product name **Hesabix**, an accounting system.
- `hesabixAPI/` — FastAPI + PostgreSQL + SQLAlchemy + Alembic. **Out of scope. Do not touch.**
- `hesabixUI/` — **Flutter Web** app, currently Material Design. **This is the only thing you modify.**
- The product is **Persian-first**: RTL layout, Jalali (Persian) calendar, Persian + English i18n, Persian digits in numeric/financial displays.
- Domain is dense enterprise data: invoices, ledgers, journal entries, reports, long tables, big forms. Ant Design is *built* for exactly this — lean into its data-dense patterns, not into consumer-app whitespace.

### 2. Authoritative sources for the spec

Do not invent values. Pull them from source, in this order of trust:

1. **The package itself** (highest fidelity). In a scratch dir outside the repo:
   `npm pack antd` → untar → read `es/theme/themes/seed.js`, `es/theme/themes/default/colorAlgorithm.js`, `es/theme/themes/shared/genFontSizes.js`, `es/theme/interface/*`. These files contain the exact seed tokens, the derived-token algorithms, the color palette generator, and every component's token contract.
2. **The LLM-oriented docs**: `https://ant.design/docs/spec/introduce.md` and `https://ant.design/docs/react/for-agents.md` (Markdown, agent-friendly).
3. The spec pages: Colors, Layout, Font, Shadow, Dark Mode, Motion, Data Entry, Data Display, Buttons, Data List.

Target **antd v6** (current). If v6 seed values differ from Appendix A of this document, **the package wins** — and tell me what changed.

### 3. Non-negotiable rules

1. **No backend changes.** No API contract changes. No changes to models, services, repositories, or state management logic.
2. **No behavior changes.** This is a visual/interaction-language migration. If you find a bug, report it — do not fix it inside a styling commit.
3. **Persian/RTL is a first-class requirement, not a follow-up.** Every component you touch must be verified under `TextDirection.rtl`. Icons that imply direction (back, next, chevrons, sort, breadcrumb separators) must mirror. Do not hardcode `left`/`right` — use `start`/`end`, `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`.
4. **Typography:** replace Ant Design's Latin font stack with **Vazirmatn** as the primary family, with the antd stack as Latin fallback. Keep antd's *size and line-height scale* exactly; only the family changes.
5. **Zero magic numbers.** After Phase 1, no color literal, padding literal, radius literal, duration literal, or font size literal may appear anywhere in widget code. Everything reads from the token file. I will grep for `Color(0xFF`, `EdgeInsets.all(`, `BorderRadius.circular(` with raw numbers, and `Duration(milliseconds:` — anything left must be justified.
6. **Incremental and reversible.** One logical unit per commit, conventional commit messages, `flutter analyze` clean before every commit. Never mass-rewrite files across the app in a single pass.
7. **Ask before you delete.** Existing custom widgets may encode business rules. Wrap or restyle before replacing.
8. **Stop at every phase gate** and report. Do not chain phases without my approval.

### 4. Phase 0 — Audit (do this first, write no production code)

Produce `hesabixUI/docs/ui-audit.md` containing:

- Flutter/Dart SDK versions, full dependency list, and which packages are UI-relevant (theming, tables, date pickers, charts, forms, icons).
- The current theming architecture: where `ThemeData` is defined, whether dark mode exists, how colors/text styles are currently sourced, whether there is already a design-token or constants file.
- A complete inventory of screens/routes and reusable widgets, each tagged with: which Ant Design component it maps to, complexity (S/M/L), and blast radius.
- A list of every hardcoded style value found, grouped by file, with counts.
- The RTL/i18n/Jalali touchpoints: where `Directionality` is set, which date picker is used, how numbers are formatted.
- A **migration order** — lowest-risk, highest-visibility first — with a rough sequence of PRs.
- A list of the top risks and anything in the codebase that will genuinely resist Ant-ification.

Then **stop** and present a summary plus your recommended order. Wait for my approval.

### 5. Phase 1 — The token layer

Create `hesabixUI/lib/theme/ant/`:

- `ant_seed_tokens.dart` — the seed tokens, verbatim from the package.
- `ant_color_algorithm.dart` — a Dart port of antd's palette generator, so any seed color produces the correct 10-step palette (light) and dark variants. Port the algorithm; do not hand-copy palettes.
- `ant_tokens.dart` — the full derived token set: colors (text/border/fill/bg/status), font sizes and line heights, the 4px size step, control heights, border radii, shadows, z-indices, motion durations and easing curves.
- `ant_tokens_dark.dart` — the dark algorithm equivalents.
- A `AntTokens` object exposed via `InheritedWidget` / `ThemeExtension` so widgets read tokens through context, not via global statics.

Write unit tests asserting a handful of known derived values (e.g. that seed `#1677ff` yields the expected 10 palette steps, that `controlHeight` 32 derives SM 24 / LG 40). This is how we prove the port is faithful.

**Gate:** show me the generated palette rendered as a swatch page before continuing.

### 6. Phase 2 — ThemeData mapping

Map the token set onto `ThemeData` (`ColorScheme`, `TextTheme`, and every relevant component theme: `ElevatedButtonTheme`, `OutlinedButtonTheme`, `TextButtonTheme`, `InputDecorationTheme`, `CardTheme`, `DialogTheme`, `AppBarTheme`, `DataTableTheme`, `ChipTheme`, `TooltipTheme`, `SnackBarTheme`, `DividerTheme`, `CheckboxTheme`, `RadioTheme`, `SwitchTheme`, `DropdownMenuTheme`, `NavigationRailTheme`, `PopupMenuTheme`).

Kill Material's tells: no ripple splashes where antd has none, no elevation tint overlays, no Material 3 rounded-pill buttons, no floating label inputs. Ant Design's default control is a 32px-tall, 6px-radius, 1px-bordered, flat surface.

Add a **theme preview route** (dev-only, e.g. `/dev/theme`) that renders every token and every wrapper component in both LTR/RTL and light/dark. This is your regression harness for the rest of the migration.

**Gate:** screenshot the preview route in all four combinations and show me.

### 7. Phase 3 — Component wrapper layer

In `hesabixUI/lib/ui/ant/`, build a wrapper for each Ant component the app needs, matching antd's **anatomy, sizes, states, and variants** — not just its colors. Minimum set, in this order:

`AntButton` (type: primary/default/dashed/text/link × size sm/md/lg × states: default/hover/active/disabled/loading/danger) → `AntInput` / `AntTextArea` / `AntInputNumber` → `AntSelect` → `AntForm` + `AntFormItem` (label placement, required mark, help text, error state — antd's form is the single biggest UX win here) → `AntTable` (fixed header, fixed columns, sorting, filtering, pagination, row selection, empty state, loading skeleton) → `AntCard` → `AntModal` → `AntDrawer` → `AntTabs` → `AntMessage` / `AntNotification` / `AntAlert` → `AntTag` / `AntBadge` → `AntDatePicker` (**Jalali-aware**) → `AntPagination` → `AntBreadcrumb` → `AntMenu` (sider navigation) → `AntLayout` (Header / Sider / Content / Footer) → `AntEmpty` / `AntSpin` / `AntResult` / `AntSkeleton`.

Rules for this layer:
- Every wrapper is token-driven and RTL-correct by construction.
- Every wrapper gets an entry in the `/dev/theme` preview.
- Match antd's *interaction* feel: `motionDurationMid` transitions on hover/focus, focus rings as a 2px primary-color outline at low opacity, not Material's fill overlays.
- Prefer composing Flutter primitives over fighting Material widgets. If a Material widget can't be made to look like antd within ~30 minutes, build it from `Container` + `InkWell`/`MouseRegion` + `Focus`.

**Gate:** after `AntButton`, `AntInput`, `AntFormItem`, stop and show me. Get the feel right on three components before building twenty.

### 8. Phase 4 — Screen migration

One screen (or one tightly-coupled cluster) per commit, in the order agreed in Phase 0. For each:

1. Replace Material widgets with `Ant*` wrappers.
2. Remove every local hardcoded style value.
3. Apply antd's **layout spec**: 24px content gutters, 24px card padding, 16px vertical rhythm between blocks, 8px within a block, forms on antd's grid.
4. Apply antd's **data-display patterns** to the accounting screens specifically: list pages get filter bar + toolbar + table + pagination; detail pages get header + descriptions block + tabbed sections; form pages get a fixed action footer.
5. Verify in RTL and LTR, light and dark, at 1440px / 1024px / 768px.
6. `flutter analyze`, then `flutter build web` must succeed.
7. Commit with a before/after screenshot pair saved to `hesabixUI/docs/migration-shots/`.

Report progress after every 3 screens.

### 9. Phase 5 — Persian conformance pass

- Vazirmatn loaded correctly for web (subset + `font-display: swap`; verify no FOUT/flash of Latin fallback).
- Jalali date picker matching antd `DatePicker` anatomy (header with month/year selectors, today highlight, range selection, disabled dates).
- Persian digits and thousands separators in all financial figures; currency alignment correct in RTL.
- Line-height sanity: Persian glyphs need more vertical room than Latin — if antd's line-heights clip diacritics or descenders, raise the *line-height tokens only*, document the deviation, and keep font sizes on spec.
- Full keyboard navigation and focus order correct under RTL.

### 10. Phase 6 — Cleanup and definition of done

- No unused Material theming code left behind.
- `hesabixUI/docs/design-system.md` written: token reference, component catalogue, usage rules, and a "how to add a new screen" guide.
- `hesabixUI/CLAUDE.md` written so future sessions automatically follow these rules.
- A documented list of every intentional deviation from the antd spec, with the reason.

**Done means:** the token file is the single source of truth; `/dev/theme` renders correctly in 4 modes; every screen migrated; `flutter analyze` clean; `flutter build web` green; no regressions in existing flows.

### 11. How to talk to me

- Start every response with which phase you are in.
- Before any change touching more than 5 files, show me the plan and wait.
- If a spec value is ambiguous or the antd behavior doesn't translate to Flutter, say so and propose two options — don't silently pick one.
- If you're unsure whether something is styling or business logic, assume business logic and ask.

---

## Appendix A — Baseline token values (verify against the package; the package wins)

**Seed:** `colorPrimary #1677ff` · `colorSuccess #52c41a` · `colorWarning #faad14` · `colorError #ff4d4f` · `colorInfo #1677ff` · `colorTextBase #000000` · `colorBgBase #ffffff` · `fontSize 14` · `borderRadius 6` · `sizeUnit 4` · `sizeStep 4` · `controlHeight 32` · `lineWidth 1` · `motionUnit 0.1` · `wireframe false` · `zIndexPopupBase 1000`

**Derived text:** `colorText rgba(0,0,0,.88)` · `colorTextSecondary .65` · `colorTextTertiary .45` · `colorTextQuaternary .25`
**Border:** `colorBorder #d9d9d9` · `colorBorderSecondary #f0f0f0`
**Fill:** `colorFill rgba(0,0,0,.15)` · `Secondary .06` · `Tertiary .04` · `Quaternary .02`
**Background:** `colorBgContainer #ffffff` · `colorBgElevated #ffffff` · `colorBgLayout #f5f5f5` · `colorBgMask rgba(0,0,0,.45)`
**Blue palette:** `#e6f4ff #bae0ff #91caff #69b1ff #4096ff #1677ff #0958d9 #003eb3 #002c8c #001d66`
**Sizes:** control `XS 16 / SM 24 / base 32 / LG 40` · radius `XS 2 / SM 4 / base 6 / LG 8`
**Font scale:** `12 / 14 / 16 / 20 / 24 / 30 / 38` (h5→h1 = 16/20/24/30/38); base line-height ≈ 1.5714
**Spacing:** `XXS 4 / XS 8 / SM 12 / base 16 / MD 20 / LG 24 / XL 32`
**Motion:** fast `0.1s` · mid `0.2s` · slow `0.3s`; easeInOut `cubic-bezier(.645,.045,.355,1)` · easeOut `cubic-bezier(.215,.61,.355,1)` · easeOutBack `cubic-bezier(.12,.4,.29,1.46)`
**Shadow (default):** `0 6px 16px 0 rgba(0,0,0,.08), 0 3px 6px -4px rgba(0,0,0,.12), 0 9px 28px 8px rgba(0,0,0,.05)`

## Appendix B — Material → Ant mapping cheat sheet

| Material (current) | Ant Design target |
|---|---|
| `ElevatedButton` | `Button type="primary"` — flat, 6px radius, no elevation |
| `OutlinedButton` | `Button type="default"` |
| `TextButton` | `Button type="text"` / `type="link"` |
| `FloatingActionButton` | usually **remove** — antd uses a toolbar primary button |
| `TextField` (floating label) | `Input` with an external `Form.Item` label above/beside |
| `DataTable` | `Table` — header bg `#fafafa`, hover row fill, fixed header, pagination |
| `Card` (elevated) | `Card` — 1px border + `borderRadiusLG`, shadow only on hover/elevated variants |
| `SnackBar` | `message` (top-center toast) or `notification` (corner) |
| `AlertDialog` | `Modal` — title bar, footer with cancel/ok ordering |
| `BottomSheet` | `Drawer` |
| `Chip` | `Tag` |
| `NavigationRail` / `Drawer` | `Layout.Sider` + `Menu` |
| Material ripple | remove — antd uses background/border color transitions |

## Appendix C — If you want the *real* React `antd` instead

That is a frontend rewrite, not a restyle. Swap Phases 1–4 for:

1. Scaffold a new `hesabixWeb/` with **Vite + React + TypeScript + antd v6 + Ant Design Pro Components** (`ProTable`, `ProForm`, `ProLayout` — these are purpose-built for exactly this kind of accounting CRUD and will save you months).
2. Generate a typed API client from the FastAPI OpenAPI schema (`openapi-typescript` + `openapi-fetch`), so the backend contract is enforced at compile time.
3. RTL via `<ConfigProvider direction="rtl" locale={faIR} theme={{ token: { fontFamily: 'Vazirmatn, ...' } }}>`.
4. Jalali via `dayjs` + `@calidy/dayjs-calendarsystems` (or antd's `DatePicker` with a custom `generateConfig`).
5. Migrate route-by-route, running both frontends in parallel behind Nginx (`/` → old Flutter build, `/v2` → new React build) until parity, then flip.

Budget honestly: this is a multi-month effort for a full accounting suite. The Flutter token-port path above gets you ~80% of the visual result for ~10% of the cost. Choose deliberately.
