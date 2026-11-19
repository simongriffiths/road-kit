# Specification Patch 18 — The Default Look, App Shell and Components

**Applies to:** the demo UI only (`hello_world/`): its styles, components, screens, browser tests
and build checks. No database, ORDS or contract change.
**Status:** ruled 19 November 2026: Simon accepted every recommendation in section 11 as written.
Built 19 November 2026 (not released); section 12 records where the build differs from the plan.
**Depends on:** ADR 02 (`planning/adr-02-default-look-and-components.md`, accepted 19 November
2026), spec-patch-17 (the Todos page), spec-patch-15 (the My agents page).
**Rule it keeps:** spec-patch-08 rule 1. The demo may not cause a framework change. Where a screen
in the drafts needs data the API does not provide, this patch shows less (section 11.2) and does
not change the API.

---

## 1. What this is

ADR 02 makes road-kit the owner of the default look and components. This patch builds them in
hello_world, so that an app forked from road-kit starts with a finished-looking app:

- a palette with derived shades, status colours, chart colours and a dark theme, in `tokens.css`;
- a per-app `brand.css` that sets the app's colours, fonts and corner radius;
- an app shell with a top bar layout, a sidebar layout and a phone layout;
- an account menu and a session drawer, which take the session data off the home page;
- a sign-in page, a home page, and the Todos and My agents pages rebuilt with shared components.

The design canvas is the starting point: https://claude.ai/artifact/4wztTJzttNDT1pLH6Mp2ks. Where
this patch and the canvas differ, this patch is right. The canvas shows data the API does not
provide; section 11 says what replaces it.

## 2. Libraries

Added to `hello_world/package.json`:

| Package | Used by |
|---|---|
| `sonner` | Toasts, through shadcn's `sonner` component |
| `cmdk` | shadcn's `command` component, for the search box in the top bar |
| `react-day-picker`, `date-fns` | shadcn's `calendar` and the due-date picker on Todos |
| `recharts` | shadcn's `chart` component. Not used by a screen in this patch; installed so the chart tokens can be checked against it (section 9, test 6) |
| `@tanstack/react-table` | Not installed. ADR 02 leaves the data table out of the first set |

shadcn components added with the CLI (`npx shadcn add`), using the existing `components.json`
(style `base-nova`, Base UI): `avatar`, `badge`, `calendar`, `card`, `chart`, `command`,
`dropdown-menu`, `input`, `label`, `popover`, `separator`, `sheet`, `sidebar`, `skeleton`,
`sonner`, `tabs`, `textarea`, `toggle-group`, `tooltip`. `button` is already there.

The CLI must not rewrite `src/theme.css`. Its header says so; whoever runs the CLI checks the diff
of `theme.css` and reverts anything the CLI added there.

## 3. Tokens and brand

### 3.1 `src/tokens.css`

Every existing token keeps its name and its light value. The file gains the tokens below. Light
values are given where they are new colour choices; derived tokens are computed with `color-mix()`
and carry no new colour.

| Token | Light value | Meaning |
|---|---|---|
| `--ink-soft` | `color-mix(in oklab, var(--ink) 78%, var(--ink-muted))` | Secondary text that must stay dark, such as nav links |
| `--raised` | `color-mix(in oklab, var(--surface), var(--ink) 4%)` | Group headers, the footer of a drawer |
| `--hover` | `color-mix(in oklab, var(--surface), var(--ink) 4%)` | Background of a hovered row or menu item |
| `--primary-soft` | `color-mix(in oklab, var(--primary) 12%, var(--surface))` | Selected item, focus halo, avatar fill |
| `--primary-strong` | `color-mix(in oklab, var(--primary), var(--ink) 25%)` | Primary button on hover, link on hover |
| `--on-primary` | `var(--surface)` | Text on a primary fill |
| `--success-bg`, `--success-fg`, `--success-border` | `#eef6f0`, `#1f5135`, `#b9d7c3` | Accepted, active, done |
| `--info-bg`, `--info-fg`, `--info-border` | `#eef3f9`, `#24456b`, `#bccde2` | Neutral notices; work an agent did |
| `--chart-1` … `--chart-5` | `#2c6f5b`, `#2f5d8a`, `#b26a1c`, `#7a4f9a`, `#a23b3b` | Categorical chart colours |

