# Session for <Full Name> (`users/<name>`)

Open Claude Code with **this folder** as the working directory. Claude Code then loads this
file and the kit's `CLAUDE.md` one level up (`AGENTS.md` + `HANDOFF.md`). Every rule there
applies here. This file adds what belongs to this user only.

## Identity
- Owner name in the kit: `<name>`. Every device file in `config/` here starts with
  `cfg = default_config(); cfg = apply_user_folder(cfg, '<name>');`
- Start every MATLAB job with `setup_paths('<name>')`, for example:
  `"C:\Program Files\MATLAB\R2026b\bin\matlab.exe" -batch "cd('C:\Agent_assist_project\4200_agent_assisted_testing'); setup_paths('<name>'); ..."`
- Runs are saved in `users/<name>/data/raw/`. A real run always uses a device file from
  `config/` here, never a bare `default_config()` or `sim_config(...)`.

## Language
- Reply in the language the user writes in.
- Content in this folder may be in any language the user prefers: `NOTES.md`, `README.md`,
  device IDs, sample names, notes, analysis files. Write `NOTES.md` in the user's language
  unless they ask otherwise.
- Device-file and test-file names (and their function names) must stay ASCII: MATLAB cannot
  call anything else.

## Where things go
- Device files: `config/device_<sample>_<R#C#>_<purpose>.m`, copied from
  `../../config/device_TEMPLATE.m`.
- Own tests and run scripts: `tests/`, copied from
  `../../examples/example_custom_test_skeleton.m`. Use names no kit function uses.
- Analysis and plots: `analysis/`.
- Progress: `NOTES.md` here. Add a dated entry at the end of each working session: what
  ran (test, device_id, run directory), key numbers, problems, next steps. `HANDOFF.md` at
  the kit root describes the setup as a whole. Do not write personal progress there.

## Limits of this session
- Edit only files inside `users/<name>/`. The shared kit (`src/`, `config/`, `tests/`,
  `examples/`, `docs/`, the root files) and the other users' folders are read-only here.
  `.claude/settings.json` blocks Claude's edit tools on them. If the kit needs a change,
  write it down in `NOTES.md` and ask the kit maintainer (a session opened at the kit root).
- Never edit, move or delete anything under `data/raw/`, yours or anyone else's.
- One controller at a time. If a connection fails with `instrument_lock:InUse`, someone else
  is measuring: say who (the message names them) and wait. Never work around it.
  `instrument_lock:Stale` means a MATLAB was killed while connected: run
  `test_instrument_connection` (it turns every output off and clears the lock) and report
  what it printed.
- The Claude account is shared. Start the session title with the user's name, e.g.
  "<Full Name> – IV on chipA".
- The current state of the instrument (what works, what does not) is in `HANDOFF.md`
  section 0. Check it before planning a measurement. The day-to-day procedure is in
  `../../docs/00_SOP.md`.
