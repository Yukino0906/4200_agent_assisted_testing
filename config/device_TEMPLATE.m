function cfg = device_TEMPLATE()
%DEVICE_TEMPLATE  Per-device configuration. COPY this file for every new device.
%
%   1. Copy to config/device_<sample>_<R#C#>_<purpose>.m, e.g.
%      device_chipA_R9C9_iv.m, and rename the function on the first line to
%      match the file name.
%   2. Fill in every field marked REQUIRED. Start conservative: low voltage,
%      low compliance, few cycles. Raise values only with evidence from a
%      previous run on the SAME device.
%   3. Run the test in simulation first (cfg.mode.simulate_instrument = true).
%   4. For the real run, the OPERATOR sets the two confirmation flags at the
%      bottom after reviewing the numbers. An agent sets them only after you
%      approve the limits in chat.
%
%   Each device gets its own file. Never reuse another device's numbers:
%   thresholds, windows and read bias all differ from device to device.
%
%   Usage:
%       setup_paths
%       cfg = device_chipA_R9C9_iv();
%       r = run_dc_cycle_test(cfg);
%
%   See also DEFAULT_CONFIG, VALIDATE_CONFIG.

cfg = default_config();

% ---- identity (REQUIRED) -------------------------------------------------
cfg.device.device_id = 'SAMPLE_RxCy_purpose';   % REQUIRED, unique per device+purpose
cfg.device.sample_id = '';                      % sample / wafer name
cfg.device.stack     = '';                      % e.g. 'TE / oxide / BE'
cfg.device.area      = NaN;                     % [m^2]
cfg.device.notes     = '';                      % probe position, anything unusual

% ---- safety envelope (REQUIRED: agree these with the device owner) ------
cfg.safety.max_abs_voltage = 2.0;     % [V] nothing above this, ever
cfg.safety.max_abs_current = 1e-2;    % [A] measured |I| above this aborts

% ---- read (REQUIRED) -----------------------------------------------------
% Small bias in the RESET direction. Conduction current must be far above
% any offset current seen at ~0 V after a write (see docs/06_pitfalls.md).
cfg.read.voltage    = -0.1;   % [V]
cfg.read.compliance = 1e-3;   % [A]

% ---- DC I-V --------------------------------------------------------------
% First sweep: small range, few cycles. Widen step by step.
cfg.dc.v_positive_max = 1.0;   % [V]  SET side
cfg.dc.v_negative_max = -1.0;  % [V]  RESET side
cfg.dc.v_step         = 0.02;  % [V]
cfg.dc.compliance     = 1e-3;  % [A]
cfg.dc.num_cycles     = 3;

% ---- pulses (set AFTER the first DC/pulse results on this device) ---------
cfg.pulse.set_amplitudes   = [0.8 1.0];     % [V]  > 0
cfg.pulse.reset_amplitudes = [-0.8 -1.0];   % [V]  < 0
cfg.pulse.widths           = [10e-6 100e-6];% [s]  FWHM; verify with test_single_safe_pulse
cfg.pulse.timing_source    = 'pmu';         % 'pmu' (hardware-timed) | 'pc' (SMU, >= 20 ms)
cfg.pulse.compliance       = 1e-3;          % [A]  SMU ('pc' engine) only

% ---- PMU pulse path (REQUIRED for 'pmu': read docs/05_safety.md section 3) ---
% The PMU has NO current compliance. Limit the current with a series resistor
% or a 1T1R cell when the SET can run away, keep pulses short, and set a
% software limit that stops the run after an over-current pulse.
cfg.pmu.current_range_A    = 1e-3;     % [A] fixed RPM range, >= largest expected current
cfg.pmu.max_current_A      = 0.9e-3;   % [A] stop the run above this (< 0.95 x range)
cfg.pmu.series_resistance_Ohm = NaN;   % [Ohm] record an external series resistor
cfg.pmu.rise_time          = 100e-9;   % [s]
cfg.pmu.fall_time          = 100e-9;   % [s]
cfg.pmu.no_compliance_acknowledged = false;   % OPERATOR ONLY, see section 3

% ---- connection and wiring (see docs/01_setup.md) ---------------------------
cfg.instrument.transport   = 'visa';           % 'visa' | 'tcpclient'
cfg.instrument.host        = '192.168.0.2';    % the 4200A's IP address
cfg.instrument.port        = 1225;             % KXCI port set in KCon
cfg.instrument.resource_candidates = { ...
    sprintf('TCPIP0::%s::%d::SOCKET', cfg.instrument.host, cfg.instrument.port)};
cfg.instrument.resource    = cfg.instrument.resource_candidates{1};
cfg.instrument.return_path = 'gndu';           % 'gndu' | 'pmu_sense'

% ---- conductance window ----------------------------------------------------
% Leave NaN to take the window from this device's latest run_dc_cycle_test,
% or set it from your own data (both values in S, measured at cfg.read.voltage).
cfg.device.G_hrs_S = NaN;
cfg.device.G_lrs_S = NaN;

% ---- write-verify amplitudes (used by map / LTP-LTD / relaxation init) ---
% Keep these OFF the amplitudes under test.
cfg.initial_states.coarse_amplitude_set   =  0.9;
cfg.initial_states.fine_amplitude_set     =  0.7;
cfg.initial_states.coarse_amplitude_reset = -0.9;
cfg.initial_states.fine_amplitude_reset   = -0.7;

% ---- test-specific blocks: copy from default_config.m and edit -------------
% cfg.ltp_ltd.*   cfg.single_pulse.*   cfg.read_noise.*   cfg.relaxation.*
% cfg.endurance.* cfg.retention.*

% ---- execution mode ----------------------------------------------------------
cfg.mode.simulate_instrument       = true;    % false = real 4200A
cfg.mode.dry_run                   = true;    % false = output may turn on
cfg.mode.require_user_confirmation = true;    % keep true for first runs

% ---- confirmation gates (OPERATOR ONLY) --------------------------------------
% Set both to true yourself after checking every number above. An AI agent
% leaves them false until you approve these limits in chat for this device.
cfg.safety.compliance_confirmed = false;
cfg.safety.limits_confirmed     = false;
end
