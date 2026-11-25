# 4200A handoff (HANDOFF)

Last updated: 2026-11-24. Readers: Claude Code on the lab PC (the kit-maintainer session at
the kit root and every user's session) and the people who use this setup.

Session memory does not travel between sessions or computers: this file is the shared
context for **the setup as a whole**. Each person's own progress lives in
`users/<name>/NOTES.md`. Whenever a decision is made or a check produces a new result,
update this file and commit. The day-to-day procedure is in
[docs/00_SOP.md](docs/00_SOP.md); the generic first-time setup (any PC already cabled to a
4200A) is the Quick start in [README.md](README.md).

This file records one particular lab setup. When the kit is reused elsewhere, start a new
HANDOFF from the Quick start; the facts below (addresses, versions, wiring) belong to this
setup only.

## 0. Current state

| Area | State (2026-11-24) |
|---|---|
| Connection to the 4200A (bring-up A) | **Pass.** tcpclient, `169.254.66.232:5230`, NUL terminator, replies `ACK` |
| SMU measurement (bring-up B) | **Pass.** 221 kΩ resistor measured 221.53 kΩ (+0.24 %), both polarities |
| RPM path switching (C) | Not applicable with the present wiring (SMU straight to probe 1) |
| PMU pulses (E–G) | **Not available**: Clarius V1.12 has no `:PMU:` KXCI commands (they start at V1.13) |
| Rejected-command detection (I) | **Fail.** KXCI answers `ACK` even to invalid commands; the kit cannot read KXCI errors yet |
| Killed-MATLAB recovery (H) | Not done |
| One-controller lock | **Verified on the real 4200A** (claim, refusal of a second MATLAB, release) |
| Per-user Claude sessions | Set up; not yet tried in a real per-user session |
| Clarius upgrade | Under discussion in the lab (see section 3.4) |
| MATLAB licence for shared use | Open (see section 3.1) |

What works today: **SMU-only measurements** (DC I-V sweeps, reads, SMU-timed pulses of
20 ms or longer) with `cfg.pmu.enabled = false` and `cfg.pulse.timing_source = 'pc'`, as in
`config/device_RES_bringup.m`. AGENTS.md rule 15 still requires items A–C, E–G and I before
real devices; with C not applicable, E–G impossible on V1.12 and I failing, using real
devices for SMU-only work needs the operator's explicit decision.

### Next steps (each instrument step needs the operator's explicit approval)

1. Try `SP` (status byte) as the error query with every output off: after `XX9`, bit B1 (2)
   should be set. If it works, set `cfg.instrument.error_query` / `no_error_pattern` and repeat
   item I.
2. Lab decision on upgrading Clarius to V1.13 or V1.14 (not V1.15, see 3.4). After an upgrade:
   repeat A, then C–G on resistors.
3. Bring-up H (outputs off after a killed MATLAB) once per setup.
4. In the first real per-user session: confirm both `CLAUDE.md` files load, the edit
   restrictions work, the memory goes to the user's own folder, and Grep finds the user's
   files (section 9).

## 1. Hardware and wiring

- 4200A-SCS: **one SMU** (slot 1, 4201 MPSMU = SMU1), **one 4225-PMU**
  (slot 9), **two 4225-RPMs**, ground unit (GNDU). KCon's main page does not list the RPMs;
  whether both are detected is not confirmed (click the 4225 PMU entry in KCon).
- Rear panel, left: the built-in Windows PC with **four RJ45 ports**. One carries a grey
  CAT5e patch cable with an orange light: the building network. **Do not unplug it or change
  its adapter settings.** The cable labelled "HDMI Cable with Ethernet" is the monitor cable.
- Rear panel, right, GNDU: a **yellow triax on FORCE** (return path via GNDU,
  `cfg.instrument.return_path = 'gndu'`).
- Probe wiring (operator, 2026-11-24): **probe 1 = SMU1, connected directly (no RPM in the
  SMU path); probe 2 = ground (GNDU)**. With this wiring PMU pulses cannot reach the probes.
- The lab PC is connected by an Ethernet cable to the 4200A port that Windows calls
  **`Ethernet 4`** (I219-LM, MAC `00-04-5F-AD-36-C3`, confirmed through the PC's ARP table).

## 2. Network

- Claude Code (and git) need the internet. The lab PC's only wired port goes to the 4200A, so
  the PC uses **Wi-Fi** for the internet.
- **Direct link in use (operator's decision, 2026-11-24): automatic link-local addresses, no
  settings changed on either side.** 4200A `Ethernet 4` = `169.254.66.232/16`, lab PC
  `Ethernet` (Intel I219-LM) = `169.254.147.13/16`. If the 4200A restarts, its address may
  change: run `ipconfig` on the 4200A, read the "Autoconfiguration IPv4 Address" of
  `Ethernet 4`, and update `cfg.instrument.host` in `config/default_config.m` (the only place
  it is set).
- 4200A adapters (operator's `ipconfig /all`, 2026-11-24): `Ethernet` (I210) = building
  network, DHCP with gateway, **leave alone**; `Ethernet 2` and `Ethernet 3` (I210 #2/#3)
  unplugged; `Ethernet 4` as above. The building subnet does not clash with 192.168.0.x.
- Alternative for a fixed address later: static IPs on both direct-link adapters with **no
  gateway** (lab PC `192.168.0.1/24`, 4200A `Ethernet 4` `192.168.0.2/24`, needs the 4200A
  administrator). Changing only that adapter does not affect the 4200A's internet access.
- **The 4200A's firewall does not answer ping.** To check the link: `ping <host>` (times out),
  then `arp -a`; seeing MAC `00-04-5f-ad-36-c3` means the link is up. The KXCI port 5230 is not
  blocked.
- If a connection is refused: is KXCI running, is the port right; then the 4200A's Windows
  firewall (new networks are often "Public" and block the port; setting `Ethernet 4` to
  "Private" or allowing TCP 5230 from the lab PC are the narrow fixes, administrator's call).

## 3. Software and configuration

### 3.1 Lab PC
- **MATLAB R2026b** at `C:\Program Files\MATLAB\R2026b\bin\matlab.exe` (not on PATH; always use
  the full path). **No Instrument Control Toolbox** → no `visadev` → the kit uses
  `cfg.instrument.transport = 'tcpclient'`.
- NI-VISA 26.8.0 is installed but unusable from MATLAB without the toolbox.
- **MATLAB licence (open):** installed by the operator with their own account. Recommendation:
  ask the university's IT whether this lab PC can be licensed under the campus licence as a
  lab machine; otherwise each person signs in with their own university MathWorks account. The kit stores data
  by `users/` folder, independent of the MATLAB account.
- The kit folder is `C:\Agent_assist_project\4200_agent_assisted_testing` (merged from the
  former `-main` subfolder on 2026-11-24). Since 2026-11-24 it is a git working copy of
  `github.com/Yukino0906/4200_agent_assisted_testing` (public). git is the copy bundled with
  GitHub Desktop: `C:\Users\<user>\AppData\Local\GitHubDesktop\app-<version>\resources\app\git\cmd\git.exe`.
  That git has no stored GitHub login, so an agent can commit but **cannot push**: push from
  GitHub Desktop (repository added from this folder; "Push origin"). Personal folders and
  `data/` are gitignored and never appear there.

### 3.2 4200A (KCon, photographed 2026-11-24)
- **Clarius+ V1.12**, system software 4200A-852-1.12C, platform 4200A-300-4.
- KXCI Settings: Communications **Ethernet**, **Port 5230**, Reading Delimiter = String
  Terminator, String Terminator Character = LF, Command Set = 4200A (Normal), SMU1 → SMU 1.
  The LF setting does not affect Ethernet: commands and replies use NUL (the manual says
  "Commands must always be terminated with null").
- The 4200A clock runs about 57 minutes behind the lab PC (KXCI window 17:06:02 = PC 18:03:38).

### 3.3 Kit settings for this setup (`config/default_config.m`)
- `transport = 'tcpclient'`, `host = '169.254.66.232'`, `port = 5230`. Device files inherit
  these; `config/device_TEMPLATE.m` no longer sets them.
- One-controller lock: `cfg.instrument.lock_file = <kit>/data/instrument_lock.json`.
- `config/device_RES_bringup.m`: kit-level SMU-only resistor file (PMU disabled, `'pc'` timing,
  all widths ≥ 20 ms, ceiling 1.5 V, sweep ±0.5 V, 1 mA).

### 3.4 Clarius version (from the KXCI manual 4200A-KXCI-907-01 Rev F and release notes)
- **All `:PMU:` KXCI commands require Clarius V1.13 or later.** On V1.12 they give
  `KXCI command error. (-992)`; this includes the RPM path command that the kit sends before
  SMU reads when the PMU is enabled.
- `:ERROR:LAST:GET` (remote error message) was also added in V1.13. On V1.12 the candidate is
  `SP` (status byte; B1 = syntax error), not yet tried.
- V1.15 (Feb 2026) moves KXCI Ethernet to HiSLIP/VISA. Whether the raw socket this kit uses
  still works there is not confirmed; this PC has no Instrument Control Toolbox for VISA.
  **If upgrading, V1.13 or V1.14 suit the kit best.** An upgrade affects every Clarius user of
  this 4200A: export everyone's Clarius projects first.

## 4. What has been verified on this setup

Details and numbers: [docs/07_bring_up.md](docs/07_bring_up.md) (record table) and
[docs/04_kxci_cheatsheet.md](docs/04_kxci_cheatsheet.md).

- **Software (lab PC):** `test_dry_run` **78 passed / 0 failed** (simulator, KxciMock,
  instrument-lock tests, non-ASCII device names); `test_instrument_connection`,
  `test_read_only` and `test_single_safe_pulse` pass on KxciMock; checkcode 0 on every
  changed file.
- **First connection (18:03):** `*IDN?` → `KEITHLEY INSTRUMENTS,KI4200A,<serial>,V1.12`; reply to
  commands without data is `ACK` (item A). Log `data/logs/connection_test.log`.
- **Item I (18:06):** the bogus command `XX9` was answered `ACK`; the KXCI window showed
  `ERROR: KXCI command error. (-992)` for it and for `:PMU:OUTPUT:STATE 1, 0`; the SRQ lamp
  lit. The instrument notices errors; the kit cannot read them yet.
- **SMU on a resistor** (`run_dc_cycle_test` with `config/device_RES_bringup.m`, ±0.5 V,
  1 mA, blind test, nominal 221 kΩ given afterwards):
  - run 1 (18:36): open circuit (constant −15 pA, the SMU offset): probes not in contact;
  - run 2 (18:40): poor contact for the first 26 points, then 221.6 kΩ (negative branch);
  - run 3 (18:50): good contact throughout, **221.53 kΩ**, positive 221.72 kΩ, negative
    221.44 kΩ, −0.1 V read 221.05 kΩ. `TI1` reply form `NAI-14.74702E-12`.
- **One-controller lock on the real 4200A (19:08):** a connected MATLAB wrote the lock (user,
  Windows user, computer, PID); a second MATLAB was refused with `instrument_lock:InUse` naming
  the holder; a lock from a non-existent PID was recognised as stale; after disconnecting, the
  lock file was gone.

## 5. Open assumptions (bring-up item in brackets)

| Assumption | Setting | State |
|---|---|---|
| KXCI answers every command with an acknowledge (A) | `ack_mode = true`, `ack_pattern = '^ACK'` | Verified: `ACK`, also for invalid commands |
| `TI1` reply format (B) | parser accepts a bare number or `NAI+…` | Verified: `NAI-14.74702E-12` |
| RPM SMU path code (C) | `cfg.pmu.rpm_code_smu = 3` | Not applicable now; needs V1.13+ |
| PMU CH2 holds 0 V during SMU reads (D) | not used (`'gndu'`) | Open |
| PMU width, current sign and size (E, F) | trapezoid FWHM | Needs V1.13+ |
| Software PMU current limit trips (G) | `max_current_A ≤ 0.95 × range` | Needs V1.13+ |
| Outputs off after a killed MATLAB (H) | `test_instrument_connection` | Open |
| A rejected command is noticed (I) | error query | **Fails**: needs `SP` or V1.13's `:ERROR:LAST:GET` |

## 6. Rules in short (full text: `AGENTS.md`, `docs/05_safety.md`)

- Never above the device file's `cfg.safety.max_abs_voltage`; the code refuses anything above 5 V.
- **The PMU has no hardware current limit.** Forming and the first SET use the SMU only.
- The confirmation gates (`compliance_confirmed`, `limits_confirmed`,
  `pmu.no_compliance_acknowledged`) are set only by the operator, or by an agent after the
  operator approves the numbers in chat: per device, per session.
- No real devices until bring-up passes; settings marked UNVERIFIED change only as the outcome
  of a bring-up item.
- No `.m` edits while a measurement runs; background hardware jobs need a timeout longer than
  the whole procedure.
- After a killed MATLAB: `test_instrument_connection` first (it also clears the stale lock).
- One controller at a time: Clarius closed, one MATLAB; the lock enforces this between MATLABs.
- `data/raw/` and `users/*/data/raw/` are append-only; no `data/` goes into git.
- Work in one user's folder at a time; never change another user's folder (AGENTS.md rule 18).

## 7. Known pitfalls

- With `'visa'`, changing `host` without `resource_candidates` connects to the old address.
  This PC uses `'tcpclient'` (host and port directly); change addresses in `default_config.m`.
- **Fixed 2026-11-24:** `test_instrument_connection`, `test_read_only` and
  `test_single_safe_pulse` built their `onCleanup` guard while `inst` was still `[]`, so Ctrl+C
  did not turn outputs off. The guard is now created after `connect_instruments` (verified on
  KxciMock; a real Ctrl+C cannot be sent in `-batch`). `begin_measurement` never had this issue.
- The kit's DC analysis prints "NO VALID LRS … raise cfg.dc.compliance" also for an open
  circuit or a resistor. Do not raise the compliance because of it; look at the currents.
- Poor probe contact looks like a megaohm, noisy, asymmetric I-V that suddenly turns clean. Run
  the contact check after every landing.
- One long batch run once gave "Out of memory" when the first figure opened in
  `test_examples`; a rerun passed.
- `matlab -batch` can exit non-zero after finishing: judge by `run_summary.txt` and the log.
- To see whether a background job is alive, watch the newest run directory's files grow, not
  the process list.

## 8. How agents work here

- **Language.** Reply in the language the person writes in; chat may be in any language.
  Everything that belongs to the kit is English: code, comments, docs, templates, this file,
  every `CLAUDE.md`. Inside `users/<name>/`, the person's own notes, README, device IDs,
  sample names, analysis files and data labels may be in any language (Chinese, Korean, …);
  run directories keep those names. MATLAB file and function names (device files, tests) and
  the `users/<name>` folder name must stay ASCII (MATLAB identifier rules).
- MATLAB: use the full path above; run hardware jobs in the background with a long timeout.
- On a new PC: read this file, `AGENTS.md`, `docs/05_safety.md`, `docs/07_bring_up.md`; run
  `check_setup`; report; **do not connect, turn on outputs or change network settings without
  the operator's explicit approval.**
- After each bring-up item: update section 0 here and the record in `docs/07_bring_up.md`.
- In a session at the kit root, ask whose work a measurement is (`users/<name>`) before writing
  a device file.

## 9. Shared PC: users and Claude sessions

- Shared kit (changed only from the kit-root session, following AGENTS.md section 5):
  `config/default_config.m`, `config/device_TEMPLATE.m`, `src/`, `examples/`, `tests/`, `docs/`.
- One folder per person, `users/<name>/` (given name _ family name, lower case, e.g.
  `jane_doe`). Five folders were created on the lab PC on 2026-11-24 (provisional list).
  Personal folders are **not in the git repository** (`.gitignore`: `users/*/`); only
  `users/README.md`, `users/sync_users.ps1` and `users/_TEMPLATE/` are. Each personal folder
  has `CLAUDE.md`, `NOTES.md`, `README.md`, `.claude/settings.json`, `config/`, `tests/`,
  `analysis/` and, after the first run, `data/`. Back them up separately if needed.
- Routing: `setup_paths('<name>')`, and in every device file
  `cfg = apply_user_folder(cfg, '<name>');` right after `default_config()`. A file in
  `users/A/` naming another owner (or none) is refused; a user file named like a kit function
  never replaces the kit's version.
- The kit's own `data/` holds kit-level runs only (bring-up, dry runs) and the lock file.
- **Claude sessions (operator's decision, 2026-11-24; a shared lab Claude account is planned):**
  - Each person opens Claude Code with **their own folder** as the working directory. Claude
    Code then loads that folder's `CLAUDE.md` and the kit's `CLAUDE.md` above it (confirmed in
    the Claude Code docs; the first time it may ask to approve the external imports).
  - `users/<name>/.claude/settings.json` denies Claude's edit tools on the shared kit, on the
    other users' folders, on the person's own `data/raw/` and on the settings file itself
    (rule syntax `Edit(//c/...)`, confirmed in the docs). It guards Claude's file tools and
    shell commands Claude Code recognises, not the operating system: a safety net.
  - Add a person (from the kit root):
    `powershell -ExecutionPolicy Bypass -File users\sync_users.ps1 -NewUser <name> -FullName "<Full Name>"`.
    It creates the folder from `_TEMPLATE`, fills in the name and regenerates **everyone's**
    settings. Renaming a person: rename the folder, fix `apply_user_folder(cfg, '<name>')` in
    their device files, run the script.
  - Kit changes, bring-up and post-upgrade checks happen in the kit-root (maintainer) session.
  - Session titles start with the person's name; everyone sees everyone's sessions.
  - Claude's auto memory is keyed by the git repository, so without extra settings every
    user folder inside the kit would share one memory. Each user's settings therefore set
    their own memory directory (see `users/sync_users.ps1`).
- Not yet tried in a real per-user session: whether both `CLAUDE.md` files load, whether
  edits to the kit are refused, whether the memory goes to `users/<name>/.claude-memory`
  (needs the folder to be trusted), and whether Claude's Grep search finds the user's own
  files. The Claude Code docs say Grep skips gitignored files, and personal folders are
  gitignored; Glob and reading a file by path are not affected.

## 10. Changes made on the lab PC (2026-11-24)

- Folder merge (`-main` removed). `users/` structure: `src/utilities/apply_user_folder.m`,
  `setup_paths.m` (optional user), `users/README.md`, `users/_TEMPLATE/`, `users/sync_users.ps1`,
  five user folders.
- `config/default_config.m`: `cfg.user`, connection settings for this setup, lock settings.
  `config/device_TEMPLATE.m`: owner line; connection block removed. New
  `config/device_RES_bringup.m`.
- One-controller lock: `src/instrument/instrument_lock.m`; `connect_instruments` claims,
  `disconnect_instruments` releases; `test_instrument_connection` may take over a stale lock.
- Ctrl+C guard fix in the three real-instrument tests.
- `create_run_directory`: run directories keep letters of any language.
- `test_dry_run`: lock tests and the non-ASCII name test (78 checks).
- Docs: `AGENTS.md` (rules 12, 13, 17, 18, layout, sections 3–5), `README.md`, `docs/00_SOP.md`
  (new), `docs/01`–`05`, `docs/07` record (A, B, C, I), this file (now in English).
