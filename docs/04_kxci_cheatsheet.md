# 04 — KXCI cheat sheet

The 4200A is driven through **KXCI** (Keithley External Control Interface). It is neither
SCPI nor TSP. This page lists every command the kit sends, what it means, and how sure we
are about it.

**Status column**
- **Example** — appears in Keithley's own KXCI examples with this meaning
  (tektronix/keithley on GitHub, `Instrument_Examples/Model_4200A/KXCI_Examples`, and the
  application note *Controlling the 4200A-SCS Parameter Analyzer Using KXCI and Python 3*).
- **Inferred** — the command is in the examples, but the meaning of an argument is read off
  how the examples use it.
- **UNVERIFIED** — this kit's assumption. [07_bring_up.md](07_bring_up.md) checks it on the
  instrument before any device is touched. The authority for all of them is the *Model
  4200A-SCS KXCI Remote Control Programming* manual (4200A-KXCI-907-01).

## Transport

| Item | Kit setting | Status |
|---|---|---|
| Ethernet resource | `TCPIP0::<ip>::<port>::SOCKET` (raw socket) | Example |
| Port | set in KCon; Keithley's examples use 1225 | Example (default not confirmed) |
| Terminator over Ethernet | NUL (`cfg.instrument.terminator = 0`) | Example |
| Reply to a command without data | an acknowledge, matched by `cfg.instrument.ack_pattern = '^ACK'` | **UNVERIFIED** (item A) |
| Error query | none (`cfg.instrument.error_query = ''`) | **UNVERIFIED** (item I) |

Every exchange goes through `kxci_transact`. In ack mode every command's reply is read, so a
reply can never be mistaken for the data of the next query.

## General

| Command | Meaning | Used in | Status |
|---|---|---|---|
| `BC` | clear the reading buffer | `connect_instruments` | Example |
| `*RST` | reset all modules to their defaults (outputs off) | `connect_instruments` | Example |
| `*IDN?` | identity | `connect_instruments` | **UNVERIFIED** (a missing reply is tolerated) |

## SMU, user mode

| Command | Meaning | Used in | Status |
|---|---|---|---|
| `US` | enter SMU user mode | `kxci_select_path`, `kxci_force_safe` | Example |
| `DV1, 1, 0.1, 1e-3` | SMU1: 20 V source range (code 1), 0.1 V, 1 mA compliance | `set_voltage` | Example |
| `DV1` | SMU1 output off | `kxci_force_safe` | Example |
| `TI1` | measure SMU1 current, reply is one reading | `measure_current` | Example; reply format **UNVERIFIED** (item B) |

The compliance is an argument of every `DV`, so `set_voltage` resends it each time.
`kxci_parse_reading` accepts a bare number or the HP 4145-style prefix (`NAI+1.23E-06`:
status, channel, quantity). Status `C` is counted as compliance (**UNVERIFIED**).

## RPM and PMU (segment ARB)

| Command | Meaning | Used in | Status |
|---|---|---|---|
| `:PMU:INIT 1` | initialise the PMU in segment-ARB mode | `kxci_select_path` | Example |
| `:PMU:RPM:CONFIGURE PMU1-1, 0` | RPM on PMU1 CH1 → **PMU path** | `kxci_select_path` | Example |
| `:PMU:RPM:CONFIGURE PMU1-1, 3` | RPM on PMU1 CH1 → **SMU path** | `kxci_select_path` | **UNVERIFIED** (item C) |
| `:PMU:MEASURE:RANGE 1, 2, 1e-3` | CH1 current measure range, fixed (type 2), 1 mA | `kxci_select_path` | Inferred |
| `:PMU:SARB:SEQ:TIME 1, 1, t1, …` | segment durations, CH1, sequence 1 | `pmu_run_sequence` | Example |
| `:PMU:SARB:SEQ:STARTV / STOPV 1, 1, …` | segment start / stop voltages | `pmu_run_sequence` | Example |
| `:PMU:SARB:SEQ:MEAS:TYPE 1, 1, …` | per segment: 0 none, 1 spot mean, 2 waveform | `pmu_run_sequence` | Inferred |
| `:PMU:SARB:SEQ:MEAS:START / STOP 1, 1, …` | measurement window, relative to each segment's start | `pmu_run_sequence` | Inferred |
| `:PMU:SARB:WFM:SEQ:LIST 1, 1, 1` | CH1 runs sequence 1 once | `pmu_run_sequence` | Example |
| `:PMU:OUTPUT:STATE 1, 1` / `1, 0` | CH1 output on / off | `pmu_run_sequence`, `kxci_force_safe` | Example |
| `:PMU:EXECUTE` | run the test | `pmu_run_sequence` | Example |
| `:PMU:TEST:STATUS?` | 1 = running, 0 = idle | `pmu_run_sequence` | Example |
| `:PMU:DATA:COUNT? 1` | number of points for CH1 | `pmu_run_sequence` | Example |
| `:PMU:DATA:GET 1, start, count` | points `V,I,t,status;V,I,t,status;…` | `pmu_run_sequence` | Example; status field meaning unknown |

One write pulse is a five-segment trapezoid: pre (0 V) → rise → top → fall → post (0 V).
The width is the FWHM: top = width − (rise + fall)/2 (`pmu_build_pulse`).

## Not used (yet)

- **System mode** (`DE`, `CH`, `SS`, `VR`, `SM`, `MD`, `ME1`, `SP`, `RD`): the 4145-style
  sweep engine. A bipolar DC loop would need four separate staircases, so the kit sweeps
  point by point in user mode instead.
- **User-library mode** (`UL`, then `EX <library> <module>(<args>)`): runs a KULT user module
  (C code compiled on the 4200A) and is the 4200A counterpart of downloading a TSP script
  to a 2600-series SMU. It is the route for a closed pulse–verify loop that must run faster
  than the network round-trip. Calling a module is shown in Keithley's CVIV examples;
  reading its output arguments back has not been confirmed for this kit.

## Adding a command

1. Look it up in the KXCI programming manual (4200A-KXCI-907-01).
2. Send it once with every output off, on a resistor, and read the reply in
   `instrument_log.txt` and in the KXCI window.
3. Add it to this page with its status, then to the KXCI mock (`src/instrument/KxciMock.m`)
   so `test_dry_run` exercises it.
