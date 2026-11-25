# 00 — Standard operating procedure: 4200A-SCS with MATLAB and Claude

For everyone who measures with the Keithley 4200A-SCS from the lab PC. It covers who does
what, what to check before a session, how to run a measurement (with Claude or by hand),
where data goes, how to finish, and what to do when something goes wrong. The safety rules
behind it are in [05_safety.md](05_safety.md) and [../AGENTS.md](../AGENTS.md); the current
state of the setup is in [../HANDOFF.md](../HANDOFF.md) section 0. Read that section before
planning a measurement: it says what works today.

## 1. The setup at a glance

```
 lab PC (Windows)                                   4200A-SCS (built-in Windows PC)
 ├─ MATLAB R2026b + this kit  ── Ethernet cable ──► port "Ethernet 4", KXCI on TCP 5230
 ├─ Claude Code (one session per person)            SMU1 ──► probe 1 (direct)
 └─ Wi-Fi for the internet                          GNDU ──► probe 2
                                                    4225-PMU + 2 RPMs (not usable on Clarius V1.12)
```

- The PC controls the 4200A through **KXCI**, Keithley's remote-control program on the 4200A.
  **KXCI and Clarius cannot both control the hardware**: use one or the other.
- Kit folder: `C:\Agent_assist_project\4200_agent_assisted_testing` (below: "the kit").
- MATLAB: `C:\Program Files\MATLAB\R2026b\bin\matlab.exe`.
- 4200A address: `169.254.66.232`, port `5230` (set in `config/default_config.m`).

## 2. Roles

| Role | Who | Works in | Does |
|---|---|---|---|
| User | each lab member | `users/<name>/` (own Claude session) | own devices, tests, analysis, data, notes |
| Kit maintainer | the person responsible for the setup | the kit root (Claude session opened there) | shared code and docs, bring-up checks, adding users, network/address changes, checks after a Clarius upgrade |
| 4200A administrator | whoever administers the 4200A | the 4200A | Windows/network settings on the 4200A, Clarius upgrades |

Users never change the shared kit (`src/`, `config/`, `tests/`, `examples/`, `docs/`, the
root files) or anyone else's folder. If the kit needs a change, write it in your `NOTES.md`
and tell the maintainer.

## 3. Safety essentials

1. **Every voltage and current limit comes from you, in numbers.** Claude proposes a
   specification table; nothing runs on the instrument until you answer "yes" to it.
2. **SMU compliance on every run, starting at 1 mA or lower.** Raise it only with evidence.
3. **The PMU has no current limit at all** (when it becomes usable). Forming and the first
   SET of a fresh device use the SMU only.
4. **Simulate first, small run before full run.**
5. **Land the probes, then run the contact check.** Poor contact looks like a noisy
   megaohm "device" that suddenly turns clean.
6. **Stop on anything odd** (shorts, opens, sign flips, repeated compliance) and report it;
   never raise limits to get past a refusal.
7. **One controller at a time.** The kit refuses a second connection while someone is
   connected (`instrument_lock:InUse`) and names that person. Wait for them.
8. **Raw data are append-only.** Never edit, move or delete anything under `data/raw/`.

## 4. Once per person

1. Ask the kit maintainer to create your folder (or, in the kit-root session:
   `powershell -ExecutionPolicy Bypass -File users\sync_users.ps1 -NewUser <name> -FullName "<Full Name>"`).
   Folder names are given name _ family name, lower case, ASCII: `jane_doe`.
2. Fill in `users/<name>/README.md` (group, samples, anything others should know).
3. MATLAB licence: follow the lab's decision (HANDOFF section 3.1).

Your folder:

| Item | Purpose |
|---|---|
| `CLAUDE.md` | tells Claude whose work this is and what it may change (do not edit) |
| `NOTES.md` | your progress log; Claude adds an entry each session |
| `.claude/settings.json` | stops Claude editing the kit or other folders (do not edit) |
| `config/` | your device files `device_<sample>_<R#C#>_<purpose>.m` |
| `tests/` | your own tests and run scripts |
| `analysis/` | your analysis and plotting scripts |
| `data/` | your runs (created by the first run; never in git) |

## 5. Before every measurement session

On the 4200A:
1. Make sure nobody else is using the instrument (ask; Clarius users included).
2. **Close Clarius.** Start **KXCI** (Start menu → Keithley Instruments → KXCI) and leave its
   window visible: it shows every command received and any error.
