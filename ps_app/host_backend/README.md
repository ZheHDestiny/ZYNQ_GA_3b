# GA3B v1.1 PC HTTP backend

The backend owns the board UART, exposes a same-origin HTTP API, and serves the
static Web dashboard. Normal operation is:

```text
Browser -> Flask -> COM UART -> bare-metal board_agent -> AXI DMA -> Pure3 PL
```

## Start

Close every serial terminal that is using the board COM port, then run from the
repository root:

```powershell
.\scripts\run\run_v1_web_demo.ps1 -Port COM13
```

The launcher opens <http://127.0.0.1:8000/>. Stop it with `Ctrl+C`.

## API

- `GET /api/health`
- `GET /api/capabilities`
- `POST /api/selftest`
- `POST /api/search`
- `POST /api/estimate`
- `POST /api/custom-replay`
- `POST /api/performance/probe`
- `GET /api/results` and `GET /api/results/<id>`
- `GET /api/presets` and `POST /api/presets/<id>/run`

## Decimal parameter semantics and result storage

The Web UI intentionally does not expose hexadecimal values:

- `x0/y0/x1/y1` are normalized center-of-mass-frame positions.
- `vx0/vy0/vx1/vy1` are normalized velocities.
- Physical values are decoded Q16.16 numbers. The accompanying signed Q16
  integer is `physical_value * 65536` rounded to the nearest integer.
- Mutation/crossover inputs are decimal unsigned Q16 probabilities in
  `0..65535`; probability is `value / 65536`.
- Seeds are shown as signed decimal 32-bit values. The service masks them to
  the same two's-complement 32-bit pattern used by the FPGA RNG.
- Fitness is displayed as an unsigned decimal 64-bit integer.

Search and custom-replay responses are automatically stored in
`doc/test_results/ga3b_results.sqlite3`. This local database is ignored
by Git. Preset definitions are versioned in
`ps_app/host_backend/presets/trajectory_templates.json`.

The four labels are finite-window classifiers, not mathematical proofs.
“Long survival” does not imply infinite stability, and “near recurrence” does
not imply an exact periodic orbit.

Example:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health

Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/search `
  -ContentType application/json `
  -Body '{"max_gen":2,"steps":256,"mutation_q16":4096,"crossover_q16":49152,"seed0":305419896,"seed1":-2023406815}'
```

The trajectory is a PC replay of the returned FPGA chromosome using the same
approximate Q16.16 integration rules. It is not a live stream of PL internal
states. The current Zynq-7020 profile is the Pure3 resource-fit fallback.

The four browser objective profiles (`survival`, `close_pass`, `braid`, and
`recurrence`) use multi-start FPGA searches followed by physically interpretable
host-side trajectory re-ranking. The deployed PL fitness remains the survival
fitness. A response includes `profile_match`; the UI warns when the best
available candidate does not actually satisfy the selected criterion.

Custom initial states are validated on both client and server and replayed by
the PC RTL-compatible model. The current board protocol cannot inject one
chromosome directly into the PL lane, so the UI labels this mode `PC
RTL-COMPATIBLE REPLAY` instead of presenting it as FPGA execution.

## Performance probe boundary

The FPGA measurement contains the complete GA, DMA and UART round trip. The
Python scalar and NumPy measurements are fitness-only workload proxies for the
same count of candidate evaluations. The UI therefore reports throughput and
the measurement boundary instead of claiming an algorithm-identical speedup.
The browser uses a reproducible bounded workload (`max_gen=8`, `steps=8192`,
two hardware samples, fixed seeds). The API clamps probe requests to at most
8 generations, 8192 steps and 3 hardware samples so that the comparison is
large enough to expose FPGA throughput but remains interactive.
