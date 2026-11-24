function cfg = default_config()
%DEFAULT_CONFIG  Single source of truth for every tunable measurement parameter.
%
%   cfg = DEFAULT_CONFIG() returns the configuration struct used by every
%   script and measurement function in this kit.
%
%   Inputs : none
%   Outputs: cfg  - struct, see field documentation below. Every physical
%                   quantity is in SI base units:
%                       voltage      [V]
%                       current      [A]
%                       time         [s]
%                       resistance   [Ohm]
%                       conductance  [S]
%                       energy       [J]
%
%   Instrument side effects: NONE. This function only builds a struct.
%
%   Exceptions: none (pure function).
%
%   THE VALUES BELOW ARE CONSERVATIVE STARTING POINTS, NOT DEVICE PARAMETERS.
%   They are sized so that the dry-run simulator exercises every code path.
%   For a real device, copy config/device_TEMPLATE.m, set every field it
%   marks as REQUIRED from your own measurements, and pass that cfg on.
%
%   HOW TO CUSTOMISE
%       Do NOT edit measurement functions. Either copy device_TEMPLATE.m, or:
%           cfg = default_config();
%           cfg.device.device_id = 'chipA_R9C9_iv';
%           cfg.dc.num_cycles    = 3;
%
%   SAFETY GATES that must be cleared before any real-instrument test runs
%   (see validate_config.m and docs/05_safety.md):
%       cfg.safety.compliance_confirmed = true
%       cfg.safety.limits_confirmed     = true
%
%   See also VALIDATE_CONFIG, DEVICE_TEMPLATE.

% ------------------------------------------------------------------------
%% Paths
% ------------------------------------------------------------------------
% Kit root is derived from this file's location -> no hard-coded paths.
thisFile          = mfilename('fullpath');
cfg.project_root  = fileparts(fileparts(thisFile));   % <root>/config/.. = <root>
cfg.data_root     = fullfile(cfg.project_root, 'data');
cfg.raw_root      = fullfile(cfg.data_root, 'raw');
cfg.metadata_root = fullfile(cfg.data_root, 'metadata');
cfg.log_root      = fullfile(cfg.data_root, 'logs');

% ------------------------------------------------------------------------
%% Instrument  (Keithley 4200A-SCS through KXCI, Ethernet or GPIB)
% ------------------------------------------------------------------------
% The laptop controls the 4200A remotely: the KXCI application runs on the
% 4200A, this kit runs on the laptop. See docs/01_setup.md for KCon, the
% network settings and the wiring. Items marked UNVERIFIED are this kit's
% best reading of Keithley's examples; docs/07_bring_up.md checks each one
% on the real instrument before any device is touched.
%
% Transport:
%   'visa'      visadev + NI-VISA. Ethernet raw socket or GPIB resource.
%   'tcpclient' plain MATLAB TCP socket, no NI-VISA (Ethernet only).
%   'mock'      software stand-in (KxciMock), for testing without hardware.
cfg.instrument.transport           = 'visa';
cfg.instrument.host                = '192.168.0.2';   % 4200A IP (set it, see docs/01_setup.md)
cfg.instrument.port                = 1225;            % KXCI port from KCon (Keithley examples use 1225)
cfg.instrument.resource_candidates = { ...
    sprintf('TCPIP0::%s::%d::SOCKET', cfg.instrument.host, cfg.instrument.port)};
%   GPIB alternative: {"GPIB0::17::INSTR"} with terminator "LF" and ack_mode false.
cfg.instrument.resource          = cfg.instrument.resource_candidates{1};
cfg.instrument.model             = 'Keithley 4200A-SCS';
cfg.instrument.language          = 'KXCI';      % NOT SCPI, NOT TSP. Do not change.
cfg.instrument.timeout           = 30;          % [s] per reply
cfg.instrument.terminator        = 0;           % NUL over Ethernet (Keithley examples); "LF" for GPIB
cfg.instrument.reset_on_connect  = true;        % BC + *RST on connect
% Over Ethernet KXCI answers every command; the reply to a command without
% data is an acknowledge. UNVERIFIED text: confirm with
% test_instrument_connection, which prints the raw reply.
cfg.instrument.ack_mode          = true;        % false over GPIB
cfg.instrument.ack_pattern       = '^ACK';      % regexp a good acknowledge matches
cfg.instrument.error_query       = '';          % UNVERIFIED; leave empty until confirmed
cfg.instrument.no_error_pattern  = '^0';        % regexp of a "no error" reply to it
cfg.instrument.check_errors      = true;        % check acknowledges after command bursts