`--warning-*` and `--error-*` stay as they are. The chart colours are a starting set; test 6 in
section 9 checks each against `--surface` in both themes, and the builder adjusts a value that
fails before shipping.

### 3.2 The dark theme

`tokens.css` gains a second set of values for the base tokens under `:root.dark`: `--ink`,
`--ink-muted`, `--ink-eyebrow`, `--bg`, `--surface`, `--border`, `--border-strong`, `--primary`,
`--divider`, `--scrim`, `--shadow-panel`, the four status sets and the five chart colours. The
derived tokens need no dark values, because they are computed from the base tokens. The builder
chooses the dark values; every pair of text and background tokens must reach 4.5:1 (test 6).

The dark theme applies only through the `.dark` class. Section 4 explains why the class, and not a
`prefers-color-scheme` block, is the single switch.

### 3.3 `src/brand.css`

A new file, owned by the app. It is imported after `tokens.css` in `theme.css`. It may set only
tokens that `tokens.css` defines, in `:root` and `:root.dark`. The copy road-kit ships repeats the
house values for `--primary`, `--font-body`, `--radius-control` and `--radius-panel`, each with a
one-line comment, so a new app has the file to edit.

### 3.4 `src/theme.css`

- Imports `brand.css` after `tokens.css`.
- Maps the new tokens into Tailwind's `@theme inline` block, as `--color-ink-soft`, `--color-raised`,
  `--color-hover`, `--color-primary-soft`, `--color-success`, `--color-info` and so on, and maps
  shadcn's `--chart-1` … `--chart-5` to the chart tokens.
- Sets `--primary-foreground` to `var(--on-primary)`, and `--accent` to `var(--hover)`.
- Removes the comment blocks "NO CHART PALETTE", "NO DARK MODE" and "TIER 2", which this patch
  resolves, and replaces them with a short note pointing at ADR 02.

`theme.css` stays byte-identical across apps; only `brand.css` differs.

### 3.5 `scripts/check-theme-tokens.mjs`

- Parity: `tokens.css` must match road-kit's copy byte for byte, as now. `theme.css` is added to
  the parity check, since it is meant to be shared and nothing checks it today. `brand.css` is not
  compared.
- Literals: every colour in the built stylesheet must be a value written in `tokens.css` or
  `brand.css`.
- New: `brand.css` may set only custom properties that `tokens.css` defines. A property it sets
  that `tokens.css` does not define fails the check, with the property's name.

## 4. The theme switch

A small hook in road-kit, `src/hooks/useTheme.ts`, with no new dependency (ruling 11.1).

- The person's choice is `light`, `dark` or `system`, stored in `localStorage` under
  `road-theme`. The default is `system`.
- When the choice is `system`, the hook follows `matchMedia('(prefers-color-scheme: dark)')` and
  updates when it changes.
- The hook adds or removes the `dark` class on `<html>` and sets `color-scheme` to match.
- `index.html` carries a short inline script that reads `road-theme` and the media query and sets
  the class before the first paint, so a dark-theme user does not see a white flash. The script is
  the only inline script in the app, and the same logic is in `useTheme.ts`.
- The choice is in the account menu, as a three-way toggle: Light, Dark, System.

ADR 02 says the dark theme applies under `prefers-color-scheme: dark` and under the `.dark` class.
This patch uses the class only, set from the media query when the choice is `system`. Two switches
would need a `.light` class to force light on a dark system, and shadcn's `dark:` variant in
`theme.css` already keys on `.dark`. The effect for the person is what ADR 02 describes.

## 5. App identity

A new file, `src/config/app.ts`, owned by the app:

```ts
export const app = {
  name: 'Hello World',
  description: 'One todo list for you and the agents you approve.',
  layout: 'topbar' as 'topbar' | 'sidebar',
  nav: [
    { to: '/', label: 'Home', icon: 'home' },
    { to: '/todos', label: 'Todos', icon: 'list-checks' },
    { to: '/agents', label: 'Agents', icon: 'bot' }
  ]
};
```

`src/components/road/AppMark.tsx` draws the mark beside the name. road-kit's mark is a tick on a
rounded square in `--primary`. An app replaces the file to change its mark.

`index.html`'s `<title>` stays `hello_world`; the page sets `document.title` from `app.name` and
the page name, for example "Todos · Hello World".

