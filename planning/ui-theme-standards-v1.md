# ROAD UI Theme Standards v1

**Shared across every `road-*` application. This file must stay byte-identical in all of them** —
same rule as `coding-standards-v1.md`, and enforced the same way (§6). Never edit it to record a
fact about one repo.

**Canonical home: road-kit.** road-kit is the template the other apps fork from, so the theme's
source of truth lives there and reaches the others by copying.

**Supersedes** `calendar-ui-design-spec-v1.md` §13, which framed this as a possible *backport* from
road-cal to road-kit and told a future session not to action it from road-cal. That framing was
right for two repos that might or might not converge. It is wrong for four applications that are
**intended** to share one design language — Simon, 2026-08-19: "I would be OK with them using the
same UI design language". §13's caution is now friction, and it is why nothing moved between
2026-08-10 and this document.

---

## 1. The correction this document starts from

`calendar-ui-design-spec-v1.md` §13 and the surrounding notes say road-cal **adopted
road-blogger's utility system**, leaving road-kit's sparse editorial scaffold as the lone outlier.

That is not what the files show. Class-name overlap, measured 2026-08-19:

| pair | shared classes |
|---|---|
| road-cal ∩ road-kit | **15** |
| road-cal ∩ road-blogger | **5** |
| road-kit ∩ road-blogger | 4 |

road-cal adopted road-blogger's **visual values** — Inter, `#f6f7f4`, `#1d2522`, tight radii, an
86rem shell — and tokenised them. It kept **road-kit's class vocabulary**. The five names road-cal
and road-blogger actually share are `app-shell`, `notice`, `notice--warning`, `panel`, `topbar`.

road-blogger holds 33 classes nobody else has (`bar-chart`, `kpi-grid`, `segmented-control`,
`status-pill`, `tabs`, `metric`, …). They are dashboard components, not a general system.

**So what converged was the palette and typography, not the components.** That distinction is the
whole design of this document: the values are shared because sharing them is what makes four apps
look like one product; the component vocabularies are mostly not shared, because a calendar grid
and a bar chart are different problems and forcing one vocabulary over both produces a worse
version of each.

## 2. What is shared, and what is not

Three tiers. Only the first two are byte-identical.

| Tier | File | Shared? | Contains |
|---|---|---|---|
| 1. Tokens | `src/tokens.css` | **byte-identical** | Every colour, font, radius, shadow. No selectors but `:root`. |
| 2. Core components | `src/styles.css` | **byte-identical** | The ~19 classes every app of this kind needs. |
| 3. App components | `src/**/*.module.css` and app-local CSS | per-app | Everything else. Consumes tier 1; never redefines it. |

**Tier 3 may not define a colour, radius or font-family literal.** That is the one rule that makes
the design language real rather than aspirational: an app-specific component still gets its
appearance from the shared tokens, so changing `--primary` changes all four apps. A literal hex in
tier 3 is the defect this document exists to prevent, and it is greppable (§6).

## 3. Tier 1 — the tokens

Derived from road-cal's existing 23, which are road-blogger's values with names attached.

```
--font-body  --font-mono
--ink  --ink-muted  --ink-eyebrow
--bg  --surface  --border  --border-strong  --primary
--radius-control  --radius-panel  --radius-pill
--shadow-panel
--warning-bg  --warning-fg  --warning-border
--error-bg    --error-fg    --error-border
--divider  --scrim
```

**22 tokens. Two changes from road-cal's current set, both evidenced rather than assumed:**

- **`--today-tint` is dropped from the shared layer.** Verified used only under `src/calendar/`. It
  is genuinely calendar-specific and belongs in road-cal's own tier 3.
- **`--grid-line` is renamed `--divider` and KEPT.** §13 listed it as calendar-specific alongside
  `--today-tint`. It is not: `src/admin/components/Admin.module.css` uses it for table rules. Since
  `src/admin/` is itself a pre-declared backport to road-kit, a token the admin UI depends on
  cannot live in the calendar's private layer — the backport would arrive referencing a token that
  does not exist. The name was wrong, not the token; it means "subtle divider", and it was named
  after the first place it was used.

That second one is the general lesson: **a token named after where it was first used will be
mistaken for app-specific later.** Name tier 1 tokens for their role.

