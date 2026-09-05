# ADR 01: Default front-end UI stack

- **Status:** Accepted
- **Date:** 2026-09-05
- **Scope:** All ROAD projects — road-kit, road-cal, road-blogger, quorate, aida. road-store is at
  concept stage and has no repository; it inherits this on creation.
- **Canonical home:** road-kit, and copied to each consumer repo — the same arrangement as
  `coding-standards-v1.md` and `ui-theme-standards-v1.md`, for the same reasons and at the same
  cost (§6 of that document).
- **Supersedes** `ui-theme-standards-v1.md` §8, which lists "any component library" as out of
  scope, and retires its tier 2. Tier 1 survives unchanged. See §"What this does to the theme
  standard".

## Decision

shadcn/ui with Tailwind CSS is the default front-end component and styling stack across all
projects.

**One shared vocabulary, extended or overridden only by an active decision.** The intent is that a
component means the same thing in every ROAD application. A repository may extend the vocabulary,
or override part of it, where the project genuinely needs something different — but that is a
decision taken and **recorded in that repository each time**, not a drift that happens by default.
An unrecorded divergence is a defect, not a local preference.

The failure this clause exists to prevent has already happened once, and is documented below.

## Context

Visual design is not an in-house strength. The requirement is a system that supplies consistency
and accessibility without originating a design language from scratch, and that coding agents handle
reliably.

- shadcn/ui copies component source into the repository rather than installing a runtime
  dependency: no version lock-in, components are directly editable.
- Built on accessible primitives (Base UI by default since July 2026; Radix available via
  `--base`). Focus management, keyboard navigation and ARIA are handled by the primitives rather
  than hand-rolled. This is a floor, not a ceiling — see consequence 3.
- Tailwind supplies enforced spacing, type, colour and radius scales — a design system by default,
  without designing one.
- Tailwind is the industry default (State of CSS 2025) and both Tailwind and shadcn/ui are the
  patterns coding agents produce most reliably. shadcn ships an MCP server and agent skills for
  this purpose.
- Theme tokens are expressible as a shadcn preset, making the design direction a portable artefact
  rather than a per-repo re-decision.

### The evidence that a hand-rolled vocabulary did not hold

`ui-theme-standards-v1.md` required `src/styles.css` to be byte-identical across every `road-*`
application, and specified `bin/check-theme-parity.sh` to enforce it. Measured 2026-09-05:

| Repo | `tokens.css` (tier 1) | `styles.css` (tier 2) |
|---|---|---|
| road-kit | canonical, 39 lines | 259 lines |
| road-cal | byte-identical | 259 lines |
| quorate | byte-identical | **497 lines** |
| road-blogger | byte-identical | never adopted tier 2 at all |

Quorate appended 238 lines of app-specific CSS into the file that was required to be identical —
`.button-link`, `.table-scroll`, the sub-640px table-to-card layout, `.visually-hidden`, the
`fieldset` grid fixes. One of its own comments says so out loud: *"this is visibly Quorate's
addition."* `bin/check-theme-parity.sh` **was never created in any repository**, so nothing
detected it.

This ADR therefore ratifies what the files already show rather than abandoning a working standard.
It also explains the shape of the decision above: **tier 1 held because it was small, role-named
and shared; tier 2 drifted because a component vocabulary grows against real screens.** shadcn is
the answer to the second problem — an upstream vocabulary large enough that a repo reaches for
`Badge` rather than inventing `.notice.inline-flag`.

## What this does to the theme standard

`ui-theme-standards-v1.md` had three tiers. Two change.

- **Tier 1 — `src/tokens.css`. Survives, unchanged, and becomes the source of the shadcn theme
  preset.** The 22 role-named tokens are genuinely byte-identical across the family today and are
  the reason four applications look related. shadcn's theme variables are defined in terms of them,
  not alongside them. §1 of that document argued that what converged was the palette and
  typography, not the components; this ADR agrees with it and acts on it.
- **Tier 2 — `src/styles.css`, the nineteen shared classes. Retired.** Replaced by shadcn
  components. The four classes already dead in quorate (`app-shell`, `topbar`, `nav-actions`,
  `nav-link`) go with it.
- **Tier 3 — app-local CSS. Continues, and its one rule is unchanged and now enforced by Tailwind
  as well:** no colour, radius or font-family literal outside the token layer.

`bin/check-theme-parity.sh` is superseded before ever having been written. What replaces it is a
check that `tokens.css` matches road-kit and that no colour literal appears outside it — the half
of the original design that addressed the failure that actually occurs.

## Consequences

