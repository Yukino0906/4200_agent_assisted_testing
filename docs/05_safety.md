# 05 — Safety: limits, stop rules, recovery

The kit protects the device and the instrument in layers. Know every layer before you
change a limit. Section 3 matters most on the 4200A: **the PMU pulse path has no current
compliance.**

## 1. Protection layers

| Layer | Where | What it does |
|---|---|---|
| Config validation | `validate_config` (called by every test) | Rejects voltages above `cfg.safety.max_abs_voltage`, anything above 5 V, inverted polarity, compliance above `cfg.safety.max_abs_current`, PMU widths that cannot hold their edges or exceed `cfg.pmu.max_width_s`, a PMU current limit the fixed range cannot see, inconsistent wiring settings |
| Confirmation gates | `cfg.safety.compliance_confirmed`, `cfg.safety.limits_confirmed`, `cfg.pmu.no_compliance_acknowledged` | A real-instrument run refuses to start while any of them is `false` |
| Operator checkpoint | `confirm_step` | Prints every number of the step and waits for `y` (when `cfg.mode.require_user_confirmation = true`) |
| Voltage gate | `check_voltage_limit`, inside `set_voltage` / `apply_voltage_pulse` | Last check before any level reaches the SMU or the PMU |
| SMU compliance | `DV<n>, range, V, I_comp` | The SMU clamps the current during reads, DC sweeps and `'pc'` pulses. The main hardware protection — **SMU only** |
| PMU current limit | `cfg.pmu.max_current_A`, in `apply_voltage_pulse` | After each PMU pulse: \|I\| above the limit triggers an emergency shutdown. Software, after the fact (section 3) |
| Current limit | `check_current_limit` | A measured \|I\| above `cfg.safety.max_abs_current` triggers an emergency shutdown |
| Compliance streak | `measure_current` | `cfg.safety.max_compliance_hits` consecutive clamped reads in read or pulse mode abort the run (DC sweeps are exempt: they are meant to reach compliance) |
| Path interlock | `kxci_select_path` | Brings the SMU to 0 V before the RPM leaves the SMU path, and turns PMU outputs off before it leaves the pulse path |
| Pulse budget | `apply_voltage_pulse` | Stops at `cfg.safety.max_total_pulses` per run |
| Duration limit | `set_voltage`, `apply_voltage_pulse` | Stops at `cfg.safety.max_test_duration` per run |
| Contact check | `check_contact`, `test_read_only` | 50 mV probe: open / short / ok, before any high voltage |
| Output-off guard | `begin_measurement` (`onCleanup`) | PMU off, SMU 0 V and off on any exit: normal, error, Ctrl+C |
| Emergency shutdown | `emergency_shutdown` → `kxci_force_safe` | Every output off, session marked aborted; an aborted session refuses all further bias |

## 2. Rules for everyone (people and agents)

1. Keep `|V| ≤ cfg.safety.max_abs_voltage`. The device owner sets that number. Raise it
   only on purpose, for one device, and write down why.
2. Set the SMU compliance explicitly for DC, pulse and read. Start at 1 mA or lower.
3. Only the operator confirms the gates. An agent sets them to `true` only after the
   operator approves the limits in chat for that device, in that session.
4. Simulate first. Every new or edited test runs on the simulator before the instrument.
5. Run `test_dry_run` after any code change. 0 failures before hardware.
6. Bring the setup up on a resistor first ([07_bring_up.md](07_bring_up.md)). A kit
   assumption that has not been checked there is not a fact.
7. Land the probes, then run `test_read_only`. Never apply a write voltage to an
   unchecked contact.
8. Change one parameter at a time, in small steps, and look at the data between steps.
   Typical ladder for a new device: DC ±0.5 V → ±1.0 V → ±1.5 V → ..., 3 cycles each,
   stopping as soon as switching is clear.
9. A refusal (validation error, gate, checkpoint, safety stop) is a result. Report it.
   Do not work around it.
10. Do not edit `.m` files while a measurement is running.
11. Never drive the hardware from Clarius while KXCI is in control.

## 3. The PMU has no current compliance

