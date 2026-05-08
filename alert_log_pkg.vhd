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

  type t_alert_level is (AL_WARNING, AL_ERROR, AL_FAILURE);

  subtype t_alert_log_id is natural range 0 to 63;
  constant ALERTLOG_BASE_ID : t_alert_log_id := 0;

  type t_alert_log is protected

    impure function get_id (name : in string) return t_alert_log_id;

    procedure alert (id  : in t_alert_log_id;
                     msg : in string;
                     lvl : in t_alert_level := AL_ERROR);

    -- log now delegates level directly to Transcript.print
    procedure log (id  : in t_alert_log_id;
                   msg : in string;
                   lvl : in t_log_level := INFO);

    procedure affirm_if (id        : in t_alert_log_id;
                         condition : in boolean;
                         msg       : in string;
                         lvl       : in t_alert_level := AL_ERROR);

    procedure affirm_if_equal (id       : in t_alert_log_id;
                                actual   : in string;
                                expected : in string;
                                msg      : in string        := "";
                                lvl      : in t_alert_level := AL_ERROR);

    procedure set_stop_count  (lvl : in t_alert_level; n : in natural);

    procedure report_alerts;

    impure function get_alert_count (lvl : in t_alert_level) return natural;
    impure function passed          return boolean;

  end protected t_alert_log;

  shared variable AlertLog : t_alert_log;

end package alert_log_pkg;

-- =============================================================================

library std;
use std.textio.all;
library work;
use work.transcript_pkg.all;

package body alert_log_pkg is

  constant MAX_IDS : positive := 64;

  type t_counts is record
    warnings : natural;
    errors   : natural;
    failures : natural;
  end record;

  type t_counts_array     is array (0 to MAX_IDS - 1) of t_counts;
  type t_name_array       is array (0 to MAX_IDS - 1) of line;
  type t_stop_count_array is array (t_alert_level)    of natural;

  type t_alert_log is protected body

    variable names    : t_name_array;
    variable counts   : t_counts_array     := (others => (0, 0, 0));
    variable id_count : natural            := 0;
    variable stop_cnt : t_stop_count_array := (AL_WARNING => natural'high,
                                                AL_ERROR   => natural'high,
                                                AL_FAILURE => 1);

    -- ââ Private helpers âââââââââââââââââââââââââââââââââââââââââââââââââââââââ
    impure function get_name (id : t_alert_log_id) return string is
    begin
      if names(id) /= null then return names(id).all;
      else return "ID" & integer'image(id);
      end if;
    end function;

    impure function alert_level_str (lvl : t_alert_level) return string is
    begin
      case lvl is
        when AL_WARNING => return "AL_WARNING";
        when AL_ERROR   => return "AL_ERROR";
        when AL_FAILURE => return "AL_FAILURE";
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

    -- ââ Public subprograms ââââââââââââââââââââââââââââââââââââââââââââââââââââ
    impure function get_id (name : in string) return t_alert_log_id is
    begin
      for i in 0 to id_count - 1 loop
        if names(i) /= null and names(i).all = name then return i; end if;
      end loop;
      assert id_count < MAX_IDS
        report "[AlertLog] ID table full: " & name severity failure;
      names(id_count) := new string'(name);
      id_count        := id_count + 1;
      return id_count - 1;
    end function;

    procedure alert (id  : in t_alert_log_id;
                     msg : in string;
                     lvl : in t_alert_level := AL_ERROR) is
    begin
      inc_count(id, lvl);

      -- Map alert level to transcript log level
      case lvl is
        when AL_WARNING => Transcript.print(WARNING, "[" & get_name(id) & "] " & msg);
        when AL_ERROR   => Transcript.print(ERROR,   "[" & get_name(id) & "] " & msg);
        when AL_FAILURE => Transcript.print(ERROR,   "[" & get_name(id) & "] " & msg);
                           report "[" & get_name(id) & "] FAILURE  " & msg severity failure;
      end case;

      if get_count(id, lvl) >= stop_cnt(lvl) then
        report "[AlertLog] Stop count reached: " & alert_level_str(lvl) &
               " in [" & get_name(id) & "]" severity failure;
      end if;
    end procedure;

    procedure log (id  : in t_alert_log_id;
                   msg : in string;
                   lvl : in t_log_level := INFO) is
    begin
      Transcript.print(lvl, "[" & get_name(id) & "] " & msg);
    end procedure;

    procedure affirm_if (id        : in t_alert_log_id;
                         condition : in boolean;
                         msg       : in string;
                         lvl       : in t_alert_level := AL_ERROR) is
    begin
      if not condition then alert(id, msg, lvl); end if;
    end procedure;

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

    procedure set_stop_count (lvl : in t_alert_level; n : in natural) is
    begin
      stop_cnt(lvl) := n;
    end procedure;

    impure function get_alert_count (lvl : in t_alert_level) return natural is
      variable total : natural := 0;
    begin
      for i in 0 to id_count - 1 loop
        total := total + get_count(i, lvl);
      end loop;
      return total;
    end function;

    impure function passed return boolean is
    begin
      return get_alert_count(AL_ERROR) = 0 and get_alert_count(AL_FAILURE) = 0;
    end function;

    procedure report_alerts is
      variable any_fail : boolean := false;
    begin
      Transcript.print(INFO, "================================================");
      Transcript.print(INFO, " AlertLog Summary");
      Transcript.print(INFO, "================================================");

      for i in 0 to id_count - 1 loop
        if names(i) /= null then
          Transcript.print(INFO,
            "  [" & names(i).all & "]" &
            "  W=" & integer'image(counts(i).warnings) &
            "  E=" & integer'image(counts(i).errors)   &
            "  F=" & integer'image(counts(i).failures));
          if counts(i).errors > 0 or counts(i).failures > 0 then
            any_fail := true;
          end if;
        end if;
      end loop;

      Transcript.print(INFO, "------------------------------------------------");
      Transcript.print(INFO,
        "  Total" &
        "  W=" & integer'image(get_alert_count(AL_WARNING)) &
        "  E=" & integer'image(get_alert_count(AL_ERROR))   &
        "  F=" & integer'image(get_alert_count(AL_FAILURE)));

      if any_fail then
        Transcript.print(ERROR, "  Result : *** FAIL ***");
        report "*** TEST FAILED ***" severity error;
      else
        Transcript.print(INFO, "  Result : *** PASS ***");
        report "*** TEST PASSED ***" severity note;
      end if;

      Transcript.print(INFO, "================================================");
    end procedure;

  end protected body t_alert_log;

end package body alert_log_pkg;
