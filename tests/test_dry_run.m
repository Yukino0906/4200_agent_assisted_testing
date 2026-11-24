function ok = test_dry_run()
%TEST_DRY_RUN  Exercise every code path against the virtual device. No hardware.
%
%   ok = TEST_DRY_RUN() runs the kit's measurement suite in simulation with
%   deliberately tiny parameters, and checks that each test:
%
%       - completes without throwing
%       - creates its run directory
%       - writes a non-empty measurement_data.csv
%       - writes metadata.json, metadata.mat, run_summary.txt
%       - returns status 'completed'
%
%   It also verifies the safety machinery itself:
%       - an over-limit voltage is rejected
%       - inverted polarity is rejected
%       - an over-limit compliance is rejected
%       - the confirmation gates block a real run until they are set
%       - emergency_shutdown blocks any subsequent bias
%       - append_measurement_row rejects a changed column set
%
%   RUN THIS AFTER EVERY CODE CHANGE, and always before touching a real
%   device. It takes a few minutes and needs no instrument.
%
%   Inputs: none.
%
%   Outputs:
%       ok - logical, true when every check passed
%
%   Instrument side effects: none. cfg.mode.simulate_instrument is forced true.
%
%   Exceptions: none propagate; failures are counted and reported.
%
%   See also TEST_INSTRUMENT_CONNECTION, DEFAULT_CONFIG, VALIDATE_CONFIG.

fprintf('\n================================================================\n');
fprintf(' DRY RUN / SIMULATION SUITE\n');
fprintf('================================================================\n\n');

passed = 0;
failed = 0;
notes  = {};

    function record(name, success, detail)
        if success
            passed = passed + 1;
            fprintf('  [ PASS ] %s\n', name);
        else
            failed = failed + 1;
            fprintf(2, '  [ FAIL ] %s -- %s\n', name, detail);
            notes{end+1} = sprintf('%s: %s', name, detail);
        end
    end

cfg = local_small_config();

% ======================================================================
fprintf('--- Configuration and safety gates ---\n');

% 1. validate_config accepts the simulated configuration
try
    validate_config(cfg);
    record('validate_config accepts the simulated config', true, '');
catch e
    record('validate_config accepts the simulated config', false, e.message);
end

% 2. the device template is a valid simulated configuration
try
    validate_config(device_TEMPLATE());
    record('device_TEMPLATE validates (simulation)', true, '');
catch e
    record('device_TEMPLATE validates (simulation)', false, e.message);
end

% 3. an over-limit sweep voltage is rejected
try
    bad = cfg; bad.dc.v_positive_max = 10;
    validate_config(bad);
    record('over-limit sweep voltage is rejected', false, 'no error raised');
catch
    record('over-limit sweep voltage is rejected', true, '');
end

% 4. an over-limit endurance amplitude is rejected
try
    bad = cfg; bad.endurance.set_amplitude_V = cfg.safety.max_abs_voltage + 0.5;
    validate_config(bad);
    record('over-limit endurance amplitude is rejected', false, 'no error raised');
catch
    record('over-limit endurance amplitude is rejected', true, '');
end

% 5. inverted polarity is rejected
try
    bad = cfg; bad.pulse.set_amplitudes = [-1 -1.2];
    validate_config(bad);
    record('inverted SET polarity is rejected', false, 'no error raised');
catch
    record('inverted SET polarity is rejected', true, '');
end

% 6. a real run without the confirmation flags is blocked
try
    bad = cfg;
    bad.mode.simulate_instrument   = false;
    bad.safety.compliance_confirmed = false;
    bad.safety.limits_confirmed     = false;
    validate_config(bad);
    record('unconfirmed real run is blocked', false, 'no error raised');
catch e
    record('unconfirmed real run is blocked', ...
        strcmp(e.identifier, 'validate_config:NotConfirmed'), e.identifier);
end

% 7. compliance above the safety limit is rejected
try
    bad = cfg; bad.pulse.compliance = 10 * cfg.safety.max_abs_current;
    validate_config(bad);
    record('over-limit compliance is rejected', false, 'no error raised');
catch
    record('over-limit compliance is rejected', true, '');
end