An SMU clamps the current the moment it reaches the compliance. The 4225-PMU does not: it
is a voltage source with a 50 Ω output, and during a pulse the current is set only by the
device, the 50 Ω and any series resistance. An abrupt SET into a few hundred ohms at 2 V
can draw tens of milliamps for the whole pulse. That is how filaments overgrow and devices
short.

What the kit does about it:

- `cfg.pmu.max_current_A` is checked **after** every PMU pulse. Above it the run stops
  (`emergency_shutdown`). It cannot shorten the pulse that tripped it.
- The current reading cannot exceed its fixed range (`cfg.pmu.current_range_A`), so a
  limit at the range would never trip. `validate_config` requires the limit to be at most
  0.95 × the range.
- `cfg.pmu.max_width_s` (default 1 ms) caps the energy of a single pulse.
- A real PMU run refuses to start until the operator sets
  `cfg.pmu.no_compliance_acknowledged = true`.

What you should do:

1. **Forming and the first SET of a fresh device: SMU only** (`run_dc_cycle_test` or a
   custom test with `cfg.pulse.timing_source = 'pc'`), with a low compliance.
2. Limit the current physically when the SET can run away: a series resistor at the probe,
   or a 1T1R cell. Record it in `cfg.pmu.series_resistance_Ohm`.
3. Start PMU pulses short (µs or less) and low, and raise the amplitude in small steps.
4. Choose the smallest `cfg.pmu.current_range_A` that covers the expected current, and a
   `max_current_A` just above what the device should draw.
5. Watch the first pulses at each new amplitude: `peak_current_A` in the CSV, the KXCI
   window, the log.

## 4. When to stop a device

Stop, save, and report when you see any of these. Continuing only destroys the evidence
and the device.

- **Short:** resistance drops to the order of the line/probe resistance, or the contact
  check reports `short`. Above all, a large step to a low-ohm state after a high-voltage
  pulse.
- **Open:** a device that read normally now reads at the noise floor, or the contact check
  reports `open`. Check the probe landing and the RPM path before blaming the device.
- **Window collapse:** HRS and LRS converge (endurance stops on this automatically).
- **Sustained clamping** in read or `'pc'` pulse mode, or PMU currents at the top of the
  range: the state keeps running away.
- **Repeated write-verify failures** at the same target.
- **Anything in `instrument_log.txt` marked `SAFETY` or `EMERGENCY SHUTDOWN`.**

## 5. Stopping a run and recovering

| Situation | What to do |
|---|---|
| You want to stop a run | Ctrl+C in MATLAB. The output-off guard runs. |
| A checkpoint asks to proceed and you are unsure | Answer anything other than `y`. The test stops cleanly. |
| MATLAB was killed (Task Manager, agent killed the process, tool timeout) | `onCleanup` did **not** run. Start MATLAB and run `setup_paths; test_instrument_connection`. It resets the 4200A and turns every PMU and SMU output off. Then check the KXCI window for errors. |
| Cannot connect / connection refused | KXCI not running, Clarius holding the hardware, wrong port, or an earlier MATLAB still holds the socket. Close it, restart KXCI if needed, connect again. |
| Every command reported as "not acknowledged" | `cfg.instrument.ack_pattern` does not match the instrument's reply ([07_bring_up.md](07_bring_up.md), item A). Stop and fix the setting; do not continue with errors. |
| Session reports `aborted` | Read `inst.LastError` and the run log. A new run needs a new connection; nothing resumes automatically. |
| Unsure whether a background run is alive | Look at whether `measurement_data.csv` / `instrument_log.txt` in the newest run directory are still growing. Crashed MATLAB processes can stay in the process list. |

## 6. Background (agent) runs

- The tool timeout must exceed the whole procedure. A 10-minute default timeout kills a
  1-hour retention run halfway, with the outputs in an unknown state.
- One MATLAB session talks to the instrument at a time.
- Restarting the agent session can kill the MATLAB process it started. Treat that like any
  killed MATLAB (section 5).
- Decide success from `run_summary.txt` and the log, not from the process exit code.
