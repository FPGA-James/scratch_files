-- =============================================================================
-- transcript_pkg.vhd
-- Lightweight transcript with log levels and verbosity filtering.
-- Mirrors output to a log file and/or the console.
--
-- Compile order : 1  (no dependencies)
-- VHDL standard : 2008
-- =============================================================================

library std;
use std.textio.all;

package transcript_pkg is

  -- Ordered least → most severe; threshold comparison uses positional values.
  type t_log_level is (DEBUG, INFO, WARNING, ERROR);

  type t_transcript is protected

    -- Open a log file. Set append=true to accumulate across runs.
    procedure open_transcript (filename : in string;
                                append   : in boolean := false);

    -- Flush and close the current log file.
    procedure close_transcript;

    -- When true (default), every line is also written to the console.
    procedure set_mirror      (en        : in boolean);

    -- Only messages at or above this level are printed. Default: DEBUG (all).
    procedure set_verbosity   (level     : in t_log_level);

    impure function verbosity  return t_log_level;
    impure function is_open    return boolean;

    -- Primary output call — level is first parameter.
    procedure print (level : in t_log_level; msg : in string);

  end protected t_transcript;

  -- Global singleton.
  shared variable Transcript : t_transcript;

end package transcript_pkg;

-- =============================================================================

library std;
use std.textio.all;

package body transcript_pkg is

  type t_transcript is protected body

    file     trans_file  : text;
    variable v_open      : boolean     := false;
    variable v_mirror    : boolean     := true;
    variable v_verbosity : t_log_level := DEBUG;   -- print everything by default

    -- ── Private: level prefix ─────────────────────────────────────────────────
    function level_prefix (level : t_log_level) return string is
    begin
      case level is
        when DEBUG   => return "[DEBUG  ] ";
        when INFO    => return "[INFO   ] ";
        when WARNING => return "[WARNING] ";
        when ERROR   => return "[ERROR  ] ";
      end case;
    end function;

    -- ── Private: write one line to a destination ──────────────────────────────
    -- writeline deallocates the line, so each destination needs its own write.
    procedure write_dest (dest : inout text; msg : in string) is
      variable l : line;
    begin
      write(l, string'(msg));
      writeline(dest, l);
    end procedure;

    -- ── open_transcript ───────────────────────────────────────────────────────
    procedure open_transcript (filename : in string;
                                append   : in boolean := false) is
      variable status : file_open_status;
    begin
      if v_open then
        file_close(trans_file);
        v_open := false;
      end if;

      if append then
        file_open(status, trans_file, filename, append_mode);
      else
        file_open(status, trans_file, filename, write_mode);
      end if;

      if status = open_ok then
        v_open := true;
        print(INFO, "=== Transcript opened: " & filename & " ===");
      else
        report "[Transcript] Failed to open file: " & filename severity error;
      end if;
    end procedure;

    -- ── close_transcript ──────────────────────────────────────────────────────
    procedure close_transcript is
    begin
      if v_open then
        print(INFO, "=== Transcript closed ===");
        file_close(trans_file);
        v_open := false;
      end if;
    end procedure;

    -- ── set_mirror ────────────────────────────────────────────────────────────
    procedure set_mirror (en : in boolean) is
    begin
      v_mirror := en;
    end procedure;

    -- ── set_verbosity ─────────────────────────────────────────────────────────
    procedure set_verbosity (level : in t_log_level) is
    begin
      v_verbosity := level;
    end procedure;

    -- ── verbosity ─────────────────────────────────────────────────────────────
    impure function verbosity return t_log_level is
    begin
      return v_verbosity;
    end function;

    -- ── is_open ───────────────────────────────────────────────────────────────
    impure function is_open return boolean is
    begin
      return v_open;
    end function;

    -- ── print ─────────────────────────────────────────────────────────────────
    procedure print (level : in t_log_level; msg : in string) is
      variable full : string := level_prefix(level) & msg;
    begin
      -- Drop anything below the current verbosity threshold
      if level < v_verbosity then
        return;
      end if;

      if v_mirror then
        write_dest(OUTPUT, full);
      end if;

      if v_open then
        write_dest(trans_file, full);
      end if;
    end procedure;

  end protected body t_transcript;

end package body transcript_pkg;
