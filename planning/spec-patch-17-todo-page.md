# Specification Patch 17 — A Todos Page for the Reference Surface

**Applies to:** the demo UI only (`hello_world/src`, `hello_world/e2e`). No database, ORDS or
contract change: the page calls the governed todo API that spec-patch-16 built.
**Status:** ruled 15 November 2026: Simon accepted every recommendation in section 7 as written.
Built 15 November 2026 (not committed).
**Depends on:** spec-patch-16 (the governed todo surface, contract 0.1.0), spec-patch-15 (the My
agents page, which this page follows).
**Rule it keeps:** spec-patch-08 rule 1. The demo may not cause a framework change. If the page
needs something the API lacks, that is raised separately.

---

## 1. What this is

Spec-patch-16 rebuilt the todo demo as a governed surface, but only as an API. A person can reach it
only through `curl` or the tests; an agent reaches it through `road-cli`. The React app has no page
for it. Spec-patch-16 section 9 item 9 records that its plan assumed a todo page that did not exist.

This patch adds a Todos page. A signed-in person can list their todos, add one, revise it, mark it
done, reopen it and delete it. The page calls the same API, with the same rules, that agents use.

## 2. Why it belongs in the reference

The reference surface shows the server side of a governed action: rules, decision records and read
tokens. It does not yet show the client side, which every application builds again:

- A refusal arrives as HTTP 200 with `decision: rejected`. The page shows it as an answer to what
  the person asked, and does not treat it as an error.
- A stale read token means someone else changed the record. The page shows the record as it now is
  and keeps the person's edit so they can apply it again.
- A create carries an Idempotency-Key that survives a retry and is replaced after an accepted answer.
- The text of a refusal comes from the database (`rejections[].message`). The page holds no copy of
  the rules.

road-tracker's board and item panel already do this (`road_tracker/src/components/tracker/ItemPanel.tsx`,
`settle`). This page brings the same handling into the template in its smallest form.

## 3. The page

Route `/todos`, behind `RequireAuth`. A "Todos" link appears in the top bar when the person is
signed in, beside "Agents".

### 3.1 List

- Calls `GET /todos/` (view `todos.list`). Two tabs: **Open** (`status=OPEN`) and **Done**
  (`status=DONE`). Deleted todos are not shown (7.2).
- A search box sends `query` (ORDS reserves `q`). It searches titles.
- Shows 25 todos at a time. "Show more" fetches the next page with `offset` while `hasMore` is true.
- Each row shows the title, the notes (first line only), the due date if set, and the buttons for
  that row: **Done** or **Reopen**, **Edit**, and **Delete**.
- The list's `read_token` is kept with the list. Every action on a row sends that token.
- An empty tab says "No open todos." or "No done todos."

### 3.2 Add

- A form above the list: title (required, up to 200 characters), notes (optional, up to 4,000), due
  date (optional; see 7.7).
- Sends `POST /todos/` (action `todos.create`) with an Idempotency-Key held in the page's state. The
  key is replaced only after an accepted answer, so a second click or a retry after a network error
  replays the first proposal instead of making a second todo. This is the pattern the My agents page
  uses.
- On acceptance the form clears and the list reloads.

### 3.3 Edit

- **Edit** opens a form in the row with the current title, notes and due date (7.5).
- **Save** sends `POST /todos/{id}/revisions/` (`todos.revise`) with the read token and only the
  fields the person changed. With no change, the page sends nothing and closes the form.
- **Cancel** closes the form.

### 3.4 Done, reopen and delete

- **Done** sends `POST /todos/{id}/completions/`; **Reopen** sends `POST /todos/{id}/reopenings/`.
- **Delete** asks for confirmation with the browser's own dialog, as My agents does for retire and
  revoke. It then sends `DELETE /todos/{id}/` with the read token in the body.

### 3.5 Answers

The page reads every answer in one function, modelled on road-tracker's `settle`:

| Answer | What the page does |
|---|---|
| `accepted` | Clears any notice, closes the edit form, reloads the list. |
| `rejected`, `STALE_TOKEN` | Reloads the list. Shows: "Someone changed this todo while you were looking. The list now shows the change. If you were editing, your edit is still in the form; save it again if it is still right." The edit form stays open with the person's text. |
| `rejected`, any other rule (`TITLE_TAKEN`, `TODO_DONE`, `TODO_NOT_DONE`, `TODO_NOT_FOUND`) | Shows `rejections[].message` as the database wrote it, and reloads the list. |
| 400 | Shows the error `message`. A wrong call from this page is a defect in the page, so the browser test fails on any 400. |
| 401 | The token has expired. The client clears it and sends the person to Login (7.10). |
| 403 | "You are not allowed to do that." |
| Network failure or 5xx | "Something went wrong. Nothing was changed by this page; try again." The Idempotency-Key is kept, so trying again is safe. |

Notices use the existing `notice` class with `role="status"`, so a screen reader announces them.

## 4. Code

Following `spec/react-project-structure-conventions-v1.md` sections 6 and 9:

