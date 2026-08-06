whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

-- INTENT:
-- Purpose: Seed the single JWT_SCAFFOLD_CONFIG row used by the dev auth scaffold.
-- Approach: MERGE on config_id = 1 so the script is idempotent and re-runnable.
-- Reason: The auth scaffold needs issuer/audience/scope and signing key material
--   present before any token can be minted or validated.
-- Expected objects:
--   JWT_SCAFFOLD_CONFIG (one row, config_id = 1)
-- Risk: Medium. This script carries dev signing key material and an environment-specific
--   issuer/JWKS URL. Confirm both are correct for the target environment before running -
--   a wrong issuer produces tokens that fail validation with an unhelpful error.
-- Prior history checked: Search db-history for prior 80_standalone runs and confirm the
--   issuer URL matches this environment.
-- END INTENT

prompt === deploy standalone objects ===

merge into jwt_scaffold_config target
using (
  select 1 as config_id,
         'https://fmp9lqfndhnrat9-sjgadbforprototyping.adb.us-sanjose-1.oraclecloudapps.com/ords/hello_api' as issuer,
         'road-dev' as audience,
         'session.me.read' as scope_name,
         60 as ttl_minutes,
         'https://fmp9lqfndhnrat9-sjgadbforprototyping.adb.us-sanjose-1.oraclecloudapps.com/ords/hello_api/jwt-auth/.well-known/jwks.json' as jwk_url,
         'road-dev-key-001' as kid,
         'MIIEpQIBAAKCAQEArJXx+QlPcM6LSeJRfQ/UhBvwZn+afs+XyavAcFbm5GZFKL0mmZ3JcNtgM/emuzZrwafhkMqMaj5KcsKbad7UFbkRnz5VJqfK6sbPTugMyCkYna4TG1c4TJkkSD+To0q5iQskB/Q0sMIy+yV+iLj8luyWb1y73NUCWOvHYE5zYsJBo0Go/5KobWmoRqb4GsUvg0xVF/sYXjDM4gb5SGhC/4muNelZeIFLWzQyZv2iTOZp5C4OJfXfLgEVlYBinYvzUa6/kDopjdozg80uVxqRBdMIrA2JUBNFhKw2wopaWpCJsiF1P3639HpxUTzrTBkEJ1EazVxbHI1amUKRnZHl8QIDAQABAoIBAB6vkHTzk1Te3IQ4Ab4nROVyZEWNNaaLeZUJfS9cPDRq/Kv4KbdRh0ISN2I2C8aor/MgSupoIRw41BrggCqMTJBKNhhmyFQVrG4fCDgi6Tbjm7VZgJsxYFi6N+nCqBj2DdQQj4j8givVc6QU8BEWNw8MpNjLF7n1g7PUxD/a4wgxb1l/a55XbnmkGNvgFGVUBxAW1pjBYrGMKh6z8GnGE3YenIylA6Rp6zGe1ZsxuodVLVlWdL5pj91YNXEsiGAGz95MnzIGxwHOTCzltTnHPcLo/AfzrI2aH/4JEKxrs+bnrXVSh32k2PMCgkzaJU1srGK5XEhHxMI8CcvDzIh0/bkCgYEA8xa70sYd/tK8KE+yzJDeetm28mtO6PapI+mhpyPP+vgLWk26Xy1Dfcrjz4tMLYRAuuWPsAWUUJ67YmE7b08ONG0/krf01A8OTWsqo1/jjAfLQsSnX+UeLqd3N9mgnhEV9Qc/dQmOlH68XWzoSPGC3itJjDOH4WfgUgHVl9PNu4UCgYEAtcCVrJ6O8/3QTLMJTH64axV6ZExWKiIZK+wwvscSHoZHLjZtNgqpHy3/7cKKrNDTin3s5V+zmJRu+XcfiQRGJKF7em1NQNTEftibd0gCNDDGS03nh38La1VbbUYqWg8SMgvYeyudrH9/dS0SqtJSLcZir7/0/U2fDJ3DBhuA3n0CgYEAgJJKn22oGcqOOGgG8snA0otqhweYwgEMbvE4TfXUIDKnloi8BXEkXFk+atyLWxuzPOcEO56H1qhOBffVfsb6hWIvGMPxW2PnNa1z7NtfuAW7TUJEIKVHdHegx8p0eIYi7el6d8WpQwNRT7y1kzch964/hUcQHHlbnSRZO6eMDh0CgYEAiKUZ4oXzBA23JXMVcqVzEU88jVu3DEZGlnckzsnsHXbm3R+eTBsHu6Fh4Od6SyNVZ7H1AR5KcFRoerXMx76m3bNqmkjC5BMTCCrh93Pz9DkXXFZd08j4VOH/stAl1z+tdmLhhvjrulzA/t+8QSGPF0sntuqizi4lfd6+WUEkSiECgYEA6fBXIYDoITJiG5FQZXeHSxtIxIbwlADisyA6mKeGQqoxD3ahI6ywWM0BuFNNN7QiateAWTK0urKfHFiLPAOL9NCbOvOWSl4FhrBY5oAl5vqGxRrjvAlNroUSW2X86pWWFoN8eiC2PLEFGxYM7Zk7is28lJo8X3DTBoW0n7omqf0=' as private_key_b64,
         'rJXx-QlPcM6LSeJRfQ_UhBvwZn-afs-XyavAcFbm5GZFKL0mmZ3JcNtgM_emuzZrwafhkMqMaj5KcsKbad7UFbkRnz5VJqfK6sbPTugMyCkYna4TG1c4TJkkSD-To0q5iQskB_Q0sMIy-yV-iLj8luyWb1y73NUCWOvHYE5zYsJBo0Go_5KobWmoRqb4GsUvg0xVF_sYXjDM4gb5SGhC_4muNelZeIFLWzQyZv2iTOZp5C4OJfXfLgEVlYBinYvzUa6_kDopjdozg80uVxqRBdMIrA2JUBNFhKw2wopaWpCJsiF1P3639HpxUTzrTBkEJ1EazVxbHI1amUKRnZHl8Q' as public_n,
         'AQAB' as public_e
    from dual
) source
on (target.config_id = source.config_id)
when matched then
  update set issuer          = source.issuer,
             audience        = source.audience,
             scope_name      = source.scope_name,
             ttl_minutes     = source.ttl_minutes,
             jwk_url         = source.jwk_url,
             kid             = source.kid,
             private_key_b64 = source.private_key_b64,
             public_n        = source.public_n,
             public_e        = source.public_e,
             updated_at      = systimestamp
when not matched then
  insert (
    config_id,
    issuer,
    audience,
    scope_name,
    ttl_minutes,
    jwk_url,
    kid,
    private_key_b64,
    public_n,
    public_e
  )
  values (
    source.config_id,
    source.issuer,
    source.audience,
    source.scope_name,
    source.ttl_minutes,
    source.jwk_url,
    source.kid,
    source.private_key_b64,
    source.public_n,
    source.public_e
  );
