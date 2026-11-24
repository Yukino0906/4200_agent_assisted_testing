# 4200A Agent Kit

> **Setting up on a new PC? Start with [START_HERE.md](START_HERE.md)** (clone, open Claude
> Code, first message).

MATLAB code and instructions for automated electrical tests of memristive / RRAM devices
on a probe station with a **Keithley 4200A-SCS** (one SMU, one 4225-PMU, two 4225-RPMs).
The laptop is the control centre: the kit and, optionally, an AI coding agent (Claude
Code, Codex, Cursor, ...) run there and drive the 4200A through Keithley's **KXCI**
interface over an Ethernet cable or GPIB. Nothing is installed on the 4200A.

Reads and DC sweeps use the SMU (with compliance). Write pulses use the PMU: hardware-timed
trapezoids from sub-µs to ms, with the voltage and current measured on the pulse top.
**The PMU has no current compliance** — read [docs/05_safety.md](docs/05_safety.md)
section 3 before the first pulse.

| Test | Function | Example (runs + plots) |
|---|---|---|
| DC I-V cycling | `run_dc_cycle_test` | `example_iv` |
| LTP / LTD pulse trains | `run_ltp_ltd_test` | `example_ltp_ltd` |
| Single-pulse map ΔG(G, V, t) | `run_single_pulse_map` | `example_single_pulse_map` |
| Endurance | `run_endurance_test` | `example_endurance` |
| Retention | `run_retention_hold_test` | `example_retention` |
| Read noise | `run_read_noise_test` | `example_read_noise` |
| Relaxation (short-term drift) | `run_relaxation_test` | `example_relaxation` |
| Anything else | copy `example_custom_test_skeleton` | — |

Every test validates its configuration, asks before it applies voltage, writes each
measurement to disk as it happens, and turns every output off however it ends.

## Try it in five minutes (no instrument)

```matlab
cd <path to>\4200A_agent_kit
setup_paths
test_dry_run          % simulator + a software 4200A (KxciMock); must end "0 failed"
example_iv            % simulated DC I-V, saves a plot
example_ltp_ltd       % simulated LTP/LTD
```

The simulator is a toy, and the KXCI mock encodes the kit's assumptions about KXCI. Both
exist to rehearse and to test the code, not to predict a device or the real instrument.

## On a new PC

`check_setup` (or `check_setup('<4200A IP>')`) checks MATLAB, the Instrument Control
Toolbox, NI-VISA, the network adapters and the regression suite, without contacting the
instrument. The state of this particular setup and the next steps are in
[HANDOFF.md](HANDOFF.md).

## First time on the real instrument

1. Network, KCon and KXCI on the 4200A, IP on the laptop, wiring:
   [docs/01_setup.md](docs/01_setup.md).
2. `test_instrument_connection` — talks to KXCI at 0 V only. Safe with probes down.
3. **Bring-up on resistors**: [docs/07_bring_up.md](docs/07_bring_up.md). It checks every
   KXCI assumption the kit makes (acknowledge text, reply format, RPM path codes, pulse
   timing, current sign, the software current limit). Fill in its record.
4. Copy `config/device_TEMPLATE.m` to `config/device_<sample>_<R#C#>_<purpose>.m`, rename the
   function inside, fill in the device ID, voltage ceiling, compliance, read bias and the
   PMU current limits. Set `cfg.mode.simulate_instrument = false` and `cfg.mode.dry_run = false`.
5. Read the numbers once more, then set `cfg.safety.compliance_confirmed`,
   `cfg.safety.limits_confirmed` and `cfg.pmu.no_compliance_acknowledged` to `true`.
   Nothing runs on hardware until you do.
6. Land the probes, then: `cfg = device_<...>(); test_read_only(cfg)` — contact check and
   ten reads.
7. A small DC I-V first (`example_iv(cfg)`, ±0.5–1.0 V, 3 cycles); forming and the first SET
   only with the SMU.
8. `test_single_safe_pulse(cfg)` — width check at the read voltage, then one gentle PMU pulse.
9. Then the other tests, in the order of [docs/03_test_recipes.md](docs/03_test_recipes.md).

Each test stops at a checkpoint that prints every voltage, compliance and count, and waits
for `y`.

## Working with an AI agent

1. Open the agent in this folder. It reads `AGENTS.md` (Claude Code reads it through
   `CLAUDE.md`).
2. Describe the test with numbers, using the template in
   [docs/02_how_to_ask_agent.md](docs/02_how_to_ask_agent.md).
3. The agent replies with a specification table and waits. Check it and say "yes".
4. It rehearses on the simulator, runs a small version, then the full run, and reports
   with a plot.

The agent must not raise voltage, compliance or PMU current limits, skip checks, or
confirm the safety flags on its own. If it tries, stop it.

## Where the data goes

```
data/raw/<yyyy-mm-dd_HHMMSS>_device_<id>_<test>/
    measurement_data.csv   one row per measurement, written as it happens
    metadata.json / .mat   instrument, full configuration, status
    run_summary.txt        what ran, how it ended
    instrument_log.txt     every KXCI command and reply
    <plot>.png             from the example wrappers
```

Load a run with `T = load_run_csv(r)` (or `load_run_csv('<run folder>')`).
Never edit files under `data/raw/`.

## Stopping

- **Ctrl+C** in MATLAB: every output goes off automatically.
- **MATLAB was killed** (Task Manager, crash, agent timeout): cleanup did not run. Start
  MATLAB, `setup_paths; test_instrument_connection`, and check the KXCI window.

## Documentation

| File | For | Content |
|---|---|---|
| [docs/01_setup.md](docs/01_setup.md) | everyone | software, network, KCon/KXCI, wiring, folder layout |
| [docs/02_how_to_ask_agent.md](docs/02_how_to_ask_agent.md) | people | request template and examples for every test |
| [docs/03_test_recipes.md](docs/03_test_recipes.md) | everyone | each test: procedure, parameters, outputs, mistakes |
| [docs/04_kxci_cheatsheet.md](docs/04_kxci_cheatsheet.md) | agents, coders | every KXCI command the kit sends, and how sure we are of it |
| [docs/05_safety.md](docs/05_safety.md) | everyone | protection layers, the PMU without compliance, stop rules, recovery |
| [docs/06_pitfalls.md](docs/06_pitfalls.md) | everyone | measurement traps and how to avoid them |
| [docs/07_bring_up.md](docs/07_bring_up.md) | everyone | resistor checklist before the first device |
| [AGENTS.md](AGENTS.md) | agents | hard boundaries, workflow, coding rules |

## Hard rules (short version)

- Never exceed the voltage ceiling in the device file; the code refuses anything above 5 V.
- Explicit SMU compliance for every run; start at 1 mA or lower. PMU pulses have none: set a
  current limit, keep pulses short, form with the SMU.
- Bring-up on resistors before the first device.
- Simulate first; small run before the full run.
- A refusal or an abnormal device means stop and report, not retry harder.
- Do not edit code while a measurement runs. Do not drive from Clarius at the same time.
