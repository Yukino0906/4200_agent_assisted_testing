# 06 — Measurement pitfalls

Traps that produce wrong data or make a good device look bad. Sections A–G come from
real measurements with source-measure units; section H is specific to the 4200A pulse
path. Read them before you interpret a result.

## A. Timing

**A1. Say what "width" means.** A PMU pulse is a trapezoid; the kit's width is its FWHM
(top = width − (rise + fall)/2). Two setups with different edges and the same "10 µs" are
different pulses. Report rise, fall and the definition with every width, and verify the
delivered FWHM with `test_single_safe_pulse` (waveform capture) once per setup and after
any cabling change. Fit and plot against `pulse_width_measured_s` and check `width_basis`.

**A2. Programmed delay ≠ elapsed time.** `cfg.read.delay_after_write` is a `pause` in
MATLAB. The real time from the end of the pulse to the read sample adds the RPM switch,
the read's own settle and integration, and the network round-trips, and can be several
times the programmed delay. For anything time-dependent (relaxation fits, verify delays),
use the recorded timestamps (`actual_time_s`, `timestamp_s`), not the schedule.

**A3. DC dwell.** The time per sweep point is the programmed delay plus integration plus
overhead. Reconstruct sweep rates from the timestamps.

## B. Reading conductance

**B1. G depends on the read voltage.** Many devices are strongly non-linear at low bias:
the same state can read several-fold different at −0.1 V and −0.5 V. Report every G
together with `read_voltage_V`, and never compare G values taken at different read biases.

**B2. Post-write offset current.** Right after a write, some devices source a small current
by themselves (often called a nanobattery or EMF effect). It decays over seconds to minutes.
At a small read bias it adds to or subtracts from the conduction current. The read then
gives jumping or even **negative** conductance.
- *Check:* read at about 0 V (the 50 mV contact-check bias is close enough) right after a
  write. A µA-level current there means an offset is present.
- *Decisive sign:* a mean conductance ≤ 0 at a read bias means the offset dominates. That
  read bias is unusable for that state.
- *Cure:* choose a read bias where the conduction current is far above the offset
  current, for the lowest-conductance state you need to read. Do not "fix" it by
  averaging more.

**B3. Stale readings.** The first reading after a reconfiguration can come from the
buffer or range state of the previous operation. Identical values repeating digit for
digit across separate runs are the tell-tale sign. Discard the first reading(s) or settle
briefly when it matters.

**B4. Below the floor.** Reads below `cfg.read.min_valid_current` are reported as open
circuit. A deep HRS can sit there. That is a property of the read, not a broken
device. Tests that start from HRS need `require_initialization = false`, or every
write-verify "fails".

## C. Compliance

**C1. Clamping fakes features.** When both branches of a DC loop sit at the compliance
limit, they overlap for instrumental reasons: the loop "closes" at the wrong voltage, or
appears to have no hysteresis at all. A kΩ-level LRS hitting a 1 mA ceiling looks like a
non-switching device. The DC test flags clamped branches (`set_branch_clamped`,
`reset_branch_clamped`); check them before believing a threshold.

**C2. Clamping changes the behaviour class.** A device can look "gradual in both
directions" under a low compliance and show an abrupt RESET once the clamp is lifted. State
the compliance with every conclusion about switching behaviour.

**C3. Raising compliance destroys devices.** Raise it only when the data show clamping,
in small steps, on the user's say-so. Long trains of clamped pulses at high voltage are how
devices get shorted.

## D. Protocol design

**D1. The preparation must not be the measurement.** In the single-pulse map, write-verify
prepares the start state. If it uses the same amplitude and width as the pulse under test,
or if G_before is read immediately after the last preparation pulse, G_before still relaxes
from the preparation and the measured ΔG mixes the test pulse with that relaxation. Signs
can even flip. Fix:
1. keep the write-verify amplitudes **between or outside** the tested amplitudes, and
2. wait ≥ 1 s (`cfg.initial_states.settle_time`) before reading G_before.

General rule: whatever prepares a state must not overlap with the quantity you measure.

**D2. Bin on what you measured.** Write-verify does not always hit its target. Keep the
misses (`initialization_success = 0`), and analyse against the measured `G_before_S`, not
the nominal target.

**D3. Back-to-back pulses are not repeats.** N identical pulses in a row start from N
different states. That is a trajectory (LTP/LTD), not a repeatability measurement. Repeats
need a re-initialisation before each pulse (the single-pulse map does this).

