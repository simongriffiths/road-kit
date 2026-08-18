# ROAD Stack Build Lessons

Generalized, technical findings from building road-cal — written to generalize beyond this one
app, so they're reusable on any ROAD-stack project (and liftable into a road-kit skill file with
minimal rework). Kept separate from `calendar-build-instructions.md`, which is the road-cal-specific
build narrative — this doc is the distilled, skill-file-shaped version of what that narrative
uncovered, in the same style as the installed `db@oracle-skills` plugin (fact-per-entry, "why" +
"how to apply", not story). Updated as the build progresses; not a point-in-time snapshot.

Each entry: what breaks, why, the fix. Verified against Oracle AI Database 26ai
(23.26.3.2.0) unless noted.

---

## Oracle MLE (JavaScript in the database)

**MLE call spec parameters cannot declare default values (`PLS-00255`).** Neither the package
spec's public declaration nor the body's `AS MLE MODULE ... SIGNATURE ...` implementation can use
`DEFAULT`, even though an ordinary PL/SQL function/procedure in the same package can. Every caller
must pass all arguments explicitly, using `NULL` for ones that don't apply. Not documented in
Oracle's own MLE JavaScript guide as far as we found it — discovered by hitting the compile error.

**rrule.js's `tzid` option does not reliably produce DST-correct expansion, and this is silent, not
documented.** Tracing the library's source (`iter/index.js` → `rezoneIfNeeded` → `dateutil.js` →
`dateInTimeZone`) shows per-occurrence rezoning works by comparing the occurrence formatted in the
**JS engine's system default timezone** against the same occurrence formatted in the target `tzid`,
then applying the difference. If the engine's default timezone equals the target tzid, that
difference is zero and rezoning silently no-ops — no error, the naive UTC-arithmetic value just
passes through mislabelled as correct. This is not a hypothetical edge case: Oracle MLE's own
default timezone was `Europe/London` on the instance tested, which was also the application's
target tzid — the worst case, hit by default. Separately, `tzid` set on `RRuleSet` instead of
`RRule` has zero effect on `RRULE`-pattern expansion at all (it only rezones explicit
`RDATE`/`EXDATE` entries).
**Fix:** never pass `tzid` to rrule. Let it do pure naive calendar-field arithmetic (its actual
strength, and immune to any timezone concept), then resolve each occurrence's real UTC instant via
a proper IANA-timezone-aware library (luxon) applied to the naive date's UTC-labelled fields. Write
a standing test asserting wall-clock stability across a DST boundary — don't trust this once and
move on, since a future rrule upgrade or a differently-configured host could silently reintroduce
the bug.

**A package function only declared in the body (not the spec) cannot be called from SQL**
(`PLS-00231: function may not be used in SQL`) — this applies even to ordinary PL/SQL helper
functions, not just MLE call specs, whenever that function is invoked from inside a `SELECT`
(including nested inside `JSON_ARRAYAGG`/`JSON_OBJECT VALUE` clauses, or a `WHERE` clause). The fix
is to move the function's declaration into the package spec, even if it's a pure
implementation-detail helper not meant for external callers — note clearly in a comment that it's
spec-exposed only for SQL callability, not part of the public interface. **Easy to reintroduce**:
hit this twice independently in the same build (once for a JSON-building helper, once for a test's
own JSON-extraction helper called inline inside a `WHERE`) — worth a specific check before writing
any test/helper that calls a private function from inside a SQL statement rather than assigning its
result to a variable first.

## SQL/JSON (native `JSON` type, `JSON_OBJECT`, `JSON_VALUE`, `JSON_ARRAY`, `JSON_ARRAYAGG`)

**A JS function returning a plain array/object (no `JSON.stringify()`) marshals correctly to
PL/SQL's native `JSON` return type from an MLE call spec.** Contrast with `BLOB`/`CLOB` MLE
returns, which do need explicit `JSON.stringify()`/serialization on the JS side — the native `JSON`
return type behaves differently. Don't assume stringification is always required; check the actual
declared return type.

**`FORMAT JSON` on a `CASE WHEN ... THEN 'true' ELSE 'false' END` string literal does not produce a
JSON boolean** (`ORA-00932: expression is of data type CHAR, which is incompatible with expected
data type CLOB`). Use a native SQL boolean instead: `CASE WHEN <cond> THEN TRUE ELSE FALSE END`
(no `FORMAT JSON` needed) — `JSON_OBJECT`/`JSON_ARRAYAGG` serialize a native SQL boolean as a JSON
boolean automatically. Oracle 23ai+ has a native SQL `BOOLEAN` type usable directly in `CASE`.

**`COALESCE(JSON_ARRAYAGG(... RETURNING CLOB), JSON_ARRAY())` fails** — the two branches return
different types (CLOB vs native JSON) and `COALESCE` requires matching types. Fix: make both sides
return the same type explicitly — `JSON_ARRAY(RETURNING CLOB)`. Note the `RETURNING` clause goes
**inside** the parens even for a niladic (zero-argument) call; `JSON_ARRAY() RETURNING CLOB` is a
syntax error (`ORA-00907`).

**`JSON_VALUE` called as a bare PL/SQL expression (not inside a `SELECT`) silently misbehaves** with
the `RETURNING` clause and the `.size()` array item method — it returns empty/`NULL` rather than
raising an error, so the failure is invisible unless you check the result. Always route
`JSON_VALUE`/`JSON_QUERY` calls that need `RETURNING` or path item methods through a real SQL
context (`SELECT json_value(...) INTO l_var FROM DUAL`), not a direct PL/SQL expression.

**`JSON_VALUE`'s path argument must be a literal known at parse time — a runtime-concatenated path
string fails** (`ORA-40597: JSON path expression syntax error`), even though the concatenation
itself is a normal runtime operation. Indexing into a JSON array with a variable index (`$[0]`,
`$[1]`, ...) needs `EXECUTE IMMEDIATE` to build a fresh literal path into the SQL text per call —
string concatenation inside a static `SELECT`'s path argument does not work.

**`WHERE <col> MEMBER OF <sys.odcinumberlist variable>` fails to compile inside embedded SQL**
(`ORA-00932: expression is of data type ODCINUMBERLIST, which is incompatible with expected data
type NESTED TABLE`), even though `SYS.ODCINUMBERLIST` is itself a nested table type and `MEMBER
OF`'s whole purpose is nested-table membership. This surfaced building a JSON response that
re-selects rows by a list of ids collected earlier via `BULK COLLECT`/manual `.extend` into a
`SYS.ODCINUMBERLIST` local variable. Fix: `WHERE <col> IN (SELECT column_value FROM
TABLE(<variable>))` instead of `MEMBER OF` — functionally equivalent, compiles fine. Treat `MEMBER
OF` against a locally-declared collection variable (as opposed to a column of that type) as
suspect and default to the `TABLE()` form.

**A JSON key built via `JSON_OBJECT(... 'key' value l_var ... NULL ON NULL)` where `l_var` is SQL
NULL stores an actual JSON scalar `null` at that key — not an absent key.** Reading it back with
`JSON_QUERY(doc, '$.key' RETURNING JSON)` then returns a JSON value that is `IS JSON SCALAR` true
and **is not SQL NULL** (confirmed by direct probe: `l_val IS NULL` → false). A plain `IF p_val IS
NULL THEN RETURN; END IF;` guard therefore silently falls through. Worse, the "obvious" follow-up
guard, `JSON_EXISTS(p_val, '$[*]')`, is *also* true against a JSON scalar null (`$[*]` apparently
treats a lone scalar as satisfying "any array element" in lenient mode), and `JSON_TABLE(p_val,
'$[*]' COLUMNS(...))` against it produces **one row with all columns NULL**, not zero rows — which
then blows up as a not-null constraint violation several statements away from the real cause,
looking unrelated. The reliable guard is `p_val IS NULL OR p_val IS JSON SCALAR` — note `IS JSON
SCALAR`/`ARRAY`/`OBJECT` are SQL-only conditions, not valid inside a plain PL/SQL boolean
expression, so route the check through `SELECT CASE WHEN ... THEN 'Y' ELSE 'N' END INTO l_flag FROM
DUAL` rather than using it directly in an `IF`. General rule: whenever a value that started as "SQL
NULL, meaning absent" gets round-tripped through a `JSON_OBJECT(... NULL ON NULL)` and back out via
`JSON_QUERY(... RETURNING JSON)`, downstream code must handle "JSON scalar null" as a distinct case
from "SQL NULL", not assume they collapse to the same thing.