% 8. check_voltage_limit throws on an unsafe level
try
    check_voltage_limit(cfg.safety.max_abs_voltage + 1, cfg);
    record('check_voltage_limit throws above the ceiling', false, 'no error raised');
catch e
    record('check_voltage_limit throws above the ceiling', ...
        strcmp(e.identifier, 'check_voltage_limit:Exceeded'), e.identifier);
end

% 9. append_measurement_row refuses a changed column set
try
    tmp = [tempname '.csv'];
    append_measurement_row(tmp, struct('a', 1, 'b', 2));
    try
        append_measurement_row(tmp, struct('a', 1, 'c', 3));
        record('CSV column mismatch is rejected', false, 'no error raised');
    catch e2
        record('CSV column mismatch is rejected', ...
            strcmp(e2.identifier, 'append_measurement_row:FieldMismatch'), e2.identifier);
    end
    if exist(tmp, 'file'); delete(tmp); end
catch e
    record('CSV column mismatch is rejected', false, e.message);
end

% ======================================================================
fprintf('\n--- Instrument layer ---\n');

inst = [];
try
    inst = connect_instruments(cfg);
    record('connect (simulated)', inst.Connected && inst.Simulate, 'not connected');

    configure_instruments(inst, cfg, 'read');
    [G, info] = measure_conductance(inst, cfg);
    record('measure_conductance returns a finite value', ...
        isfinite(G) && G > 0 && strcmp(info.status, 'ok'), info.status);

    configure_instruments(inst, cfg, 'pulse');
    pr = apply_voltage_pulse(inst, cfg, 1.4, 10e-6);
    record('apply_voltage_pulse succeeds', strcmp(pr.status, 'ok'), pr.status);
    record('pulse energy is estimated', isfinite(pr.energy_J), 'energy is NaN');

    ir = initialize_to_state(inst, cfg, sqrt(cfg.sim.G_hrs * cfg.sim.G_lrs));
    record('initialize_to_state converges', ir.success, ir.status);

    % emergency shutdown must block any further bias
    emergency_shutdown(inst, 'dry-run self test');
    okRefused = ~set_voltage(inst, cfg, 1.0);
    record('bias is refused after emergency_shutdown', okRefused, 'voltage was applied');

    pr2 = apply_voltage_pulse(inst, cfg, 1.2, 10e-6);
    record('pulse is refused after emergency_shutdown', ...
        strcmp(pr2.status, 'aborted'), pr2.status);

    disconnect_instruments(inst);
    record('disconnect', ~inst.Connected, 'still connected');
catch e
    record('instrument layer', false, sprintf('%s: %s', e.identifier, e.message));
    if ~isempty(inst) && isvalid(inst); disconnect_instruments(inst); end
end

% ======================================================================
fprintf('\n--- KXCI helpers (pure functions) ---\n');

try
    [v, st, ok1] = kxci_parse_reading('NAI+1.234500E-06');
    [v2, st2, ok2] = kxci_parse_reading('-2.5E-03');
    [~, st3]  = kxci_parse_reading('CAI+1.000000E-03');
    [~, ~, ok4] = kxci_parse_reading('ERROR: unrecognised command');
    [~, ~, ok5] = kxci_parse_reading('NAI+9.910000E+37');
    record('kxci_parse_reading handles prefixed, bare, compliance, text, overflow', ...
        ok1 && abs(v - 1.2345e-6) < 1e-12 && strcmp(st, 'N') && ...
        ok2 && v2 == -2.5e-3 && isempty(st2) && strcmp(st3, 'C') && ~ok4 && ~ok5, ...
        'unexpected parse result');
catch e
    record('kxci_parse_reading', false, e.message);
end

try
    d = kxci_parse_pmu_data('0.1,1e-06,1e-06,0;0.2,2e-06,2e-06,0;bad;');
    record('kxci_parse_pmu_data parses points and drops bad ones', ...
        isequal(size(d), [2 4]) && d(2, 2) == 2e-6, mat2str(size(d)));
catch e
    record('kxci_parse_pmu_data', false, e.message);
end

