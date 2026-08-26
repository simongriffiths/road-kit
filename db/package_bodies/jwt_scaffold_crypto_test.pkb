create or replace package body jwt_scaffold_crypto_test as

  -- Published PBKDF2-HMAC-SHA256 test vectors. The SHA-1 vectors in RFC 6070 do not apply; these
  -- are the SHA-256 equivalents of the same four cases, widely published and used here for the
  -- same reason RFC 6070 exists -- so that an implementation is checked against something outside
  -- itself rather than against its own output.
  --
  -- The c=1 vector was independently confirmed against this database on 2026-08-26 before any of
  -- this package existed (road-cal run 20260826_221310_probe_pbkdf2), which is what makes it safe
  -- to treat a disagreement here as a defect in the code rather than a typo in the constant.
  c_v1_c1     constant varchar2(80) := '120FB6CFFCF8B32C43E7225256C4F837A86548C92CCC35480805987CB70BE17B';
  c_v2_c2     constant varchar2(80) := 'AE4D0C95AF6B46D32D0ADFF928F06DD02A303F8EF3C251DFD6E2D85A95474C43';
  c_v3_c4096  constant varchar2(80) := 'C5E478D59288C841AA530DB6845C4C8D962893A001CE4E11A4963873AA98134A';

  -- dkLen 40 -- two blocks. The only vector here that exercises the block index.
  c_v4_2block constant varchar2(120) :=
    '348C89DBCBD32B2F32D814B8116E84CF2B17347EBC1800181C4E2A1FB8DD53E1C635518C7DAC47E9';

  procedure assert_eq(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
  begin
    if p_actual is null and p_expected is null then
      return;
    end if;
    if p_actual is null or p_expected is null or p_actual != p_expected then
      raise_application_error(
        -20000,
        p_label || ': expected [' || p_expected || '] got [' || p_actual || ']'
      );
    end if;
  end assert_eq;

  procedure assert_true(p_label in varchar2, p_condition in boolean) is
  begin
    if not nvl(p_condition, false) then
      raise_application_error(-20000, p_label || ': expected true');
    end if;
  end assert_true;

  function utf8(p_text in varchar2) return raw is
  begin
    return utl_i18n.string_to_raw(p_text, 'AL32UTF8');
  end utf8;

  procedure test_rfc_vector_one_iteration is
  begin
    assert_eq(
      'P=password S=salt c=1 dkLen=32',
      c_v1_c1,
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('password', utf8('salt'), 1, 32))
    );
  end test_rfc_vector_one_iteration;

  procedure test_rfc_vector_two_iterations is
  begin
    assert_eq(
      'P=password S=salt c=2 dkLen=32',
      c_v2_c2,
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('password', utf8('salt'), 2, 32))
    );
  end test_rfc_vector_two_iterations;

  -- Also the closest vector to the real cost: 4096 iterations against the configured 10,000.
  procedure test_rfc_vector_many_iterations is
  begin
    assert_eq(
      'P=password S=salt c=4096 dkLen=32',
      c_v3_c4096,
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('password', utf8('salt'), 4096, 32))
    );
  end test_rfc_vector_many_iterations;

  -- The load-bearing test. A single-block implementation -- the obvious shortcut, since the
  -- credential store only ever wants 32 bytes -- passes all three tests above and fails this one.
  procedure test_rfc_vector_two_blocks is
  begin
    assert_eq(
      'multi-block dkLen=40',
      c_v4_2block,
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256(
        'passwordPASSWORDpassword',
        utf8('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        4096,
        40
      ))
    );
  end test_rfc_vector_two_blocks;

  procedure test_deterministic is
    l_salt raw(16) := utl_raw.cast_to_raw('0123456789ABCDEF');
  begin
    assert_eq(
      'same inputs, same digest',
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('hunter2', l_salt, 1000, 32)),
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('hunter2', l_salt, 1000, 32))
    );
  end test_deterministic;

  -- The property that makes a per-principal salt worth storing: two principals who choose the same
  -- password must not share a digest.
  procedure test_salt_changes_digest is
    l_a raw(32);
    l_b raw(32);
  begin
    l_a := jwt_scaffold_crypto.pbkdf2_sha256('same password', hextoraw('00000000000000000000000000000001'), 1000, 32);
    l_b := jwt_scaffold_crypto.pbkdf2_sha256('same password', hextoraw('00000000000000000000000000000002'), 1000, 32);
    assert_true('different salts produce different digests', rawtohex(l_a) != rawtohex(l_b));
  end test_salt_changes_digest;

  procedure test_iterations_change_digest is
    l_salt raw(16) := hextoraw('0102030405060708090A0B0C0D0E0F10');
  begin
    assert_true(
      'iteration count is part of the derivation',
      rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('p', l_salt, 100, 32))
        != rawtohex(jwt_scaffold_crypto.pbkdf2_sha256('p', l_salt, 200, 32))
    );
  end test_iterations_change_digest;

  procedure assert_raises_20001(p_label in varchar2, p_thunk in varchar2) is
    l_dk     raw(32);
    l_raised boolean := false;
  begin
    begin
      case p_thunk
        when 'null_password'  then l_dk := jwt_scaffold_crypto.pbkdf2_sha256(null, hextoraw('01'), 10, 32);
        when 'null_salt'      then l_dk := jwt_scaffold_crypto.pbkdf2_sha256('p', null, 10, 32);
        when 'zero_iters'     then l_dk := jwt_scaffold_crypto.pbkdf2_sha256('p', hextoraw('01'), 0, 32);
        when 'zero_dk_len'    then l_dk := jwt_scaffold_crypto.pbkdf2_sha256('p', hextoraw('01'), 10, 0);
        when 'zero_salt_len'  then l_dk := jwt_scaffold_crypto.random_salt(0);
      end case;
    exception
      when others then
        if sqlcode != -20001 then
          raise;
        end if;
        l_raised := true;
    end;
    assert_true(p_label, l_raised);
  end assert_raises_20001;

  procedure test_guards is
  begin
    assert_raises_20001('null password rejected', 'null_password');
    assert_raises_20001('null salt rejected', 'null_salt');
    assert_raises_20001('zero iterations rejected', 'zero_iters');
    assert_raises_20001('zero dk_len rejected', 'zero_dk_len');
    assert_raises_20001('zero-length salt rejected', 'zero_salt_len');
  end test_guards;

  procedure test_random_salt is
    l_a raw(16);
    l_b raw(16);
  begin
    l_a := jwt_scaffold_crypto.random_salt;
    l_b := jwt_scaffold_crypto.random_salt;
    assert_eq('default salt is 16 bytes', '16', to_char(utl_raw.length(l_a)));
    assert_true('two salts differ', rawtohex(l_a) != rawtohex(l_b));
    assert_eq('explicit length honoured', '32',
              to_char(utl_raw.length(jwt_scaffold_crypto.random_salt(32))));
  end test_random_salt;

  -- Not a property of the algorithm -- a guard on the configured cost. Lowering the default is a
  -- security decision and should require editing this line, not just the constant.
  procedure test_default_cost_not_weakened is
  begin
    assert_true(
      'default iterations at least 10000',
      jwt_scaffold_crypto.c_default_iterations >= 10000
    );
    assert_eq('algorithm label', 'PBKDF2-HMAC-SHA256', jwt_scaffold_crypto.c_algorithm);
  end test_default_cost_not_weakened;

  procedure run_all is
    l_pass number := 0;
    l_fail number := 0;

    procedure run(p_name in varchar2, p_proc in varchar2) is
    begin
      case p_proc
        when 'rfc_c1'        then test_rfc_vector_one_iteration;
        when 'rfc_c2'        then test_rfc_vector_two_iterations;
        when 'rfc_c4096'     then test_rfc_vector_many_iterations;
        when 'rfc_2block'    then test_rfc_vector_two_blocks;
        when 'deterministic' then test_deterministic;
        when 'salt_matters'  then test_salt_changes_digest;
        when 'iters_matter'  then test_iterations_change_digest;
        when 'guards'        then test_guards;
        when 'random_salt'   then test_random_salt;
        when 'default_cost'  then test_default_cost_not_weakened;
      end case;
      dbms_output.put_line('PASS ' || p_name);
      l_pass := l_pass + 1;
    exception
      when others then
        dbms_output.put_line('FAIL ' || p_name || ': ' || sqlerrm);
        l_fail := l_fail + 1;
    end run;
  begin
    run('test_rfc_vector_one_iteration', 'rfc_c1');
    run('test_rfc_vector_two_iterations', 'rfc_c2');
    run('test_rfc_vector_many_iterations', 'rfc_c4096');
    run('test_rfc_vector_two_blocks', 'rfc_2block');
    run('test_deterministic', 'deterministic');
    run('test_salt_changes_digest', 'salt_matters');
    run('test_iterations_change_digest', 'iters_matter');
    run('test_guards', 'guards');
    run('test_random_salt', 'random_salt');
    run('test_default_cost_not_weakened', 'default_cost');

    dbms_output.put_line('jwt_scaffold_crypto_test: ' || l_pass || ' passed, ' || l_fail || ' failed');
  end run_all;

end jwt_scaffold_crypto_test;
/