**A clean "0 invalid objects" check from the apply script is not proof of a working deploy.** A
package body that fails to compile due to embedded-SQL errors (like the `MEMBER OF` case above) can
still show `VALID` in `USER_OBJECTS` at the moment right after `CREATE OR REPLACE`, only flipping to
the true `INVALID` status once something actually forces Oracle to resolve the body — the first real
call to it (`ORA-06508: PL/SQL: could not find program unit being called`, `ORA-04063: package body
... has errors`). Don't trust a status check alone as the deploy gate; always also execute the test
package (or any real call into the object) once before declaring a step done. To debug after the
fact, force resolution explicitly with `DBMS_DDL.ALTER_COMPILE(type, schema, name)` (generic across
object types — package/package body/type/type body/trigger/view — unlike a hardcoded `ALTER PACKAGE
... COMPILE BODY`) and then read `USER_ERRORS` directly.

**`JSON_ARRAY_T.PUT(pos, value)` does not replace an element in place — it inserts, leaving both
the old and new values in the array.** Confirmed with a throwaway probe before relying on it: a
2-element array, with index 1 "replaced" via `PUT`, came out 3 elements long (`[a, b, b-replaced]`,
not `[a, b-replaced]`). If a PL/SQL routine needs to build a `JSON_ARRAY_T` incrementally while
sometimes needing to mutate the *most recently appended* element (e.g. folding continuation text
into the current list item while scanning line-by-line), don't reach for `GET`+`PUT`-by-index to do
that mutation — accumulate the in-progress element's fields as plain scalars in local variables and
only construct the `JSON_OBJECT_T`/`APPEND` it once it's actually complete. Converting a finished
`JSON_ARRAY_T`/`JSON_OBJECT_T` to the native `JSON` type is also not `TREAT(x AS JSON)` (`PLS-00725:
type 'JSON' must be a supertype or subtype of the TREAT expression`) — use `JSON(x.to_clob)` instead
(round-trips through the serialized text, but works).

**`REGEXP_SUBSTR(clob, '[^\n]*', 1, level)` combined with `CONNECT BY LEVEL <= REGEXP_COUNT(clob,
chr(10)) + 1` — a commonly-cited Oracle idiom for splitting a delimited string into "rows" — silently
drops real content when the pattern is zero-or-more (`*`) rather than one-or-more (`+`).** A
zero-or-more character class can match a zero-length string at *every* character position, not only
between delimiters, so as `level` increments through occurrences, spurious empty matches interleave
with the real lines and shift every subsequent line out of alignment. A 3-line input
(`"## Agenda\n- Approve minutes\n- Budget overrun\n"`) produced
`['## Agenda', '', '- Approve minutes', '']` — silently losing the second bullet entirely, with no
error of any kind. This is dangerous specifically because it doesn't fail loudly: a naive test with
only one bullet per section would never catch it. Caught here because a from-scratch parser's own
standalone test suite (10 cases covering multiple bullets) failed 4/10 with plausible-but-wrong
output, not a compile error. Fix: don't use this idiom for a pattern that can match empty. A manual
`DBMS_LOB.INSTR`/`DBMS_LOB.SUBSTR` walk through the CLOB, splitting on each `chr(10)` position
directly, has no such edge case and is barely more code.

**`COUNT(clob_column)` raises `ORA-22849: Type CLOB is not supported for this function or
operator`** — unlike most aggregate functions, `COUNT` doesn't accept a `CLOB` expression directly,
even though counting non-null values is otherwise a completely ordinary use of `COUNT`. Fix:
`COUNT(CASE WHEN clob_column IS NOT NULL THEN 1 END)` instead of `COUNT(clob_column)`.

**`RETURN JSON_OBJECT(... RETURNING CLOB)` used directly as a PL/SQL expression (a bare `RETURN`, or
a plain `:=` assignment) raises `PLS-00684: invalid data type for the JSON return value`** — the same
family as the `JSON_VALUE`-as-bare-expression entry above, but for `JSON_OBJECT` and hitting a hard
compile error instead of a silent wrong answer. Confirmed on Oracle AI Database 26ai
(23.26.3.2.0) building MCP tool functions (`db_agents_and_mcp` skill work). Fix: same pattern as
`JSON_VALUE` — route it through a real SQL context, `SELECT JSON_OBJECT(...) INTO l_var FROM DUAL`,
never a direct PL/SQL-expression `RETURN`/`:=`. Worth checking any function whose only job is
"build and return a JSON_OBJECT" for this before assuming the spec/sample code that inspired it was
ever actually compiled and run.

## PL/SQL general gotchas

**`IF l_col != l_expected THEN raise_application_error(...); END IF;` silently does nothing when
`l_col` is NULL** — three-valued logic means `NULL != <anything>` evaluates to NULL, not TRUE, so
the branch is skipped rather than raising. Hit validating that a referenced row belongs to a given
parent (`instance.series_id = expected series_id`): when the referenced row's own `series_id`
column happened to be NULL (a standalone, non-series instance passed in by mistake), the intended
"reject if it doesn't belong" check let the request through instead of rejecting it. Any equality/
inequality guard whose left-hand side can legitimately be NULL needs an explicit `IS NULL OR`
(or `IS NOT NULL AND`) — don't rely on the comparison alone to catch the NULL case.

**Calling a `FUNCTION` as a bare statement (`pkg.some_function(args);` with no assignment) is a
compile error, not a warning** — PL/SQL functions aren't callable procedure-style by default (that
needs the function declared with a `PRAGMA`/keyword allowing it, which none of this codebase's
functions do). The error (`PLS-00221: '<NAME>' is not a procedure or is undefined`) reads as if the
function doesn't exist at all, which is misleading when the function is right there in the package
spec — the actual problem is the missing assignment target, not a missing declaration. Always
capture a function's return value into a variable, even a throwaway one, when calling it from
another PL/SQL block.

**A `WHERE (col IS NULL OR col = fn_or_pkg.param)`-style "optional filter" guard silently never
matches the "no filter" branch if only the second `col` reference is qualified to the parameter.**
`col IS NULL` unqualified binds to the *table column* (whatever scope resolution finds first), not
the identically-named parameter, even inside the function whose parameter it's meant to be — PL/SQL
column/parameter name collisions resolve per-reference, not per-statement, so qualifying one
occurrence does not carry over to an unqualified sibling in the same expression. If the column
itself is `NOT NULL` (a very common case for a filterable category-type column), that branch is
`FALSE` unconditionally, and the whole `OR` only ever succeeds when the caller supplies an exact
match — "omit to get everything" silently breaks with no error, just an empty/wrong result set.
Caught only by comparing the function's output against an equivalent raw `SELECT` with the same
literal offset/limit — a case worth testing explicitly (call the "optional" filter param as both
`NULL` and a real value) any time a PL/SQL function parameter shares a name with a column it filters
against. Fix: qualify **every** reference to the parameter, not just the equality one —
`fn_or_pkg.param IS NULL OR col = fn_or_pkg.param` — or simpler, avoid the collision entirely by not
naming parameters after the columns they filter.

