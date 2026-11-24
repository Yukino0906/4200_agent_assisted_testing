function result = example_custom_test_skeleton(cfg, inst)
%EXAMPLE_CUSTOM_TEST_SKELETON  Template for a NEW test: arbitrary pulse sequence, read after each.
%
%   COPY THIS FILE to src/measurement/run_<name>_test.m when no existing test
%   fits a request, rename the function, and change only the parts marked
%   "TEST-SPECIFIC". Everything else is the safety skeleton every test in the
%   kit shares; do not remove any of it.
%
%   As shipped it is a usable test in its own right: it applies the pulses
%   listed in cfg.sequence one by one and reads G after each, e.g. a
%   staircase, an alternating SET/RESET pattern, or an increasing-width
%   series.
%
%   result = EXAMPLE_CUSTOM_TEST_SKELETON()          simulator, demo sequence
%   result = EXAMPLE_CUSTOM_TEST_SKELETON(cfg)       your config
%   result = EXAMPLE_CUSTOM_TEST_SKELETON(cfg, inst) reuse an open session
%
%   cfg.sequence fields (TEST-SPECIFIC):
%       amplitudes_V  [V] row vector, one entry per pulse (+ = SET, - = RESET)
%       widths_s      [s] scalar, or one entry per pulse
%       label             char, written into every row
%
%   CSV columns: device_id, run_id, label, step_index, timestamp_s,
%       pulse_voltage_V, pulse_width_s, pulse_width_measured_s, compliance_A,
%       peak_current_A, compliance_hit, read_voltage_V, G_before_S, G_after_S,
%       delta_G_S, instrument_status
%
%   Instrument side effects: applies every pulse in the sequence. Returns to
%   0 V with the output off.
%
%   See also BEGIN_MEASUREMENT, FINISH_MEASUREMENT, APPLY_VOLTAGE_PULSE,
%   MEASURE_CONDUCTANCE, APPEND_MEASUREMENT_ROW.

narginchk(0, 2);
if nargin < 2; inst = []; end
if nargin < 1 || isempty(cfg)
    % TEST-SPECIFIC: demo sequence for the simulator.
    cfg = sim_config('pulse_sequence');
    cfg.sequence.amplitudes_V = [1.0 1.1 1.2 1.3 -1.0 -1.1 -1.2 -1.3];
    cfg.sequence.widths_s     = 10e-6;
    cfg.sequence.label        = 'staircase';
end

% ---- TEST-SPECIFIC: read and check the parameters BEFORE connecting ------
seq    = cfg.sequence;
amps   = seq.amplitudes_V(:).';
widths = seq.widths_s(:).';
if isscalar(widths); widths = repmat(widths, size(amps)); end
if numel(widths) ~= numel(amps) || any(~isfinite(widths)) || any(widths <= 0)
    error('example_custom_test_skeleton:BadSequence', ...
        'cfg.sequence.widths_s must be a positive scalar or match amplitudes_V.');
end
% Refuse the whole run up front if any step is outside the envelope, rather
% than failing halfway through the sequence.
check_voltage_limit(amps, cfg);

% ---- SKELETON: validate, run directory, connect, output-off guard --------
% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off.
[run, inst, guard] = begin_measurement(cfg, 'pulse_sequence_test', inst); %#ok<ASGLU>

result = struct('steps', struct([]), 'summary', struct());
status = 'completed';
reason = '';

try
    % ---- SKELETON: checkpoint with every number the operator must see ----
    ok = confirm_step(cfg, 'Pulse sequence', { ...
        sprintf('device_id  : %s', cfg.device.device_id), ...
        sprintf('pulses     : %d  [%s] V', numel(amps), num2str(amps, '%+.2f ')), ...
        sprintf('widths     : [%s] s', num2str(unique(widths), '%.3g ')), ...
        sprintf('compliance : %.4g A', cfg.pulse.compliance), ...
        sprintf('read       : %+.3f V after every pulse', cfg.read.voltage)});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', ...
            'operator declined the checkpoint');
        return;
    end

    % ---- TEST-SPECIFIC: the measurement loop ------------------------------
    t0 = tic;
    configure_instruments(inst, cfg, 'read');
    Gbefore = measure_conductance(inst, cfg);
    steps = struct([]);
    for k = 1:numel(amps)
        if inst.Aborted; break; end

        configure_instruments(inst, cfg, 'pulse');
        pr = apply_voltage_pulse(inst, cfg, amps(k), widths(k), ...
            struct('label', sprintf('%s:%d', seq.label, k), 'g_before_S', Gbefore));

        if cfg.read.delay_after_write > 0
            pause(cfg.read.delay_after_write);
        end
        configure_instruments(inst, cfg, 'read');
        [Gafter, rinfo] = measure_conductance(inst, cfg);

        % One row per step, written immediately: a crash loses nothing.
        row = struct( ...
            'device_id',              cfg.device.device_id, ...
            'run_id',                 run.run_id, ...
            'label',                  seq.label, ...
            'step_index',             k, ...
            'timestamp_s',            toc(t0), ...
            'pulse_voltage_V',        amps(k), ...
            'pulse_width_s',          widths(k), ...
            'pulse_width_measured_s', pr.width_measured_s, ...
            'compliance_A',           cfg.pulse.compliance, ...
            'peak_current_A',         pr.peak_current_A, ...
            'compliance_hit',         pr.compliance_hit, ...
            'read_voltage_V',         rinfo.read_voltage_V, ...
            'G_before_S',             Gbefore, ...
            'G_after_S',              Gafter, ...
            'delta_G_S',              Gafter - Gbefore, ...
            'instrument_status',      pr.status);
        append_measurement_row(run.data_csv, row);

        s = struct('step_index', k, 'G_before_S', Gbefore, 'G_after_S', Gafter);
        if isempty(steps); steps = s; else; steps(end+1) = s; end %#ok<AGROW>
        Gbefore = Gafter;

        % Stop on a safety status; never continue past one.
        if any(strcmp(pr.status, {'aborted', 'limit_exceeded'}))
            break;
        end
    end
    result.steps   = steps;
    result.summary = struct('n_steps', numel(steps), 'pulses_applied', inst.PulseCount);

catch err
    % ---- SKELETON: any error -> output off, record, rethrow ---------------
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'pulse_sequence_test failed: %s', reason);
    emergency_shutdown(inst, reason);
    finish_measurement(run, cfg, inst, result, 'failed', reason);
    rethrow(err);
end

% ---- SKELETON: final status, metadata, summary ---------------------------
if inst.Aborted && strcmp(status, 'completed')
    status = 'aborted';
    reason = inst.LastError;
end
result = finish_measurement(run, cfg, inst, result, status, reason);
end