## 6. Shell and shared components

Components that road-kit owns go in `src/components/road/`, apart from shadcn's copied source in
`src/components/ui/` and the app's own components. `bin/check-road-kit-parity.sh` lists them.

| Component | What it does |
|---|---|
| `AppShell.tsx` | Renders the layout set in `app.layout`, the skip link, the `<main>` landmark and the toaster |
| `TopBar.tsx` | Mark and name, the nav links, the search box (Todos only, section 7.3), the account button |
| `SideNav.tsx` | The sidebar layout, from shadcn's `sidebar`, with the account button at the foot |
| `TabBar.tsx` | Below 768 px wide, both layouts move the nav into a bottom tab bar; the top bar keeps the mark and the account button |
| `AccountMenu.tsx` | From shadcn's `dropdown-menu`. Holds: the principal; Session details and API and contract, which open the drawer at its Session and Contract tabs; My agents; the Light, Dark, System toggle; Sign out |
| `SessionDrawer.tsx` | From shadcn's `sheet`. Three tabs (section 6.1). Opens from the account menu; Escape and the close button shut it and return focus to the account button |
| `PageHeader.tsx` | Title, one line of description, optional date line, optional actions |
| `StatTile.tsx` | Label, value, one line of note. A tile that shows a warning or error state carries a word for it, not colour alone |
| `StatusBadge.tsx` | A word on a tinted pill: success, info, warning, error or neutral |
| `Notice.tsx` | Information, warning or error message with an icon and an optional action. Replaces the `notice` classes |
| `EmptyState.tsx` | Icon, one sentence and an optional action, for an empty list |
| `DataList.tsx` | A `<ul>` of rows, each with a checkbox or icon, a title, a secondary line, a badge and an actions menu. Optional group headers |
| `SegmentedControl.tsx` | From shadcn's `toggle-group`, for the Open and Done tabs on Todos |

### 6.1 The session drawer

The drawer reads `GET /session/me/` when it opens and shows when it was read, with a Read again
button.

- **Session:** Principal, Current user, Database user, Issuer, Audience, Scope, Authenticated. These
  are the fields `SessionIdentity` already has.
- **Connection:** App name, UI base path, API base URL. The auth profile is not shown: it is a
  server setting (`AUTH_PROFILE` in `config/local.env`) that the browser build does not receive.
- **Contract:** the contract version this client sends (`API_VERSION` in `runtime.ts`) and the
  version the API last answered with, from the envelope.

Each value has a copy button. The footer has Copy all as JSON. A 401 while the drawer is open
follows `client.ts`'s rule: the token is cleared and the person goes to sign-in.

The `/session` route stays, for direct links and tests. It renders the same three sections as a
page.

## 7. Screens

### 7.1 Sign-in (`/login`)

Two panels, which stack below 768 px: on the left, the mark, `app.name`, `app.description` and three
short points about the app; on the right, the form.

- The form shows User name and Password, and a Sign in button. The scaffold profile is the only one
  hello_world supports today, so no single sign-on button is shown (ruling 11.4). A small label
  under the form says "Development sign-in". It is always shown, because the browser build does
  not know the auth profile and the scaffold is the only one it supports.
- The default user name `ADMIN` is removed from the field.
- A refusal shows in a `Notice` above the button, with the message from the API.
- After sign-in the person goes to where they came from, or to Home (`/`). Today they go to
  `/session`.

### 7.2 Home (`/`)

Signed out, Home redirects to `/login`. The current public home page, with build paths and
settings, is removed; its values move to the drawer's Connection tab (ruling 11.5).

Signed in, Home shows:

- **Page header:** "Good morning", "Good afternoon" or "Good evening", by the browser's clock,
  with no name (ruling 11.3); the date; and a line such as "4 todos are due today and 1 is
  overdue." The header action is Add todo, which opens Todos with the add form focused.
- **Stat tiles:** Open, Due today and Overdue. Each is computed from one read of the person's open
  todos (`status=OPEN`, `limit=100`, the API maximum). When the API says there are more, Open shows
  "100+" and the note under Due today and Overdue says "Of your latest 100 open todos" (ruling
  11.2). The canvas's "Done this week" tile and chart are not built.
- **Due today:** a `DataList` of open todos due today or earlier, overdue first, at most eight, with
  a link to Todos. Each row has a Done button that calls the same action as Todos. An empty list
  shows an `EmptyState`.
