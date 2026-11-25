function cfg = device_RES_bringup()
%DEVICE_RES_BRINGUP  Kit-level bring-up on a resistor (docs/07_bring_up.md). SMU only.
%
%   Wiring on this setup (operator, 2026-11-24): SMU1 straight to probe 1,
%   probe 2 to ground, a resistor between the probes. No RPM in the SMU path.
%   This 4200A runs Clarius+ V1.12, which has no :PMU: KXCI commands (they
%   start at V1.13), so the PMU is disabled here: kxci_select_path and
%   kxci_force_safe then send SMU commands only (US, DV, TI).
%
%   Kit-level file (owner ''): runs are saved in the kit's data/, not in a
%   user's folder. The measured resistance is reported from a linear fit of
%   the I-V points of run_dc_cycle_test.
%
%   Usage:
%       setup_paths
%       cfg = device_RES_bringup();
%       r = run_dc_cycle_test(cfg);
%
%   See also DEVICE_TEMPLATE, RUN_DC_CYCLE_TEST.

cfg = default_config();

% ---- owner -----------------------------------------------------------------
cfg = apply_user_folder(cfg, '');   % kit-level bring-up: data/ at the kit root

% ---- identity ------------------------------------------------------------
cfg.device.device_id = 'RES_bringup';   % runs override this with the nominal value
cfg.device.notes     = ['Resistor between probe 1 (SMU1, direct) and probe 2 (ground). ' ...
                        'PMU disabled (Clarius V1.12).'];

% ---- safety envelope -----------------------------------------------------
cfg.safety.max_abs_voltage = 1.5;     % [V] docs/07_bring_up.md value; the sweep itself stays at +/-0.5 V
cfg.safety.max_abs_current = 1e-2;    % [A] measured |I| above this aborts

% ---- read ----------------------------------------------------------------
cfg.read.voltage    = -0.1;   % [V]
cfg.read.compliance = 1e-3;   % [A]

% ---- DC I-V: one small bipolar loop --------------------------------------
cfg.dc.v_positive_max   = 0.5;    % [V]
cfg.dc.v_negative_max   = -0.5;   % [V]
cfg.dc.v_step           = 0.05;   % [V]
cfg.dc.delay            = 0.01;   % [s] settle per point
cfg.dc.compliance       = 1e-3;   % [A]
cfg.dc.num_cycles       = 1;
cfg.dc.read_after_cycle = true;

% ---- no PMU on this setup (Clarius V1.12, SMU wired directly) ---------------
cfg.pmu.enabled            = false;
cfg.pulse.timing_source    = 'pc';     % SMU-timed; no pulses are applied by the DC test
cfg.pulse.set_amplitudes   = 0.5;      % [V] unused by the DC test, kept inside the ceiling
cfg.pulse.reset_amplitudes = -0.5;     % [V]
cfg.pulse.widths           = 20e-3;    % [s] 'pc' minimum
cfg.pulse.compliance       = 1e-3;     % [A]
cfg.initial_states.coarse_amplitude_set   =  0.5;
cfg.initial_states.fine_amplitude_set     =  0.4;
cfg.initial_states.coarse_amplitude_reset = -0.5;
cfg.initial_states.fine_amplitude_reset   = -0.4;
% validate_config checks every width any test could send. With the 'pc'
% engine they must be >= 20 ms. None of them is used by the DC test.
cfg.initial_states.coarse_width = 20e-3;
cfg.initial_states.fine_width   = 20e-3;
cfg.ltp_ltd.width               = 20e-3;
cfg.endurance.width_s           = 20e-3;
[cfg.retention.states.width_s]  = deal(20e-3);

% ---- wiring ----------------------------------------------------------------
cfg.instrument.return_path = 'gndu';

% ---- execution mode ----------------------------------------------------------
cfg.mode.simulate_instrument       = true;    % false = real 4200A
cfg.mode.dry_run                   = true;    % false = output may turn on
cfg.mode.require_user_confirmation = true;

% ---- confirmation gates (OPERATOR ONLY) --------------------------------------
cfg.safety.compliance_confirmed = false;
cfg.safety.limits_confirmed     = false;
end