try
    sq = pmu_build_pulse(cfg, 1.2, 10e-6);
    f  = sq.force;
    shapeOk = numel(f.time) == 5 && abs(sq.width_fwhm_s - 10e-6) < 1e-12 && ...
              f.meastype(3) == 1 && f.startv(3) == 1.2 && f.stopv(4) == 0;
    record('pmu_build_pulse gives a 5-segment trapezoid with the requested FWHM', ...
        shapeOk, 'wrong segments');
    try
        pmu_build_pulse(cfg, 1.2, cfg.pmu.rise_time);
        record('pmu_build_pulse refuses a width shorter than its edges', false, 'no error');
    catch e2
        record('pmu_build_pulse refuses a width shorter than its edges', ...
            strcmp(e2.identifier, 'pmu_build_pulse:TooShort'), e2.identifier);
    end
catch e
    record('pmu_build_pulse', false, e.message);
end

try
    t  = (0:0.01:3)' * 1e-6;
    vt = interp1([0 0.5 0.6 2.4 2.5 3] * 1e-6, [0 0 1 1 0 0], t);   % FWHM = 1.9 us
    fw = pulse_fwhm(t, -vt);
    record('pulse_fwhm measures a sampled trapezoid (either polarity)', ...
        abs(fw - 1.9e-6) < 0.02e-6, sprintf('got %.4g s', fw));
catch e
    record('pulse_fwhm', false, e.message);
end

% ======================================================================
fprintf('\n--- PMU configuration gates ---\n');

try
    bad = cfg;
    bad.mode.simulate_instrument   = false;
    bad.safety.compliance_confirmed = true;
    bad.safety.limits_confirmed     = true;
    bad.pmu.no_compliance_acknowledged = false;
    validate_config(bad);
    record('real PMU run without the no-compliance acknowledgement is blocked', false, 'no error');
catch e
    record('real PMU run without the no-compliance acknowledgement is blocked', ...
        strcmp(e.identifier, 'validate_config:NotConfirmed'), e.identifier);
end
try
    bad = cfg; bad.pmu.max_current_A = bad.pmu.current_range_A;
    validate_config(bad);
    record('PMU current limit at the range ceiling is rejected', false, 'no error');
catch
    record('PMU current limit at the range ceiling is rejected', true, '');
end
try
    bad = cfg; bad.pulse.timing_source = 'pc';
    validate_config(bad);
    record('host-timed pulses with microsecond widths are rejected', false, 'no error');
catch
    record('host-timed pulses with microsecond widths are rejected', true, '');
end
try
    bad = cfg; bad.pmu.sense_channel = 2;     % return_path left at 'gndu'
    validate_config(bad);
    record('sense channel without the matching return path is rejected', false, 'no error');
catch
    record('sense channel without the matching return path is rejected', true, '');
end

% ======================================================================
fprintf('\n--- KXCI command layer through the mock 4200A ---\n');

