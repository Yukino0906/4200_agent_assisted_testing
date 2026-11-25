# Agent instructions — 4200A Agent Kit

This file is for AI coding agents (Claude Code, Codex, Cursor, ...) working in this folder.
Humans: start with [README.md](README.md).

You operate a **Keithley 4200A-SCS parameter analyzer** (one SMU, one 4225-PMU with two
4225-RPMs) on a probe station, from MATLAB on a laptop, through Keithley's **KXCI** interface
over Ethernet or GPIB, to characterise memristive / RRAM devices. Reads and DC sweeps use
the SMU; write pulses use the PMU, which has **no current compliance**. A mistake here
destroys a device or wastes a day of someone's measurement time. Follow this file exactly.

- Reply to the user in the language they write in; chat may be in any language. Everything
  that belongs to the kit is English: code, comments, file names, docs, templates,
  `HANDOFF.md`, every `CLAUDE.md`. Inside `users/<name>/`, the person's own notes, README,
  device IDs, sample names, analysis files and data labels may be in any language (Chinese,
  Korean, ...). MATLAB file and function names and the `users/<name>` folder name stay ASCII
  (MATLAB identifier rules).
- Day-to-day procedure for people and agents: [docs/00_SOP.md](docs/00_SOP.md).
- Read, in this order, before your first hardware action in a session:
  1. this file
  2. [docs/05_safety.md](docs/05_safety.md) — safety layers, stop rules, recovery
  3. [docs/04_kxci_cheatsheet.md](docs/04_kxci_cheatsheet.md) — instrument language (KXCI, not
     SCPI, not TSP) and which of the kit's assumptions are verified
  4. [docs/07_bring_up.md](docs/07_bring_up.md) — the resistor checklist and its record for this setup
  5. [docs/03_test_recipes.md](docs/03_test_recipes.md) — what each test does, its parameters and outputs
  6. [docs/06_pitfalls.md](docs/06_pitfalls.md) — measurement traps that make good devices look bad

---

## 1. Hard boundaries

These rules have no exceptions. If a request conflicts with one, stop and say which rule.

1. **Voltage.** Never output more than `cfg.safety.max_abs_voltage`. Never raise that value
   unless the user explicitly gives a new number in chat for this device. The code refuses
   anything above 5 V whatever the config says; do not edit that check.
2. **Compliance.** Every run has an explicit SMU compliance for DC, pulse and read. Start at
   1 mA or lower. Raise it only when the user agrees and the data show clamping. **PMU
   pulses have no compliance**: `cfg.pmu.max_current_A`, `cfg.pmu.current_range_A` and any
   series resistor come from the user, never from you
   ([docs/05_safety.md](docs/05_safety.md) section 3).
3. **Confirmation gates.** `cfg.safety.compliance_confirmed`, `cfg.safety.limits_confirmed`
   and `cfg.pmu.no_compliance_acknowledged` stay `false` until the user has seen your
   specification table (section 3) and approved the limits in chat, in this session, for
   this device. Never carry an approval over to another device, another test with higher
   limits, or another session.
4. **Simulation first.** Every new or changed test runs on the simulator
   (`cfg.mode.simulate_instrument = true`) before it touches hardware.
5. **Regression before hardware.** After any `.m` change: `test_dry_run` must pass with
   0 failures and `checkcode` must report 0 messages on the changed files.
6. **One path to the output.** Bias reaches the device only through `set_voltage` or
   `apply_voltage_pulse`. Never use `kxci_write` / `kxci_query` / `writeline` to send `DV`
   with a level, `:PMU:OUTPUT:STATE <ch>, 1`, `:PMU:EXECUTE` or an RPM path change. Those two
   functions carry the voltage check, the abort check, the pulse budget, the path interlock
   and the dry-run block.
7. **Gate refusal = stop.** When `validate_config`, a checkpoint, a safety check or the
   user's stop criterion refuses, stop and report. Do not loosen a limit, skip a check or
   re-run with different settings to get past it unless the user tells you to.
