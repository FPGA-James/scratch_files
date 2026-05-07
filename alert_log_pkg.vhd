-- =============================================================================
-- alert_log_pkg.vhd
-- Lightweight alert and logging framework with named IDs, pass/fail counts,
-- configurable severity and stop counts, and end-of-test summary reporting.
--
-- Compile order : 2  (depends on transcript_pkg)
-- VHDL standard : 2008
-- =============================================================================

library std;
use std.textio.all;
library work;
use work.transcript_pkg.all;

package alert_log_pkg is

  -- Alert levels affect pass/fail; log levels are informational only.
  type t_alert_level is (AL_WARNING, AL_ERROR, AL_FAILURE);
  type t_log_level   is (AL_DEBUG,   AL_INFO,  AL_ALWAYS);

  -- Up to 64 named components can be registered (easily extended via MAX_IDS).
  subtype t_alert_log_id is natural range 0 to 63;
  constant ALERTLOG_BASE_ID : t_alert_log_id := 0;

  -- ── Protected type ─────────────────────────────────────────────────────────
  type t_alert_log is protected

    -- Register a component name and return its ID.
    -- Calling with the same name twice returns the same ID.
    impure function get_id (name : in string) return t_alert_log_id;

    -- Raise an alert (counted, contributes to pass/fail result).
    procedure alert (id  : in t_alert_log_id;
                     msg : in string;
                     lvl : in t_alert_level := AL_ERROR);

    -- Emit a log message (not counted, filtered by log level).
    procedure log (id  : in t_alert_log_id;
                   msg : in string;
                   lvl : in t_log_level := AL_INFO);

    -- Alert if condition is false.
    procedure affirm_if (id        : in t_alert_log_id;
                         condition : in boolean;
                         msg       : in string;
                         lvl       : in t_alert_level := AL_ERROR);

    -- Alert if two strings differ. Both sides must use the same conversion.
    procedure affirm_if_equal (id       : in t_alert_log_id;
                                actual   : in string;
                                expected : in string;
                                msg      : in string        := "";
                                lvl      : in t_alert_level := AL_ERROR);

    -- Enable or disable a log level globally.
    procedure set_log_enable  (lvl : in t_log_level;   en : in boolean);

    -- Stop simulation once this many alerts of a given level are reached.
    procedure set_stop_count  (lvl : in t_alert_level; n  : in natural);

    -- Print per-component and total counts, then overall PASS/FAIL.
    procedure report_alerts;

    -- Return total alert count across all IDs for a given level.
    impure function get_alert_count (lvl : in t_alert_level) return natural;

    -- True only when ERROR and FAILURE counts are both zero.
    impure function passed return boolean;

  end protected t_alert_log;

  -- Global singleton.
  shared variable AlertLog : t_alert_log;

end package alert_log_pkg;

-- =============================================================================

library std;
use std.textio.all;
library work;
use work.transcript_pkg.all;

