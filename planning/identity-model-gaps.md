# Identity Model — Known Gaps

Known limits of `ROAD_PRINCIPALS` and `ROAD_CTX_PKG`. Recorded so they are found before they are
designed around, not after.

**Nothing here is a defect in what exists.** Each entry is a case the model does not currently
cover, with what it would take to cover it.

---

## 1. One issuer, several sign-in routes per person

**Status: recorded 2026-08-21, not being pursued.** Raised while adopting Auth0 in road-blogger
(`road-blogger/planning/build-plan-01-auth0-adoption.md`). Deliberately not built — road-blogger has
two users, both created by hand, and no signup journey at all.

### The gap

`ROAD_PRINCIPALS` is keyed on `(issuer, subject)`, and its own header explains why:

> `sub` is unique only within an issuer, and federating with a deployer's own IdP is a first-class
> scenario for a multi-cloud framework.

That anticipates **several issuers**. It does not anticipate **one issuer with several connections
per person**, which is what "sign up with email, or continue with Google or Apple" actually is.

Auth0 puts the connection in the subject:

| Route | `sub` |
|---|---|
| Email and password | `auth0\|6a8843653869644410786a7f` |
| Google | `google-oauth2\|110249296...` |
| Apple | `apple\|001234.a1b2c3...` |

Same person, same issuer, three subjects — therefore three principals, with roles attached to
whichever one they used first. The second time they sign in by a different route they are, to the
application, somebody else.

### Why it is not simply "match on email"

The same table forbids exactly that:

> `subject` is opaque and `email` is a mutable attribute, **never the key** — people change
> addresses and `principal_id` must survive that.

Linking by email means keying on email at the one moment it matters most. It does not break the
table — the key stays `(issuer, subject)` — but it contradicts the reasoning that chose the key, so
it cannot be done quietly inside a handler. It needs to be a written decision.

Three further hazards if that route is ever taken:

- **Verified only.** Matching on an unverified email lets anyone who registers a social account with
  someone else's address inherit their permissions. `email_verified` must be checked, not assumed.
- **Apple often cannot be matched.** Apple lets a user hide their address and supplies a relay
  address instead, so there is frequently no shared email to match on.
- **Auth0 account linking is the alternative**, merging identities at the provider so the
  application still sees one subject. Cleaner for the schema, but it is an Action plus Management
  API calls, and the ambiguous-merge cases have to be decided.

### Knock-on: `auto_provision_principals`

Social connections create a genuine self-signup path — anyone with a Google account who reaches the
sign-in page authenticates successfully. `auto_provision_principals = 'Y'` then means any such
person gets a row. road-kit already defaults this to `N` for exactly this class of reason; an
adopting application enabling social login should treat `Y` as a much larger decision than it is
with a closed, hand-created user list.

### What covering it would take

1. A decision, written down, on whether one human is one principal across connections.
2. If yes: either Auth0-side account linking, or a verified-email link step at first sign-in, plus a
   rule for the mismatch case. Quorate's `POST /api/user/activate` is prior art for the second —
   it matches an existing row by email, stamps the subject onto it, and refuses with
   `Account identity mismatch` when the row is already claimed by a different subject.
3. A custom claim carrying `email` and `email_verified` in the access token. A standard Auth0 access
   token carries neither.

---

## 2. Multi-tenancy: what an adopting application has to bring

**Status: recorded 2026-08-28, and largely *not* a gap.** Raised while settling Quorate's identity
model (`quorate-ks/spec/Quorate — System Requirements v2.md` revision 1, and
`Build Foundation — Decision.md` §6). Recorded so the next multi-tenant adopter does not
re-litigate a decision road-kit already took, and so the parts that genuinely are missing are
visible before they are designed around.

### What looked like a conflict, and was not

Quorate needs one person to hold authority in several councils independently. `ROAD_PRINCIPALS` is
keyed `(issuer, subject)` — one principal per person — and `ROAD_PRINCIPAL_ROLES` maps a principal
to a role with no scope. Read quickly, that is a framework that cannot express per-tenant
membership.

**It is the framework working as specified.** `road_principal_roles.create.sql` says so in its own
header:

> No scope_key: an earlier draft carried one so roles could be per-tenant, dropped on the decision
> that one primary email is one principal and no login spans tenants (spec-patch-06 sections 4.3
> and 9.3). **An application needing per-tenant membership carries its own dimension.**

So the resolution is the prescribed one, not a workaround: **authentication knows a person,
authorisation knows only memberships**, and the membership table belongs to the application.

| Layer | Object | Grain | Owner |
|---|---|---|---|
| Authentication | `ROAD_PRINCIPALS` | One per person | road-kit |
| Authorisation | Tenant membership | One per person **per tenant** | The application |

The clause worth carrying forward is that a membership must confer nothing outside its own tenant.
A principal that is a member of three tenants is still one principal; it is not one identity with
three views.

### What road-kit genuinely does not have

Three things a multi-tenant adopter has to build, none of which exists anywhere in the family.

**1. Row-level isolation.** There is no `DBMS_RLS` policy, no VPD function and no tenant column in
road-kit, road-cal or road-blogger — every application in the family is single-tenant. Quorate's
`db/02_schema_ddl.sql` is the only working implementation: a context secured to its owning package,
a pre-hook resolving the validated subject, and a policy function returning `'1=0'` when context is
unset, so the default is no rows rather than all rows. **This is the strongest backport candidate in
the family** — it is what makes road-kit capable of hosting a SaaS at all.

**2. A current-tenant dimension in `ROAD_CTX_PKG`.** The context carries the principal; it has
nowhere to carry which tenant the principal is currently acting in.

**3. A stated rule that the tenant is never client-asserted.** Quorate settles it by holding the
current tenant in the database against the identity, written by an authenticated selection and read
server-side on every request — so there is no tenant in the request to validate or to forge. Worth
promoting to a framework rule rather than leaving each adopter to invent it, because the obvious
implementation is a header and the obvious implementation is wrong.

### One thing that already exists and should be reused

`road_principals.credentials_changed_at` is the natural epoch for **global logout** — invalidating
every open session for an identity across every device, rather than only the one that signed out.
Quorate requires it (IDN-107) because changing tenant means logging out, and a session left alive
elsewhere would keep a tenant context open. An adopter should reach for this column before adding
one.

### Relationship to §1

§1 matters more under a membership model, not less: if one person becomes several principals by
signing in through different connections, their memberships attach to whichever principal they used
first, and the rest of their tenants disappear. Quorate closes it by configuration rather than
design — a single provider connection with no social sign-in — which is available to any deployment
whose accounts are created rather than self-registered. An adopter that needs social login has to
solve §1 properly first.

---

## 3. Reserved for the next gap