**A trigger that calls a package function cannot be created before that package's body exists** —
obvious once stated, but easy to violate by accident in a deploy pipeline organized by object *type*
(all triggers together, then all package specs, then all package bodies) rather than by dependency
order. If a trigger needs a package, it has to be deployed as its own step positioned after that
package's body, breaking out of the otherwise-uniform "all triggers in one file" pattern — don't try
to force it back into the type-based file just for consistency.

## PL/SQL testing: autonomous transactions, `SAVEPOINT`, and cleanup

**Autonomous-transaction writes (audit/log rows via `PRAGMA AUTONOMOUS_TRANSACTION`) are not undone
by the calling transaction's `ROLLBACK TO SAVEPOINT`.** They're committed independently the moment
the autonomous block commits. Any test that calls a procedure with this pragma (issuing a read
token, writing an error log, etc.) must clean up those specific rows itself, explicitly — the
standard `SAVEPOINT`/`ROLLBACK TO SAVEPOINT` test-isolation pattern does not cover them.

**The cleanup `COMMIT` needed to make that explicit `DELETE` durable also commits *everything else
pending in the same transaction*** — including any other fixture rows the test inserted earlier in
its own (non-autonomous) transaction, which up to that point were still protected by the outer
`SAVEPOINT`. This is easy to miss: the test appears correctly isolated (it does clean up the one
row type that motivated the `COMMIT`) while silently leaking every other fixture row it created,
which then corrupts later test runs in ways that look like logic bugs (e.g. a range query
returning 4 rows instead of an expected 2, because two stale rows from a prior run's leaked
fixtures matched the query too). **Rule: any test that must `COMMIT` for one reason must explicitly
clean up every row it created in that same transaction, not just the row that forced the commit.**

**After such a commit, the test runner's own `ROLLBACK TO SAVEPOINT` may legitimately fail**
(`ORA-01086: savepoint 'X' never established in this session or is invalid`) because the commit
already cleared it. This is expected, not a bug — wrap the rollback in its own handler that
tolerates `ORA-01086` specifically and re-raises anything else, rather than letting it kill the
test run.

## `DBMS_VECTOR` / ONNX model loading

**A model loaded under a spike-suffixed name (e.g. `_SPIKE`) during a Phase 0 spike is dropped at
the end of that spike, by design** — the real, permanently-named model still needs its own
deployment step later. Easy to forget once the spike has "proven the mechanism works": the actual
production load didn't happen until a downstream feature's compile failed with `ORA-40284: model
does not exist`. Treat "spike proved the loading mechanism" and "the model is actually loaded" as
two separate facts, and write the permanent setup script (idempotent, drop-and-reload,
dimension-asserting) as its own deliverable rather than assuming the spike's throwaway object
covers it.

**`DBMS_CLOUD.GET_OBJECT(credential_name => NULL, object_uri => <public URL>)` fetches an object
server-side straight into a `BLOB` variable** — no OCI bucket of your own, no local download, no
`DIRECTORY` object, no chunked/hex-encoded upload script. Pass that `BLOB` directly to
`DBMS_VECTOR.LOAD_ONNX_MODEL(model_name => ..., model_data => l_blob)`. This is simpler than the
`DIRECTORY`-based flow Oracle's own documentation demonstrates for prebuilt models, and simpler
than a client-side chunked-BLOB upload script. Prefer it as the default loading method.

**Official "prebuilt model" download links are not necessarily stable or long-lived** — a
well-known, widely-blogged Oracle object-storage URL for one embedding model returned a genuine
`ObjectNotFound` from OCI (not just an HTTP 404 page) despite being corroborated identically across
multiple independent, reputable sources. Verify a download link is actually live (a `HEAD`/`GET`
request, checking for a real 200 and sane `Content-Length`) before building anything around it, and
don't assume a link that worked in a year-old blog post still works now.

**A freshly provisioned schema is very likely missing privileges beyond the baseline `CREATE
PROCEDURE`/`CREATE TABLE` set** — hit and granted, one at a time, as each was needed: `CREATE MLE`
(for `mle create-module`/`CREATE MLE ENV`), `EXECUTE ON DBMS_CLOUD` (for `GET_OBJECT`), `CREATE
MINING MODEL` (for `DBMS_VECTOR.LOAD_ONNX_MODEL` to persist the model object). Expect to need an
admin-privileged connection for these one-time grants; they don't appear until the corresponding
feature is actually exercised, so a clean compile earlier doesn't mean all privileges are in place.

**`USER_MINING_MODEL_ATTRIBUTES.VECTOR_INFO` is plain `VARCHAR2(56)` text** (e.g.
`"VECTOR(384,FLOAT32)"`), not a structured/object type — confirmed via `DESC`. Extracting the
dimension for an assertion needs a regexp (`REGEXP_SUBSTR(vector_info, '[0-9]+')`), not
dot-notation on a `dimensions` attribute (which doesn't exist).

## PL/SQL DML and parallelism

**`ORA-12860: deadlock detected while waiting for a sibling row lock` on a small `INSERT ...
SELECT ... FROM JSON_TABLE(...)`** — Oracle can choose to auto-parallelize an `INSERT ... SELECT`
even for a handful of rows, and the parallel DML slave processes inserting into the same table from
the same statement can deadlock each other. A few-row insert never benefits from parallelism
anyway. Fix: an inline `NO_PARALLEL` hint on the insert (`INSERT /*+ NO_PARALLEL(target_table) */
INTO ...`). **Cross-project corroboration**: hit independently in road-blogger's site-search
indexing code around the same time frame (`ORA-12860` inside `SITE_SEARCH_API` during Hugo content
indexing) — found via that project's `logs/` history after it became cross-machine visible (see
the `logs/`-tracked-in-git decision). Worth defaulting to `NO_PARALLEL` on any `INSERT ... SELECT`
that's expected to handle a small, bounded number of rows (invitee lists, tag lists, any
child-table fan-out from a JSON array), rather than discovering the deadlock empirically each time.

**The same deadlock applies to `UPDATE`/`DELETE`, not just `INSERT ... SELECT`.** Hit again on a
plain `UPDATE event_instances SET series_id = ..., start_ts = ... WHERE series_id = ... AND
status = 'NORMAL' AND start_ts >= ...` reassigning a handful of rows to a new parent, and again on
`DELETE FROM event_series WHERE NOT EXISTS (SELECT 1 FROM event_instances ...)` cleaning up a
handful of orphaned rows — both `ORA-12801`/`ORA-12860`, both fixed the same way (`UPDATE /*+
NO_PARALLEL(alias) */ ...` / `DELETE /*+ NO_PARALLEL(alias) */ ...`). Treat this as a property of
"small bounded DML that Oracle might auto-parallelize," not something specific to `INSERT`.

**Before reaching for a `NO_PARALLEL` hint, check whether the deadlocking DML is even
necessary.** Three test-fixture cleanups hit the same `ORA-12801`/`ORA-12860` from an explicit
`DELETE FROM event_invitees WHERE instance_id IN (...)` written directly into test bodies before
calling the shared `cleanup()` helper — but `EVENT_INVITEES`'s FK to `EVENT_INSTANCES` already has
`ON DELETE CASCADE`, so `cleanup()`'s own instance delete was already removing those rows. The
explicit pre-delete was both redundant and the actual thing deadlocking; deleting it (rather than
hint-patching it) was the right fix, and it also matches how every other test in the suite already
relies on the cascade rather than deleting child rows by hand. `NO_PARALLEL` is the right fix for
DML that has to exist; check for a redundant/replaceable statement first.

## Environment tooling