- **Agents:** the person's active agents from `listAgents()`, each with the time a key was last
  used, or "Not used yet", and a link to My agents. With no agents, an `EmptyState` with a link to
  make one.

### 7.3 Todos (`/todos`)

The page keeps spec-patch-17's behaviour and its hook, `useTodos`. It changes only how it looks:

- `PageHeader` with the New todo action; the add form opens in a `sheet` on a phone and inline
  above the list on a wider screen.
- `SegmentedControl` for Open and Done, with counts from the current page.
- The list is a `DataList`, grouped under Overdue, Today, Later and No date in the Open tab. Groups
  are worked out in the browser from `due_at`, within the current page.
- The search box moves to the page's toolbar. On the top bar layout, the top bar's search box
  goes to Todos with the query filled in.
- The due date uses shadcn's `calendar` in a `popover`, and still sends local midnight with the
  browser's offset (spec-patch-17 ruling 7.7).
- The stale-token message and refusals show in a `Notice`. Accepted actions show a toast.

The test names in section 9 must keep working: buttons named "Add todo", "Edit", "Save", "Done",
"Reopen" and "Open", and the stale-token text "Someone changed this todo while you were looking".

### 7.4 My agents (`/agents`)

Restyled with `PageHeader`, `card`, `StatusBadge` and `Notice`. Its behaviour, labels and test IDs
do not change, so `agents.smoke.spec.ts` passes as it is.

## 8. Code

| File | Change |
|---|---|
| `package.json` | Section 2's packages; `@axe-core/playwright` as a dev dependency (ruling 11.6) |
| `index.html` | The theme script (section 4) |
| `src/tokens.css`, `src/theme.css` | Section 3 |
| `src/brand.css` | New (section 3.3) |
| `src/styles.css` | Deleted, with its import in `main.tsx` (ruling 11.7) |
| `src/config/app.ts` | New (section 5) |
| `src/hooks/useTheme.ts`, `src/hooks/useSession.ts`, `src/hooks/useHomeSummary.ts` | New. `useSession` reads `/session/me/` for the drawer and the `/session` page; `useHomeSummary` reads the open todos and agents for Home |
| `src/components/road/*` | New (section 6) |
| `src/components/ui/*` | Added by the shadcn CLI (section 2) |
| `src/components/todos/*` | Rebuilt with the shared components |
| `src/App.tsx` | Replaced by `AppShell` for signed-in routes; the sign-in page has no shell |
| `src/router.tsx` | Home becomes a protected route; `/login` sits outside the shell |
| `src/pages/*` | Section 7 |
| `scripts/check-theme-tokens.mjs` | Section 3.5 |
| `e2e/*` | Section 9 |
| `../bin/check-road-kit-parity.sh` | Lists `brand.css` as app-owned, and `theme.css`, `useTheme.ts` and `src/components/road/` as road-kit's |
| `../PATTERNS.md` | Section 10 |

`import.meta.env` stays in `src/config/runtime.ts` only, as `validate-build.mjs` requires. The
values the drawer and `router.tsx` need are exported from there. Today `HomePage.tsx` and
`router.tsx` read it directly; `HomePage.tsx` is replaced, and `router.tsx` takes its base path
from `runtime.ts`.

## 9. Tests

All browser tests run against the deployed app, as now, through `bin/run-agent-tests.sh` and
`npm run browser-smoke`.

1. **`login.smoke.spec.ts`** changes: the heading is "Sign in", the button is "Sign in", and after
   sign-in the URL is the app root and the heading is the greeting. It then opens the account
   menu, opens Session details and sees the principal.
2. **`todos.smoke.spec.ts`** passes unchanged. If a step has to change, it changes in the same
   commit and section 12 says why.
3. **`agents.smoke.spec.ts`** passes unchanged.
4. **`shell.smoke.spec.ts`**, new:
   - Home shows the three tiles, and a todo added through the API, due today, appears under Due
     today.
   - Using only the keyboard: the skip link, each nav link, the account menu, the drawer and its
     close all work, and focus returns to the account button.
   - The theme toggle: choosing Dark adds the `dark` class; reloading keeps it; choosing System
     follows an emulated `prefers-color-scheme`.
   - At 320 px wide, Home, Todos, My agents, the drawer and sign-in do not scroll sideways, and the
     nav is in the tab bar.