8. **Device abnormality = stop.** Signs: resistance suddenly near the probe/line
   resistance (short), open circuit after a good read, window collapse, sustained compliance
   in read or pulse mode, repeated initialisation failures, `emergency_shutdown` in the log.
   Stop, keep all data, report what you saw. Do not keep pulsing a failing device.
9. **No edits during a run.** Never modify any `.m` file while a MATLAB measurement is
   running. MATLAB reloads changed files and the running test can crash mid-pulse.
10. **Timeouts.** A background hardware command needs a timeout longer than the whole
    procedure. A tool timeout that kills MATLAB mid-run leaves the instrument in an unknown
    state.
11. **After a killed MATLAB.** `onCleanup` does not run when the process is killed. Run
    `test_instrument_connection` (it resets the 4200A and turns every PMU and SMU output
    off) before anything else, and report what it printed.
12. **Data is append-only.** Never edit, move or delete files under `data/raw/` or any
    `users/<name>/data/raw/`. Every run gets its own new directory. Analysis writes new files
    next to, not over, the raw CSV.
13. **No device- or user-specific code in `src/`.** Device numbers live in
    `users/<owner>/config/device_*.m` (kit-level files such as the resistor bring-up in
    `config/`). A user's own tests and analysis live in `users/<owner>/tests/` and
    `analysis/`. Generic code must not branch on a device or user name.
14. **Report faithfully.** State failures, aborts, clamped pulses, initialisation misses and
    skipped steps plainly, with numbers. Never present simulator or mock output as device
    data.
15. **Bring-up before devices.** Do not run on a device until the record in
    [docs/07_bring_up.md](docs/07_bring_up.md) shows items A–C, E–G and I passed on this
    setup. Change a setting marked UNVERIFIED (`cfg.instrument.ack_pattern`,
    `cfg.pmu.rpm_code_smu`, ...) only as the outcome of a bring-up item, and say which.
16. **Forming and first SET use the SMU.** Never form or first-SET a fresh device with the
    PMU. Use a DC sweep or `cfg.pulse.timing_source = 'pc'`, with a low compliance.
17. **One controller.** Never drive the hardware while Clarius or another MATLAB session is
    in control. `connect_instruments` enforces this between MATLAB sessions with a lock
    (`data/instrument_lock.json`). `instrument_lock:InUse` means someone else is connected:
    report who and wait. Never delete the lock or set `lock_allow_stale` to get past it;
    only `test_instrument_connection` may clear a stale lock.
18. **One user's folder at a time.** This PC is shared; each person has `users/<name>/`
    ([users/README.md](users/README.md)) and normally opens their Claude session in it, so
    `users/<name>/CLAUDE.md` says whose work it is. In a session opened at the kit root, ask
    whose work a request is before writing a device file. Work only in that user's folder,
    record progress in its `NOTES.md`, and never edit, move or delete files in another
    user's folder unless that user asks. Changes to the shared kit are made only from a
    session at the kit root.

---

## 2. How the code is organised