% Hardware map: ONE SMU (reads, DC sweeps), ONE 4225-PMU with two 4225-RPMs.
% The SMU reaches the device through the SMU input of the force-channel RPM.
cfg.instrument.smu               = 1;           % SMU number (DV1 / TI1)
cfg.instrument.smu_range_code    = 1;           % DV source range code; 1 = 20 V range
                                                % in Keithley's example
cfg.instrument.smu_integration_command = '';    % e.g. 'IT2' once verified; '' = instrument default
% Current return of the device's second terminal:
%   'gndu'      second probe on the 4200A ground unit (simplest; default)
%   'pmu_sense' second probe on the sense RPM, PMU channel held at 0 V
%               (needed for the two-channel pulse current measurement)
cfg.instrument.return_path       = 'gndu';
cfg.instrument.rpm_settle_s      = 0.02;        % [s] after an RPM path switch

% ------------------------------------------------------------------------
%% Device under test
% ------------------------------------------------------------------------
cfg.device.device_id   = '';        % REQUIRED for real runs: <sample>_<R#C#>_<purpose>
cfg.device.sample_id   = '';
cfg.device.area        = NaN;       % [m^2] optional, for current density
cfg.device.top_electrode    = '';
cfg.device.bottom_electrode = '';
cfg.device.stack       = '';
cfg.device.notes       = '';
% Conductance window. Left NaN until run_dc_cycle_test measures it; every
% pulse test then places its target states inside [G_hrs_S, G_lrs_S].
cfg.device.G_hrs_S     = NaN;   % [S]
cfg.device.G_lrs_S     = NaN;   % [S]
% Set manually when measuring at a raised temperature; carried into metadata.
cfg.device.temperature_C = NaN;

% ------------------------------------------------------------------------
%% READ settings
% ------------------------------------------------------------------------
% +V is the SET direction, so the default read is at small NEGATIVE bias.
% Pick the read bias per device: conduction current must dwarf any
% post-write offset current, and the read must not move the state
% (check with run_read_noise_test). Always report G with its read voltage.
cfg.read.voltage            = -0.1;     % [V] signed
cfg.read.pulse_width        = 5e-3;     % [s] time the read bias is applied
cfg.read.delay_after_write  = 0.1;      % [s] programmed pause between write and read
cfg.read.settle_time        = 2e-3;     % [s] settle before sampling
cfg.read.num_average_reads  = 3;        % reads averaged per conductance value
cfg.read.reject_outliers    = true;     % drop worst point when n >= 3
cfg.read.current_range      = [];       % [A] [] = autorange
cfg.read.compliance         = 1e-3;     % [A]
cfg.read.min_valid_current  = 1e-12;    % [A] below this -> treat as open circuit

% ------------------------------------------------------------------------
%% DC sweep  (run_dc_cycle_test)
% ------------------------------------------------------------------------
cfg.dc.v_start        = 0.0;    % [V]
cfg.dc.v_positive_max = 1.5;    % [V]  positive = SET
cfg.dc.v_negative_max = -1.5;   % [V]  negative = RESET
cfg.dc.v_step         = 0.05;   % [V]
cfg.dc.delay          = 2e-3;   % [s] settle time per point
cfg.dc.compliance     = 1e-3;   % [A]  start low; raise only with evidence
cfg.dc.num_cycles     = 5;      % START AT 5. Raise only after review.
cfg.dc.read_after_cycle = true; % read HRS/LRS at cfg.read.voltage each cycle
% The sweep is paced point by point from the laptop (DV, wait, TI). Each
% point is written to disk as it is measured.

% --- switching-threshold extraction (hysteresis closure) -----------------
% A gradually switching device has no current jump to anchor a threshold
% on. V_set / V_reset are therefore defined as the voltage at which the
% state transition COMPLETES, i.e. where the outbound and return branches of
% the hysteresis loop merge again on their way to the sweep endpoint.
% These values are higher than jump-onset thresholds; always quote the
% definition with the numbers.
cfg.dc.closure_ratio_threshold    = 1.5;   % branches count as merged when the
                                           % symmetric ratio r drops to this
cfg.dc.search_start_abs_voltage_V = 0.3;   % [V] start |V| of the search; below
                                           % this the branches meet trivially
cfg.dc.current_noise_floor_A      = 1e-12; % [A] below this a reading carries no
                                           % information: interpolate linearly
                                           % instead of in log space, and floor
                                           % the ratio so it cannot blow up