for wiring = {'gndu', 'pmu_sense'}
    cfgM = local_mock_config(cfg, wiring{1});
    tag  = sprintf('[%s] ', wiring{1});
    inst = [];
    try
        inst = connect_instruments(cfgM);
        mock = inst.Dev;
        record([tag 'connect through the mock'], inst.Connected && ~inst.Simulate && ...
            isa(mock, 'KxciMock'), 'not connected to the mock');

        configure_instruments(inst, cfgM, 'read');
        [G1, i1] = measure_conductance(inst, cfgM);
        record([tag 'read through RPM (SMU path)'], isfinite(G1) && G1 > 0, i1.status);

        configure_instruments(inst, cfgM, 'pulse');
        pr = apply_voltage_pulse(inst, cfgM, 1.4, 10e-6);
        record([tag 'PMU pulse executes and returns V and I'], ...
            strcmp(pr.status, 'ok') && isfinite(pr.v_measured_V) && ...
            pr.peak_current_A > 0 && strcmp(pr.width_basis, 'pmu_programmed_fwhm'), ...
            sprintf('%s, V=%g, I=%g', pr.status, pr.v_measured_V, pr.peak_current_A));
        record([tag 'measured pulse voltage is below the programmed one (50 Ohm)'], ...
            pr.v_measured_V > 0 && pr.v_measured_V < 1.4, sprintf('V=%g', pr.v_measured_V));

        pw = apply_voltage_pulse(inst, cfgM, cfgM.read.voltage, 2e-6, ...
            struct('capture', 'waveform'));
        record([tag 'waveform capture recovers the programmed FWHM'], ...
            strcmp(pw.status, 'ok') && abs(pw.width_measured_s - 2e-6) < 0.05 * 2e-6, ...
            sprintf('%s, %.4g s', pw.status, pw.width_measured_s));

        configure_instruments(inst, cfgM, 'read');
        [G2, i2] = measure_conductance(inst, cfgM);
        record([tag 'read after the pulse sees the SET'], isfinite(G2) && G2 > G1, ...
            sprintf('%s, G %.4g -> %.4g S', i2.status, G1, G2));

        r1 = run_ltp_ltd_test(local_tiny(cfgM), inst);
        record([tag 'run_ltp_ltd_test through the mock'], ...
            isempty(local_check_result(r1)), strjoin(local_check_result(r1), '; '));
        r2 = run_dc_cycle_test(local_tiny(cfgM), inst);
        record([tag 'run_dc_cycle_test through the mock'], ...
            isempty(local_check_result(r2)), strjoin(local_check_result(r2), '; '));

        record([tag 'no order or safety violation seen by the mock'], ...
            isempty(mock.Violations), strjoin(mock.Violations, ' | '));
        record([tag 'every command was accepted'], mock.Errors == 0, ...
            sprintf('%d rejected', mock.Errors));
        record([tag 'no reply left unread'], isempty(mock.Replies), ...
            sprintf('%d stale', numel(mock.Replies)));

        emergency_shutdown(inst, 'mock self test');
        record([tag 'emergency_shutdown turns every output off'], ...
            ~mock.SmuOn && ~any(mock.OutputState), 'an output is still on');
        record([tag 'emergency_shutdown leaves no unread reply'], isempty(mock.Replies), ...
            sprintf('%d stale', numel(mock.Replies)));
        disconnect_instruments(inst);
    catch e
        record([tag 'mock transport'], false, sprintf('%s: %s', e.identifier, e.message));
        if ~isempty(inst) && isvalid(inst); disconnect_instruments(inst); end
    end
end

% ======================================================================
fprintf('\n--- Measurement suite (simulated, tiny parameters) ---\n');

tests = { ...
    'run_dc_cycle_test',        @run_dc_cycle_test; ...
    'run_single_pulse_map',     @run_single_pulse_map; ...
    'run_ltp_ltd_test',         @run_ltp_ltd_test; ...
    'run_read_noise_test',      @run_read_noise_test; ...
    'run_relaxation_test',      @run_relaxation_test; ...
    'run_endurance_test',       @run_endurance_test; ...
    'run_retention_hold_test',  @run_retention_hold_test; ...
    'example_custom_test_skeleton', @example_custom_test_skeleton};

dcResult = [];
for i = 1:size(tests, 1)
    name = tests{i, 1};
    fn   = tests{i, 2};
    fprintf('\n  running %s ...\n', name);
    try
        res = fn(cfg);
        problems = local_check_result(res);
        record(name, isempty(problems), strjoin(problems, '; '));
        if strcmp(name, 'run_dc_cycle_test'); dcResult = res; end
    catch e
        record(name, false, sprintf('%s: %s', e.identifier, e.message));
    end
end

% ======================================================================
fprintf('\n--- Switching-threshold extraction (hysteresis closure) ---\n');

% The threshold fields and the definition note must survive every change:
% numbers without their definition are worse than no numbers.
try
    need = {'V_set_complete_V', 'V_reset_complete_V', 'set_r_max', 'reset_r_max', ...
            'set_confidence', 'reset_confidence', 'set_manual_review', ...
            'reset_manual_review', 'set_failure_reason', 'reset_failure_reason'};
    % Read the header line directly: readtable's type detection can mistake
    % the header for data when every threshold column is empty.
    csv   = fullfile(dcResult.run_dir, 'cycle_summary.csv');
    lines = readlines(csv);
    lines = lines(strlength(strtrim(lines)) > 0);
    hdr   = cellstr(strtrim(split(lines(1), ',')));
    miss  = setdiff(need, hdr);
    record('cycle_summary.csv has all threshold columns', isempty(miss), ...
        strjoin(miss, ', '));

    nRows = numel(lines) - 1;
    ok3 = nRows == cfg.dc.num_cycles;
    record('cycle_summary.csv has one row per cycle', ok3, ...
        sprintf('%d rows for %d cycles', nRows, cfg.dc.num_cycles));

    s = dcResult.summary;
    record('summary carries the threshold definition', ...
        isfield(s, 'threshold_definition') && ...
        contains(s.threshold_definition, 'COMPLETION'), 'definition missing');

    m = jsondecode(fileread(fullfile(dcResult.run_dir, 'metadata.json')));
    record('metadata carries the threshold definition', ...
        isfield(m.key_parameters, 'switching_threshold_definition') && ...
        contains(m.key_parameters.switching_threshold_definition, 'SYSTEMATICALLY HIGHER'), ...
        'metadata definition missing');
