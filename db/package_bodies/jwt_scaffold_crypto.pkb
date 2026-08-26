create or replace package body jwt_scaffold_crypto as

  c_hash_bytes constant pls_integer := 32;   -- SHA-256 output width, and so the PBKDF2 block width

  function pbkdf2_sha256(
    p_password   in varchar2,
    p_salt       in raw,
    p_iterations in pls_integer default c_default_iterations,
    p_dk_len     in pls_integer default c_default_dk_len
  ) return raw is
    l_key    raw(32767);
    l_blocks pls_integer;
    l_index  raw(4);
    l_u      raw(32);
    l_t      raw(32);
    l_dk     raw(32767);
  begin
    -- Fail loudly on nonsense rather than deriving a key from it. An empty password is the case
    -- that matters: UTL_I18N.STRING_TO_RAW('') returns NULL because Oracle cannot represent a
    -- zero-length RAW, and DBMS_CRYPTO.MAC with a NULL key raises ORA-28239 -- an error about key
    -- management, several frames from the actual cause.
    if p_password is null then
      raise_application_error(-20001, 'password is required');
    end if;
    if p_salt is null then
      raise_application_error(-20001, 'salt is required');
    end if;
    if nvl(p_iterations, 0) < 1 then
      raise_application_error(-20001, 'iterations must be at least 1');
    end if;
    if nvl(p_dk_len, 0) < 1 then
      raise_application_error(-20001, 'dk_len must be at least 1');
    end if;

    l_key := utl_i18n.string_to_raw(p_password, 'AL32UTF8');

    -- RFC 2898 splits the derived key into ceil(dkLen / hLen) blocks, each block seeded with its
    -- own big-endian index. The credential store only ever asks for 32 bytes -- exactly one block,
    -- where the index is always 1 -- so a single-block implementation would pass every test it was
    -- likely to be given and be wrong the first time anyone asked for more.
    --
    -- Blocks are implemented for one reason above all: it makes the 40-byte RFC vector usable as a
    -- test, and that vector is the only one that proves the index is being fed in at all. A
    -- single-block shortcut cannot be distinguished from a correct implementation by any 32-byte
    -- vector. See jwt_scaffold_crypto_test.test_rfc_vector_two_blocks.
    l_blocks := ceil(p_dk_len / c_hash_bytes);

    for b in 1 .. l_blocks loop
      -- INT(i): the block index as four big-endian octets, appended to the salt for U_1 only.
      l_index := utl_raw.cast_from_binary_integer(b, utl_raw.big_endian);

      -- U_1 = PRF(P, S || INT(i))
      l_u := dbms_crypto.mac(utl_raw.concat(p_salt, l_index), dbms_crypto.hmac_sh256, l_key);
      l_t := l_u;

      -- U_j = PRF(P, U_j-1), accumulated by XOR. This loop IS the cost function -- it is
      -- deliberately serial and must not be "optimised" into anything cheaper.
      for i in 2 .. p_iterations loop
        l_u := dbms_crypto.mac(l_u, dbms_crypto.hmac_sh256, l_key);
        l_t := utl_raw.bit_xor(l_t, l_u);
      end loop;

      if b = 1 then
        l_dk := l_t;
      else
        l_dk := utl_raw.concat(l_dk, l_t);
      end if;
    end loop;

    -- The final block is truncated when dkLen is not a multiple of the hash width.
    return utl_raw.substr(l_dk, 1, p_dk_len);
  end pbkdf2_sha256;

  function random_salt(p_bytes in pls_integer default c_default_salt_bytes) return raw is
  begin
    if nvl(p_bytes, 0) < 1 then
      raise_application_error(-20001, 'salt length must be at least 1 byte');
    end if;

    return dbms_crypto.randombytes(p_bytes);
  end random_salt;

end jwt_scaffold_crypto;
/
