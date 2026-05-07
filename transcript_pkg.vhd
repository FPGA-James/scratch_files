-- =============================================================================
-- transcript_pkg.vhd
-- Lightweight transcript: mirrors output to a log file and/or the console.
--
-- Compile order : 1  (no dependencies)
-- VHDL standard : 2008
-- =============================================================================

library std;
use std.textio.all;

package transcript_pkg is

  type t_transcript is protected

    -- Open a log file. Set append=true to accumulate across runs.
    procedure open_transcript  (filename : in string;
                                 append   : in boolean := false);

    -- Flush and close the current log file.
    procedure close_transcript;

    -- When true (default), every line is also written to the console.
    procedure set_mirror       (en : in boolean);

    impure function is_open    return boolean;

    -- Primary output call: writes msg + newline to active destinations.
    procedure print_line       (msg : in string);

  end protected t_transcript;

  -- Global singleton — visible to alert_log_pkg and scoreboard_pkg.
  shared variable Transcript : t_transcript;

end package transcript_pkg;

-- =============================================================================

library std;
use std.textio.all;

package body transcript_pkg is

  type t_transcript is protected body

    file     trans_file  : text;
    variable v_open      : boolean := false;
    variable v_mirror    : boolean := true;   -- echo to console by default

    -- -----------------------------------------------------------------
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
        print_line("=== Transcript opened: " & filename & " ===");
      else
        report "[Transcript] Failed to open file: " & filename
          severity error;
      end if;
    end procedure;

    -- -----------------------------------------------------------------
    procedure close_transcript is
    begin
      if v_open then
        print_line("=== Transcript closed ===");
        file_close(trans_file);
        v_open := false;
      end if;
    end procedure;

    -- -----------------------------------------------------------------
    procedure set_mirror (en : in boolean) is
    begin
      v_mirror := en;
    end procedure;

    -- -----------------------------------------------------------------
    impure function is_open return boolean is
    begin
      return v_open;
    end function;

    -- -----------------------------------------------------------------
    -- writeline deallocates the line after writing, so we must call
    -- write() separately for each destination.
    procedure print_line (msg : in string) is
      variable l : line;
    begin
      if v_mirror then
        write(l, string'(msg));
        writeline(OUTPUT, l);       -- console
      end if;
      if v_open then
        write(l, string'(msg));
        writeline(trans_file, l);   -- log file
      end if;
    end procedure;

  end protected body t_transcript;

end package body transcript_pkg;
