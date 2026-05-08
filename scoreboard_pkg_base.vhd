-- =============================================================================
-- scoreboard_pkg.vhd
-- Out-of-order scoreboard using a string-based linked list.
-- Overloads for the most common VHDL types.
-- No external dependencies — uses bare VHDL report statements.
--
-- Compile order : 1  (no dependencies)
-- VHDL standard : 2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;

package scoreboard_pkg is

  type t_scoreboard is protected

    -- Label used in all report messages.
    -- Call once before push/check. Defaults to "SB" if not called.
    procedure set_name (name : in string);

    -- ── String base ──────────────────────────────────────────────────────────
    procedure push  (tag      : in  integer;
                     expected : in  string);

    procedure check (tag      : in  integer;
                     actual   : in  string;
                     pass     : out boolean);

    -- ── integer ──────────────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in integer);
    procedure check (tag : in integer; actual   : in integer;
                     pass : out boolean);

    -- ── boolean ──────────────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in boolean);
    procedure check (tag : in integer; actual   : in boolean;
                     pass : out boolean);

    -- ── std_logic ────────────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in std_logic);
    procedure check (tag : in integer; actual   : in std_logic;
                     pass : out boolean);

    -- ── std_logic_vector ─────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in std_logic_vector);
    procedure check (tag : in integer; actual   : in std_logic_vector;
                     pass : out boolean);

    -- ── unsigned ─────────────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in unsigned);
    procedure check (tag : in integer; actual   : in unsigned;
                     pass : out boolean);

    -- ── signed ───────────────────────────────────────────────────────────────
    procedure push  (tag : in integer; expected : in signed);
    procedure check (tag : in integer; actual   : in signed;
                     pass : out boolean);

    -- ── Control ──────────────────────────────────────────────────────────────

    -- Remove an entry without checking (e.g. on error recovery).
    procedure pop   (tag : in integer);

    -- Remove all pending entries and reset counts.
    procedure flush;

    -- Print a pass/fail summary; call at end of test.
    procedure report_status;

    impure function size       return natural;
    impure function is_empty   return boolean;
    impure function pass_count return natural;
    impure function fail_count return natural;

  end protected t_scoreboard;

end package scoreboard_pkg;

-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;

