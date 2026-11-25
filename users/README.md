# users/ — one folder per person

This PC is shared. The kit itself (`config/default_config.m`, `config/device_TEMPLATE.m`,
`src/`, `examples/`, `tests/`, `docs/`) is common to everyone and is changed only on
purpose, for everyone (AGENTS.md section 5). Everything that belongs to one person's work
lives in that person's folder here.

```
users/
├── README.md           this file
├── sync_users.ps1      adds a user; regenerates everyone's .claude/settings.json
├── _TEMPLATE/          the starting point for a new user
└── <name>/             e.g. jane_doe (given name _ family name, lower case)
    ├── CLAUDE.md       instructions for Claude sessions opened in this folder
    ├── NOTES.md        this user's progress log (one entry per working session)
    ├── README.md       who, which samples, anything the next person should know
    ├── .claude/        settings.json: Claude may not edit the kit or other users' folders
    ├── config/         device files: device_<sample>_<R#C#>_<purpose>.m
    ├── tests/          your own tests (copied from examples/example_custom_test_skeleton.m)
    │                   and run scripts
    ├── analysis/       your analysis and plotting scripts
    └── data/           created by the first run, never in git
        ├── raw/<yyyy-mm-dd_HHMMSS>_device_<id>_<test>/   one folder per run
        ├── metadata/   JSON copy of every run's metadata
        └── logs/
```

The kit's own `data/` at the top level keeps kit-level runs only: the resistor bring-up
([docs/07_bring_up.md](../docs/07_bring_up.md)), the dry run, and anything else that
belongs to the setup rather than to a person.

## Working with Claude

Open Claude Code (or the Code tab of the desktop app) with **your own folder**,
`users/<name>/`, as the working directory. Claude Code then loads your `CLAUDE.md` and the
kit's `CLAUDE.md` one level up, so the session knows the shared safety rules and who it is
working for. It saves your runs in your `data/`, writes your progress into your `NOTES.md`, and
cannot edit the shared kit or anyone else's folder. Changes to the shared kit are made from
a session opened at the kit root (the kit maintainer's session).

The lab shares one Claude account, so everyone sees everyone's session list. Start each
session title with your name ("Jane Doe – IV on chipA").

The 4200A takes one controller at a time. When someone else is connected, a connection
attempt stops with `instrument_lock:InUse` and names that person. Wait for them; do not work
around it.

## Start a new user

1. From the kit root, run (PowerShell):
   `powershell -ExecutionPolicy Bypass -File users\sync_users.ps1 -NewUser <name> -FullName "<Full Name>"`.
   The name is a letter followed by letters, digits or `_` (`jane_doe`; no spaces, no
   Chinese characters, no `-`). The script copies `_TEMPLATE`, fills in the name, and
   regenerates every user's `.claude/settings.json` so the new folder is protected from the
   others and the others from it.
2. Fill in `users/<name>/README.md`.
3. For each device, copy `config/device_TEMPLATE.m` to
   `users/<name>/config/device_<sample>_<R#C#>_<purpose>.m`, rename the function on its first
   line, and set the owner line to your name:

   ```matlab
   cfg = default_config();
   cfg = apply_user_folder(cfg, '<name>');
   ```

## Use it

```matlab
cd <kit folder>
setup_paths('<name>')          % kit + your config/, tests/, analysis/
cfg = device_<id>();           % your device file
r   = run_<test>(cfg);         % data go to users/<name>/data/raw/...
```

## What the kit enforces

- `apply_user_folder` moves `cfg.data_root`, `raw_root`, `metadata_root` and `log_root` to
  `users/<name>/data/`. It refuses a name whose folder does not exist (a typo cannot create
  a stray folder), and it refuses when the file calling it lives in another user's folder
  (a device file copied from someone else cannot send data back into their folder or into
  the kit's `data/`).
- `setup_paths('<name>')` puts only that user's folders on the MATLAB path and removes any
  other user's folders left over from an earlier call in the same MATLAB session.
- The kit's folders stay in front of a user's on the path. A user file with the same name as
  a kit function (for example a copy of `run_ltp_ltd_test.m`) never replaces the kit's version:
  `setup_paths` warns and the kit's version runs. Give your files their own names.
- A device's conductance window is looked up from the latest DC run of the same
  `device_id` in **your** `data/metadata/` only.
- One controller at a time: `connect_instruments` claims `data/instrument_lock.json` (kit
  root) before it opens a connection and `disconnect_instruments` releases it. A lock left by
  a killed MATLAB is cleared only by `test_instrument_connection`, which also turns every
  output off.
- `users/<name>/.claude/settings.json` (written by `sync_users.ps1`) denies Claude's edit
  tools on the shared kit, on the other users' folders, on your own `data/raw/` and on the
  settings file itself. It guards Claude's file tools, not the operating system: it is a
  safety net, not access control.

## Language

- Chat with Claude in any language.
- Your own content may be in any language: `NOTES.md`, `README.md`, device IDs
  (`cfg.device.device_id`), sample names, notes in device files, analysis files and folders.
  Run directories keep those names (e.g. `2026-11-24_120000_device_<Chinese or Korean name>_dc_cycle_test`).
- Names MATLAB has to call stay ASCII: device-file and test-file names (and the function name
  on their first line), and your folder name `users/<name>`.
- The shared kit and the templates are English.

## Rules

- The day-to-day procedure is in [../docs/00_SOP.md](../docs/00_SOP.md).
- Only add to, never edit or delete, anything under `data/raw/` — yours or anyone else's.
- Do not edit another user's folder unless that user asks you to.
- A test in `tests/` still runs on the simulator first (AGENTS.md rule 4), and `checkcode`
  must report nothing on it. A test that would be useful to everyone belongs in
  `src/measurement/` and in `test_dry_run` instead; see AGENTS.md section 5.
- No device numbers or user names in `src/`.
