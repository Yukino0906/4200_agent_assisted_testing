# 01 — Setup

The laptop is the control centre: MATLAB, the kit and the agent run there. The 4200A-SCS
only runs Keithley's **KXCI** application (Keithley External Control Interface), which
accepts commands over Ethernet or GPIB. Nothing is installed on the 4200A.

## What you need

| Item | Notes |
|---|---|
| Keithley 4200A-SCS | Clarius with KXCI. The PMU commands used here need Clarius 1.13 or later. |
| One SMU, one 4225-PMU, two 4225-RPMs | The hardware this kit is written for (see "Wiring"). |
| Laptop with MATLAB R2021a or newer | |
| Instrument Control Toolbox + NI-VISA | For `cfg.instrument.transport = 'visa'` (Ethernet raw socket or GPIB). |
| — or nothing extra | `cfg.instrument.transport = 'tcpclient'` uses MATLAB's own TCP socket (Ethernet only, R2020b+). |
| Ethernet cable (or a USB-Ethernet adapter) | Laptop to the 4200A LAN port. A lab switch also works. |
| GPIB adapter (optional) | KUSB-488B or NI GPIB-USB-HS, if you prefer GPIB. |
| An AI coding agent (optional) | Claude Code, Codex, Cursor, ... opened in this folder. |

## 1. On the 4200A (once)

1. **Network.** If the 4200A is already on the lab network, note its IPv4 address
   (`ipconfig` in a command prompt on the 4200A) and leave its settings alone. For a direct
   cable, give its LAN adapter a static address such as `192.168.0.2 / 255.255.255.0`
   (ask whoever administers the instrument).
2. **KCon** (Keithley Configuration Utility) → **KXCI Settings**: choose **Ethernet**, note
   the **port number**, set the terminators as Keithley's KXCI Python application note
   describes, then *Save* and exit KCon.
3. **Start KXCI** from the Start menu. Its window shows the commands it receives and any
   error messages; keep it visible while you bring the setup up.
4. **Close Clarius** while the laptop is in control. Only one program may drive the hardware.

## 2. On the laptop (once)

1. Give the laptop's Ethernet adapter a static address in the same subnet, e.g.
   `192.168.0.1 / 255.255.255.0`, and check `ping 192.168.0.2`.
2. With NI-VISA: NI MAX → *Create New* → *VISA TCP/IP Resource* → *Manual Entry of Raw
   Socket* → address and port → **Validate** (KXCI must be running). The resource name is
   `TCPIP0::192.168.0.2::<port>::SOCKET`.
3. Copy the `4200A_agent_kit` folder anywhere, then in MATLAB:
   ```matlab
   cd <path to>\4200A_agent_kit
   setup_paths            % once per MATLAB session
   test_dry_run           % simulation and KXCI mock only; must end with "0 failed"
   ```
4. Put the address into `config/default_config.m` (it belongs to the setup; device files
   inherit it): `cfg.instrument.transport`, `cfg.instrument.host`, `cfg.instrument.port`.
   The VISA resource string is built from them there.

GPIB instead of Ethernet: set the GPIB address in KCon, use
`cfg.instrument.resource_candidates = {"GPIB0::17::INSTR"}`, `cfg.instrument.terminator = "LF"`
and `cfg.instrument.ack_mode = false`, and confirm with `test_instrument_connection`.

## 3. Wiring

```
 4200A-SCS                                   probe station
 PMU1 CH1 ──(RPM cable)──► RPM1 ──(triax)──► probe 1 ── first terminal (top electrode)
 SMU1 ─────(triax)───────► RPM1 SMU input
 PMU1 CH2 ──(RPM cable)──► RPM2 ──(triax)──► probe 2 ── second terminal   (option B)
 GNDU ─────(triax)───────────────────────────► probe 2 ── second terminal   (option A)
```

- **The RPM is a switch.** Its output goes to the PMU *or* to the SMU, never both. The kit
  switches it (`:PMU:RPM:CONFIGURE`) before every read and every pulse; a read on the pulse
  path sees an open circuit.
- **Option A, `cfg.instrument.return_path = 'gndu'` (default).** Second probe on the ground
  unit. Simplest; reads never depend on the PMU. The pulse current is measured on CH1.
- **Option B, `'pmu_sense'` with `cfg.pmu.sense_channel = 2`.** Second probe on RPM2. CH2
  sits at 0 V and measures the current leaving the device, which excludes CH1's own charging
  current: better for sub-µs pulses. Whether CH2 holds the second terminal at 0 V during SMU
  reads must be confirmed on a resistor ([07_bring_up.md](07_bring_up.md), item D).
- Keep the RPMs as close to the probes as the cables allow.

Polarity: **+V on probe 1 = SET direction, −V = RESET direction.** If your device switches the
other way round, keep the convention and read "SET" as "conductance up".

## 4. First contact

```matlab
test_instrument_connection      % 0 V only, safe with probes up or down
```

It prints the identity and the **raw reply** to a harmless command. Over Ethernet that reply
must match `cfg.instrument.ack_pattern`. Then work through [07_bring_up.md](07_bring_up.md)
on a resistor before you touch a device.

## Running MATLAB from the command line (what an agent does)

```bash
matlab -batch "cd('<path to>/4200A_agent_kit'); setup_paths; test_dry_run"
```

Use the full path of `matlab.exe` if it is not on the system PATH. For long real-instrument
runs, see [05_safety.md](05_safety.md) section 6.

## Folder layout

```
4200A_agent_kit/
├── README.md, AGENTS.md, CLAUDE.md
├── setup_paths.m, check_setup.m
├── config/      default_config.m, device_TEMPLATE.m, kit-level device files (bring-up)
├── src/         instrument/ (KXCI, RPM, PMU, KxciMock), safety/, utilities/, measurement/
├── examples/    example_*.m, load_run_csv.m, sim_config.m, save_run_figure.m
├── tests/       test_dry_run.m, test_examples.m, test_instrument_connection.m,
│                test_read_only.m, test_single_safe_pulse.m
├── docs/        01–07
├── users/       one folder per person (see users/README.md)
│   ├── _TEMPLATE/   copy to users/<name>/
│   └── <name>/      config/ (device files), tests/, analysis/, data/ (at run time)
└── data/        kit-level runs only, created at run time: raw/, metadata/, logs/
```
