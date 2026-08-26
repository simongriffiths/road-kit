create or replace package jwt_scaffold_crypto as
  -- Password key derivation for the ords_local_jwt_scaffold provider profile
  -- (spec-patch-09 section 3.3).
  --
  -- WHY THIS PACKAGE EXISTS AT ALL: this database has no PBKDF2. DBMS_CRYPTO on Oracle AI Database
  -- 26ai (23.26.3.2.0) exposes HASH, HASH_LEN, MAC, KMACXOF, RANDOMBYTES, RANDOMINTEGER,
  -- RANDOMNUMBER, SIGN, VERIFY, the cipher calls and the ECDH pair -- and no key-derivation
  -- function of any kind. Verified 2026-08-26, road-cal run 20260826_221152_probe_crypto.
  -- Do not replace this with a DBMS_CRYPTO call that "must be in there somewhere". It is not.
  --
  -- SCAFFOLD-NAMESPACED DELIBERATELY. This drops with the scaffold when a deployment selects the
  -- external_oidc profile, because password storage is an identity-provider concern and the ROAD_*
  -- framework must stay ignorant of how a subject was authenticated (spec-patch-09 section 3.1).

  -- 10,000 costs 80ms on this database; 1,000 costs 10ms and 50,000 costs 410ms. Measured, not
  -- guessed -- road-cal run 20260826_221310_probe_pbkdf2. Raise it freely: JWT_SCAFFOLD_CREDENTIALS
  -- stores the iteration count per row, so existing rows keep verifying with the count they were
  -- written with.
  c_default_iterations constant pls_integer := 10000;

  -- Recorded in JWT_SCAFFOLD_CREDENTIALS.ALGORITHM alongside each digest, so a future change of
  -- primitive is a new value rather than a silent reinterpretation of the stored bytes.
  c_algorithm constant varchar2(30) := 'PBKDF2-HMAC-SHA256';

  c_default_salt_bytes constant pls_integer := 16;
  c_default_dk_len     constant pls_integer := 32;

  -- PBKDF2 as specified in RFC 2898 section 5.2, with HMAC-SHA256 as the pseudorandom function.
  -- Supports p_dk_len beyond one 32-byte block; see the body for why that matters even though the
  -- credential store only ever asks for 32.
  function pbkdf2_sha256(
    p_password   in varchar2,
    p_salt       in raw,
    p_iterations in pls_integer default c_default_iterations,
    p_dk_len     in pls_integer default c_default_dk_len
  ) return raw;

  -- Cryptographically random salt. Separate from pbkdf2_sha256 so that verifying a password never
  -- generates one -- a salt is chosen once, when the password is set, and stored.
  function random_salt(p_bytes in pls_integer default c_default_salt_bytes) return raw;
end jwt_scaffold_crypto;
/
