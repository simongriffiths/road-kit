-- Password credentials for the ords_local_jwt_scaffold provider profile (spec-patch-09 section 3).
--
-- Replaces three usernames, three salts and three SHA-256 digests that were compiled into
-- JWT_SCAFFOLD_AUTH_API's package body as constants. That arrangement is why both repositories'
-- git histories had to be rewritten on 2026-08-18: a password change was a code change, so a
-- password lived in version control by construction.
--
-- SCAFFOLD-NAMESPACED, AND THAT IS THE DESIGN. This table drops with the scaffold when a
-- deployment selects external_oidc. Credentials are an identity-provider concern; ROAD_PRINCIPALS
-- stays keyed on (issuer, subject) and stays ignorant of how a subject was authenticated. That
-- ignorance is what let road-blogger change provider without touching the framework, and it is the
-- property the profile switch depends on. This table references ROAD_PRINCIPALS; nothing in the
-- ROAD_* surface may ever reference this table.
--
-- NO USERNAME COLUMN. The username IS the principal's subject. Login resolves
-- (issuer from the JWT profile, subject) against ROAD_PRINCIPALS and arrives here by principal_id,
-- so there is one identity namespace rather than two that can disagree.
create table jwt_scaffold_credentials (
  principal_id  number not null,

  -- Per principal, 16 bytes from DBMS_CRYPTO.RANDOMBYTES. Two principals who choose the same
  -- password must not share a digest.
  salt          raw(16) not null,

  -- PBKDF2 output at the width JWT_SCAFFOLD_CRYPTO derives: one SHA-256 block.
  password_hash raw(32) not null,

  -- Stored PER ROW rather than assumed, so the cost can be raised without invalidating existing
  -- rows: each row is verified with the parameters it was written with.
  iterations    number not null,
  algorithm     varchar2(30 char) not null,

  created_at    timestamp with time zone default systimestamp not null,
  updated_at    timestamp with time zone default systimestamp not null,

  constraint jwt_scaffold_credentials_pk primary key (principal_id),

  -- ON DELETE CASCADE: a deleted principal must not leave a verifiable credential behind.
  constraint jwt_scaffold_cred_principal_fk foreign key (principal_id)
    references road_principals (principal_id) on delete cascade,

  -- A FLOOR AGAINST TYPOS, NOT A POLICY. The policy is JWT_SCAFFOLD_CRYPTO.C_DEFAULT_ITERATIONS
  -- (10,000, guarded by jwt_scaffold_crypto_test.test_default_cost_not_weakened). This constraint
  -- exists to reject `iterations => 10` written where 10000 was meant, which would otherwise store
  -- a verifiable and nearly worthless digest.
  constraint jwt_scaffold_cred_iterations_ck check (iterations >= 1000),

  -- Named values only. An unrecognised algorithm produces a row nothing can verify, which surfaces
  -- as a failed login rather than as the data error it is. A second algorithm is a deliberate
  -- change to this constraint.
  constraint jwt_scaffold_cred_algorithm_ck check (algorithm in ('PBKDF2-HMAC-SHA256'))
);

comment on table jwt_scaffold_credentials is
  'Password credentials for the local JWT scaffold. Development-use only per authentication-spec-v1 section 11.5. Dropped when the external_oidc profile is selected.';
comment on column jwt_scaffold_credentials.principal_id is
  'The principal these credentials authenticate. Also the username, via ROAD_PRINCIPALS.SUBJECT.';
comment on column jwt_scaffold_credentials.iterations is
  'PBKDF2 iteration count this row was written with, and must be verified with.';
comment on column jwt_scaffold_credentials.algorithm is
  'Key derivation function used, so a future change of primitive is a new value rather than a silent reinterpretation of the stored bytes.';
