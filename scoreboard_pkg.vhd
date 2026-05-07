-- =============================================================================
-- scoreboard_pkg.vhd
-- Out-of-order scoreboard using a string-based linked list.
-- Overloads for the most common VHDL types.
-- Integrates with alert_log_pkg for consistent pass/fail reporting.
--
-- Compile order : 3  (depends on alert_log_pkg, transcript_pkg)
-- VHDL standard : 2008
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;
use work.transcript_pkg.all;
use work.alert_log_pkg.all;

package scoreboard_pkg is

  type t_scoreboard is protected

    -- Register this scoreboard with AlertLog under the given name.
    -- Call once before push/check. Defaults to "SCOREBOARD" if not called.
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

    impure function size     return natural;
    impure function is_empty return boolean;

  end protected t_scoreboard;

end package scoreboard_pkg;

-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
library work;
use work.transcript_pkg.all;
use work.alert_log_pkg.all;

package body scoreboard_pkg is

  type t_scoreboard is protected body

    -- ── Private linked-list types (not visible outside the protected body) ───
    type t_node;
    type t_node_ptr is access t_node;
    type t_node is record
      tag      : integer;
      expected : line;          -- heap-allocated string, any length
      next     : t_node_ptr;
    end record;

    -- ── State ────────────────────────────────────────────────────────────────
    variable head        : t_node_ptr    := null;
    variable count       : natural       := 0;
    variable al_id       : t_alert_log_id := 0;
    variable initialized : boolean       := false;

    -- ── Private: lazy initialization ─────────────────────────────────────────
    procedure ensure_init is
    begin
      if not initialized then
        al_id       := AlertLog.get_id("SCOREBOARD");
        initialized := true;
      end if;
    end procedure;

    -- ── Private: linked-list helpers ─────────────────────────────────────────
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

    -- ── Public: set_name ─────────────────────────────────────────────────────
    procedure set_name (name : in string) is
    begin
      al_id       := AlertLog.get_id(name);
      initialized := true;
    end procedure;

    -- ── Public: base string push/check ───────────────────────────────────────
    procedure push (tag : in integer; expected : in string) is
      variable n : t_node_ptr;
    begin
      ensure_init;
      n          := new t_node;
      n.tag      := tag;
      n.expected := new string'(expected);
      n.next     := head;
      head       := n;
      count      := count + 1;
      AlertLog.log(al_id,
        "PUSH  tag=" & integer'image(tag) &
        "  expected=" & expected,
        AL_DEBUG);
    end procedure;

    procedure check (tag    : in  integer;
                     actual : in  string;
                     pass   : out boolean) is
      variable found : t_node_ptr;
      variable prev  : t_node_ptr;
    begin
      ensure_init;
      find_node(tag, found, prev);

      if found = null then
        AlertLog.alert(al_id,
          "ORPHAN  tag=" & integer'image(tag) &
          "  actual=" & actual);
        pass := false;
        return;
      end if;

      -- affirm_if_equal raises an alert on mismatch and logs the values.
      AlertLog.affirm_if_equal(al_id,
        actual, found.expected.all,
        "tag=" & integer'image(tag));

      pass := (actual = found.expected.all);

      if pass then
        AlertLog.log(al_id,
          "PASS  tag=" & integer'image(tag) & "  value=" & actual,
          AL_INFO);
      end if;

      remove_node(found, prev);
    end procedure;

    -- ── Public: overloads — all delegate to the string base ──────────────────
    --    push and check use identical conversions so comparisons are symmetric.

    procedure push (tag : in integer; expected : in integer) is
    begin push(tag, integer'image(expected)); end procedure;

    procedure push (tag : in integer; expected : in boolean) is
    begin push(tag, boolean'image(expected)); end procedure;

    procedure push (tag : in integer; expected : in std_logic) is
    begin push(tag, std_logic'image(expected)); end procedure;

    -- std_logic_vector: hex string (compact, width-agnostic).
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

    -- ── Public: pop / flush / queries ────────────────────────────────────────
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
      head  := null;
      count := 0;
    end procedure;

    impure function size     return natural is begin return count;      end function;
    impure function is_empty return boolean is begin return count = 0; end function;

  end protected body t_scoreboard;

end package body scoreboard_pkg;