**SQLcl's launcher hardcodes `-Xmx2G`, and this is not overridable via `JAVA_TOOL_OPTIONS`** — the
hardcoded command-line `-Xmx2G` wins over any JVM options supplied through the environment. A large
generated SQL script (e.g. a naive chunked-hex BLOB upload of a >100MB file) can OOM the SQLcl
parser outright. If you must generate a large script, minimize its size directly: avoid duplicating
large literals across statements (e.g. don't re-derive a byte length from a second copy of the same
hex string — compute it once, pass it as a plain integer), and use fewer, larger statements rather
than many small ones. Better: avoid generating a large client-side script at all — see the
`DBMS_CLOUD.GET_OBJECT` entry above, which sidesteps this class of problem entirely for anything
reachable by URL.

**Cross-project corroboration (found 2026-08-08, after road-cal's `logs/` policy change made
cross-repo history visible for the first time).** `road-blogger` independently hit the *exact same*
failure back on 2026-06-01, attempting the *exact same* pattern — a chunked hex-encoded `BLOB`
upload of an ONNX model (`ALL_MINILM_L6_V2`, ~90MB) via a generated temp script. Two of three
attempts failed with the identical `java.lang.OutOfMemoryError: Java heap space`; the third was
seemingly abandoned (killed manually, no error in the log) after producing far too little progress
for the elapsed time. **The ONNX model was never successfully loaded in road-blogger** — a
downstream test later reports `PASS: Configured embedding model exists`, but that only checks an
`app_config` text setting, not that a real model object exists in `USER_MINING_MODELS`; no
`MODEL_LOADED`/successful `LOAD_ONNX_MODEL` output appears anywhere in that project's run history.
This means the `install-embedding-model.sh` chunked-BLOB approach has now failed identically in two
independent projects, months apart — strong, independent confirmation that it's a structural
problem with the approach (not a one-off environment quirk), and that `DBMS_CLOUD.GET_OBJECT`
(above) should be the default for any future ROAD-stack project needing this, not a from-scratch
chunked-BLOB script. Also surfaces the value of the `logs/`-tracked-in-git decision itself: this
finding was invisible until that history became readable from a different machine.