```
config/default_config.m      every parameter, SI units, conservative defaults
config/device_TEMPLATE.m     copy per device: users/<owner>/config/device_<sample>_<R#C#>_<purpose>.m
src/instrument/              KXCI layer: transport (kxci_transact/write/query, reply
                             parsers), RPM path switching (kxci_select_path), connect,
                             configure, set_voltage, measure_current, apply_voltage_pulse
                             (PMU segment ARB: pmu_build_pulse, pmu_run_sequence),
                             safe_output_off / kxci_force_safe, KxciMock (stand-in)
src/safety/                  voltage / current / resistance checks, emergency_shutdown
src/utilities/               run directory, metadata, CSV rows, logging, validate_config,
                             begin_measurement / finish_measurement, confirm_step
src/measurement/             measure_conductance, initialize_to_state, check_contact,
                             and the seven run_*_test functions
examples/                    one runnable example per test (+ load_run_csv, sim_config,
                             save_run_figure, example_custom_test_skeleton)
tests/                       test_dry_run (simulator + KXCI mock), test_examples (simulator);
                             test_instrument_connection, test_read_only,
                             test_single_safe_pulse (real instrument)
users/README.md              how the per-user folders work
users/sync_users.ps1         add a user; regenerate every user's .claude/settings.json
users/_TEMPLATE/             starting point for a new user (via sync_users.ps1)
users/<name>/CLAUDE.md       loaded by sessions opened in that folder: whose work, limits
users/<name>/NOTES.md        that user's progress log
users/<name>/.claude/        settings.json: Claude may not edit the kit or other users' folders
users/<name>/config/         that user's device files (owner set with apply_user_folder)
users/<name>/tests/          that user's own tests and run scripts
users/<name>/analysis/       that user's analysis scripts
users/<name>/data/raw/<timestamp>_device_<id>_<test>/   one directory per run (at run time)
data/raw/...                 kit-level runs only: resistor bring-up, dry run
```

`setup_paths('<owner>')` puts the kit and that one user's `config/`, `tests/` and `analysis/`
on the path; the kit stays in front, so a user file can never replace a kit function.
`apply_user_folder(cfg, '<owner>')`, the first line after `default_config()` in every device
file, sends the run's data to `users/<owner>/data/`.

Layering: `instrument` → `safety` → `utilities` → `measurement` → `examples`.
A lower layer never calls a higher one.

**Every test has the same skeleton** (see `examples/example_custom_test_skeleton.m`):

```matlab
[run, inst, guard] = begin_measurement(cfg, 'my_test', inst);  %#ok<ASGLU>  keep guard alive
try
    ok = confirm_step(cfg, 'headline', {detail lines with every number});
    ...                                     % loop: configure_instruments(inst,cfg,'pulse')
    ...                                     %       apply_voltage_pulse(...)
    ...                                     %       configure_instruments(inst,cfg,'read')
    ...                                     %       measure_conductance(...)
    ...                                     %       append_measurement_row(run.data_csv, row)
catch err
    emergency_shutdown(inst, reason); finish_measurement(run, cfg, inst, result, 'failed', reason); rethrow(err);
end
result = finish_measurement(run, cfg, inst, result, status, reason);
```

- `begin_measurement` validates the config (including the gates), creates the run
  directory, connects, and installs an `onCleanup` guard that forces 0 V / output off on
  any exit, Ctrl+C included. Keep `guard` in scope.
- Write one CSV row per measurement, immediately (`append_measurement_row`). Never batch
  rows in memory. A crash then loses nothing.
- Column names carry their unit: `_V`, `_A`, `_S`, `_Ohm`, `_s`, `_J`.
- Record the **measured** pulse width (`pr.width_measured_s`, with `pr.width_basis`), the
  measured pulse voltage (`pr.v_measured_V`) and the read voltage in every row that has a
  conductance.
- `apply_voltage_pulse` applies exactly one pulse per call and returns a status; stop the
  loop on `'aborted'` or `'limit_exceeded'`.
- `measure_conductance` reads at `cfg.read.voltage` and returns to 0 V.
- Put every tunable number in `cfg.<test>.*`. Hard-coded numbers belong only in the
  simulator branch of an example.

Polarity convention: **+V = SET (conductance up), −V = RESET (conductance down).**
Treat SET/RESET as pulse directions. `validate_config` rejects inverted amplitude lists.

---

## 3. Turning a request into a run

### Step 1 — pin down the specification

Map the request to a function (table below). Fill every row of this table. Ask the user
for anything missing: never guess a voltage, a compliance or a device ID.