3. If the 4200A was restarted, check its address: `ipconfig`, adapter `Ethernet 4`,
   "Autoconfiguration IPv4 Address". If it is no longer `169.254.66.232`, ask the maintainer
   to update `config/default_config.m` before anyone connects.

On the probe station:
4. Land the probes (probe 1 = SMU1, probe 2 = ground).

On the lab PC:
5. Check [../HANDOFF.md](../HANDOFF.md) section 0 for what currently works.
6. If you want to check the link first: `ping 169.254.66.232` (times out: the 4200A firewall
   does not answer ping), then `arp -a` must list `00-04-5f-ad-36-c3`.

## 6. Measuring with Claude (normal way)

1. Open Claude Code (desktop app, Code tab) with **your folder** `users/<name>/` as the
   working directory. Title the session with your name first: "Jane Doe – IV on chipA".
   On first use, answer **yes** when Claude Code asks whether to trust this folder (your
   settings and your separate Claude memory only take effect in a trusted folder), and
   approve reading the kit's files outside your folder if asked.
2. Describe the measurement **with numbers**: device ID, test, maximum |V|, compliance, read
   bias, amplitudes, widths, counts, stop conditions, what you want as output. A request
   template and examples are in [02_how_to_ask_agent.md](02_how_to_ask_agent.md). Any language
   is fine.
3. Claude replies with a **specification table**. Check every number. Answer "yes" only when
   it is right; change a number and Claude shows the table again.
4. Claude writes the device file in your `config/`, **rehearses on the simulator**, and shows
   the result.
5. On the instrument, smallest first:
   1. connection test (only if the instrument has not been used this session),
   2. contact check (`test_read_only`) after every probe landing,
   3. a **small** version of the run, then a look at the data,
   4. the full run.
6. Claude reports: status, run directory, key numbers with their read voltage and compliance,
   anything abnormal, and the plot. It adds an entry to your `NOTES.md`.
7. Long runs go to the background. While one runs: do not edit `.m` files, do not start a
   second MATLAB against the instrument, do not close the Claude session or the PC.

## 7. Measuring by hand in MATLAB

```matlab
cd C:\Agent_assist_project\4200_agent_assisted_testing
setup_paths('jane_doe')                % kit + your folders; use your own name
cfg = device_chipA_R1C1_iv();            % your device file in users/<name>/config/
r = run_dc_cycle_test(cfg);              % or another run_* test, see 03_test_recipes.md
T = load_run_csv(r);                     % the data, one row per measurement
```

- Copy `config/device_TEMPLATE.m` to your `config/`, rename the file **and** the function on
  its first line, set the owner line `cfg = apply_user_folder(cfg, '<name>');`, and fill in
  every REQUIRED field.
- **On Clarius V1.12 (today): SMU only.** Also copy the block "no PMU on this setup" from
  `config/device_RES_bringup.m` (`cfg.pmu.enabled = false`, `cfg.pulse.timing_source = 'pc'`,
  all widths at least 20 ms).
- Real runs need `cfg.mode.simulate_instrument = false`, `cfg.mode.dry_run = false` and the
  confirmation gates (`cfg.safety.compliance_confirmed`, `cfg.safety.limits_confirmed`) set
  by you after checking the numbers.
- Every test stops at a checkpoint that prints every voltage, compliance and count and waits
  for `y`.

## 8. Where data go, names and language

- Your runs: `users/<name>/data/raw/<yyyy-mm-dd_HHMMSS>_device_<id>_<test>/` with
  `measurement_data.csv`, `metadata.json`, `run_summary.txt`, `instrument_log.txt`,
  `config_snapshot.*` and plots.
- Kit-level runs (bring-up on resistors, dry runs) go to the kit's own `data/`.
- **Language.** Talk to Claude in any language. Inside your folder, notes, README, device
  IDs, sample names, analysis files and data labels may be in any language (Chinese, Korean,
  ...); run directories keep those names. Names MATLAB has to call stay ASCII: device-file and
  test-file names and the function name on their first line, and your folder name. The shared
  kit and its templates are English.
- Analysis writes new files next to the raw CSV, never over it.

## 9. Ending a session

1. Let the run finish (or stop it, section 10). The kit turns every output off at the end of
   every run.
2. Make sure your session is disconnected: the file `data/instrument_lock.json` in the kit
   must not exist. If it does and no MATLAB of yours is running, see section 10.