**`bin/run-sql.sh` (vendored from the sql-runner skill — don't hand-edit it; see its own "not to be
hand-edited" note) sets `SET DEFINE OFF` for the whole outer session and does not pass any CLI
arguments through to `@script`.** This rules out both of SQLcl's normal script-parameterization
mechanisms: `&1`/`&2` positional substitution (nothing to substitute from) and plain `&var`
substitution (disabled). Editing `DEFINE var = '...'` lines at the top of the script before each run
technically works but reintroduces the original "unique script per use" problem in miniature (a file
edit is still required every time). **Better: a thin bash wrapper in `bin/` that takes real CLI
arguments, generates a small temp `.sql` file with those arguments interpolated directly into the
SQL text, and calls `bin/run-sql.sh --script <temp file>`** — this keeps `run-sql.sh` as the actual
executor (so logging/run-history capture still happens) while doing the parameterization in bash
instead of SQLcl substitution variables. `bin/` already hosts other non-vendored project scripts
alongside sql-runner's own (`trim-large-logs.sh`, `get-test-token.sh`), so this fits existing
convention; `scratch/` does not work for this purpose since it's entirely gitignored (see below).

**A temp file generated under `scratch/` for a wrapper script like the above is fine to leave
gitignored/ephemeral — `scratch/` is never committed, confirmed via `.gitignore` (`scratch/` as a
whole line).** This has a real consequence: anything meant to be *reusable* (a script future
sessions or other machines should find) cannot live in `scratch/`, no matter how generic it's
written to be — it has to go in a tracked directory (`bin/`, `db/`, etc.) or it effectively
disappears the moment the local checkout is gone.

**BSD `mktemp` (macOS) only randomizes a *trailing* run of `X`s — a template with a suffix after
the `X` block (e.g. `mktemp .../name.XXXXXX.sql`) is not substituted at all**, and `mktemp` still
exits 0 and prints/creates a file at the literal, unmodified path. This is silent: no error, just
every invocation reusing the exact same filename (clobbering itself on the next call) instead of
getting a fresh unique name. Fix: `mktemp` without the suffix (`.../name.XXXXXX`), then `mv` to
append the extension afterward if one is needed for the tool being invoked (e.g. SQLcl doesn't
actually require a `.sql` extension, but it's nice for readability in logs).

**A new SQLcl saved connection created via a bare `connect -save <name> -savepwd
user/pw@<tns_alias>` does not inherit the per-connection wallet association that an existing
wallet-based connection (e.g. one originally set up via SQL Developer / cloud config import) has** —
`connmgr show` on the new connection is missing the `oracle.net.wallet_location`/`TNSNAMES.ORA`/`TNS
Descriptor` lines entirely, and connecting via `-name` then fails with `ORA-12263: Failed to access
tnsnames.ora` unless `TNS_ADMIN` happens to be set in the shell's environment — which existing,
correctly-wired connections (e.g. an `ADMIN` connection already in use for other project work) do
**not** need. Exporting `TNS_ADMIN` is a workaround, not a fix, and doesn't survive between separate
non-interactive shell invocations (no persistent shell state) — reintroducing the same failure on
every subsequent script run. The actual fix: create the new connection via `connmgr clone -original
<existing-wallet-connection> -username <new-user> <new-name>`, which does carry over the wallet
association; getting the *password* to persist on a cloned connection via the SQLcl CLI wasn't
found from `HELP CONNECT`/`CONNMGR` alone in an automated session — needed manual, interactive
resolution outside the agent loop. Treat "new schema needs its own saved SQLcl connection,
same underlying database as one already working" as a task worth flagging for manual setup rather
than grinding through automatically.

## MCP tool servers on ADB Serverless (`DBMS_CLOUD_AI_AGENT`)

Findings from a throwaway spike (`spec/spike-adb-mcp-server.md` /
`spec/spike-adb-mcp-findings.md`) proving out ADB's built-in MCP server, kept here in generalized
form since road-cal is building on this going forward.

**`USER_CLOUD_AI_AGENT_TOOLS` does not exist as a dictionary view on Oracle AI Database 26ai
(23.26.3.2.0), despite being cited in Oracle's own sample verification SQL.** Neither `all_views`,
`dba_views`, nor `all_tables` has any object matching `%CLOUD_AI_AGENT%` other than the
`DBMS_CLOUD_AI_AGENT` package synonym itself. `DBMS_CLOUD_AI_AGENT.LIST_TOOLS(team_name)` exists but
is team-scoped and raises `ORA-20053: Team name must be provided` for standalone tools registered
without a team. The working substitute for "is this tool registered and enabled":
`DBMS_CLOUD_AI_AGENT.GET_DEFINITION('TOOL', tool_name, NULL)`, which returns the tool's original
`CREATE_TOOL` call text including its current `status`.

**The `SYS_CONTEXT` namespace that actually carries the MCP caller's identity is
`MCP_SERVER_ACCESS_CONTEXT$` — with a trailing `$` — which matches *neither* of the two names
Oracle's own docs use interchangeably (`MCP_SERVER_ACCESS_CONTEXT`, `MCP_SERVER_CONTEXT$`).** Both
documented variants return `NULL` silently rather than erroring (normal `SYS_CONTEXT` behaviour for
an unrecognized namespace), so there's no diagnostic signal pointing at the real name — it has to be
found by brute-force trying variants. Standard `USERENV` attributes are not useful for this purpose
during an MCP-invoked call: `SESSION_USER`/`AUTHENTICATED_IDENTITY` show the internal ADB service
account (`C##CLOUD$SERVICE`), not the calling database user, and `CURRENT_USER` shows the function's
definer (owner schema), not the caller either — a VPD policy must key off
`MCP_SERVER_ACCESS_CONTEXT$.USER_IDENTITY` specifically, not any `USERENV` attribute. Confirmed
identical across both the bearer-token auth path and the interactive OAuth path.

**`DBMS_CLOUD_AI_AGENT.CREATE_TOOL`'s generated MCP `inputSchema` marks every parameter
`"required": true`, regardless of whether the underlying PL/SQL function treats it as optional (e.g.
via `NVL(param, default)`), and the server enforces that schema.** Omitting an "optional" parameter
from a `tools/call` fails with `ORA-20001: Required parameter '<NAME>' ... not provided in JSON
input`. Passing an explicit JSON `null` is worse — it crashes the server outright (HTTP 500 with a
raw, unhandled Java stack trace leaked in the response body), rather than returning a clean
JSON-RPC error or an in-band `isError: true` tool result. The only way found to get "treat this as
absent" behaviour through to the PL/SQL layer's own NULL-handling is to pass an **empty string**
`""`, which the MCP bridge evidently converts to a PL/SQL `NULL` bind. Any tool whose PL/SQL
signature relies on `NULL` meaning "no filter"/"use default" needs its description and any calling
client's expectations built around "pass empty string," not "omit the field."

**Tool parameter name casing is not preserved from registration through to the client-visible
schema** — registering `tool_inputs` with lowercase names matching the PL/SQL parameter names
(matching the function signature exactly) causes no registration error, but the `inputSchema`
returned by `tools/list` reports all parameter names **uppercased** regardless. A client builds its
`tools/call` arguments from what `tools/list` shows it, so this is transparent in practice, but
don't assume the case used at `CREATE_TOOL` time is what will actually appear on the wire.

## npm / frontend dependency tooling

**`npm audit` reports on npm's bookkeeping, not on what is actually on disk — and the two can
silently disagree.** Found 2026-08-10 pinning road-cal's frontend deps before Phase 3.

Sequence: `package.json` had `react`/`react-dom`/`react-router-dom` (and six devDeps) at `"latest"`.
Pinning them to caret ranges of the installed versions, then `npm audit`, reported **5 high-severity
advisories** (react-router RCE/CSRF/open-redirect, vite `server.fs.deny` bypass, postcss path
traversal, nanoid). `npm audit fix` reported "up to date" and then **"found 0 vulnerabilities"** —
but the installed version numbers had not changed.

What had actually happened: `audit fix` updated **`package-lock.json`** (react-router-dom
7.14.1 → 7.18.2, vite 8.0.9 → 8.2.1, postcss and nanoid likewise) **and `node_modules/.package-lock.json`**,
npm's record of the installed tree — but never wrote the new package files. So:

- `npm ls` said `react-router-dom@7.18.2`, `vite@8.2.1`
- `node_modules/react-router-dom/package.json` said `7.14.1`; `node_modules/vite/package.json` said `8.0.9`
- `./node_modules/.bin/vite --version` said `8.0.9` — the binary agreed with the disk, not with npm
- `npm audit` read the metadata and reported **clean, while every vulnerable file was still present**

A subsequent `npm install` did *not* reconcile it: npm compares the lockfile against
`node_modules/.package-lock.json`, sees them agree, and concludes there is nothing to do. The
divergence is self-sustaining.

**Lesson, and it generalizes past this one incident**: a clean `npm audit` is evidence about
metadata, not about code — exactly the same shape as the Oracle lesson that a clean
"0 invalid objects" check does not prove a working deploy (see the `bin/deploy-and-test.sh` entry
below, and Phase 1 step 7's `ORA-06508`). In both cases the tool reports on a *record* of the state
rather than the state.

**Verify, don't trust:**

```bash
grep -m1 '"version"' node_modules/<pkg>/package.json   # the disk
./node_modules/.bin/<tool> --version                   # the binary's own claim
```

**Fix**: `npm ci`, which deletes `node_modules` and installs strictly from the lockfile, rather than
`npm install`, which trusts the metadata. After it, disk, binary and audit all agreed. Then rebuild
and confirm the build output actually changed — road-cal's `vite build` banner went from
`vite v8.0.9` to `vite v8.2.1` and the emitted JS hash changed (`index-Cpjk2AnI.js` →
`index-xvQeCTK3.js`), which is what proves the rebuild used the new dependencies rather than
reprinting a cached result.

**Also**: `"latest"` in `package.json` is not a version and gives the lockfile nothing to anchor to.
Pin to caret ranges before adding any dependency with peer-version expectations.

## ORDS (REST layer)

**`l_var := JSON_OBJECT(...)` / `JSON_MERGEPATCH(...)` as a bare PL/SQL assignment fails or
misbehaves — same underlying class of bug as `JSON_VALUE`'s bare-expression gotcha, but hitting
different functions and different failure modes.** `JSON_OBJECT` raises `PLS-00382: expression is
of wrong type`; `JSON_MERGEPATCH` raises `PLS-00201: identifier 'JSON_MERGEPATCH' must be declared`
(it isn't overloaded for direct PL/SQL use at all, only for SQL contexts). Both work correctly via
`SELECT ... INTO l_var FROM DUAL`. Under ORDS specifically, this doesn't surface as a normal
compile error at deploy time — `ords.define_handler`'s source is stored as text and only
parsed/compiled per request, so a bare-assignment bug like this makes *every single call* to that
handler fail with a generic `ORDS-25001`/HTTP 555 "UserDefinedResourceError", before the handler's
own `EXCEPTION WHEN OTHERS` block ever runs. Treat this as the general rule now: **never assign the
result of `JSON_OBJECT`, `JSON_ARRAY`, `JSON_MERGEPATCH`, `JSON_VALUE`, or `JSON_QUERY` directly to
a PL/SQL variable — always route through a `SELECT ... INTO ... FROM DUAL`.** `JSON(text)` (the
plain constructor, parsing a string) is the one exception that's fine bare.

**ORDS reserves the query-string parameter name `q` globally, for its own AutoREST JSON-filter
syntax, and rejects any non-JSON value with a platform-level 400** — confirmed this applies even
to a plain `ords.source_type_plsql` handler (not an AutoREST-enabled table/view resource), even
with an explicit `ords.define_parameter` declaration for `q`, and even when `q` is the *only* query
parameter on the request (so it's not an interaction with other parameters). No workaround found.
If an API design calls for a free-text search parameter named `q`, rename it at the HTTP layer
(`query`, `search`, `text`, ...) — the underlying PL/SQL package's own field name doesn't need to
change, only the ORDS handler's external binding.

**A path-parameter URI template written in RFC 6570 curly-brace style (`{id}/`) silently breaks
ORDS routing the instant a query string is appended to the request** — `GET /resource/123/` routes
correctly, `GET /resource/123/?foo=bar` returns a generic ORDS-level 404 (not from the handler's own
PL/SQL — it never runs), for every HTTP method, with or without an explicit
`ords.define_parameter` for the query key or even the path key itself. This is a serious trap for
any endpoint needing `path-param + query-string` together (a `DELETE .../{id}?token=` pattern is a
completely ordinary REST shape). **Fix: use the colon-prefixed template style instead
(`:id/`)** — same ORDS routing engine, different template syntax, no routing bug observed. Prefer
colon-style path templates over curly-brace ones in this stack generally, not just when a query
string is involved, until/unless the curly-brace behavior is understood.

**Setting a custom response header (e.g. `Location` on a 201) via the classic Oracle Web
Toolkit/mod_plsql idiom — `owa_util.status_line(p_status, p_close_header => FALSE)`, then raw
`htp.p('Header-Name: value')`, then `owa_util.http_header_close` — produces the same
`ORDS-25001`/HTTP 555 stored-source failure under ORDS's PL/SQL handler execution model, even
though it's a legitimate, well-documented pattern in other Oracle web contexts (mod_plsql, APEX
process code).** The correct ORDS-specific mechanism is `ords.define_parameter` with
`p_source_type => 'HEADER'` and `p_access_method => 'OUT'`, bound to a PL/SQL variable that the
handler simply assigns (`:location := '/events/' || l_id;`) — ORDS handles emitting the actual HTTP
header. This is the same mechanism already used for outbound JSON response fields (`p_source_type
=> 'RESPONSE'`) in this codebase's pre-existing `auth` module; the header case just swaps the
source type.

**`ords.define_parameter`'s `p_source_type` for an inbound query-string or path-template value is
the literal string `'URI'`** — not `'QUERY_STRING'` or `'QUERY'` (both plausible-sounding guesses,
both rejected by a check constraint, `ORDS_METADATA.REST_PARAMS_SOURCE_TYPE_CK`, whose actual
allowed-value list isn't surfaced in any `USER_ORDS_*` view). `'HEADER'` and `'RESPONSE'` are
correct as named. When ORDS metadata needs inspecting directly (e.g. to see what's already
registered for a module), `USER_ORDS_PARAMETERS` is queryable and useful, even though
`USER_VIEWS`/`ALL_TAB_COLUMNS` lookups for `'%ORDS%'` don't reliably surface it or its related
views by name — query it directly by its known name rather than trying to discover it first.

**A "clean SQL deploy" is not sufficient proof of a working ORDS handler, for the same reason a
clean `USER_OBJECTS` status isn't sufficient proof of a working package body (see the SQL/JSON
section above).** `ords.define_handler`'s source is stored as text; nothing compiles or runs it
until an actual HTTP request arrives. Every one of the bugs in this section (bare JSON
assignments, the `q` reservation, curly-brace routing, the `Location` header) deployed without
error and were only found by making real HTTP calls against the live endpoint. Always verify a new
ORDS module with actual `curl`/HTTP-level tests, not just a successful `ords.define_*` deploy
script.

## Recurring pattern, now a helper: `bin/deploy-and-test.sh`

Every Phase 1/2 build step in this project (9+ of them) hand-wrote its own
`scratch/phaseN-*-apply.sql` with the identical shape: `@`-include a list of package spec/body
files in order, check `USER_OBJECTS` for any that ended up `INVALID`, `EXEC` a test package's
`run_all`, then report leftover-row counts across a handful of tables. Generalized into
`bin/deploy-and-test.sh --env <name> --file <path>... [--object <name>...] --test-package <name>
[--check-table <name>...]` — generates that same script from flags (following the
`bin/debug-compile-errors.sh` pattern: temp file under `scratch/`, cleaned up via `trap`) and runs
it through `bin/run-sql.sh`. Built in road-cal's `bin/` first, matching how `ROAD_AUDIT_API` and
`bin/debug-compile-errors.sh` were built here before being flagged as road-kit extraction
candidates — promote once proven on a second project.

A closely related but messier pattern (worth a future helper, not yet built): ad hoc fixture-row
cleanup scripts (`DELETE FROM <table> WHERE <predicate>; COMMIT;` against event tables, by title
pattern / explicit id / orphan-series detection) recurred about as often as the deploy-and-test
pattern but with much more varied predicates — less mechanically uniform, so a generic wrapper
would need real thought about what predicate shapes to support rather than a straight
flags-to-SQL translation.

## Config correctness and the tests that check it

**ORDS JWT validation depends on a URL it actually fetches (`jwk_url`), not just strings it
compares (`iss`, `aud`) — and the two fail in completely different, easily confused ways.** A JWT
`iss` is an opaque identifier: ORDS compares the token's claim against the registered profile and
never dereferences it, so a *fictional* issuer validates perfectly as long as both sides share the
fiction. In this stack both sides read the same `JWT_SCAFFOLD_CONFIG` row, so `iss` can never be
the discriminator — it is structurally incapable of mismatching. `jwk_url` is the opposite: ORDS
fetches it over the network at validation time to get the public key. Point it at a host that
returns 404 and every protected endpoint returns a generic `401 Unauthorized` with nothing
distinguishing it from an expired or forged token. When debugging a 401 that "should" work, check
whether the JWKS URL resolves *before* reasoning about claims. (Cost: a whole session chasing an
issuer mismatch that was not, and could not have been, the cause.)

**`ords_security.create_jwt_profile` snapshots its config — it is not a view over it.** Updating
the row the profile was built from changes nothing until the profile is re-registered. Fixing the
config and re-testing therefore *still fails*, which reads as "my fix didn't work" and invites
undoing a correct change. Keep config seeding and profile registration in the same script so the
two cannot drift.

**A config test that reconstructs the value it is checking is testing its own arithmetic.** The
first version of the JWKS reachability check built the URL from `ROAD_ORDS_HOST` — the
*conventional* path — and asserted it returned 200. Pointed at a deliberately broken config, it
passed: it was verifying that the app serves a JWKS where one is expected, not that the value the
database is configured with is reachable. The fix is to read the live value out of the system
under test (here, via SQLcl) and assert against that. **Generally: when testing configuration,
the value under test must come from the running system, never be re-derived from the same inputs
the system was configured from.** Only a deliberate red-run exposed this — a config test that has
never been observed failing should be assumed broken.

**SQLcl skips a missing `@`-included script without failing the run.** A deploy chain that
`@`-includes a generated file completes "successfully" if the generate step was never run, leaving
whatever that script configures silently absent. Any `@` of a generated artifact needs a
corresponding hard check (`raise_application_error`) that its effect actually landed.

## DBMS_CRYPTO RSA signing and key generation

**`DBMS_CRYPTO.SIGN` with `KEY_TYPE_RSA` wants the private key as the base64 TEXT of a PKCS#1 DER
key, passed through `utl_i18n.string_to_raw` — not the decoded DER bytes.** This looks like a bug
every time you read it (`string_to_raw` on a base64 string yields the ASCII bytes of the base64,
not the key), which invites "fixing" it. Probed directly with a throwaway key: the base64-text form
signs and the signature verifies against the public key with `openssl dgst -verify`; passing
properly decoded binary DER fails with **`ORA-28817: PL/SQL function returned an error`**. If you
are generating key material for Oracle to sign with, reproduce this convention exactly.

**Oracle cannot generate an RSA keypair.** `DBMS_CRYPTO` signs, verifies, hashes and produces
random bytes, but has no RSA key generation — key material must come from outside (openssl), even
in 23ai. Worth knowing before designing anything that assumes in-database key lifecycle.

**OpenSSL 3.x emits PKCS#8 by default; Oracle wants PKCS#1.** `-traditional` is required on **both**
`openssl genrsa` and `openssl rsa -outform DER`. Passing it to only one silently yields PKCS#8
(recognisable because the base64 starts `MIIEvAIBADANBgkqhkiG...` rather than `MIIEpQIBAAKCAQEA...`).

**Rotating a signing key needs no ORDS JWT profile re-registration.** The profile stores issuer,
audience and JWKS URL — none of which change on rotation — and a changed `kid` makes ORDS refetch
the JWKS. Always change `kid` when the key changes; reusing it risks validation against ORDS's
cached copy of the old key.

## Testing a template from the template's starting state

**A defect in a scaffold is only visible from the scaffold's initial state, which is never the
state of the repo you are developing in.** Making four config columns nullable and testing in an
app that already had a populated row passed cleanly; the genuinely-empty path — the one every newly
scaffolded app takes — failed on `ORA-01407` because one column had been missed. The mature repo
cannot exercise the first-deploy path by definition. When changing anything a template ships,
construct the empty starting state deliberately and run against that.

## Third-party UI components: verify against the installed source

Written after enabling `react-big-calendar`'s Week/Day/Agenda views in road-cal (spec patch 05).
All of these were found by reading `node_modules`, not the docs, and each would have produced a
plausible-looking wrong implementation.

**A library callback that "obviously" fires may be structurally unreachable in your configuration.**
The UI spec instructed the client to fetch its data range from `onRangeChange`. That callback is
invoked only from the library's own toolbar and drilldown paths; the app renders with
`toolbar={false}` and drives navigation from its own buttons, so it had never fired once — the
build had quietly derived the range itself instead. **The spec was wrong and the code was right,
which is the harder direction to notice**, because the reflex on finding a divergence is to make
the code match the spec. Before implementing a documented callback, grep the library for its call
sites and check whether your configuration reaches any of them.

**Sibling APIs in the same library need not return the same shape.** The four view classes each
expose a static `range()`: two return `{start, end}`, two return an array of `Date`s at midnight.
Consuming the array form directly as a range would silently drop the final day — the entire day in
Day view. A wrapper that normalises the shapes is worth writing even when it looks like a
pass-through.

**Locale is not inherited — an unset `culture` prop silently means en-US.** The date-fns localizer
resolves `locales[culture]`; with no `culture` passed that is `locales[undefined]`, and date-fns
falls back to its default locale. Times rendered as "8:00 AM" in an otherwise 24-hour app. Note
also that several of the library's default format *strings* bake US ordering in directly
(`'ccc MMM dd'` → "Wed Aug 12"); those stay wrong under the correct locale and need overriding
individually. **The bug had existed since the component was written but was strictly unobservable**,
because the one shipped view never asked the localizer to format a time — a whole class of latent
defect that only surfaces when a feature is switched on.

**A style getter may be applied to a container you did not anticipate.** `eventPropGetter` returns
a style for "the event", which in the grid views is a chip and in the agenda view is the whole
table row — so returning a background colour flooded every row and made the date and time cells
unreadable. Types were satisfied, nothing threw. Only looking at the rendered page caught it.
**Anything that hands styling to a library needs a visual check per view, not a type check.**

**Enabling a view switches on code paths that have never executed.** `onEventResize` had been wired
since the component was written, but month view has no duration axis and cannot produce a resize,
so the handler had never run. It came live with the time views carrying no test history at all —
and it shared a handler with the drag path, so the series scope prompt it opened was headed with
the wrong verb. **When enabling a feature flag or a view, inventory what becomes reachable and
treat all of it as new code**, however long it has been sitting in the file.

## Tests written alongside their implementation agree with it by construction

A companion to the config-test lesson above, found while unit-testing a date-range helper.

Every range end was wrapped in `endOfDay()`, with a comment claiming it guarded against a
library's midnight-terminated ranges. Deliberately deleting that call from the week case left all
22 tests green: date-fns `endOfWeek` and `endOfMonth` already return `23:59:59.999`, so the call
was a no-op there and the "guard" guarded nothing. It was load-bearing only for the two cases
whose input is an arbitrary time of day.

**Mutate each assertion you rely on and confirm the suite goes red.** A passing test proves the
implementation and the test agree; it says nothing about whether either is right, and nothing at
all about whether the assertion has any grip on the line it claims to protect. Three one-line
mutations here took two minutes and reclassified a third of the "protection" as decoration.

---

## Compiled config files shadowing their own source

**`tsc -b` on a `composite: true` project with no `noEmit` writes `vite.config.js` next to
`vite.config.ts`, and Vite loads the `.js` in preference.** The emitted file then shadows the real
config: every subsequent edit to `vite.config.ts` is silently ignored until someone runs a build
that regenerates the shadow. There is no error, no warning, and the stale config is usually a
recent enough copy that the app still starts — so the symptom is "my config change did nothing",
which reads as a bug in the config itself.

**Why it happens:** the standard `create-vite` template ships `tsconfig.node.json` with
`"noEmit": true` alongside `"composite": true`. Templates copied by hand tend to drop it, because
`composite` historically conflicted with `noEmit` and the pairing looks wrong.

**How to apply:** if a Vite/TS project type-checks its own config, assert `noEmit` is set in
whichever tsconfig `include`s `vite.config.ts`, and make sure `vite.config.js` / `vite.config.d.ts`
are neither present nor tracked. Diagnose by printing `configFile` from `resolveConfig()` — it
names the file actually loaded, which is faster than any amount of reading. Generalises past Vite:
any tool that resolves `.js` before `.ts` (or `.mjs` before `.js`) can be shadowed by its own
build output.

## Reaching a same-origin API from a dev server

**Prefer a dev-server proxy over configuring CORS on the deployed API.** When a
built-for-same-origin app needs to run on `localhost` against a real backend, the reflex is to
allow the dev origin on the server — which permanently loosens a deployed environment for a local
convenience. A `server.proxy` entry does the same job with no server change at all: the browser
only ever talks to localhost, and the dev server forwards server-side, so no cross-origin request
is made and there is nothing for CORS to police.

**How to apply:** proxy the API path prefixes only, and check they do not collide with the app's
own `base` path. Where the client derives its API base from `window.location.origin`, it already
points at the dev server and needs no code change. Keep the target host in a gitignored
`.env.local` rather than a tracked `.env`, and **warn rather than throw** when it is absent — test
runners load the same config file and have no business needing a backend host.

## Hiding a UI region because "the data can't produce it"

**Verify what a third-party component puts in a region before hiding it.** A calendar's all-day
lane was hidden with a comment reasoning that the API carried no all-day flag, so the lane "is
always empty". The component populated that lane from a second, independent condition — an event
spanning more than one day — so the lane was not empty, and hiding it deleted real records from two
of four views while a third still showed them. The reasoning was recorded confidently in both the
code and a spec patch, which is what made it survive review.

**Why it matters:** the failure is invisible in exactly the place you would look. The elements are
present in the DOM with correct content and zero size, so the data layer, the network tab and the
component's own props all look right.

**How to apply:** before hiding a region on the grounds that it cannot be populated, inspect it
with real data and confirm it is empty — `getBoundingClientRect()` plus `textContent` on the
container settles it in one call. When the justification is "our data model cannot produce X",
check whether the component infers X from something else as well.

## Parser rules that mirror a server rule are not bugs

**A client-side rule that deliberately reimplements a server rule will be reported as a bug, and
must not be "fixed".** An agenda preview reimplemented the server's markdown rule exactly —
heading, then bullets — so typing bullets with no heading rendered nothing. That is correct: the
server would store nothing either. It was reported as a broken preview, and the tempting fix
(accept bare bullets) would have made the preview disagree with what the server actually saves,
which is a far worse defect and an invisible one.

**How to apply:** when a mirrored rule surprises users, fix the *affordance*, not the rule — say
what the rule requires at the point of input, and make the empty state distinguish "you typed
nothing" from "what you typed produces nothing". Then write the tests that pin the surprising
behaviour and say in the test file why it must not be relaxed, because the next reader will arrive
holding the same bug report.

## Public-by-omission in ORDS

**An ORDS module with no privilege defined is fully public, and nothing in a normal test run says
so.** Two calendar modules shipped with `privileges.create.sql` files whose entire content was a
`prompt` line stating no privilege was required. The endpoints returned real data to callers with
no token and to callers with a junk token. The application looked secure from the outside: it had a
login page, a route guard, and a client that attached a bearer token to every call.

**Why it survives:** every test in the suite authenticated, so every test passed. Nothing exercised
the unauthenticated path except on the one module that *was* protected. Absence of a privilege is
absence of a file's content, which does not show up in a diff of behaviour.

**How to apply:** for each REST module, assert the negative — no token and wrong-scope must both be
rejected — as a normal part of the endpoint suite. A green run against an authenticated client
proves nothing about the door being locked. When protecting a module, remember it is two changes,
not one: the ORDS privilege *and* the scope in issued tokens. Landing only the first 401s every
existing user; landing only the second is a silent no-op.

## Central 401 handling is not optional once scopes are enforced

**Route guards that only check whether a token exists will strand users the moment tokens can
become insufficient.** A `RequireAuth` that tests `getToken() !== null` admits a user holding an
expired or under-scoped token; every data call then 401s and the page renders error banners over an
empty view instead of returning to login. This stays hidden for as long as tokens are never
rejected — that is, until the day scopes start being enforced, when it hits every existing session
at once.

**How to apply:** handle 401 once, in the shared request function — clear the token, redirect to
login, show no banner for the 401 itself — rather than per page. Keep the login request off that
path so a failed sign-in shows its own message instead of looping. Derive the redirect target from
the same constant the router uses for its basename, so the two cannot drift.

## `SYS_CONTEXT` returns NULL, and NULL is not FALSE

**A boolean-returning function built on `SYS_CONTEXT` fails *open* unless you `NVL` it.** `road_ctx_pkg.has_permission` was written as:

```plsql
return sys_context('ROAD_CTX', 'PERM$' || p_permission_name) = 'Y';
```

`SYS_CONTEXT` returns NULL for an attribute that was never set, and `NULL = 'Y'` evaluates to NULL rather than FALSE. That NULL then propagates:

```plsql
if not has_permission(p_permission) then
  raise_application_error(c_forbidden, ...);   -- NOT NULL is NULL, so this never runs
end if;
```

**Every permission the caller did not hold passed silently.** The fix is one word per predicate — `nvl(sys_context(...), 'N') = 'Y'` — but the defect is invisible at the call site and reads as correct in review.

**Why it survives:** the happy path is completely unaffected. A principal who *does* hold the permission gets `'Y' = 'Y'` → TRUE, so every positive test passes. Only the denial path is broken, and denial is the path nobody writes first.

**How to apply:** in any three-valued-logic language, an authorization predicate must return FALSE, never NULL — write the assertion helper so that `assert_false` fails on NULL rather than accepting it as "not true", or the test will agree with the bug. Write the denial test before the implementation. Here the pooled-session test was written first on the build plan's instruction and caught this on its first execution; had it been written afterwards it would have been shaped around the behaviour and proved nothing.

## `SYS_CONTEXT` silently truncates at 256 bytes

**Reading a context value without an explicit length argument returns at most 256 characters, with no error and no warning.** Measured on ADB: a 1000-byte value set with `DBMS_SESSION.SET_CONTEXT` reads back as 256 via `sys_context(ns, attr)` and as 1000 via `sys_context(ns, attr, 4000)`. The maximum settable value is 4000 bytes; attribute *names* accept up to 128 bytes (129 raises ORA-28106).

**How to apply:** pass the length argument whenever the value can exceed 256 bytes, and size it from the column definition rather than a guess. An OIDC `iss` is comfortably longer than 256 characters in some providers, so an issuer stored and read back without the length argument silently stops matching any principal — a failure that looks like "the user does not exist" rather than like truncation. Where the values are short and fixed, one attribute per item avoids the problem entirely and removes the ceiling: prefer `PERM$<name>` attributes over packing a delimited list into a single value.

## A credential in source is not rotated by deleting the string

**Removing a committed password from the script that carries it is redaction. Rotation is changing the secret the system will accept.** A scaffold password lived in `bin/get-test-token.sh` as a fallback default, and its salt and hash were compiled into a PL/SQL package body. Deleting the default from the script left a fully working credential on an internet-facing dev host, while the task read as complete.

Two related traps in the same incident:

- **The string was in two files, not the one every document named.** Three separate write-ups — a spec, a build plan and a dedicated analysis document — all cited one file and line. A second copy sat in another script. Documents describing a known issue get written once and copied forward; the grep is what is authoritative.
- **Git history keeps it regardless.** Anyone who cloned before the rotation still holds the old value. That is an argument for rotating promptly, not for rewriting history reflexively.

**How to apply:** treat "remove the credential from source" and "invalidate the credential" as two tasks and check both off separately. When rotating, verify the *negative*: hash the old password under the new salt and assert it does not match the new hash, which catches an accidental re-entry of the same value. Generate the replacement with a tool that reads it interactively and computes the digest locally — sending a plaintext password to the database as a SQL literal leaves it in the shared pool, which reintroduces the problem being fixed.

## Application contexts are database-global, not schema-scoped

**`CREATE CONTEXT` creates a namespace shared by the whole database. Two applications in the same database cannot both own one called `ROAD_CTX`.** The name looks schema-qualified because it is created by a schema and secured to that schema's package, but it is not.

The failure is remote and silent. Deploying application B runs

```sql
create or replace context road_ctx using road_ctx_pkg;
```

which re-points the one shared namespace at **B's** package. Application A, whose code has not changed and whose deploy has not run, then gets `ORA-01031: insufficient privileges` from `DBMS_SESSION` on every single request — because `SET_CONTEXT` is only permitted from the package named in the `USING` clause, and that is no longer A's. Re-deploying A fixes A and breaks B. Confirmed by doing exactly that on a shared ADB.

**How to apply:** derive the namespace from the schema rather than fixing it —
`substr('ROAD_CTX_' || sys_context('USERENV','CURRENT_SCHEMA'), 1, 30)` — and have the deploy script create a context of that name with dynamic DDL, so the runtime and the DDL cannot disagree. Namespace names cap at 30 bytes, so a very long schema name truncates; that is acceptable because a truncated collision fails loudly at the first `SET_CONTEXT` rather than silently sharing session state.

Note also that `CREATE ANY CONTEXT` and `DROP ANY CONTEXT` are **separate privileges**, and there is no schema-scoped form of either. A schema that can create its context cannot necessarily remove it, and `ORA-41726` reads like "not found" rather than "not allowed".

**The wider point:** this class of bug is invisible to any amount of single-application testing. It needed a second application deployed to the same database, which is precisely what a framework's own dev target is for. A backport verified by reading would have shipped it.

## Backporting is a test, not a copy

**A framework extracted from a working application looks finished until a second application deploys it.** Spec patch 06 was built in road-cal, passed 70 endpoint assertions and 29 PL/SQL tests there, and was then copied into road-kit and deployed to a second schema on the same database. Four defects surfaced in the first hour, none of which any amount of testing in the original repo could have found:

1. **A globally-scoped object collided.** The application context is database-wide, so the second deploy silently broke the first (see the context lesson above).
2. **The test suite encoded the first application's configuration.** Two tests assumed auto-provisioning was enabled, because road-cal enables it. The framework defaults it off — fail closed — so both failed. The tests now set what they need and restore it, which is what a *framework's* tests must do.
3. **A shared script outgrew its peer.** `get-test-token.sh` is maintained byte-identical across repos and had started passing five arguments to a package that only had two in the other repo. It failed silently, returning an empty token.
4. **An identifier was application-specific.** Copying an ORDS module verbatim carried the source application's module name, producing `ORA-01403` from deep inside `ORDS.DEFINE_HANDLER` — an error that says nothing about names.

**How to apply:** give the framework repo a deployable target *before* the backport, not after, and treat the backport as a verification step with an expected yield of bugs rather than a mechanical copy. Deploy the second application to the **same database** as the first, at least once — that is the only way to find objects with database-wide scope, and it costs one schema.

Two habits that made the difference here: a teardown-then-rebuild from an empty schema rather than an incremental apply, which proves the deploy chain and not just the diff; and running the *original* application's suite again immediately afterwards, which is what caught the context collision. A backport that only proves the new repo works has tested half of what changed.

**Corollary on the shared surface.** Every file the two repos hold identically is maintained by hand. The mitigation is not discipline, it is a `diff -q` list that can be run on demand — cheap, and it converts "we think these agree" into a yes or no.