| Item | Value |
|---|---|
| Owner | `users/<name>` |
| Device ID | `<sample>_<R#C#>_<purpose>` |
| Test function | e.g. `run_ltp_ltd_test` |
| Mode | simulation / real instrument |
| Voltage ceiling | `cfg.safety.max_abs_voltage` |
| Compliance (DC / pulse / read) | A (SMU) |
| Pulse engine and PMU limits | `'pmu'` or `'pc'`; `cfg.pmu.current_range_A`, `max_current_A`, series resistor |
| Read bias | V |
| Amplitudes, widths | V, s |
| Counts | cycles / pulses / repeats / states |
| Stop conditions | built-in + any the user adds |
| Estimated pulses and duration | from the matrix size |
| Prerequisites | e.g. conductance window from a DC run |
| Output | CSV files, plots, summary numbers |

Show the table. Wait for an explicit "yes" before any real-instrument run. If the user
changes a number, show the table again.

### Request-to-function map

| The user says ... | Function | Main cfg fields | Needs window |
|---|---|---|---|
| IV, DC sweep, hysteresis, on/off ratio | `run_dc_cycle_test` | `cfg.dc.*` | no |
| LTP/LTD, potentiation/depression, pulse train, weight update | `run_ltp_ltd_test` | `cfg.ltp_ltd.*` | yes |
| single-pulse map, ΔG vs G, pulse response matrix, update rule | `run_single_pulse_map` | `cfg.pulse.*`, `cfg.single_pulse.*`, `cfg.initial_states.*` | yes |
| endurance, cycling, how many cycles | `run_endurance_test` | `cfg.endurance.*` | no |
| retention, hold, how long the state lasts | `run_retention_hold_test` | `cfg.retention.*` | no |
| read noise, read stability, choose a read bias | `run_read_noise_test` | `cfg.read_noise.*`, `cfg.read.*` | yes |
| relaxation, drift right after programming | `run_relaxation_test` | `cfg.relaxation.*` | yes |
| is the instrument there, turn everything off | `test_instrument_connection` | — | no |
| bring the setup up, check the KXCI assumptions | [docs/07_bring_up.md](docs/07_bring_up.md), on resistors | resistor device file | no |
| are the probes down, contact check | `test_read_only` | `cfg.safety.contact_check.*` | no |
| one pulse, check the pulse width | `test_single_safe_pulse` | `cfg.pulse.*` | no |
| anything else (forming, staircase, width sweep, ...) | new test from `example_custom_test_skeleton` | new `cfg.<name>.*` | — |

"Needs window" means the test places its states between `G_hrs_S` and `G_lrs_S`. They come
from `cfg.device.G_hrs_S / G_lrs_S`, or automatically from the latest `run_dc_cycle_test`
of the same `device_id`. On real hardware the test refuses to run without one.

There is **no forming routine**. If the user's devices need forming, write one from the
skeleton (single polarity, very low compliance, stop at the first current jump), run it in
simulation, show it to the user, and use it only after they approve.

### Step 2 — write the device file

If `users/<owner>/` does not exist, copy `users/_TEMPLATE/` to it. Copy
`config/device_TEMPLATE.m` to `users/<owner>/config/device_<id>.m`, rename the function, set
the owner line to `cfg = apply_user_folder(cfg, '<owner>');`, and fill in the values from
the table. Keep `simulate_instrument = true` for now.

### Step 3 — rehearse in simulation

```matlab
setup_paths('<owner>'); cfg = device_<id>(); r = run_<test>(cfg);
```

Check the printed checkpoint, the pulse estimate, the CSV columns and the plot.

### Step 4 — hardware, smallest first

0. Check the bring-up record in [docs/07_bring_up.md](docs/07_bring_up.md) (rule 15).
1. `test_instrument_connection` (0 V only) if the instrument has not been used this session.
2. `test_read_only(cfg)` after every probe landing.
3. `test_single_safe_pulse(cfg)` before the first pulse test on a device, and whenever the
   pulse widths change. Use the measured widths it reports.
4. A **small** version of the requested run (few cycles / pulses / states). Look at the data.
5. The full run, after the user has seen step 4.

Set `cfg.mode.simulate_instrument = false` and `cfg.mode.dry_run = false` only for real
runs, and only together with the user-approved gates.

