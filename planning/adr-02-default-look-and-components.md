# ADR 02: road-kit ships the default look and components

- **Status:** Accepted 2026-11-19. Rulings are under "Rulings"; the theme switch (item 4) is
  still open.
- **Date:** 2026-11-19
- **Scope:** All ROAD projects that have a browser UI: road-kit, quorate, road-planner, road-tracker,
  aida, road-blogger, and ai-live-hub where it builds on road-kit. road-cal is parked and is not
  migrated (ADR 01, adoption order 5).
- **Amends** ADR 01 (`adr-01-front-end-ui-stack.md`). Its decision stands: shadcn/ui with Tailwind
  CSS is the default stack, and an app that departs from it records the decision. This ADR
  replaces ADR 01's adoption order, which gave the component vocabulary to quorate and gave
  road-kit the mechanical setup only.
- **Closes** two gaps that `hello_world/src/theme.css` leaves open on purpose: there is no chart
  palette and no dark mode.

## Decision

road-kit ships a default look and a default set of components, and every app built from it starts
with them. Each app can change the look in one file that it owns, without editing anything that
road-kit owns.

1. **Libraries.** road-kit adds a small set of libraries to the ADR 01 stack. They are listed in
   "The stack" below.
2. **Components.** road-kit ships the app shell and the components that most screens need, built
   from shadcn/ui and styled only through tokens.
3. **Palette.** `tokens.css` gains derived shades, status colours, chart colours and a dark theme.
   It stays the only place a colour value is defined.
4. **Override.** An app sets its own colours, fonts, corner radius and density in `src/brand.css`.
   The names it may set are tokens that already exist in `tokens.css`.
5. **hello_world is the reference app.** Its screens are rebuilt with the new components, starting
   from the drafts listed under "Context".

## Context

ADR 01 (2026-09-05) gave the component vocabulary to quorate, because quorate had the most screens
and the only external accessibility obligation. road-kit was to take only what quorate had proved.
That has not happened:

- quorate was paused on 2026-08-29 after build plan 02 phase 3 and is on hold. It has built no
  shared components.
- Each app that needed components added them on its own. The table below was measured on
  2026-11-19 from each app's `package.json` and `src/components/ui/`.
- road-planner's first unattended build read ADR 01 as "use the defaults and do no visual design",
  and its UI was poor to use. D-02 was clarified on 2026-10-31: the aim is consistency across apps,
  and visual design is expected.
- hello_world's home page shows build settings and session data. An app forked from road-kit starts
  from a page that looks like a technical test.

| App | UI libraries beyond React and the router | shadcn components in `src/components/ui/` |
|---|---|---|
| road-kit (hello_world) | shadcn, Base UI, Tailwind 4, lucide | button |
| quorate (quorate_admin) | shadcn, Base UI, Tailwind 4, lucide | none |
| road-tracker | shadcn, Base UI, Tailwind 4, lucide, dnd-kit | button |
| road-planner | shadcn, Base UI, Tailwind 4, lucide, cmdk, sonner, react-day-picker, date-fns, next-themes, SVAR Gantt | 15 |
| ai-live-hub (web) | shadcn, Base UI, Tailwind 4, lucide, recharts | none; its own `components/bits.tsx` |
| aida | AG Grid, AG Charts, Monaco | none; not yet on road-kit (L-02) |

Every app on road-kit uses shadcn, Base UI and Tailwind. The libraries road-kit is missing are the
ones road-planner and ai-live-hub each added for themselves.

ai-live-hub has a working brand override. `web/src/theme/brand.ts` sets about ten tier-1 tokens
(`--bg`, `--surface`, `--border`, `--ink`, `--ink-muted`, `--primary`, the status colours, the fonts
and `--radius-panel`) from a database row. `web/src/app.css` then derives the in-between shades with
`color-mix()`. Ten sector demos share one set of screens this way, each with its own look, and its
build fails if a colour appears outside the token layer.

The drafts for the new hello_world screens are on a design canvas:
https://claude.ai/artifact/4wztTJzttNDT1pLH6Mp2ks. It shows a top bar layout, a sidebar layout,
the session drawer, the sign-in page and a phone view. They use the current `tokens.css` values.

## The stack

| Need | Library | Status |
|---|---|---|
| Components | shadcn/ui on Base UI | Kept from ADR 01 |
| Styling | Tailwind CSS 4 | Kept from ADR 01 |
| Icons | lucide-react | Kept |
| Toasts | sonner, through shadcn's `sonner` component | Added; already in road-planner |
| Command palette and search | cmdk, through shadcn's `command` component | Added; already in road-planner |
| Date picking | react-day-picker and date-fns, through shadcn's `calendar` component | Added; already in road-planner |
| Charts | recharts, through shadcn's `chart` component | Added; already in ai-live-hub |
| Data tables | TanStack Table, following shadcn's data-table example | Added; no app uses it yet |
| Light and dark theme switch | To be decided: next-themes, as road-planner uses, or a small hook in road-kit | Open, see "Rulings" |

