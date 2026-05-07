-- =============================================================================
-- tb_example.vhd
-- Example testbench demonstrating transcript_pkg, alert_log_pkg,
-- and scoreboard_pkg working together.
--
-- Compile order : 4  (depends on all three packages)
-- VHDL standard : 2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.transcript_pkg.all;
use work.alert_log_pkg.all;
use work.scoreboard_pkg.all;

entity tb_example is
end entity tb_example;

architecture sim of tb_example is

  -- ── Scoreboards: one per logical check domain ───────────────────────────
  shared variable sb_data : t_scoreboard;
  shared variable sb_resp : t_scoreboard;

  -- ── Simple DUT stimulus/response signals ────────────────────────────────
  signal clk        : std_logic := '0';
  signal sim_done   : boolean   := false;

begin

  -- 10 ns clock
  clk <= not clk after 5 ns when not sim_done else '0';

  -- ═══════════════════════════════════════════════════════════════════════
  -- Testbench setup
  -- ═══════════════════════════════════════════════════════════════════════
  setup_proc : process
  begin

    -- ── Open transcript file; console mirror stays on (default) ──────────
    Transcript.open_transcript("tb_example.log");

    -- ── Global alert config ───────────────────────────────────────────────
    AlertLog.set_log_enable(AL_DEBUG, true);    -- show PUSH messages
    AlertLog.set_stop_count(AL_ERROR, 20);      -- stop sim after 20 errors

    -- ── Name the scoreboards (registers them with AlertLog) ───────────────
    sb_data.set_name("DATA-SB");
    sb_resp.set_name("RESP-SB");

    wait;
  end process;

  -- ═══════════════════════════════════════════════════════════════════════
  -- Stimulus: push expected results (in order)
  -- ═══════════════════════════════════════════════════════════════════════
  stimulus_proc : process
  begin
    wait until rising_edge(clk);

    -- std_logic_vector (stored as hex)
    sb_data.push(tag => 1, expected => x"DEADBEEF");
    sb_data.push(tag => 2, expected => x"CAFEBABE");
    sb_data.push(tag => 3, expected => x"12345678");

    -- integer
    sb_resp.push(tag => 10, expected => 0);
    sb_resp.push(tag => 11, expected => 0);
    sb_resp.push(tag => 12, expected => 1);    -- intentional mismatch later

    -- unsigned / signed
    sb_data.push(tag => 4, expected => to_unsigned(255, 8));
    sb_data.push(tag => 5, expected => to_signed(-42, 8));

    -- boolean / std_logic
    sb_resp.push(tag => 20, expected => true);
    sb_resp.push(tag => 21, expected => '1');

    -- Raw string for a custom type (e.g. a record serialised as "addr|len")
    sb_data.push(tag => 99, expected => "1000|64");

    wait;
  end process;

  -- ═══════════════════════════════════════════════════════════════════════
  -- Checker: results arrive OUT OF ORDER (tags 3, 1, 2 not 1, 2, 3)
  -- ═══════════════════════════════════════════════════════════════════════
  check_proc : process
    variable pass : boolean;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- ── std_logic_vector checks — out of order ────────────────────────────
    sb_data.check(tag => 3, actual => x"12345678", pass => pass);  -- PASS
    sb_data.check(tag => 1, actual => x"DEADBEEF", pass => pass);  -- PASS
    sb_data.check(tag => 2, actual => x"00000000", pass => pass);  -- FAIL (wrong value)

    -- ── integer checks ────────────────────────────────────────────────────
    sb_resp.check(tag => 11, actual => 0,  pass => pass);   -- PASS
    sb_resp.check(tag => 10, actual => 0,  pass => pass);   -- PASS
    sb_resp.check(tag => 12, actual => 0,  pass => pass);   -- FAIL (expected 1)

    -- ── unsigned / signed ─────────────────────────────────────────────────
    sb_data.check(tag => 4, actual => to_unsigned(255, 8), pass => pass);  -- PASS
    sb_data.check(tag => 5, actual => to_signed(-42, 8),   pass => pass);  -- PASS

    -- ── boolean / std_logic ───────────────────────────────────────────────
    sb_resp.check(tag => 20, actual => true, pass => pass);   -- PASS
    sb_resp.check(tag => 21, actual => '1',  pass => pass);   -- PASS

    -- ── Custom string check ───────────────────────────────────────────────
    sb_data.check(tag => 99, actual => "1000|64", pass => pass);   -- PASS

    -- ── Orphan check: tag 999 was never pushed ────────────────────────────
    sb_data.check(tag => 999, actual => "DEADBEEF", pass => pass);  -- ORPHAN error

    -- ── Direct AlertLog use (outside scoreboard) ──────────────────────────
    declare
      constant TB_ID : t_alert_log_id := AlertLog.get_id("TB");
    begin
      AlertLog.affirm_if(TB_ID, (2 + 2 = 4), "Basic sanity check");
      AlertLog.affirm_if(TB_ID, (1 + 1 = 3), "Intentional failure");
      AlertLog.log(TB_ID, "Checker process complete", AL_INFO);
    end;

    -- ── End of test ───────────────────────────────────────────────────────
    AlertLog.report_alerts;
    Transcript.close_transcript;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