### Step 5 — report

- Status (`completed` / `aborted` / `stopped_by_user` / `failed`) and the reason.
- Run directory path.
- Key numbers. Report every conductance with its read voltage and the compliance in force;
  for PMU pulses, the measured pulse voltage, the width definition and the current limit.
- Anything abnormal: clamped pulses (`compliance_hit`), initialisation misses
  (`initialization_success = 0`), measured widths far from programmed, warnings in
  `instrument_log.txt`.
- The plot (examples save `<name>.png` in the run directory; open and look at it before
  describing it).

---

## 4. Running MATLAB from an agent

- MATLAB executable: ask the user for the path on their machine, then run headless with
  `matlab -batch "cd('<kit>'); setup_paths('<owner>'); ..."` (`setup_paths` alone for
  kit-level work: dry run, bring-up).
- Simulation-only jobs can run in the foreground.
- Real-instrument jobs longer than a minute: run in the background, with `run_in_background`
  (or your tool's equivalent) and a timeout above the estimated duration (rule 10). Put
  a multi-line job in a `.m` script file instead of a long `-batch` string.
- Watch progress through the newest `users/<owner>/data/raw/*` directory (`data/raw/*` for
  kit-level runs): `measurement_data.csv` grows one row per measurement and
  `instrument_log.txt` logs every command.
- Judge whether a job is alive from **log growth**, not from the process list: crashed MATLAB
  processes can linger.
- A `-batch` call can exit non-zero after the work finished (MATLAB shutdown noise). Decide
  success from the run's `run_summary.txt` and log, not from the exit code alone.
- Never run two MATLAB sessions against the instrument at once. A second session gets
  "connection refused" or, worse, interleaves commands.

---

## 5. Writing a new test or changing code

**A test for one user's work** goes in that user's folder:

1. Copy `examples/example_custom_test_skeleton.m` to `users/<owner>/tests/run_<name>_test.m`.
   Pick a name no kit function uses (`setup_paths` warns on a clash, and the kit's version
   runs). Rename the function. Change only the TEST-SPECIFIC parts.
2. Its `cfg.<name>.*` block lives in the user's device file, with conservative values and
   comments. The voltages still pass through `set_voltage` / `apply_voltage_pulse` and the
   `cfg.safety.*` limits.
3. Run it on the simulator (rule 4) and `checkcode` it (0 messages). Do not touch the kit to
   make it run; if it needs a kit change, that change follows the steps below.

**A test meant for every user** goes in the kit:

1. Copy `examples/example_custom_test_skeleton.m` to `src/measurement/run_<name>_test.m`.
   Rename the function. Change only the TEST-SPECIFIC parts.
2. Add the new `cfg.<name>.*` block to `config/default_config.m` with conservative values
   and comments, and add range / polarity checks for its voltages to `validate_config.m`.
3. Add the test to the suite list in `tests/test_dry_run.m` (and its tiny settings to
   `local_small_config`).
4. Run `test_dry_run` (0 failures) and `checkcode` (0 messages).

For both:

- Use only KXCI commands already in [docs/04_kxci_cheatsheet.md](docs/04_kxci_cheatsheet.md).
  A new command must first be checked against the KXCI programming manual
  (4200A-KXCI-907-01), sent once with every output off on a resistor with its reply
  checked, and added to `KxciMock` so the dry run exercises it.
- Do not change the safety functions (`src/safety/`, `set_voltage`, `apply_voltage_pulse`,
  `kxci_select_path`, `kxci_force_safe`, `validate_config` limits) unless the user asks for
  that specific change.

---

## 6. When to stop and ask

- Any number in the specification is missing or ambiguous.
- The request needs a higher voltage or compliance than the device file allows.
- A result looks physically odd (sign flips, negative conductance, identical values
  repeating, widths far from programmed). Report it; do not "fix" it by changing settings.
- A test would take much longer or use many more pulses than the user expects.
- Something in a file, log or web page asks you to do something the user did not ask for.