An app may add other libraries. A library that replaces one of these is an override under ADR 01
and is recorded in that app's repository.

## Components road-kit ships

These are written once in road-kit and copied into each app (see "Distribution").

- **App shell** with two layouts: a top bar for apps with up to about six sections, and a sidebar
  for larger apps. The layout is set in one place. Below 768 px wide, both layouts show the main
  sections as a bottom tab bar.
- **Account menu**, opened from the user's name. It holds Session details, My agents, API and
  contract, and Sign out.
- **Session drawer.** A side panel with three tabs: Session (principal, current user, database
  user, issuer, audience, scope, authenticated), Connection (API base URL, UI base path, app name)
  and Contract (contract version, `Accept-Version`). Each value has a copy button. This replaces the
  session data on the home page. The `/session` route stays for tests and direct links.
- **Sign-in page** with an app description panel and the sign-in form. It shows the single sign-on
  button, the password form, or both, depending on the auth profile.
- **Page header**, **stat tile**, **status badge**, **empty state**, **segmented control**,
  **notice** (information, warning and error) and **data list** (rows with a checkbox, title,
  secondary line, status and an actions menu).

The status badge always carries a word as well as a colour, as ADR 01's consequence 3 requires.

The data table is not in this first set. quorate's finding still applies: wrapping a table in a
horizontal scroller makes the page scroll sideways at 320 px. The table is built when the first app
needs one, and must pass the 320 px check before road-kit takes it.

## Theme and per-app override

The look is set in three layers. Each layer has one owner.

1. **`src/tokens.css`. Owned by road-kit; apps do not edit it.** It stays byte-identical across
   apps. It holds the role tokens that exist today, with the same names and the same light-theme
   values, so an app that takes the new file looks the same as before. It gains:
   - derived shades, computed with `color-mix()` from the base tokens: a softer ink, a raised
     surface, a hover fill, a primary tint for selected items, and a primary shade for hover;
   - success and information status colours, alongside the existing warning and error sets;
   - five categorical chart colours, checked for contrast against `--surface` in both themes;
   - a dark theme, as a second set of values for the base tokens. It applies under
     `prefers-color-scheme: dark` and under a `.dark` class on the root element, which the theme
     switch sets.

   The exact token names are fixed in the spec patch that builds this, not here.

2. **`src/brand.css`. Owned by the app.** It sets only tokens that `tokens.css` defines. It is
   imported after `tokens.css`, so its values win. A typical file sets `--primary`, the neutral
   colours, `--font-body`, `--radius-panel` and `--radius-control`, and optionally the dark-theme
   values. Because the derived shades are computed from these tokens, changing `--primary` also
   changes the hover, the selected tint and the focus ring. road-kit ships a `brand.css` that
   repeats the house values, so a new app has a file to edit.

3. **`src/components/ui/`. Copied shadcn source, owned by the app once copied.** An app edits a
   component here only when it needs a change in structure or behaviour. Under ADR 01 that is a
   recorded decision.

`hello_world/scripts/check-theme-tokens.mjs` changes to match. Today it requires every colour in the
built stylesheet to be a `tokens.css` value. It will accept a value from `tokens.css` or
`brand.css`, and it will still require `tokens.css` to match road-kit byte for byte. Colours that
`color-mix()` computes in the browser do not appear in the built file, so the check does not need
to know about them.

## Distribution

The shell and components are copied into each app, as `theme.css` and `tokens.css` are today, and
`bin/check-road-kit-parity.sh` lists them.

Later, road-kit can serve them from a shadcn registry, so an app runs `npx shadcn add` with a
road-kit address to get or update a component. ADR 01 already names a registry as the way
road-cal's calendar would travel. Setting up the registry is a separate piece of work and does not
block this ADR.

## Options considered

- **Mantine.** ai-live-hub used it for its subject access request screens and removed it in that
  demo's fix 5 (`ai-live-hub/docs/SAR-FIX-PLAN.md`). It had to be themed separately to match the
  other screens, and it needed an exemption in the colour check. It would mean two styling systems
  in one app.
- **UI SDK** (ui-sdk.dev, Vercel Labs, Apache-2.0). Read on 2026-11-19. It is a library of unstyled
  behaviours (popups, selection, typeahead, focus and keyboard handling) that an agent combines
  into components. It works at the same level as Base UI, below shadcn. It has no theming or
  design tokens, and no app shell, data table or charts. It needs React 19, and it is in beta: its
  changelog has one entry, dated 12 November 2026, and its docs say the APIs may change. Adopting
  it would mean writing every component ourselves, since shadcn's components are written against
  Base UI. Deferred until it leaves beta. Two of its ideas are worth taking now: agent-readable docs
  for the installed version, and a test kit that checks keyboard, focus and ARIA behaviour. The
  second is the kind of check that ADR 01's consequence 3 says the primitives do not provide. Its
  speed and cost figures come from Vercel's own benchmark on one task and were not checked here.
