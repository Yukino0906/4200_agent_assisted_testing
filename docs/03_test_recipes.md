# 03 — Test recipes

One section per test: what it measures, what it does, the parameters that matter (kit
defaults in brackets), what it needs first, what it writes, and the usual mistakes.

All tests share:

- **Call:** `r = run_<test>(cfg)` or the example wrapper `r = example_<test>(cfg)`, which also
  plots. With no argument, an example runs on the simulator.
- **Output directory:** `data/raw/<yyyy-mm-dd_HHMMSS>_device_<id>_<test>/` containing
  `measurement_data.csv` (one row per measurement, written as it happens),
  `metadata.json/.mat` (instrument, config, status), `run_summary.txt`,
  `instrument_log.txt` (every KXCI command and reply), `config_snapshot.*`, and the example's PNG.
- **Load the CSV with** `T = load_run_csv(r)`, not a bare `readtable` (see
  [06_pitfalls.md](06_pitfalls.md)).
- **Read:** `measure_conductance` applies `cfg.read.voltage` [−0.1 V], averages
  `cfg.read.num_average_reads` [3] samples, drops the worst outlier, returns to 0 V.
  G = I / V_read. Conductance depends on the read voltage; report them together.
- **Write-verify** (`initialize_to_state`), used by tests that start from a chosen state:
  read → pulse up (SET) or down (RESET) → read again, coarse then fine amplitudes, until
  G is within `cfg.initial_states.tolerance` [10 %] of the target or a budget runs out.
  Targets are positions between G_HRS (0) and G_LRS (1), log-spaced. The real starting
  G is always measured and recorded as `G_before_S`; `initialization_success` says whether
  the target was hit.

Recommended order on a new device:

1. `test_read_only` — contact and a stable read
2. `run_dc_cycle_test` — small range first, widen step by step; gives the window
3. `test_single_safe_pulse` — the pulse path and the delivered width
4. `run_ltp_ltd_test` — does the device respond gradually to pulses, in both directions?
5. `run_read_noise_test` — is the read bias quiet and non-disturbing?
6. `run_relaxation_test` — does a written state hold for seconds?
7. `run_single_pulse_map` — the full ΔG(G, V, t) dataset
8. `run_endurance_test`, `run_retention_hold_test` — long and wearing; run last

---

## DC I-V — `run_dc_cycle_test` / `example_iv`

**Measures:** bipolar I-V loops, cycle-to-cycle spread, HRS/LRS window, on/off ratio,
switching (closure) voltages.

**Does:** per cycle, 0 → +`v_positive_max` → 0 → `v_negative_max` → 0, recording (t, V, I)
at every point; reads HRS and LRS at the read bias after each half.

| Field | Meaning |
|---|---|
| `cfg.dc.v_positive_max` / `v_negative_max` | sweep ends [+1.5 / −1.5 V] |
| `cfg.dc.v_step`, `cfg.dc.delay` | point spacing [0.05 V] and dwell per point [2 ms] |
| `cfg.dc.compliance` | current limit [1 mA]; the main protection |
| `cfg.dc.num_cycles` | [5]; start with 3–5 |
| `cfg.dc.closure_ratio_threshold` | loop counts as closed when branch current ratio ≤ this [1.5] |

**Writes:** `measurement_data.csv` (cycle_id, segment, point_id, timestamp_s,
applied_voltage_V, measured_current_A, compliance_A, estimated_conductance_S, ...) and
`cycle_summary.csv` (one row per cycle: G_hrs_S, G_lrs_S, on_off_ratio,
V_set_complete_V, V_reset_complete_V, set/reset_r_max, confidence, manual-review flags,
failure reasons, clamped-branch flags).

**Reading it:** the window (G_hrs_S, G_lrs_S) goes into the run metadata and later pulse
tests on the same `device_id` use it. The extracted voltages are **closure** voltages,
where the outbound and return branches merge again, i.e. where the transition has
completed. They sit above jump-onset thresholds. When the loop never closes inside the
sweep, the value is NaN with a reason ("extend v_positive_max"). That is a valid result,
not an error.

**Mistakes:** starting with a wide sweep; raising compliance before checking whether the
branch is clamped (`set_branch_clamped`); using DC closure voltages to set pulse
amplitudes (pulse response often starts well below them).

---

## LTP / LTD — `run_ltp_ltd_test` / `example_ltp_ltd`

**Measures:** conductance trajectory under trains of identical pulses: step size,
non-linearity, saturation, LTP/LTD asymmetry, cycle-to-cycle repeatability.

**Does:** for each amplitude pair and cycle: write-verify near HRS (position 0.05) → N SET
pulses with a read after each (LTP); write-verify near LRS (0.95) → N RESET pulses with a
read after each (LTD).

