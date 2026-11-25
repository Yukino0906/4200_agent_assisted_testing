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
| Port | set in KCon; Keithley's examples use 1225 | Verified 2026-11-24: this 4200A uses **5230** |
| Terminator over Ethernet | NUL (`cfg.instrument.terminator = 0`) | Verified 2026-11-24 (item A): replies arrive NUL-terminated even though KCon shows String Terminator = LF (that setting appears to apply to GPIB) |
| Reply to a command without data | an acknowledge, matched by `cfg.instrument.ack_pattern = '^ACK'` | Verified 2026-11-24 (item A): the reply is exactly `ACK`. Whether an *unknown* command also gets `ACK` is item I |
| Error query | none (`cfg.instrument.error_query = ''`) | **NEEDED** — item I failed 2026-11-24: the unknown command `XX9` was answered `ACK`, so `ACK` alone does not show a command was accepted. The KXCI window logs the error as `KXCI command error. (-992)` and the SRQ lamp lights. Candidates below |
| `:ERROR:LAST:GET` / `:ERROR:LAST:CLEAR` | last error message, e.g. `KXCI command error. (-992)`; read is non-destructive | Manual Rev F p. 4-3; **added in Clarius V1.13** (release notes CLS-979) → **not available on this 4200A (V1.12)** |
| `SP` | status byte over Ethernet (decimal). B0 = 1 data ready, B1 = 2 syntax error (set by an invalid command), B4 = 16 busy, B6 = 64 RQS (set with B1). B1/B6 clear when serial polled | Manual Rev F p. 3-14, 4-6; used over Ethernet in app note 1KW-74006-1. Presence in V1.12 inferred, **not yet tried** |

Manual Rev F p. 2-2 (2026-11-24 lookup): "Commands must always be terminated with null"; commands without data answer `ACK\0`, including unknown ones; data replies end with the KCon terminator plus NUL; errors show only in the KXCI window. From **V1.15** (Feb 2026) KXCI Ethernet is based on HiSLIP/VISA (`TCPIP0::<ip>::hislip0,<port>::INSTR`); whether the raw socket this kit uses still works there is not confirmed.

Every exchange goes through `kxci_transact`. In ack mode every command's reply is read, so a
reply can never be mistaken for the data of the next query.

## General

| Command | Meaning | Used in | Status |
|---|---|---|---|
| `BC` | clear the reading buffer | `connect_instruments` | Example |
| `*RST` | reset all modules to their defaults (outputs off) | `connect_instruments` | Example |
| `*IDN?` | identity | `connect_instruments` | Verified 2026-11-24: `KEITHLEY INSTRUMENTS,KI4200A,<serial>,V1.12` (last field = Clarius version) |

## SMU, user mode

| Command | Meaning | Used in | Status |
|---|---|---|---|
| `US` | enter SMU user mode | `kxci_select_path`, `kxci_force_safe` | Example |
| `DV1, 1, 0.1, 1e-3` | SMU1: 20 V source range (code 1), 0.1 V, 1 mA compliance | `set_voltage` | Example |
| `DV1` | SMU1 output off | `kxci_force_safe` | Example |
| `TI1` | measure SMU1 current, reply is one reading | `measure_current` | Example. Reply form verified 2026-11-24: `NAI-14.74702E-12` (4145-style: status `N` normal, channel `A`, quantity `I`); parsed correctly. Status `C` (compliance) not yet seen |

The compliance is an argument of every `DV`, so `set_voltage` resends it each time.
`kxci_parse_reading` accepts a bare number or the HP 4145-style prefix (`NAI+1.23E-06`:
status, channel, quantity). Status `C` is counted as compliance (**UNVERIFIED**).

## RPM and PMU (segment ARB)

**Every `:PMU:` command needs Clarius+ V1.13 or later** (manual Rev F p. 7-1: "available in
Clarius+ versions 1.13 and later"; V1.13 release notes CLS-692; Keithley's GitHub PMU examples).
V1.12 and earlier have only the two-letter PGU commands (`PS`, `PO`, `PT`, `PV`, `PG`, …, manual
p. 7-62), without measurement. On this 4200A (V1.12) `:PMU:OUTPUT:STATE 1, 0` gave
`KXCI command error. (-992)` (2026-11-24). Until Clarius is upgraded, nothing below works here,
including the RPM path switching that `kxci_select_path` sends before SMU reads.

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
| `:PMU:OUTPUT:STATE 1, 1` / `1, 0` | CH1 output on / off | `pmu_run_sequence`, `kxci_force_safe` | Example. **Rejected on this 4200A (Clarius V1.12), 2026-11-24**: `1, 0` → `KXCI command error. (-992)` in the KXCI window (sent after `*RST`, without `:PMU:INIT`). Either V1.12 lacks the PMU commands or the command needs `:PMU:INIT` first — not yet resolved |
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