## 4. Tier 2 — the core components

Nineteen classes, taken from the road-cal ∩ road-kit intersection plus the two road-blogger
contributes:

```
app-shell   auth-form   button      card        card-grid
eyebrow     field       kv          muted       nav-actions
nav-link    notice      notice--error  notice--warning
panel       row         section-heading  stack   topbar
```

**Deliberately excluded, and why:**

- **road-kit's `hero`, `lede`, `masthead`, `status-line`** — the sparse marketing scaffold. Retiring
  these *is* the convergence; carrying them into the shared core would preserve the thing being
  replaced.
- **road-blogger's 33 dashboard classes** — real components, but for one app's problem. If a second
  app needs `kpi-grid`, promote it then, on evidence.
- **road-cal's `wordmark`** — one app, and plausibly per-brand rather than per-theme.

**One reconciliation required before tier 2 can be byte-identical:** road-blogger uses
`page-heading` / `panel-heading` where road-cal and road-kit use `section-heading`. Pick one. This
document does not, because it is a rename in a live app and belongs in the implementation plan.

## 5. Naming convention: BEM-ish `--` modifiers

`.notice--warning`, not `.notice.error`. road-blogger and road-cal both already do this; road-kit's
compound form is the sole holdout, so this ratifies an existing 2-1 majority rather than opening an
argument. road-kit's `.notice.error` becomes `.notice--error` when it takes tier 2.

## 6. Enforcement

**A separate check from the framework parity one.** `bin/check-road-kit-parity.sh` compares
road-cal and road-kit across 54 files of ORDS/PL/SQL framework surface; it is pairwise by
construction and road-blogger is not a participant in that surface. Overloading it would couple two
unrelated scopes.

`bin/check-theme-parity.sh` therefore lives in every `road-*` app and checks exactly two files
against road-kit:

```
src/tokens.css
src/styles.css
```

It additionally greps tier 3 for colour, radius and font-family literals and fails on a hit — the
rule in §2 is worthless unchecked, and unlike the byte comparison it catches the failure that
actually happens in practice.

**What copying costs, stated plainly:** a theme change is four commits in four repos, and nothing
forces the other three to follow. This is the same trade already accepted for
`coding-standards-v1.md` and the framework surface, chosen for the same reason — it uses machinery
that exists and needs no registry, build step or version negotiation. An npm package would be
better once the theme is stable and worse while it is moving.

## 7. Adoption order

Deliberate, because getting it wrong wastes the work:

1. **road-kit takes tiers 1 and 2 first**, and becomes canonical. Everything else forks from it, so
   a half-applied theme there is worse than a late one everywhere else.
2. **road-cal follows** — it is closest already: it has the tokens, needs the rename to `--divider`
   and the `--today-tint` demotion.

   **Done 2026-08-19, tier 1 only.** `tokens.css` is byte-identical with road-kit's; `--today-tint`
   is declared in road-cal's own `styles.css`. **Tier 2 is NOT aligned yet** — road-cal's
   `styles.css` still carries app classes (`wordmark`, the `.notice.error` compatibility selector)
   alongside the core, so the two files are deliberately not identical. Finishing that is a
   separate, larger job: it means finding a home for the app classes first.
3. **road-blogger follows** — the largest job. It has no token layer at all; its 462 lines hardcode
   the values tier 1 names. Its 33 dashboard classes stay exactly where they are.
4. **aida adopts on rebuild.** It has no CSS today and is due a fresh start, so it is the first real
   test of whether tiers 1 and 2 are usable by an app that did not grow them.

**road-kit's admin UI backport waits for step 1 and no longer waits for anything else.** That
backport (`ui-authorisation-design-v1.md`, `build-plan-08` §6) was blocked on "the theme
convergence", which until now named no deliverable and had no owner. Step 1 is that deliverable.

## 8. Out of scope

Dark mode, responsive breakpoint conventions, an icon set, animation/motion tokens, and any
component library. Tokens make dark mode *possible* later — a second `:root` block — which is a
reason to name them by role rather than by value. None of it is designed here.

## 9. Version history

- 2026-08-19 — first version. Supersedes `calendar-ui-design-spec-v1.md` §13.