| File | What it holds |
|---|---|
| `src/api/todos.ts` | Typed calls for the five actions and the list view, like `src/api/agents.ts`. Uses `GovernedOutcome` from `src/types/api.ts`. |
| `src/hooks/useTodos.ts` | The list, its read token, paging, the tab and the search, and the action functions. Section 9.4's pattern (7.1). |
| `src/utils/outcome.ts` | `isStale(outcome)` and `refusalText(outcome)`, so the rule for reading an answer is written once. |
| `src/components/todos/TodoForm.tsx` | The add form and the edit form, which share fields. |
| `src/components/todos/TodoRow.tsx` | One row, its buttons and its edit form. |
| `src/pages/TodosPage.tsx` | Composes the above; holds the notice; the loading and empty states. |
| `src/router.tsx`, `src/App.tsx` | The route and the top-bar link. |

Styling uses the classes that already exist (`panel`, `row`, `field`, `button`, `button ghost`,
`notice`, `muted`) and the existing shadcn `button`. The list is a `<ul>`, so each row reflows on a
narrow screen. No new component is added to the shared vocabulary: ADR-01 gives that work to quorate,
against real screens. `npm run build` must still pass its theme-token check.

## 5. Tests

`hello_world/e2e/todos.smoke.spec.ts`, run by `bin/run-agent-tests.sh` (which already sets
`ROAD_APP_URL` and `TOKEN_USER1` and runs `agents.smoke.spec.ts`). Todo titles start with
`agent-test`, which `test/agents/90_cleanup.sql` already removes for USER1. The test:

1. Adds a todo and sees it in the Open tab.
2. Adds the same title again and sees the `TITLE_TAKEN` message. The list still holds one copy.
3. Edits the title and sees the new title.
4. Opens the edit form, changes the todo through the API from the test (a fresh read, then a
   revision), saves the form, and sees the stale-token notice with the person's text still in the
   form. Saves again and sees it accepted.
5. Marks it done, finds it in the Done tab, reopens it.
6. Deletes it and sees it gone from both tabs.
7. Adds a todo using only the keyboard (7.8).
8. At a 320-pixel-wide viewport, checks that the page does not scroll sideways (7.8).

The PL/SQL and HTTP suites are unchanged; the API does not change.

## 6. Deploy

```bash
(cd hello_world && npm run build)
```

```bash
bin/deploy-react.sh --env dev --app hello_world
```

## 7. Rulings (15 November 2026: each recommendation accepted)

### 7.1 Where the API calls live

The conventions (section 9.2 and 9.4) say pages make no API calls and use hooks. The My agents page
and road-tracker's pages call the API modules from the page. **Recommendation:** follow the written
convention, with `useTodos`, since this is the reference. Leave My agents as it is; moving it is a
separate tidy-up.

### 7.2 Deleted todos

The API can list deleted todos (`status=DELETED`), but no action restores one. **Recommendation:**
show only Open and Done. A Deleted tab would show records the person can do nothing with.

### 7.3 The purge

`todos.purge` needs the reserved permission `todo.purge`, held only by `todo_admin`, which no test
principal holds. **Recommendation:** leave it off this page. An administration page belongs with the
later patch that converts the admin API to decisions (spec-patch-16 section 6.5).

### 7.4 Another owner's todos

A holder of `todo.list_all` may list another principal's todos with `owner`. `todo_admin` holds
`todo.list_all` but not `todo.list`, so it cannot use this page at all. **Recommendation:** leave the
owner filter out.

### 7.5 How editing looks

**Recommendation:** an edit form inside the row. A dialog or side panel would need a component the
template does not have, and ADR-01 leaves new components to quorate.

### 7.6 The Accept-Version header

`src/api/client.ts` sends no `Accept-Version`. The API serves contract major version 0 either way.
**Recommendation:** add `Accept-Version: 0` to every call in `client.ts`, with the value in
`src/config/runtime.ts`. A copied template then sends it from the start, and a later major version
gets a clear 400 `VERSION_MISMATCH`. This also changes what My agents sends, without changing its
behaviour.

### 7.7 The due date

The API takes `due_at` as a date and time with an offset. **Recommendation:** a date input. The page
sends local midnight with the browser's offset, and shows the date only. A time of day adds a time
zone question the demo does not need to answer.

### 7.8 The accessibility checks

road-kit carries no external accessibility obligation, and ADR-01 says the keyboard-only and
320-pixel checks are mandatory only in repositories that do. **Recommendation:** include both in the
browser test anyway. The template is what applications copy, and both checks cost a few lines.

### 7.9 The home page

The home page links to Login and Session only. **Recommendation:** add a link to Todos, and one
sentence saying the page uses the same governed API as the agents.

### 7.10 An expired token

`spec/error-handling-contract-v1.md` section 6.5 says that on a 401 the fetch wrapper clears the
stored token and redirects to Login, with no banner. `src/api/client.ts` does not: it throws an
`ApiError` with status 401, and `RequireAuth` only checks that a token is present. Today a person whose
token has expired sees "Could not load your agents." on My agents. **Recommendation:** make
`client.ts` do what 6.5 says, in this patch, since the Todos page is the first page a person is
likely to keep open past the token's lifetime. This also changes My agents, which then sends the
person to Login instead of showing that message.

## 8. Out of scope

- The purge and any administration view (7.3).
- Live updates when another person or an agent changes a todo. The page reloads after each action
  and on demand; the stale-token check catches a conflict when it happens.
- Restoring a deleted todo, which the contract does not offer.
- New shared components, such as a dialog or a responsive table (ADR-01).
- Retrofitting My agents to the hook pattern (7.1).
