# APEX Safety FSM (SystemVerilog)

[![sim](https://github.com/efedemi/apex-safety-fsm/actions/workflows/ci.yml/badge.svg)](https://github.com/efedemi/apex-safety-fsm/actions/workflows/ci.yml)

A hardware (RTL) safety supervisor for an FPGA-controlled autonomous vehicle. It
arbitrates between three modes — **Standby**, **Autonomous**, and **Emergency** —
and guarantees one thing above all: **an emergency stop preempts the AI from any
state, forces the motors off, and stays latched until a human clears it.**

This is the RTL re-implementation of the safety state machine I originally wrote
in C firmware for **APEX**, an FPGA-supervised autonomous vehicle with on-chip
Edge-AI (SJSU EE277, Embedded SoC Design). In APEX the FSM ran on an ARM
Cortex-M0 soft-core; here the same logic is synthesizable hardware.

## State diagram

```
                 btn_auto
   reset      ┌────────────► ┌─────────────┐
     │        │              │ AUTONOMOUS  │   motor_cmd = AI command
     ▼        │   btn_resume │ (GO/SLOW/   │   (GO / SLOW / STOP)
 ┌─────────┐  │  ◄────────── │   STOP)     │
 │ STANDBY │──┘              └─────────────┘
 │ motors  │                        │
 │  off    │                        │ btn_estop
 └─────────┘   btn_estop            │
     │  └──────────────┐            │
     │   (from ANY     ▼            ▼
     └──────────► ┌──────────────────────────────┐
                  │          EMERGENCY            │
                  │  motor_cmd = STOP (forced)    │
                  │  LATCHED — AI / btn_auto can  │
                  │  NOT clear it. Only operator  │
                  │  btn_resume (after e-stop     │
                  │  released) returns to STANDBY │
                  └──────────────────────────────┘
```

## Interface

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `clk` | in | 1 | clock |
| `rst_n` | in | 1 | async, active-low reset → STANDBY |
| `btn_auto` | in | 1 | STANDBY → AUTONOMOUS (debounced upstream) |
| `btn_estop` | in | 1 | emergency stop, highest priority, any state |
| `btn_resume` | in | 1 | operator-only clear of EMERGENCY |
| `ai_cmd` | in | 2 | AI decision: 0=GO, 1=SLOW, 2=STOP (used in AUTONOMOUS) |
| `state` | out | 2 | 0=STANDBY, 1=AUTONOMOUS, 2=EMERGENCY |
| `motor_cmd` | out | 2 | 0=STOP, 1=SLOW, 2=GO |
| `emergency` | out | 1 | high while latched in EMERGENCY |

## Simulate

```bash
# Icarus Verilog
iverilog -g2012 -o sim.out rtl/safety_fsm.sv tb/safety_fsm_tb.sv
vvp sim.out                 # prints PASS/FAIL, writes safety_fsm.vcd
gtkwave safety_fsm.vcd      # view waveforms

# or in Vivado: add both files, set safety_fsm_tb as top, Run Simulation
```

The self-checking testbench covers reset, mode entry, AI-driven motion, and every
safety case: e-stop overriding `AI=GO`, the AI/auto button failing to clear
EMERGENCY, and operator-only recovery.

## Design decisions (the things an interviewer will ask)

- **Why is `btn_estop` checked first in next-state logic?** Priority encoding =
  the safety guarantee. Evaluated before any per-state branch, so it wins from
  every state — including mid-`GO`.
- **Why latch EMERGENCY and require an operator to clear it?** Fail-safe: a
  software/AI fault must never be able to "drive out" of a stop. Clearing is a
  deliberate human action (`btn_resume`) and only after e-stop is released.
- **Async reset to STANDBY.** Power-on / fault always lands in the safe,
  motors-off state.
- **Moore outputs.** `motor_cmd` is a function of `state` (AUTONOMOUS also passes
  the AI command); state is registered, outputs are combinational.
- **Unknown `ai_cmd` → STOP.** Default branch fails safe rather than moving.
- **`unique case` + `default`.** Flags overlapping/missing cases in sim and
  recovers from an illegal state.
- **Button synchronization is assumed upstream.** Real buttons need a
  debouncer + 2-FF synchronizer to avoid metastability; kept out of this module
  to isolate the control logic (a natural follow-up module).

## Next in this portfolio

1. **`uart` + `fifo`** — the data-path building blocks.
2. **`qos_scheduler`** — the hardware safety-latency scheduler APEX listed as its
   own "what's next" (slide 14). Enforces the 2 ms budget in RTL, not just by
   measurement.
3. **AHB-Lite peripheral** wrapper so this FSM is addressable from the Cortex-M0,
   closing the loop back to the real APEX SoC.

---
*Built by Efe Demir. RTL authored from my own APEX firmware design; verified with
the included self-checking testbench.*
