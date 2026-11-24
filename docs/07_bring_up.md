# 07 — Bring-up on a resistor (do this once per setup)

The kit's KXCI layer is written from Keithley's examples and tested against a software
stand-in (`KxciMock`). The stand-in proves the code is consistent and the order of
operations is safe. It cannot prove that the 4200A answers the way the kit assumes. This
checklist does, on resistors, before any device is touched. Work through it in order and
fill in the record at the bottom.

## What you need

- KXCI running, Clarius closed, `test_dry_run` passing ([01_setup.md](01_setup.md)).
- **R1 = 100 kΩ** and **R2 = 1 kΩ** (1 %), each mounted so both probes can land on it
  (a resistor soldered across two pads, or a resistor test structure).
- A device file for the resistor. Copy `config/device_TEMPLATE.m` to
  `config/device_RES_bringup.m`, rename the function, and set:

```matlab
cfg.device.device_id        = 'RES_100k_bringup';
cfg.safety.max_abs_voltage  = 1.5;
cfg.read.voltage            = -0.1;
cfg.read.compliance         = 1e-3;
cfg.pulse.set_amplitudes    = 0.5;
cfg.pulse.reset_amplitudes  = -0.5;
cfg.pulse.widths            = [1e-6 10e-6 100e-6];
cfg.pmu.current_range_A     = 10e-6;    % 0.5 V / 100 kOhm = 5 uA
cfg.pmu.max_current_A       = 9e-6;
cfg.mode.simulate_instrument = false;
cfg.mode.dry_run             = false;
% the operator sets the three gates after reading 05_safety.md
```

## Checklist

| Item | Assumption checked | How | Pass | If it fails |
|---|---|---|---|---|
| **A** | Ethernet KXCI answers every command with an acknowledge matching `cfg.instrument.ack_pattern` (`'^ACK'`) | Probes up. `test_instrument_connection(cfg)` | Identity printed; step 3 says the reply matches | Set `ack_pattern` to match the printed reply. If every command times out instead, KXCI is not answering data-less commands: set `ack_mode = false`, re-run, and tell the kit maintainer |
| **B** | `TI1` returns one parseable current; status letter as assumed | R1 between the probes, second probe on GNDU. `test_read_only(cfg)` | R within 2 % of 100 kΩ, current negative at −0.1 V. In `instrument_log.txt` the line after `?? TI1` shows the raw reply: note its form | A reply the parser cannot read: send it to the maintainer with the log |
| **C** | RPM SMU path code `cfg.pmu.rpm_code_smu = 3` | Same run as B | B passes (an open circuit here, with the probes on R1, means the SMU never reached the device) | Look up the SMU path value of `:PMU:RPM:CONFIGURE` in the KXCI manual, set `rpm_code_smu`, repeat B |
| **D** | With `return_path = 'pmu_sense'`, PMU CH2 holds the second terminal at 0 V during SMU reads | Second probe moved to RPM2. Set `cfg.instrument.return_path = 'pmu_sense'`, `cfg.pmu.sense_channel = 2`. Repeat B | Same R as in B | Use `'gndu'` for reads. Option B stays unavailable until resolved |
| **E** | PMU timing and shape: segment times, FWHM definition, RPM pulse path | R1. `test_single_safe_pulse(cfg)`, step 2 (waveform capture of every width at the read voltage) | Every width within 10 %; `pulse_voltage_measured_V` close to the programmed level (50 Ω vs 100 kΩ: < 0.1 % low) | Check `cfg.pmu.rise_time / fall_time` and the RPM cabling. A flat record means the RPM is not on the pulse path |
| **F** | PMU current sign and magnitude (and, in option B, the sense-channel sign) | Same run, step 3 (one +0.5 V pulse) | `peak_current_A` ≈ 5 µA, positive for +V; G_after = G_before (a resistor does not switch) | Wrong sign: report it, do not flip it in your analysis by hand |
| **G** | The software current limit trips on an over-range pulse | R2. `cfg.pmu.current_range_A = 1e-3`, `max_current_A = 0.9e-3`, `cfg.pulse.set_amplitudes = 1.2` (expected ≈ 1.1 mA). `test_single_safe_pulse(cfg)` | The write pulse ends in `limit_exceeded` and an emergency shutdown; the log warns about the top of the range | The limit cannot protect a device on this setup: stop and report |
| **H** | Outputs end up off after a killed MATLAB | R1. Start `example_read_noise(cfg)` in a background MATLAB, kill the process, then run `test_instrument_connection(cfg)` | Its step 4 reports 0 commands not acknowledged; the KXCI window shows the off commands; a voltmeter across R1 reads 0 V | Turn the outputs off by hand in KXCI/Clarius; report |
| **I** | A rejected command is noticed | Probes up, outputs off: `inst = connect_instruments(cfg); kxci_write(inst, 'XX9'); n = kxci_check_errors(inst), disconnect_instruments(inst)` | `n = 1` | The instrument acknowledges unknown commands: find the error query in the KXCI manual, set `cfg.instrument.error_query` and `no_error_pattern`, repeat |

Items A–C, E–G and I must pass before any device. D is needed only for option B; H once
per setup.

## Record

| Item | Date | Who | Result | Settings changed |
|---|---|---|---|---|
| A | | | | |
| B | | | | |
| C | | | | |
| D | | | | |
| E | | | | |
| F | | | | |
| G | | | | |
| H | | | | |
| I | | | | |

When an item changes a setting, change it in `config/default_config.m` (it is a property of
the setup, not of a device), update [04_kxci_cheatsheet.md](04_kxci_cheatsheet.md) from
**UNVERIFIED** to verified with the date, and update `KxciMock` so the dry run tests the
real behaviour.