5. **Accessibility scan**, new: `@axe-core/playwright` on Home, Todos, My agents, the drawer and
   sign-in, in light and dark. No serious or critical findings.
6. **Contrast**, new, in `scripts/check-theme-tokens.mjs`: for both themes, each text token on
   `--bg` and `--surface`, each status foreground on its background, and `--on-primary` on
   `--primary`, reach 4.5:1. Each chart colour reaches 3:1 on `--surface`. The check computes the
   `color-mix()` tokens itself, so it runs without a browser.

The PL/SQL, HTTP and contract suites are unchanged.

## 10. Patterns

In `PATTERNS.md`, in the same commit as the build:

- `theme-token-check` is updated: the brand file, the contrast check and the dark theme.
- New `road-app-shell`: the shell, its two layouts and the phone tab bar.
- New `road-account-menu-session-drawer`: session data behind the account menu.
- New `road-brand-override`: the one file an app edits to change its look.
- `react-auth-shell` is marked `superseded` by `road-app-shell` if the build replaces what it
  describes; otherwise it is updated.

## 11. Rulings (19 November 2026: each recommendation accepted)

### 11.1 The theme switch

ADR 02 ruling 4 leaves this to the patch. **Recommendation:** a small road-kit hook, about forty
lines, with no dependency. next-themes is built for Next.js and handles server rendering, which
these apps do not do. road-planner uses next-themes; it can keep it or move to the hook when it
takes the new shell.

### 11.2 Counts on Home

The todo list API returns at most 100 rows a call, ordered by when each todo was made, and its
`count` is the size of the page, not a total. It has no due-date filter and no summary. Exact counts
need a new governed read in the demo contract, which spec-patch-08 rule 1 keeps out of a UI patch.
**Recommendation:** compute the three tiles from one read of 100 open todos, and say so on screen
when there are more. Drop "Done this week" and the chart. If a real app needs exact counts, a
summary read is a separate patch to the demo contract.

### 11.3 The person's name

`/session/me/` returns the principal, not a display name or an email. **Recommendation:** show the
principal in the account button and menu, with its first two letters as the avatar, and greet
without a name. Display names belong with the identity work quorate owes (atlas B-01).

### 11.4 Single sign-on on the sign-in page

hello_world signs in only through the scaffold profile. **Recommendation:** build the form for the
scaffold only. The single sign-on button arrives with the external OIDC flow in the template
(atlas B-01), and the sign-in page leaves room for it above the form.

### 11.5 The public home page

The current home page is public and shows build settings. **Recommendation:** make Home a signed-in
page and move the settings to the drawer. A signed-out visitor sees the sign-in page, which says
what the app is.

### 11.6 Accessibility scan dependency

**Recommendation:** add `@axe-core/playwright` as a dev dependency. It finds missing labels, roles
and contrast failures that the keyboard and 320 px tests do not, and the shell is what every app
copies. It is not shipped to the browser.

### 11.7 Deleting `styles.css`

`styles.css` is the retired tier 2 and is byte-identical in road-cal and quorate. **Recommendation:**
delete it from hello_world in this patch, once every screen uses the new components.
`check-road-kit-parity.sh` stops listing it. quorate and road-cal keep their copies until they
adopt.

### 11.8 Where road-kit's components live

**Recommendation:** `src/components/road/`. Keeping them apart from `src/components/ui/` shows
which files came from road-kit and which from shadcn, and lets the parity check list one folder.

## 12. Where the build differs from this plan

Built and tested on `ROAD_KIT_DEV` on 19 November 2026. `npm run build` passes, including the
extended theme check. `bin/run-agent-tests.sh --env dev` passes: the agents, surface and road-cli
suites and all nine browser tests (todos and agents unchanged, plus the five new shell
tests, one of which runs twice, once for each theme). Not run: `login.smoke.spec.ts`, which needs
`ROAD_TEST_PASSWORD` (HANDOFF, "Waiting on Simon"); it was updated for the new sign-in page and is
untested.