1. **Commits the projects to utility classes throughout.**
2. **No automatic component upgrades**; updates are pulled deliberately via the CLI (`--diff`).
3. **The primitives do not discharge the accessibility requirements, and must not be read as
   doing so.** They handle widget-level concerns. Every accessibility defect actually found in
   quorate was at a level the primitives do not reach:
   - 320px reflow (UIX-004 / WCAG 1.4.10) — the page scrolled sideways
   - a data table relaid as one card per row below 640px, with **explicit** ARIA roles, because
     changing `display` on a table element strips its implicit role in most browsers
   - "Late" carried as a word, not by colour alone (WCAG 1.4.1)
   - per-row unique control labels — forty selects all announced as "Type" (WCAG 2.4.6)

   Note that shadcn's `Table` wraps in a horizontal scroller, which is an approach quorate tried
   and rejected: it left the page scrolling sideways. **Adopting this stack does not satisfy
   UIX-004, UIX-005 or UIX-006, and the keyboard-only and 320px end-to-end checks remain
   mandatory** in any repo carrying those requirements.
4. **Every existing application needs retrofitting**, and that work is intended rather than
   optional. See the adoption order below.
5. **Tailwind Labs' commercial position weakened in January 2026** (heavy layoffs, revenue collapse
   attributed to AI-generated code bypassing the docs funnel). Sponsorships followed from Vercel,
   Google AI Studio and others. Assessed as a business-model risk rather than a project risk: the
   framework is MIT-licensed, mature and widely deployed, and shadcn component source lives in our
   repos. Revisit if maintenance visibly stalls.
6. **Two design directions are expected**, sharing type and spacing mechanics but differing in
   density and colour: a consumer direction (road-store, road-blogger) and an administrative
   direction (quorate). Which tokens vary between them is not settled here.

## Adoption order

Retrofit is intended everywhere. The order is not arbitrary — it follows deployment risk and what
each repo is already about to do.

**The setup and the vocabulary are sequenced differently, and that is deliberate.**
`ui-theme-standards-v1.md` §7 said the template adopts first, and for a set of shared CSS classes
that was right. It is not right for a component vocabulary. road-kit is `hello_world`: no real
table, no seven-column screen, no accessibility obligation. A component vocabulary designed there
would be designed against nothing, which is the failure that produced tier 2 — nineteen classes that
looked complete until real screens arrived and quorate quietly appended 238 lines.

So:

1. **road-kit takes the mechanical setup first, and only that.** Tailwind and shadcn installed, and
   the theme preset resolving every shadcn variable to a `tokens.css` token. That is what forks, so
   it goes first and it goes in the template. It is small.
2. **quorate develops the component vocabulary, against real screens.** Its UI layer is being
   rebuilt regardless, it has the most screens, and it is the only repo carrying an external
   accessibility obligation — so it is the only place the hard components can honestly be settled.
   The responsive data table is the clearest case: it cannot be solved in `hello_world`, because
   `hello_world` has no table to solve it against.

   Its existing end-to-end checks (`e2e/diary.a11y.spec.ts`, `e2e/login.smoke.spec.ts`) are extended
   across all screens **before** anything is deleted; they are what makes the rebuild routine rather
   than reckless.

3. **What quorate proves is then backported to road-kit**, on road-atlas §5's test: would a second
   application want it? A responsive table and a status badge, yes. Council publication rules, no.
   Until a component has been through this loop it is quorate's, not the family's.
4. **aida on rebuild — no retrofit.** It has no CSS today and is not yet realigned onto road-kit
   (`L-02`), so it starts clean. That makes it the cheapest honest test of whether the default is
   usable by an app that did not grow it.
5. **road-cal is not a repo migration.** It is parked and being absorbed into quorate (`L-03`), so
   retrofitting it standalone is work with no consumer. Its calendar is extracted as a shadcn
   registry item instead — which is the open question below.
6. **road-blogger last.** It is the largest job (462 lines, 33 bespoke dashboard classes, never
   adopted tier 2) and **it is the only live system** (`F-06`). It changes behind a pattern proven
   in three other repos, not before.

## Not overrides

Components outside shadcn/ui's scope — calendar, tree control, rich-text editing — are additions
styled to the same tokens, not deviations from this decision. An override means using a different
component/styling system for a repository, and per the Decision above it is recorded in that
repository when taken.

## Open

- Extracting road-cal's calendar as a shadcn registry item is the first test of whether front-end
  modules can be distributed between ROAD apps, and it is now also road-cal's entire adoption path.
- Which tokens differ between the consumer and administrative design directions.

## Provenance

Simon, in session, 2026-09-05. The drift table was measured the same day: `diff` of `tokens.css`
across road-kit/road-cal/quorate (identical), `wc -l` of `styles.css` in
`road-kit/hello_world/src`, `road-cal/road_cal/src` and `quorate/quorate_admin/src` (259/259/497),
and the absence of `bin/check-theme-parity.sh` in quorate. The accessibility findings are read from
comments and code in `quorate/quorate_admin/src/styles.css` (the table and `visually-hidden`
sections), `src/pages/DiaryPage.tsx` and `src/pages/DocumentsPage.tsx`.

The Base UI default (July 2026) and the January 2026 Tailwind Labs events are Simon's, taken as
given; they postdate the assistant's knowledge cutoff and were not independently verified here.