% ------------------------------------------------------------------------
%% PULSE settings  (single-pulse map and the write path in general)
% ------------------------------------------------------------------------
% Sign convention: +V = SET, -V = RESET.
cfg.pulse.set_amplitudes   = [1.0 1.2 1.4];      % [V]
cfg.pulse.reset_amplitudes = [-1.0 -1.2 -1.4];   % [V]
% Widths are the FWHM of the PMU trapezoid (edges in cfg.pmu.rise_time /
% fall_time). Verify them once per setup with tests/test_single_safe_pulse.
cfg.pulse.widths           = [10e-6 100e-6];     % [s]
cfg.pulse.rise_time        = NaN;   % [s] reported per pulse from cfg.pmu
cfg.pulse.fall_time        = NaN;   % [s]
% SMU compliance for the 'pc' engine. The PMU has NO compliance: see
% cfg.pmu.max_current_A and docs/05_safety.md.
cfg.pulse.compliance       = 1e-3;  % [A]
cfg.pulse.samples_in_pulse = 3;     % SMU samples during a 'pc' pulse
cfg.pulse.timing_source    = 'pmu'; % 'pmu' (4225-PMU, hardware-timed, preferred)
                                    % 'pc'  (SMU DV + pause, >= 20 ms only)
cfg.pulse.energy_method    = 'average_current';  % or 'waveform_integral'
cfg.pulse.inter_pulse_delay = 0.05; % [s] quiet time after the pulse

% ------------------------------------------------------------------------
%% PMU  (4225-PMU + 4225-RPM; used when cfg.pulse.timing_source = 'pmu')
% ------------------------------------------------------------------------
cfg.pmu.enabled          = true;
cfg.pmu.card             = 1;       % PMU1
cfg.pmu.force_channel    = 1;       % PMU1 CH1 -> RPM -> first terminal (top electrode)
cfg.pmu.sense_channel    = 0;       % 0 = current measured on the force channel;
                                    % 2 = PMU1 CH2 at 0 V on the second terminal
                                    %     (requires cfg.instrument.return_path = 'pmu_sense')