3. Ask Claude to finish your `NOTES.md` entry if it has not.
4. If someone needs Clarius next: close KXCI, then start Clarius.
5. Raise the probes / unload the sample as usual.

## 10. Stopping and recovery

| Situation | What to do |
|---|---|
| You want to stop a run | Ctrl+C in MATLAB, or tell Claude to stop. The output-off guard runs. |
| MATLAB was killed (Task Manager, crash, PC restart, a closed Claude session during a background run) | Outputs may still be on. Run `setup_paths; test_instrument_connection` (or ask Claude to). It turns every output off and clears the lock left behind. Read what it prints. |
| `instrument_lock:InUse` | Someone else is connected; the message says who and since when. Wait. Never delete the lock file. |
| `instrument_lock:Stale` | A killed MATLAB left the lock. Run `test_instrument_connection` as above. |
| Connection refused / time-out | KXCI not running, Clarius open, wrong address after a 4200A restart (section 5.3), or another program holds the socket. |
| Current stays at a few pA whatever the voltage | Open circuit: probes not in contact, or wiring. Re-land and run the contact check. |
| Noisy megaohm reading that suddenly becomes clean | Poor contact that settled mid-run. Discard those points; repeat after the contact check. |
| `ERROR: KXCI command error. (-992)` in the KXCI window | The 4200A rejected a command. On Clarius V1.12 this is expected for `:PMU:` commands (for example during the connection test). For anything else, stop and tell the maintainer: the kit cannot detect rejected commands yet. |
| "NO VALID LRS ... raise cfg.dc.compliance" from a DC run | Do not raise the compliance because of this message; look at the currents first (a resistor or an open circuit triggers it too). |
| Anything you do not understand | Stop, keep the data, ask. |

## 11. Current limitations (2026-11-24; check HANDOFF section 0 for updates)

- **Clarius V1.12 has no PMU KXCI commands**: no PMU pulses, no RPM switching. SMU-only work
  (DC sweeps, reads, SMU-timed pulses of 20 ms or longer) works and is verified on a resistor.
- **The kit cannot yet detect a rejected command** (bring-up item I). Watch the KXCI window
  for errors during new kinds of runs.
- Bring-up items C–H are not done; real devices need the maintainer's go-ahead.
- A Clarius upgrade (to V1.13 or V1.14; not V1.15 for now) is under discussion.

## 12. For the kit maintainer

- **Adding or renaming a user:** `users\sync_users.ps1` (see [../users/README.md](../users/README.md));
  it regenerates everyone's `.claude/settings.json`.
- **4200A address changed:** edit `cfg.instrument.host` in `config/default_config.m`, run
  `test_dry_run`, then `test_instrument_connection`.
- **Changing shared code:** follow AGENTS.md section 5; `test_dry_run` must end with 0
  failures and `checkcode` with 0 messages before anyone uses it on the instrument.
- **After a Clarius upgrade:** repeat the connection test (bring-up A), then items C–I on
  resistors ([07_bring_up.md](07_bring_up.md)); re-check that KXCI still accepts a raw socket
  on Ethernet (V1.15 moved to HiSLIP). Update HANDOFF and the cheat sheet.
- **Bring-up records** go into [07_bring_up.md](07_bring_up.md); the setup's state into
  [../HANDOFF.md](../HANDOFF.md).

## 13. Quick reference

| What | Where / command |
|---|---|
| Kit | `C:\Agent_assist_project\4200_agent_assisted_testing` |
| MATLAB | `"C:\Program Files\MATLAB\R2026b\bin\matlab.exe"` |
| Start (MATLAB) | `cd <kit>; setup_paths('<name>')` |
| Connection test / recovery | `setup_paths; test_instrument_connection` |
| Contact check | `test_read_only(cfg)` |
| Regression (no instrument) | `setup_paths; test_dry_run` → must end "0 failed" |
| Lock file | `<kit>\data\instrument_lock.json` (exists only while someone is connected) |
| 4200A | `169.254.66.232`, TCP `5230`, KXCI, Clarius V1.12 |
| Setup state | `HANDOFF.md` section 0 |
| Your progress | `users/<name>/NOTES.md` |
| Safety | `docs/05_safety.md`, `AGENTS.md` |
| Tests and parameters | `docs/03_test_recipes.md` |
| How to ask Claude | `docs/02_how_to_ask_agent.md` |