package body scoreboard_pkg is

  type t_scoreboard is protected body

    -- ── Private linked-list types ─────────────────────────────────────────────
    type t_node;
    type t_node_ptr is access t_node;
    type t_node is record
      tag      : integer;
      expected : line;        -- heap-allocated string, any length
      next     : t_node_ptr;
    end record;

    -- ── State ─────────────────────────────────────────────────────────────────
    variable head      : t_node_ptr := null;
    variable count     : natural    := 0;
    variable pass_cnt  : natural    := 0;
    variable fail_cnt  : natural    := 0;
    variable sb_name   : line       := new string'("SB");

    -- ── Private helpers ───────────────────────────────────────────────────────
    impure function pfx return string is
    begin
      return "[" & sb_name.all & "] ";
    end function;

    procedure find_node (tag   : in  integer;
                         found : out t_node_ptr;
                         prev  : out t_node_ptr) is
      variable curr : t_node_ptr := head;
      variable prv  : t_node_ptr := null;
    begin
      found := null;  prev := null;
      while curr /= null loop
        if curr.tag = tag then
          found := curr;  prev := prv;  return;
        end if;
        prv  := curr;
        curr := curr.next;
      end loop;
    end procedure;

    procedure remove_node (node : inout t_node_ptr;
                           prev : inout t_node_ptr) is
    begin
      if prev = null then
        head := node.next;
      else
        prev.next := node.next;
      end if;
      deallocate(node.expected);
      deallocate(node);
      count := count - 1;
    end procedure;

    -- ── Public: set_name ──────────────────────────────────────────────────────
    procedure set_name (name : in string) is
    begin
      deallocate(sb_name);
      sb_name := new string'(name);
    end procedure;

    -- ── Public: base string push ──────────────────────────────────────────────
    procedure push (tag : in integer; expected : in string) is
      variable n : t_node_ptr;
    begin
      n          := new t_node;
      n.tag      := tag;
      n.expected := new string'(expected);
      n.next     := head;
      head       := n;
      count      := count + 1;
    end procedure;

    -- ── Public: base string check ─────────────────────────────────────────────
    procedure check (tag    : in  integer;
                     actual : in  string;
                     pass   : out boolean) is
      variable found : t_node_ptr;
      variable prev  : t_node_ptr;
    begin
      find_node(tag, found, prev);

      if found = null then
        report pfx & "ORPHAN  tag=" & integer'image(tag) &
               "  actual=" & actual
          severity error;
        fail_cnt := fail_cnt + 1;
        pass := false;
        return;
      end if;

      if actual = found.expected.all then
        pass_cnt := pass_cnt + 1;
        pass := true;
        report pfx & "PASS  tag=" & integer'image(tag) &
               "  value=" & actual
          severity note;
      else
        fail_cnt := fail_cnt + 1;
        pass := false;
        report pfx & "FAIL  tag="   & integer'image(tag) &
               "  expected="        & found.expected.all &
               "  actual="          & actual
          severity error;
      end if;

      remove_node(found, prev);
    end procedure;

    -- ── Overloads — all delegate to string base ───────────────────────────────

    procedure push (tag : in integer; expected : in integer) is
    begin push(tag, integer'image(expected)); end procedure;

    procedure push (tag : in integer; expected : in boolean) is
    begin push(tag, boolean'image(expected)); end procedure;

    procedure push (tag : in integer; expected : in std_logic) is
    begin push(tag, std_logic'image(expected)); end procedure;

    procedure push (tag : in integer; expected : in std_logic_vector) is
    begin push(tag, to_hstring(expected)); end procedure;

    procedure push (tag : in integer; expected : in unsigned) is
    begin push(tag, to_hstring(expected)); end procedure;

    procedure push (tag : in integer; expected : in signed) is
    begin push(tag, to_hstring(expected)); end procedure;

    -- -------------------------------------------------------------------------
    procedure check (tag : in integer; actual : in integer;
                     pass : out boolean) is
    begin check(tag, integer'image(actual), pass); end procedure;

    procedure check (tag : in integer; actual : in boolean;
                     pass : out boolean) is
    begin check(tag, boolean'image(actual), pass); end procedure;

    procedure check (tag : in integer; actual : in std_logic;
                     pass : out boolean) is
    begin check(tag, std_logic'image(actual), pass); end procedure;

    procedure check (tag : in integer; actual : in std_logic_vector;
                     pass : out boolean) is
    begin check(tag, to_hstring(actual), pass); end procedure;

    procedure check (tag : in integer; actual : in unsigned;
                     pass : out boolean) is
    begin check(tag, to_hstring(actual), pass); end procedure;

    procedure check (tag : in integer; actual : in signed;
                     pass : out boolean) is
    begin check(tag, to_hstring(actual), pass); end procedure;

    -- ── pop / flush ───────────────────────────────────────────────────────────
    procedure pop (tag : in integer) is
      variable found : t_node_ptr;
      variable prev  : t_node_ptr;
    begin
      find_node(tag, found, prev);
      if found /= null then
        remove_node(found, prev);
      end if;
    end procedure;

    procedure flush is
      variable curr : t_node_ptr;
      variable tmp  : t_node_ptr;
    begin
      curr := head;
      while curr /= null loop
        tmp  := curr.next;
        deallocate(curr.expected);
        deallocate(curr);
        curr := tmp;
      end loop;
      head     := null;
      count    := 0;
    end procedure;

    -- ── report_status ─────────────────────────────────────────────────────────
    procedure report_status is
      variable total : natural := pass_cnt + fail_cnt;
    begin
      report pfx & "─── Scoreboard Summary ───────────────" severity note;
      report pfx & "  Total   : " & integer'image(total)    severity note;
      report pfx & "  Passed  : " & integer'image(pass_cnt) severity note;
      report pfx & "  Failed  : " & integer'image(fail_cnt) severity note;

      if count > 0 then
        report pfx & "  Pending : " & integer'image(count) &
               " entries never checked!" severity error;
      end if;

      if fail_cnt = 0 and count = 0 then
        report pfx & "  Result  : *** PASS ***" severity note;
      else
        report pfx & "  Result  : *** FAIL ***" severity error;
      end if;
    end procedure;

    -- ── Queries ───────────────────────────────────────────────────────────────
    impure function size       return natural is begin return count;      end function;
    impure function is_empty   return boolean is begin return count = 0; end function;
    impure function pass_count return natural is begin return pass_cnt;  end function;
    impure function fail_count return natural is begin return fail_cnt;  end function;

  end protected body t_scoreboard;

end package body scoreboard_pkg;
