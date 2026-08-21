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

## 2. Reserved for the next gap