catch e
    record('threshold extraction outputs', false, sprintf('%s: %s', e.identifier, e.message));
end

% Polarity is not negotiable: V_set > 0, V_reset < 0, or NaN.
try
    v = [dcResult.cycles.V_set_complete_V];
    w = [dcResult.cycles.V_reset_complete_V];
    record('V_set is positive or NaN',  all(isnan(v) | v > 0), mat2str(v, 4));
    record('V_reset is negative or NaN', all(isnan(w) | w < 0), mat2str(w, 4));
    r = [dcResult.cycles.set_r_max, dcResult.cycles.reset_r_max];
    r = r(isfinite(r));
    record('r_max >= 1 by construction', isempty(r) || all(r >= 1), mat2str(r, 4));
catch e
    record('threshold polarity', false, sprintf('%s: %s', e.identifier, e.message));
end

% A sweep that never reaches the switching threshold must refuse to invent
% one: NaN plus a manual-review flag plus a stated reason.
try
    flat = cfg;
    flat.device.device_id  = 'DRYRUN_NOSWITCH';
    flat.dc.v_positive_max =  0.6;   % below the simulated 0.8 V threshold
    flat.dc.v_negative_max = -0.6;
    flat.dc.num_cycles     = 1;
    fr  = run_dc_cycle_test(flat);
    fc  = fr.cycles(1);
    good = isnan(fc.V_set_complete_V) && fc.set_manual_review && ...
           ~isempty(fc.set_failure_reason);
    record('no-switching sweep returns NaN + manual review', good, ...
        sprintf('V_set=%g review=%d reason="%s"', ...
                fc.V_set_complete_V, fc.set_manual_review, fc.set_failure_reason));
catch e
    record('no-switching sweep', false, sprintf('%s: %s', e.identifier, e.message));
end

% ======================================================================
fprintf('\n================================================================\n');
fprintf(' DRY RUN SUMMARY: %d passed, %d failed\n', passed, failed);
if failed > 0
    fprintf(2, '\n Failures:\n');
    for i = 1:numel(notes)
        fprintf(2, '   - %s\n', notes{i});
    end
    fprintf(2, '\n DO NOT run on real hardware until these are fixed.\n');
else
    fprintf(' All checks passed. The framework is ready for a hardware trial.\n');
    fprintf(' Next: tests\\test_instrument_connection.m\n');
end
fprintf('================================================================\n\n');

ok = (failed == 0);
if nargout == 0
    clear ok;
end
end

% ========================================================================
function problems = local_check_result(res)
problems = {};
if ~isstruct(res)
    problems{end+1} = 'result is not a struct';
    return;
end
if ~isfield(res, 'status') || ~strcmp(res.status, 'completed')
    problems{end+1} = sprintf('status = %s', local_get(res, 'status', '<missing>'));
end
if ~isfield(res, 'run_dir') || exist(res.run_dir, 'dir') ~= 7
    problems{end+1} = 'run directory missing';
    return;
end
csv = fullfile(res.run_dir, 'measurement_data.csv');
if exist(csv, 'file') ~= 2
    problems{end+1} = 'measurement_data.csv missing';
elseif ~isfield(res, 'n_rows') || ~(res.n_rows > 0)
    problems{end+1} = 'measurement_data.csv is empty';
end
for f = {'metadata.json', 'metadata.mat', 'run_summary.txt', 'config_snapshot.mat'}
    if exist(fullfile(res.run_dir, f{1}), 'file') ~= 2
        problems{end+1} = sprintf('%s missing', f{1}); %#ok<AGROW>
    end
end
end

