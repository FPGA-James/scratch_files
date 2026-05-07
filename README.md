# Lightweight VHDL Verification Package Stack

Three small, dependency-ordered packages that together cover transcript
logging, structured alerting, and an out-of-order scoreboard — with no
external tool or framework dependency.

---

## Files

| File | Purpose | Compile order |
|------|---------|---------------|
| `transcript_pkg.vhd` | Write output to a log file and/or console | 1 |
| `alert_log_pkg.vhd`  | Named IDs, alert counts, pass/fail summary | 2 |
| `scoreboard_pkg.vhd` | Out-of-order scoreboard with type overloads | 3 |
| `tb_example.vhd`     | Example testbench demonstrating all features | 4 |

---

## Compilation

Compile into a single work library in order:

### GHDL
```bash
ghdl -a --std=08 transcript_pkg.vhd
ghdl -a --std=08 alert_log_pkg.vhd
ghdl -a --std=08 scoreboard_pkg.vhd
ghdl -a --std=08 tb_example.vhd
ghdl -e --std=08 tb_example
ghdl -r --std=08 tb_example
```

### ModelSim / Questa
```tcl
vcom -2008 transcript_pkg.vhd
vcom -2008 alert_log_pkg.vhd
vcom -2008 scoreboard_pkg.vhd
vcom -2008 tb_example.vhd
vsim work.tb_example
run -all
```

### Vivado (xsim)
```tcl
xvhdl --2008 transcript_pkg.vhd
xvhdl --2008 alert_log_pkg.vhd
xvhdl --2008 scoreboard_pkg.vhd
xvhdl --2008 tb_example.vhd
xelab tb_example -debug all
xsim tb_example -runall
```

---

## Quick-start usage

```vhdl
library work;
use work.transcript_pkg.all;
use work.alert_log_pkg.all;
use work.scoreboard_pkg.all;

-- Declare as many scoreboards as you need
shared variable sb_data : t_scoreboard;
shared variable sb_ctrl : t_scoreboard;

process
  variable pass : boolean;
begin
  -- 1. Open log file (console mirror is on by default)
  Transcript.open_transcript("my_test.log");

  -- 2. Configure AlertLog
  AlertLog.set_log_enable(AL_DEBUG, false);  -- suppress push messages
  AlertLog.set_stop_count(AL_ERROR, 10);     -- stop sim after 10 errors

  -- 3. Name scoreboards (registers them with AlertLog)
  sb_data.set_name("AXI-DATA");
  sb_ctrl.set_name("AXI-CTRL");

  -- 4. Push expected values (any supported type)
  sb_data.push(tag => 1, expected => x"DEADBEEF");   -- std_logic_vector
  sb_data.push(tag => 2, expected => to_unsigned(42, 8));
  sb_ctrl.push(tag => 10, expected => true);

  -- 5. Check results — arrive in any order
  sb_data.check(tag => 2, actual => result_u,   pass => pass);
  sb_data.check(tag => 1, actual => result_slv, pass => pass);
  sb_ctrl.check(tag => 10, actual => result_b,  pass => pass);

  -- 6. End-of-test summary
  AlertLog.report_alerts;
  Transcript.close_transcript;
  wait;
end process;
```

---

## Supported types (scoreboard overloads)

| Type | Stored as |
|------|-----------|
| `string` | direct (base) |
| `integer` | `integer'image` |
| `boolean` | `boolean'image` |
| `std_logic` | `std_logic'image` |
| `std_logic_vector` | `to_hstring` |
| `unsigned` | `to_hstring` |
| `signed` | `to_hstring` |

### Adding your own type

```vhdl
-- 1. Write a conversion function
function to_sb_str(r : t_my_record) return string is
begin
  return to_hstring(r.addr) & "|" & integer'image(r.length);
end function;

-- 2. Use the string base directly
sb_data.push(tag => 5, expected => to_sb_str(expected_rec));
sb_data.check(tag => 5, actual  => to_sb_str(actual_rec), pass => pass);
```

The only rule: **push and check must use the same conversion** for a given type.

---

## Alert levels

| Level | Counted | Stops sim | Triggers VHDL severity |
|-------|---------|-----------|------------------------|
| `AL_WARNING` | Yes | No (configurable) | warning |
| `AL_ERROR` | Yes | No (configurable) | — (transcript only) |
| `AL_FAILURE` | Yes | Yes (default 1) | failure |

## Log levels

| Level | Default | Notes |
|-------|---------|-------|
| `AL_DEBUG` | Off | Includes PUSH messages from scoreboard |
| `AL_INFO` | On | Includes PASS messages from scoreboard |
| `AL_ALWAYS` | On | Cannot be disabled |

---

## Extending MAX_IDS

The alert log supports up to 64 named components by default.
To increase the limit, change the constant in `alert_log_pkg.vhd`:

```vhdl
constant MAX_IDS : positive := 128;   -- or any value up to t_alert_log_id'high
```

And widen the subtype if needed:

```vhdl
subtype t_alert_log_id is natural range 0 to 127;
```

---

## Architecture

```
scoreboard_pkg      push / check / pop / flush
      |  calls
      v
alert_log_pkg       affirm_if_equal / alert / log / report_alerts
      |  calls
      v
transcript_pkg      print_line → writeline(file) + writeline(OUTPUT)
```