package body alert_log_pkg is

  constant MAX_IDS : positive := 64;

  -- Per-ID alert counters.
  type t_counts is record
    warnings : natural;
    errors   : natural;
    failures : natural;
  end record;

  type t_counts_array     is array (0 to MAX_IDS - 1) of t_counts;
  type t_name_array       is array (0 to MAX_IDS - 1) of line;
  type t_log_enable_array is array (t_log_level)       of boolean;
  type t_stop_count_array is array (t_alert_level)     of natural;

  -- ── Protected body ─────────────────────────────────────────────────────────
  type t_alert_log is protected body

    variable names    : t_name_array;
    variable counts   : t_counts_array     := (others => (0, 0, 0));
    variable id_count : natural            := 0;

    variable log_en   : t_log_enable_array := (AL_DEBUG  => false,
                                                AL_INFO   => true,
                                                AL_ALWAYS => true);

    variable stop_cnt : t_stop_count_array := (AL_WARNING => natural'high,
                                                AL_ERROR   => natural'high,
                                                AL_FAILURE => 1);

    -- ── Private helpers ──────────────────────────────────────────────────────

    impure function get_name (id : t_alert_log_id) return string is
    begin
      if names(id) /= null then
        return names(id).all;
      else
        return "ID" & integer'image(id);
      end if;
    end function;

    impure function level_str (lvl : t_alert_level) return string is
    begin
      case lvl is
        when AL_WARNING => return "WARNING";
        when AL_ERROR   => return "ERROR  ";
        when AL_FAILURE => return "FAILURE";
      end case;
    end function;

    procedure inc_count (id : t_alert_log_id; lvl : t_alert_level) is
    begin
      case lvl is
        when AL_WARNING => counts(id).warnings := counts(id).warnings + 1;
        when AL_ERROR   => counts(id).errors   := counts(id).errors   + 1;
        when AL_FAILURE => counts(id).failures := counts(id).failures + 1;
      end case;
    end procedure;

    impure function get_count (id  : t_alert_log_id;
                               lvl : t_alert_level) return natural is
    begin
      case lvl is
        when AL_WARNING => return counts(id).warnings;
        when AL_ERROR   => return counts(id).errors;
        when AL_FAILURE => return counts(id).failures;
      end case;
    end function;

    -- ── Public subprograms ───────────────────────────────────────────────────

    impure function get_id (name : in string) return t_alert_log_id is
    begin
      -- Return existing ID if already registered.
      for i in 0 to id_count - 1 loop
        if names(i) /= null and names(i).all = name then
          return i;
        end if;
      end loop;
      -- Register new ID.
      assert id_count < MAX_IDS
        report "[AlertLog] ID table full, cannot register: " & name
        severity failure;
      names(id_count) := new string'(name);
      id_count        := id_count + 1;
      return id_count - 1;
    end function;

    -- -------------------------------------------------------------------------
    procedure alert (id  : in t_alert_log_id;
                     msg : in string;
                     lvl : in t_alert_level := AL_ERROR) is
    begin
      inc_count(id, lvl);
      Transcript.print_line(
        "[" & get_name(id) & "] " & level_str(lvl) & "  " & msg);

      -- For FAILURE, also assert via the simulator so it can handle it.
      if lvl = AL_FAILURE then
        report "[" & get_name(id) & "] FAILURE  " & msg severity failure;
      end if;

      -- Stop-count check.
      if get_count(id, lvl) >= stop_cnt(lvl) then
        report "[AlertLog] Stop count reached: " & level_str(lvl) &
               " in [" & get_name(id) & "]" severity failure;
      end if;
    end procedure;

    -- -------------------------------------------------------------------------
    procedure log (id  : in t_alert_log_id;
                   msg : in string;
                   lvl : in t_log_level := AL_INFO) is
    begin
      if log_en(lvl) then
        Transcript.print_line("[" & get_name(id) & "] " & msg);
      end if;
    end procedure;

    -- -------------------------------------------------------------------------
    procedure affirm_if (id        : in t_alert_log_id;
                         condition : in boolean;
                         msg       : in string;
                         lvl       : in t_alert_level := AL_ERROR) is
    begin
      if not condition then
        alert(id, msg, lvl);
      end if;
    end procedure;

    -- -------------------------------------------------------------------------
    procedure affirm_if_equal (id       : in t_alert_log_id;
                                actual   : in string;
                                expected : in string;
                                msg      : in string        := "";
                                lvl      : in t_alert_level := AL_ERROR) is
    begin
      if actual /= expected then
        if msg /= "" then
          alert(id, msg & "  expected=" & expected & "  actual=" & actual, lvl);
        else
          alert(id, "expected=" & expected & "  actual=" & actual, lvl);
        end if;
      end if;
    end procedure;

    -- -------------------------------------------------------------------------
    procedure set_log_enable (lvl : in t_log_level; en : in boolean) is
    begin
      log_en(lvl) := en;
    end procedure;

    -- -------------------------------------------------------------------------
    procedure set_stop_count (lvl : in t_alert_level; n : in natural) is
    begin
      stop_cnt(lvl) := n;
    end procedure;

    -- -------------------------------------------------------------------------
    impure function get_alert_count (lvl : in t_alert_level) return natural is
      variable total : natural := 0;
    begin
      for i in 0 to id_count - 1 loop
        total := total + get_count(i, lvl);
      end loop;
      return total;
    end function;

    -- -------------------------------------------------------------------------
    impure function passed return boolean is
    begin
      return get_alert_count(AL_ERROR)   = 0 and
             get_alert_count(AL_FAILURE) = 0;
    end function;

    -- -------------------------------------------------------------------------
    procedure report_alerts is
      variable any_fail : boolean := false;
    begin
      Transcript.print_line(
        "================================================");
      Transcript.print_line(" AlertLog Summary");
      Transcript.print_line(
        "================================================");

      for i in 0 to id_count - 1 loop
        if names(i) /= null then
          Transcript.print_line(
            "  [" & names(i).all & "]" &
            "  W=" & integer'image(counts(i).warnings) &
            "  E=" & integer'image(counts(i).errors)   &
            "  F=" & integer'image(counts(i).failures));
          if counts(i).errors > 0 or counts(i).failures > 0 then
            any_fail := true;
          end if;
        end if;
      end loop;

      Transcript.print_line(
        "------------------------------------------------");
      Transcript.print_line(
        "  Total" &
        "  W=" & integer'image(get_alert_count(AL_WARNING)) &
        "  E=" & integer'image(get_alert_count(AL_ERROR))   &
        "  F=" & integer'image(get_alert_count(AL_FAILURE)));

      if any_fail then
        Transcript.print_line("  Result : *** FAIL ***");
        report "*** TEST FAILED ***" severity error;
      else
        Transcript.print_line("  Result : *** PASS ***");
        report "*** TEST PASSED ***" severity note;
      end if;

      Transcript.print_line(
        "================================================");
    end procedure;

  end protected body t_alert_log;

end package body alert_log_pkg;