| Field | Meaning |
|---|---|
| `cfg.ltp_ltd.set_amplitudes` / `reset_amplitudes` | paired lists, weak → strong [1.0 1.2 1.4 / −1.0 −1.2 −1.4 V] |
| `cfg.ltp_ltd.width` | one width for every pulse [10 µs] |
| `cfg.ltp_ltd.num_pulses` | per branch [50] |
| `cfg.ltp_ltd.num_cycles` | per amplitude [3] |
| `cfg.ltp_ltd.stop_on_saturation`, `saturation_tol`, `saturation_patience` | stop a branch after `patience` pulses with \|ΔG\|/G < `tol` [true, 0.1 %, 8] |
| `cfg.ltp_ltd.require_initialization` | `false`: run the train even if write-verify missed [false] |

**Needs:** a conductance window.

**Writes:** one row per pulse: amplitude_index, cycle_id, branch (LTP/LTD), pulse_index,
pulse_voltage_V, pulse_width_s, pulse_width_measured_s, peak_current_A,
estimated_pulse_energy_J, read_voltage_V, G_before_S, G_after_S, delta_G_S,
normalized_delta_G, saturated.

**Reading it:** plot G_after_S against pulse number per branch. Check the direction first:
does LTP go up and LTD go down on (almost) every pulse? Then step size and
saturation.

**Mistakes:** an amplitude below the response threshold of that polarity gives a flat,
noisy branch that measures the noise, not the device. Use amplitudes clearly above
threshold (start from the LTP/LTD response, not from the DC closure voltage). The first
pulses of a branch also carry the write-verify history.

---

## Single-pulse map — `run_single_pulse_map` / `example_single_pulse_map`

**Measures:** ΔG = f(G_before, V_pulse, t_pulse, polarity) and its spread; the dataset a
pulse-programming (compact) model is fitted to.

**Does:** for every start state × amplitude (SET and RESET) × width × repeat: write-verify
to the start state → wait `cfg.initial_states.settle_time` → read G_before → **one** test
pulse → wait `cfg.read.delay_after_write` → read G_after → one row.

| Field | Meaning |
|---|---|
| `cfg.pulse.set_amplitudes` / `reset_amplitudes` | test amplitudes [1.0 1.2 1.4 / −1.0 −1.2 −1.4 V] |
| `cfg.pulse.widths` | test widths [10 µs, 100 µs] |
| `cfg.initial_states.normalized` | start positions [0.1 … 0.9] |
| `cfg.single_pulse.num_states`, `amplitudes_subset`, `repeats` | matrix size [3, 3, 10] |
| `cfg.initial_states.coarse/fine_amplitude_set/reset`, `coarse/fine_width` | write-verify drive [±1.3 / ±1.1 V, 10 µs] |
| `cfg.initial_states.settle_time` | wait before G_before [1 s] |
| `cfg.single_pulse.require_initialization` | `false`: keep trials whose write-verify missed [false] |

Trials = states × 2·amplitudes × widths × repeats; each costs one test pulse plus several
write-verify pulses. The checkpoint prints the estimate.

**Needs:** a conductance window.

**Writes:** one row per trial: target_initial_conductance_S, G_before_S, pulse_polarity,
pulse_voltage_V, pulse_width_s, pulse_width_measured_s, peak_current_A, compliance_hit,
G_after_S, delta_G_S, normalized_delta_G, initialization_pulse_count,
initialization_success, ...

**Reading it:** bin on the **measured** G_before_S, fit on pulse_width_measured_s. Check
the sign first: SET trials should have ΔG > 0, RESET trials ΔG < 0. Many wrong-sign
averages mean the preparation is contaminating the measurement.

**Mistakes:** write-verify amplitudes equal to test amplitudes, or a short settle time.
Both make G_before still relax from the preparation, so ΔG measures the preparation (see
[06_pitfalls.md](06_pitfalls.md)). Also: applying N back-to-back pulses and calling them
N repeats. Each would start from a different state.

---

## Endurance — `run_endurance_test` / `example_endurance`

**Measures:** how the HRS/LRS window evolves over many SET/RESET cycles, and when it
collapses.

**Does:** per cycle: n SET pulses → read G_set → n RESET pulses → read G_reset; ratio =
G_set/G_reset. The initial window is the median ratio of the first `baseline_cycles`. Stops
at window collapse, an invalid read, or `max_cycles`.

| Field | Meaning |
|---|---|
| `cfg.endurance.set_amplitude_V` / `reset_amplitude_V` | [+1.2 / −1.2 V] |
| `cfg.endurance.width_s` | [10 µs] |
| `cfg.endurance.pulses_per_train` | n [5] |
| `cfg.endurance.max_cycles` | [100] |
| `cfg.endurance.baseline_cycles` | [5] |
| `cfg.endurance.stop_ratio_min` | stop when ratio < this [2] |
| `cfg.endurance.stop_frac_min` | or when ratio < this × initial ratio [0.3] |