% RPM path codes for :PMU:RPM:CONFIGURE. 0 = PMU path is in Keithley's KXCI
% examples. The SMU code is UNVERIFIED (3 follows the RPM path constants of
% Keithley's C library): test_read_only on a resistor confirms it.
cfg.pmu.rpm_code_pulse   = 0;
cfg.pmu.rpm_code_smu     = 3;
% Current measurement: fixed range, type 2 = fixed in Keithley's example.
% RPM ranges: 100e-9, 1e-6, 10e-6, 100e-6, 1e-3, 10e-3 A.
cfg.pmu.measure_range_type = 2;
cfg.pmu.current_range_A  = 1e-3;    % [A] must cover the largest expected pulse current
% Trapezoid timing. The width in cfg.pulse.widths is the FWHM.
cfg.pmu.rise_time        = 100e-9;  % [s]
cfg.pmu.fall_time        = 100e-9;  % [s]
cfg.pmu.pre_time         = 1e-6;    % [s] 0 V before the pulse (baseline window)
cfg.pmu.post_time        = 1e-6;    % [s] 0 V after the pulse
cfg.pmu.min_segment_time = 20e-9;   % [s] shortest segment the kit will send
cfg.pmu.max_width_s      = 1e-3;    % [s] longest PMU pulse validate_config allows
cfg.pmu.measure_window   = [0.2 0.9];  % fraction of the top averaged for the current
cfg.pmu.baseline_measure = true;    % spot mean at 0 V before the pulse
% SOFTWARE current limit, checked AFTER each pulse. The PMU cannot clamp the
% current while the pulse runs; a series resistor or a 1T1R cell can.
cfg.pmu.max_current_A    = 0.9e-3;  % [A] above this the run is stopped (< 0.95 x range)
cfg.pmu.series_resistance_Ohm = NaN;   % [Ohm] external series resistor, recorded only
% Must be set true BY THE OPERATOR after reading docs/05_safety.md section 3.
cfg.pmu.no_compliance_acknowledged = false;
cfg.pmu.status_timeout_s = 10;      % [s] longest wait for one PMU test to finish
cfg.pmu.poll_interval_s  = 0.005;   % [s]
cfg.pmu.data_chunk       = 2048;    % points per :PMU:DATA:GET

% ------------------------------------------------------------------------
%% Initial-state targeting  (initialize_to_state.m)
% ------------------------------------------------------------------------
% Absolute conductances are unknown until DC cycling runs, so states are
% specified as normalised positions between G_HRS and G_LRS.
cfg.initial_states.normalized      = [0.10 0.30 0.50 0.70 0.90];
cfg.initial_states.spacing         = 'log';  % 'log' | 'linear'
cfg.initial_states.target_conductances = [];  % [S] filled in from DC results
cfg.initial_states.tolerance       = 0.10;   % fractional, |G-Gt|/Gt <= tol
cfg.initial_states.max_iterations  = 60;     % max write-verify pulses
cfg.initial_states.max_polarity_flips = 8;
% Write-verify strategy:
%   'bidirectional'   nudge up with SET, down with RESET (both directions
%                     gradual)
%   'reset_then_set'  rail is the NEGATIVE direction: RESET only dumps to
%                     the floor, every approach is an upward SET climb.
%                     Use when RESET is abrupt and SET is gradual.
%   'set_then_reset'  rail is the POSITIVE direction (abrupt SET)
% Or set cfg.initial_states.rail_polarity (+1/-1/0) directly, which wins.
% Which polarity is the rail is a MEASURED property -- devices differ.
cfg.initial_states.strategy        = 'bidirectional';
cfg.initial_states.rail_polarity   = 0;      % 0 = no rail (bidirectional)
cfg.initial_states.max_reset_dumps = 5;      % rail-pulse budget
% Optional third "rush" tier: while G/target is below rush_threshold, climb
% with rush_amplitude_set instead of the coarse amplitude. Set
% rush_amplitude_set to NaN to disable.
cfg.initial_states.rush_threshold    = 0.2;  % G < 20% of target -> rush
cfg.initial_states.rush_amplitude_set = NaN; % [V] disabled by default
% Keep the write-verify amplitudes OFF the amplitudes you are testing (see
% docs/06_pitfalls.md): otherwise the map measures the initialisation.
cfg.initial_states.coarse_amplitude_set   =  1.3;  % [V] far from target
cfg.initial_states.fine_amplitude_set     =  1.1;  % [V] near target
cfg.initial_states.coarse_amplitude_reset = -1.3;  % [V]
cfg.initial_states.fine_amplitude_reset   = -1.1;  % [V]
cfg.initial_states.coarse_width    = 10e-6;  % [s]
cfg.initial_states.fine_width      = 10e-6;  % [s]
cfg.initial_states.fine_threshold  = 0.30;   % switch to fine when |dG|/Gt < this
% Wait after reaching the target before G_before is read. Post-write
% relaxation is fastest in the first second; >= 1 s keeps it out of dG.
cfg.initial_states.settle_time     = 1.0;    % [s]

% ------------------------------------------------------------------------
%% Test-specific settings
% ------------------------------------------------------------------------
% --- single-pulse map ---------------------------------------------------
cfg.single_pulse.repeats           = 10;   % repeats per condition
cfg.single_pulse.num_states        = 3;    % subset of initial_states used
cfg.single_pulse.amplitudes_subset = 3;    % amplitudes per polarity
cfg.single_pulse.require_initialization = false;  % bin on measured G_before

% --- LTP / LTD ----------------------------------------------------------
cfg.ltp_ltd.num_pulses          = 50;    % pulses per LTP or LTD branch
cfg.ltp_ltd.num_cycles          = 3;     % LTP+LTD cycles per amplitude
cfg.ltp_ltd.set_amplitudes      = [1.0 1.2 1.4];   % weak / medium / strong
cfg.ltp_ltd.reset_amplitudes    = [-1.0 -1.2 -1.4];
cfg.ltp_ltd.width               = 10e-6; % [s]
cfg.ltp_ltd.stop_on_saturation  = true;
cfg.ltp_ltd.saturation_patience = 8;     % pulses with |dG|/G < tol -> saturated
cfg.ltp_ltd.saturation_tol      = 1e-3;  % fractional
cfg.ltp_ltd.require_initialization = false;  % run the train from the real state

% --- read noise ---------------------------------------------------------
cfg.read_noise.num_reads         = 300;
cfg.read_noise.states_normalized = [0.10 0.50 0.90];
cfg.read_noise.require_initialization = false;

% --- short-term relaxation ---------------------------------------------
cfg.relaxation.sample_times      = [0 0.1 0.3 1 3 10 30 100];  % [s]
cfg.relaxation.states_normalized = [0.20 0.50 0.80];
cfg.relaxation.repeats           = 3;
cfg.relaxation.require_initialization = false;

% --- endurance (run_endurance_test) ------------------------------------
cfg.endurance.set_amplitude_V   =  1.2;    % [V]
cfg.endurance.reset_amplitude_V = -1.2;    % [V]
cfg.endurance.width_s           = 10e-6;   % [s]
cfg.endurance.pulses_per_train  = 5;
cfg.endurance.max_cycles        = 100;
cfg.endurance.baseline_cycles   = 5;       % median of these = initial window
cfg.endurance.stop_ratio_min    = 2.0;     % stop when G_set/G_reset < this
cfg.endurance.stop_frac_min     = 0.3;     % ...or < this x the initial ratio
cfg.endurance.report_every      = 10;

% --- retention (run_retention_hold_test) -------------------------------
cfg.retention.states = struct( ...
    'label',       {'SET', 'RESET'}, ...
    'amplitude_V', {1.2, -1.2}, ...
    'width_s',     {10e-6, 10e-6}, ...
    'n_pulses',    {5, 5});
cfg.retention.interval_s     = 10;     % [s] read period
cfg.retention.max_hold_s     = 1800;   % [s] hold ceiling per state
cfg.retention.drift_limit    = 0.50;   % |dG/G0| that ends the hold
cfg.retention.rest_between_s = 30;     % [s] rest at 0 V between states

% ------------------------------------------------------------------------
%% SAFETY  -- read docs/05_safety.md before changing anything here
% ------------------------------------------------------------------------
cfg.safety.max_abs_voltage   = 3.0;    % [V] hard ceiling for ANY output
cfg.safety.max_abs_current   = 1e-2;   % [A] abort if measured |I| exceeds
cfg.safety.min_resistance    = 20;     % [Ohm] suspected hard short below this
cfg.safety.max_resistance    = 1e10;   % [Ohm] suspected open circuit above this
cfg.safety.max_total_pulses  = 20000;  % per run
cfg.safety.max_test_duration = 6*3600; % [s] per run
cfg.safety.max_consecutive_init_failures = 3;
cfg.safety.max_compliance_hits = 50;   % consecutive compliance hits -> abort
% ...but only in these measurement modes. A DC sweep past V_set is SUPPOSED
% to sit in compliance, so 'dc' is deliberately absent: aborting there would
% kill every normal sweep. In 'read' or 'pulse', sustained compliance means
% the device is shorted or the state ran away, and must stop the run.
cfg.safety.compliance_abort_modes = {'read', 'pulse'};

% Contact check performed before any high voltage on a fresh device.
cfg.safety.contact_check.voltage      = 0.05;   % [V]
cfg.safety.contact_check.min_current  = 1e-12;  % [A] below -> open / bad contact
cfg.safety.contact_check.max_current  = 5e-3;   % [A] above -> short / bad landing

% --- MANDATORY CONFIRMATION GATES ------------------------------------------
% Both must be set true BY THE OPERATOR (after reviewing the values above and
% in the device file) before any real-hardware measurement is allowed.
% An agent sets them only after the operator approves the limits in chat.
cfg.safety.compliance_confirmed = false;
cfg.safety.limits_confirmed     = false;

% ------------------------------------------------------------------------
%% Execution mode
% ------------------------------------------------------------------------
cfg.mode.dry_run                  = true;   % no output enabled, commands logged
cfg.mode.simulate_instrument      = true;   % no VISA at all, virtual RRAM
cfg.mode.require_user_confirmation= true;   % pause at safety checkpoints
cfg.mode.verbose                  = true;
cfg.mode.live_plot                = false;  % measurement > plotting
cfg.mode.save_mat                 = true;
cfg.mode.save_csv                 = true;

% ------------------------------------------------------------------------
%% Simulator (used only when cfg.mode.simulate_instrument == true)
% ------------------------------------------------------------------------
% A toy device for exercising code paths. Its numbers are arbitrary and do
% not describe any real device.
cfg.sim.G_hrs        = 1e-5;    % [S] 100 kOhm
cfg.sim.G_lrs        = 1e-3;    % [S] 1 kOhm
cfg.sim.v_set        = 0.8;     % [V] threshold above which SET starts
cfg.sim.v_reset      = -0.8;    % [V]
cfg.sim.alpha        = 2.5;     % voltage nonlinearity exponent
cfg.sim.width_ref    = 10e-6;   % [s] reference pulse width
cfg.sim.sigma_update = 0.15;    % fractional stochastic spread of dG
cfg.sim.sigma_read   = 0.01;    % fractional read noise
cfg.sim.relax_tau    = 20;      % [s] short-term relaxation time constant
cfg.sim.relax_frac   = 0.03;    % fractional drift amplitude
cfg.sim.rng_seed     = 1;

end