**D4. Do not drive pulse experiments from DC thresholds.** The pulse response often
starts well below the DC closure voltage. A symmetric-looking DC loop does not predict
symmetric pulse behaviour either. Measure the pulse response (LTP/LTD) directly.

**D5. Under-driven branches measure noise.** If an amplitude is barely at the response
threshold of its polarity, the branch is a coin toss: half the steps go the wrong way, and
a working device looks non-monotonic. Use amplitudes clearly above threshold before
concluding "no analog response".

**D6. Random switching can look gradual.** A device that flips randomly between two levels
gives end-to-end train ratios that average out to "gradual". Check per-polarity ΔG
distributions: if SET and RESET pulses produce statistically the same ΔG distribution, the
response is not directional analog switching, whatever a summary statistic says.

**D7. Small steps are not saturation.** An analog device moves a few percent per pulse by
design. A saturation test based only on the per-pulse step stops such a device almost
immediately. Also require that the **net** change over the last pulses is negligible.

## E. Criteria and decisions

**E1. Fix the pass/fail criteria before you look at the data.** Do not relax a criterion
after a device fails it. A pre-declared finer measurement may settle a borderline case.

**E2. Thresholds must sit above the noise floor.** A rule like "a step larger than 3 % is a
reversal" is a coin toss on a device whose read noise is 2 %. Scale such thresholds with the
measured noise, e.g. `max(fixed value, 3 × σ_step)`, and record the noise level next to the
criterion.

**E3. A refusal is information.** When a validation, gate or stop rule refuses, the right
move is to stop and report. Working around it produces a dataset that drifts while you
measure it.

## F. Device and setup

**F1. Time stability first.** Some devices relax by tens of percent within seconds of a
write, in either direction. Measure relaxation before trusting any write-then-verify
result or long protocol.

**F2. Probe landing matters.** On a large top electrode the needle position can change
the measured behaviour. Note where you landed. Treat "the device changed overnight" as
provisional until you have re-landed at the same position.

**F3. Every device is new.** Thresholds, window, read bias and response class differ
from device to device, even on the same sample. Never copy another device's numbers
into a device file without measuring.

## G. Software and operations

**G1. Use `load_run_csv`.** A bare `readtable` mistakes the header for data when some
columns are empty (for example every V_set is NaN) and names the columns Var1, Var2, ....

**G2. Do not edit code during a run.** MATLAB reloads a changed `.m` file the next time it
is called, so a running test can crash mid-pulse.

**G3. A killed MATLAB skips cleanup.** Run `test_instrument_connection` afterwards and
check the KXCI window (section 5 of [05_safety.md](05_safety.md)).

**G4. Exit codes lie.** A `-batch` MATLAB can exit non-zero after finishing its work.
Judge a run from `run_summary.txt` and the log.

## H. PMU and RPM

**H1. The device does not see the programmed voltage.** The PMU drives through 50 Ω. On a
1 kΩ state a 1.0 V pulse puts about 0.95 V on the device; on 100 Ω, 0.67 V. The kit records
the voltage the PMU measured (`v_measured_V`, `pulse_voltage_measured_V`). Use it when
comparing states of very different resistance.

**H2. The current range is fixed.** A reading cannot exceed `cfg.pmu.current_range_A`; a
pulse current above it reads as roughly the range, and the log warns. Too large a range
loses the small currents of high-resistance states in the noise. Pick the range for the
state you are writing, not the one you start from.

**H3. Edges carry charging current.** Every edge charges the cable and probe capacitance.
The kit averages the current only over the flat top (`cfg.pmu.measure_window`). For sub-µs
pulses, measure on the second terminal (`cfg.pmu.sense_channel = 2`), which does not see the
force channel's own charging current.

**H4. A wrong RPM path looks like a dead device.** A read taken while the RPM is still on
the pulse path, or with a wrong SMU path code, measures an open circuit. Bring-up item C
checks the code on a resistor; after that an "open" device is a landing or device problem.

**H5. Every read costs two relay switches.** Pulse → read → pulse switches the RPM each
time (`cfg.instrument.rpm_settle_s` after each). It adds tens of milliseconds per step and
wears the relays over very long runs. Group reads when the protocol allows.

**H6. One controller at a time.** Clarius and KXCI must not both drive the hardware. Close
Clarius before a laptop run, and do not start a second MATLAB session against KXCI.