1. **Files.** The plan's `TopBar.tsx`, `SideNav.tsx` and `TabBar.tsx` are one `AppShell.tsx` and a
   `NavLinks.tsx` (row, column or tab bar), plus `TopSearch.tsx`. shadcn's `sidebar` component was
   not used: it needs its own provider and adds nothing the plain markup lacks. It and its
   `use-mobile` hook were removed after the CLI added them. The sidebar layout was built and looked at
   in a screenshot, but no browser test runs it.
2. **Date picking.** The due date keeps the native date input from spec-patch-17. shadcn's
   `calendar` in a popover was not built; the keyboard test in `todos.smoke.spec.ts` counts the date
   input's tab stops. `calendar`, `command`, `chart`, `dialog` and `input-group` were added by the
   CLI and no screen uses them. `cmdk`, `react-day-picker`, `date-fns` and `recharts` are
   installed for the apps that copy this template.
3. **Add form.** It is always on the Todos page, inline, on every width, not in a sheet on a phone,
   and there is no "New todo" header action. The unchanged test needs `#add-title` in the page.
4. **No toast on Todos.** A toast has `role="status"`, and the unchanged test counts status
   elements to know a notice has gone. Toasts are used only for copy buttons.
5. **Segmented control.** It has no counts, because the unchanged test finds the tabs by their
   exact names "Open" and "Done".
6. **The session is read once** by the shell, for the account button and the drawer, and not each
   time the drawer opens. "Read again" in the drawer reads it again. The Contract tab shows
   `contract_version` if the session body carries it and "not reported" if not; this was not checked
   against the deployed API.
7. **Top bar search** is on every signed-in page at 1024 px and wider, and opens Todos with `?q=`.
8. **Colour check.** shadcn's vendored components carried colours that are in no token. Fixed in
   `theme.css` (the four Tailwind shadows now take the ink colour) and in the vendored source (`sheet`
   and `dialog` overlays use `bg-scrim`; `chart` matches `[stroke$='ccc']`, which is not a colour
   literal). Any component added later may do the same, and the check will name it.
9. **next-themes.** The shadcn CLI installed it for `sonner`. It was removed, and `sonner.tsx` reads
   `useTheme` from road-kit's hook.
10. **Parity.** `bin/check-road-kit-parity.sh` lists framework files, not `hello_world`'s, so
    nothing was added there. `theme.css` parity is checked by `check-theme-tokens.mjs` instead.
    `brand.css` is not compared.
11. **`import.meta.env`.** The plan said it stays in `runtime.ts`. `validate-build.mjs` restricts only
    `VITE_ORDS_BASE_URL`. `runtime.ts` now exports `APP_NAME`, `UI_BASE_PATH` and
    `ROUTER_BASENAME`; `client.ts` still reads `BASE_URL`.
12. **Accessibility findings fixed in the build,** found by axe on the first run: the account button's
    label did not contain its visible text; two `role="search"` forms on one page had no names; the
    sign-in page had no `<main>` and its app name had no contrast on the primary panel; the drawer's
    inactive tabs were too light and its `dl` held a button outside a `dd`.
13. **Contrast.** Every pair in test 6 passes in both themes as written; no colour value in section
    3.1 had to change. The dark values are the builder's choice, as section 3.2 said.

## 13. Out of scope

- The data table (ADR 02).
- A shadcn registry for distributing the components (ADR 02, "Distribution").
- Exact counts and a summary read on the todo API (11.2).
- Display names and single sign-on (11.3, 11.4).
- Marking todos that an agent changed. The list does not say who made a change.
- Adopting the new shell in road-tracker, road-planner or any other app. Each does that in its own
  repository, in the order ADR 02 gives.
- Copying ADR 02 into the other repositories.

## Provenance

Written 19 November 2026 from ADR 02 and the design canvas. Read from the code the same day: the
list query in `db/package_bodies/demo_todo_api.pkb` (limit 25, maximum 100, ordered by
`created_at`, `count` is the page size); `SessionIdentity` in `src/types/api.ts`; the agent fields
in `src/api/agents.ts`; the scaffold-only sign-in in `src/pages/LoginPage.tsx` and
`config/local.env.example`; the selectors in the three `e2e/*.spec.ts` files; the `import.meta.env`
rule in `scripts/validate-build.mjs`; `components.json` (style `base-nova`); React 19.2.5 and shadcn
4.21.0 in `node_modules`. The shadcn component names in section 2 were not checked against the
registry; the builder confirms them when running the CLI.