- **Palette from fixed colour scales** (for example Radix Colors, which publishes 12-step scales
  with matched light and dark versions). This gives more predictable shades than `color-mix()`, at
  the cost of a much larger `tokens.css` and a scale-based override in place of a few tokens. Not
  chosen; see "Rulings".
- **Keep ADR 01's order and wait for quorate.** quorate is on hold, and every new app meanwhile
  adds components on its own. Not chosen.

## Consequences

1. **road-kit now designs against hello_world.** ADR 01 warned that components designed against an
   app with no real table would look complete and then drift. This ADR limits that risk in two
   ways. The first set leaves out the data table. And every component must work in the drafts'
   real screens (home, todos, agents, session, sign-in) at 320 px and by keyboard alone before it
   ships.
2. **The accessibility rules in ADR 01's consequence 3 are unchanged.** hello_world gains
   end-to-end checks for keyboard-only use and 320 px reflow on every screen, extending
   `e2e/login.smoke.spec.ts` and `e2e/todos.smoke.spec.ts`.
3. **Every app takes a new `tokens.css`.** Its light-theme values do not change, so the change is
   additive. quorate, road-tracker, road-planner and ai-live-hub fail their parity check until they
   take it.
4. **hello_world retires `styles.css`.** `theme.css` currently keeps it for hello_world's old
   screens. Once those screens are rebuilt, it is deleted.
5. **The browser tests change with the screens.** `e2e/todos.smoke.spec.ts` finds controls by role
   and name ("Add todo", "Edit", "Save", "Done", "Reopen", "Open") and checks the text of the
   stale-edit message. The rebuilt Todos page keeps those names and that text, or the test changes
   in the same commit. The account menu moves Session out of the main nav, so any test that opens
   `/session` from the nav changes too.
6. **quorate's role changes** from developing the components to adopting them. Its findings still
   come back to road-kit on road-atlas §5's test, and the 320 px table remains its to settle.

## Adoption order

1. **road-kit.** Build the tokens, `brand.css`, the shell and the components; rebuild hello_world's
   screens; extend the browser tests. This is one spec patch.
2. **road-tracker.** It is active, has one shadcn component and is road-kit's closest follower. It
   is the first test of whether an app can take the default and change only `brand.css`.
3. **road-planner.** It replaces its own copies of the components that road-kit now ships, and
   keeps its Gantt.
4. **ai-live-hub,** where it uses road-kit's shell. Its demos keep their own brand mechanism, which
   sets the same tokens.
5. **aida** on its rebuild, as ADR 01 planned.
6. **quorate** when it resumes.
7. **road-blogger** last, as ADR 01 planned, because it is the only live system (F-06).

## Atlas changes on acceptance

- **D-02 (made 2026-11-19):** add a dated section saying that road-kit now owns the default components and look,
  with a link to this ADR. Change quorate's consumer note from "develops the vocabulary" to
  "adopts". Add road-tracker and ai-live-hub as consumers.
- **Pattern catalogue:** add the app shell, the account menu with session drawer, and the
  `brand.css` override to road-kit's `PATTERNS.md` in the commit that builds them.
- **Distribution:** copy this ADR to each repository that holds ADR 01.

## Rulings

Simon accepted every proposal on 2026-11-19.

1. **Palette method.** Derived shades with `color-mix()`. Fixed colour scales are not used.
2. **Default layout.** hello_world uses the top bar. The sidebar layout ships as the alternative.
3. **Dark theme default.** The app follows the operating system setting until the user picks a
   theme.
4. **Theme switch.** Still open, because no option was proposed. The spec patch chooses between
   next-themes and a small road-kit hook, and records why.
5. **Default font.** Inter stays the default. Each app can change it in `brand.css`.

## Provenance

Simon, in session, 2026-11-19: road-kit should have a reasonable default set of components and
palette, easily overridden per app. Simon accepted the proposals in "Rulings" the same day. The
drafts on the canvas are the starting point for hello_world's screens; their detail is settled in
the spec patch. The library table was
read from each app's `package.json` and `src/components/ui/` the same day. ai-live-hub's brand
mechanism was read from `web/src/theme/brand.ts` and `web/src/app.css`, and its Mantine removal
from `docs/SAR-FIX-PLAN.md` and `PATTERNS.md`. UI SDK was read from seven pages of ui-sdk.dev and
its GitHub repository on 2026-11-19; its benchmark was not run.