function v = local_get(s, name, default)
if isstruct(s) && isfield(s, name); v = s.(name); else; v = default; end
end

% ========================================================================
function cfg = local_small_config()
%LOCAL_SMALL_CONFIG  Simulated config sized so the whole suite runs in minutes.
cfg = default_config();

cfg.device.device_id = 'DRYRUN';
cfg.device.notes     = 'automated dry-run self test';

cfg.mode.simulate_instrument       = true;
cfg.mode.dry_run                   = true;
cfg.mode.require_user_confirmation = false;
cfg.mode.verbose                   = false;

cfg.safety.compliance_confirmed = true;   % simulated: no device at risk
cfg.safety.limits_confirmed     = true;
cfg.safety.max_test_duration    = 1800;
cfg.safety.max_total_pulses     = 100000;

% --- shrink everything ---
cfg.dc.v_step        = 0.05;
cfg.dc.delay         = 0;
cfg.dc.num_cycles    = 2;
cfg.dc.use_instrument_sweep = false;   % simulation always uses the host loop

cfg.read.settle_time       = 0;
cfg.read.delay_after_write = 0.01;
cfg.read.num_average_reads = 3;

cfg.pulse.widths            = [10e-6 30e-6];
cfg.pulse.inter_pulse_delay = 0;
cfg.pulse.set_amplitudes    = [1.0 1.4];
cfg.pulse.reset_amplitudes  = [-1.0 -1.4];

cfg.initial_states.normalized     = [0.10 0.50 0.90];
cfg.initial_states.max_iterations = 30;
cfg.initial_states.settle_time    = 0;
cfg.initial_states.tolerance      = 0.15;

cfg.single_pulse.repeats           = 2;
cfg.single_pulse.num_states        = 2;
cfg.single_pulse.amplitudes_subset = 2;

cfg.ltp_ltd.num_pulses       = 6;
cfg.ltp_ltd.num_cycles       = 1;
cfg.ltp_ltd.set_amplitudes   = 1.2;
cfg.ltp_ltd.reset_amplitudes = -1.2;

cfg.read_noise.num_reads         = 15;
cfg.read_noise.states_normalized = [0.10 0.90];

cfg.relaxation.sample_times      = [0 0.05 0.2 0.5];
cfg.relaxation.states_normalized = [0.30 0.70];
cfg.relaxation.repeats           = 1;

cfg.endurance.max_cycles       = 8;
cfg.endurance.baseline_cycles  = 3;
cfg.endurance.pulses_per_train = 3;
cfg.endurance.stop_ratio_min   = 1.01;   % the toy device must not end the run early

cfg.retention.interval_s     = 0.05;
cfg.retention.max_hold_s     = 0.3;
cfg.retention.rest_between_s = 0;
cfg.retention.drift_limit    = 10;       % run to max_hold_s
[cfg.retention.states.n_pulses] = deal(2);

cfg.sequence.amplitudes_V = [1.0 1.2 -1.0 -1.2];
cfg.sequence.widths_s     = 10e-6;
cfg.sequence.label        = 'dryrun';
end

% ========================================================================
function cfgM = local_mock_config(cfg, wiring)
%LOCAL_MOCK_CONFIG  Same tiny settings, but every command goes through KxciMock.
cfgM = cfg;
cfgM.device.device_id           = ['DRYRUN_MOCK_' upper(wiring)];
cfgM.mode.simulate_instrument   = false;
cfgM.mode.dry_run               = false;
cfgM.instrument.transport       = 'mock';
cfgM.instrument.rpm_settle_s    = 0;
cfgM.instrument.return_path     = wiring;
cfgM.device.G_hrs_S             = cfg.sim.G_hrs;   % the mock's virtual device
cfgM.device.G_lrs_S             = cfg.sim.G_lrs;
if strcmp(wiring, 'pmu_sense')
    cfgM.pmu.sense_channel = 2;
else
    cfgM.pmu.sense_channel = 0;
end
end

function c = local_tiny(c)
%LOCAL_TINY  Shrink a run further for the slower mock round-trips.
c.dc.num_cycles          = 1;
c.dc.v_step              = 0.1;
c.ltp_ltd.num_pulses     = 4;
c.ltp_ltd.num_cycles     = 1;
end
