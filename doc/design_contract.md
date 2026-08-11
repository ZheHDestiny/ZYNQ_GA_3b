# GA3B v1-min hardware design contract

This contract is normative for the routed ZYNQ-7020 `pure3` fallback and for
future restricted4 implementations. A change that violates it is not accepted
even if a one-shot smoke test passes.

## 1. AXI-Stream transfer contract

- A beat transfers only on a rising edge where `TVALID && TREADY` is true.
- The producer holds `TDATA`, `TLAST`, and `TVALID` stable while stalled.
- The consumer must not change packet state from `TVALID` alone.
- `TLAST` is asserted on exactly the final task/result word.
- After a result packet, the next task magic may be presented while `TREADY` is
  low and must be consumed exactly once when `TREADY` returns high.

## 2. Synchronous memory contract

- BRAM/read latency is explicit in the FSM; no state consumes a registered RAM
  output in the same cycle that its registered address is issued.
- The current task must overwrite every population word before that word is
  read. Memory contents do not need a global clear if this rule is satisfied.
- Read/write collisions must either be structurally impossible or have a
  defined and simulated memory mode.

## 3. Re-entrant task contract

- The accelerator accepts another task after completing the previous result
  packet without requiring FPGA reconfiguration or PS restart.
- Task start reinitializes run-local state: RNG seed/state, generation and
  individual indices, best index/fitness/steps/chromosome, errors, and valid
  pipeline state.
- A result must not depend on a previous task's seeds, population, RAM output,
  backpressure history, or best chromosome.
- `soft_reset` clears the accelerator transaction state but does not replace
  correct per-task initialization.

## 4. Determinism contract

For equal task words, equal build profile, and equal clock/reset behavior:

- all 14 words of the `pure3` SearchResult are bit-identical;
- fixed-seed RTL validation sends at least two tasks without reset;
- board acceptance sends at least 100 tasks through the persistent PS/DMA
  agent and requires 100/100 identical results, no timeout, and no protocol
  error.

## 5. Build provenance contract

- A bitstream is valid only if every custom RTL source is no newer than its OOC
  DCP and the top synthesis/implementation checkpoints were generated after it.
- Vivado IP cache must be invalidated when module-reference RTL changes. A
  successful cached build is not evidence that changed RTL entered hardware.
- Post-route timing must satisfy the 10 ns clock: `WNS >= 0`, `TNS = 0`.
- DRC must report zero errors.
- Reports, bitstream, XSA, board-test JSON, and BOOT.BIN belong to the same
  accepted build generation.

## 6. Current accepted profile

- Device: `xc7z020clg400-2`.
- Profile register: `0x00000003` (`pure3` resource-fit fallback).
- Version register: `0x00010000`.
- Clock: 100 MHz.
- The restricted4 Heng-era model remains the scientific main target, but it is
  not represented by this accepted 7020 bitstream.