**Writes:** one row per cycle: cycle_index, timestamp_s, G_set_S, G_reset_S,
window_ratio, ratio_vs_initial, stop_reason.

**Mistakes:** a pulse budget (`cfg.safety.max_total_pulses` [20000]) smaller than
2·n·max_cycles: the run stops at the budget. Long runs: raise `max_cycles` in decades and
look at the data in between. Endurance wears the device; run it last.

---

## Retention — `run_retention_hold_test` / `example_retention`

**Measures:** how long a written state holds at zero bias.

**Does:** for each entry of `cfg.retention.states`: write train → G0 = first read → read
every `interval_s` → stop at |G−G0|/G0 > `drift_limit` or after `max_hold_s`. The device
sits at 0 V between reads.

| Field | Meaning |
|---|---|
| `cfg.retention.states` | struct array: `.label` ('SET'/'RESET'), `.amplitude_V`, `.width_s`, `.n_pulses` [SET 5×+1.2 V, RESET 5×−1.2 V, 10 µs] |
| `cfg.retention.interval_s` | read period [10 s] |
| `cfg.retention.max_hold_s` | hold ceiling per state [1800 s] |
| `cfg.retention.drift_limit` | relative drift that ends the hold [0.5] |
| `cfg.retention.rest_between_s` | rest between states [30 s] |

**Writes:** one row per read: state_label, state_index, sample_index, scheduled_time_s,
actual_time_s, read_voltage_V, current_A, conductance_S, G0_S, relative_drift, stop_reason.

**Mistakes:** forgetting that every read is a small disturbance (do not read every
100 ms for an hour); background-job timeouts shorter than states × max_hold_s.

---

## Read noise — `run_read_noise_test` / `example_read_noise`

**Measures:** the spread of repeated reads of a fixed state, and whether reading
itself moves the state.

**Does:** write-verify to each state, then `num_reads` reads with no write in between.
Reports mean, std, CV and a trend test per state; a significant monotonic trend is flagged
as disturb/relaxation, not noise.

| Field | Meaning |
|---|---|
| `cfg.read_noise.states_normalized` | [0.1 0.5 0.9] |
| `cfg.read_noise.num_reads` | [300] |
| `cfg.read.voltage`, `cfg.read.num_average_reads` | the read under test |

**Needs:** a conductance window.

**Writes:** one row per read: state_index, target_conductance_S, read_index, timestamp_s,
read_voltage_V, measured_current_A, conductance_S, resistance_Ohm.

**Use it to choose the read bias:** run it at two or three candidate biases. Pick one with
low CV, no trend, and conduction current far above any offset current
([06_pitfalls.md](06_pitfalls.md)).

---

## Relaxation — `run_relaxation_test` / `example_relaxation`

**Measures:** drift in the first seconds to minutes after a write, the window in which a
just-verified state can already have moved.

**Does:** for each state and repeat: write-verify, then reads at the scheduled times
`sample_times` (0 = as early as possible). Records the actual time of every read.

| Field | Meaning |
|---|---|
| `cfg.relaxation.sample_times` | sorted, log-spaced [0 0.1 0.3 1 3 10 30 100 s] |
| `cfg.relaxation.states_normalized` | [0.2 0.5 0.8] |
| `cfg.relaxation.repeats` | [3] |

Duration ≈ max(sample_times) × states × repeats.

**Needs:** a conductance window.

**Writes:** one row per read: state_index, target_conductance_S, repeat_id, sample_index,
scheduled_time_s, actual_time_s, read_voltage_V, conductance_S, G_zero_S, relative_drift,
within_tolerance.

**Reading it:** plot relative_drift against actual_time_s on a log axis. Use the actual
times, not the schedule: the first read cannot come earlier than one read duration.

---

## Building something else

Copy `examples/example_custom_test_skeleton.m` (an arbitrary pulse sequence with a read
after each pulse) to `src/measurement/run_<name>_test.m` and adapt the TEST-SPECIFIC
parts. Typical adaptations:

- **Pulse-width sweep at fixed amplitude:** `cfg.sequence.amplitudes_V = 1.2*ones(1,5)`,
  `cfg.sequence.widths_s = [10e-6 20e-6 50e-6 100e-6 200e-6]`, with a write-verify reset
  before each pulse if the steps must be independent.
- **Staircase / increasing-amplitude programming:** amplitudes increasing in small steps.
- **Forming:** single-polarity voltage ramp with very low compliance that stops at the first
  current jump. Review it carefully before the first use.

Follow AGENTS.md section 5 for the checklist (config block, validation, dry-run entry).
