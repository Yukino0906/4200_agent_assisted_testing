function result = run_retention_hold_test(cfg, inst)
%RUN_RETENTION_HOLD_TEST  Long retention: write a state, read every dt until drift > limit.
%
%   result = RUN_RETENTION_HOLD_TEST(cfg) for each entry of cfg.retention.states:
%       1. apply the state's write train (n identical pulses, amplitude V, width w)
%       2. read G at cfg.read.voltage every cfg.retention.interval_s
%       3. stop when |G - G0| / G0 > cfg.retention.drift_limit or the
%          elapsed time exceeds cfg.retention.max_hold_s
%   G0 is the first read after the train (settled by cfg.read.delay_after_write).
%   The device rests at 0 V (output on, no bias) between reads.
%
%   cfg.retention fields (defaults in config/default_config.m):
%       states       struct array: .label ('SET'|'RESET'), .amplitude_V, .width_s, .n_pulses
%       interval_s   read period [s]
%       max_hold_s   hold ceiling per state [s]
%       drift_limit  |dG/G0| that ends the hold
%       rest_between_s  rest at 0 V between states [s]
%
%   CSV columns: device_id, run_id, state_label, state_index, sample_index,
%       scheduled_time_s, actual_time_s, read_voltage_V, current_A, conductance_S,
%       G0_S, relative_drift, stop_reason, instrument_status
%
%   Outputs: result.states (per state: label, G0_S, hold_time_s, n_reads,
%            final_drift, stop_reason) and result.summary.
%
%   See also RUN_RELAXATION_TEST, MEASURE_CONDUCTANCE, APPLY_VOLTAGE_PULSE.

narginchk(1, 2);
if nargin < 2; inst = []; end
p = local_defaults(cfg);

[run, inst, guard] = begin_measurement(cfg, 'retention_hold_test', inst); %#ok<ASGLU>
result = struct('states', struct([]), 'summary', struct());
status = 'completed'; reason = '';

try
    ok = confirm_step(cfg, 'Retention hold (write, then read until drift limit)', { ...
        sprintf('device_id  : %s', cfg.device.device_id), ...
        sprintf('states     : %s', strjoin(arrayfun(@(s) sprintf('%s %d x %+.2f V/%.3g s', s.label, s.n_pulses, s.amplitude_V, s.width_s), p.states, 'UniformOutput', false), '; ')), ...
        sprintf('read       : %.3f V every %.1f s, up to %.0f s, stop at |dG/G0| > %.0f %%', cfg.read.voltage, p.interval_s, p.max_hold_s, 100 * p.drift_limit)});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', 'operator declined');
        return;
    end

    states = struct([]);
    for si = 1:numel(p.states)
        if inst.Aborted; break; end
        st = p.states(si);
        fprintf('\n  state %d/%d (%s): %d x %+.2f V / %.3g s, then hold\n', si, numel(p.states), st.label, st.n_pulses, st.amplitude_V, st.width_s);
        configure_instruments(inst, cfg, 'pulse');
        for k = 1:st.n_pulses
            apply_voltage_pulse(inst, cfg, st.amplitude_V, st.width_s, struct('label', sprintf('%s:write%d', st.label, k)));
        end
        if cfg.read.delay_after_write > 0; pause(cfg.read.delay_after_write); end
        configure_instruments(inst, cfg, 'read');
        t0 = tic;
        [G0, info0] = measure_conductance(inst, cfg);
        nRead = 0;
        k = 0; G = G0; info = info0;
        while true
            k = k + 1;
            tAct = toc(t0);
            if k > 1
                [G, info] = measure_conductance(inst, cfg);
                tAct = toc(t0);
            end
            if isfinite(G0) && G0 > 0 && isfinite(G)
                drift = (G - G0) / G0;
            else
                drift = NaN;
            end
            nRead = nRead + 1;
            if ~isfinite(G) || G <= 0
                stopReason = 'read_invalid';
            elseif abs(drift) > p.drift_limit
                stopReason = 'drift_limit';
            elseif tAct >= p.max_hold_s
                stopReason = 'max_hold';
            elseif inst.Aborted
                stopReason = 'aborted';
            else
                stopReason = '';
            end
            row = struct('device_id', cfg.device.device_id, 'run_id', run.run_id, ...
                'state_label', st.label, 'state_index', si, 'sample_index', k, ...
                'scheduled_time_s', (k - 1) * p.interval_s, 'actual_time_s', tAct, ...
                'read_voltage_V', info.read_voltage_V, 'current_A', info.current_A, ...
                'conductance_S', G, 'G0_S', G0, 'relative_drift', drift, ...
                'stop_reason', stopReason, 'instrument_status', info.status);
            append_measurement_row(run.data_csv, row);
            if mod(k, 12) == 1
                fprintf('    t = %7.1f s  G = %.4g S  drift %+.1f%%\n', tAct, G, 100 * drift);
            end
            if ~isempty(stopReason); break; end
            pause(max(0, (k * p.interval_s) - toc(t0)));
        end
        s = struct('label', st.label, 'G0_S', G0, 'hold_time_s', toc(t0), 'n_reads', nRead, ...
            'final_drift', drift, 'stop_reason', stopReason);
        if isempty(states); states = s; else; states(end + 1) = s; end %#ok<AGROW>
        fprintf('    -> %s: held %.0f s, %d reads, final drift %+.1f%% (%s)\n', st.label, s.hold_time_s, nRead, 100 * drift, stopReason);
        if si < numel(p.states) && p.rest_between_s > 0
            pause(p.rest_between_s);
        end
    end
    result.states = states;
    result.summary = struct('n_states', numel(states), ...
        'hold_times_s', [states.hold_time_s], 'final_drifts', [states.final_drift]);
catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_retention_hold_test failed: %s', reason);
    emergency_shutdown(inst, reason);
    finish_measurement(run, cfg, inst, result, 'failed', reason);
    rethrow(err);
end
if inst.Aborted && strcmp(status, 'completed'); status = 'aborted'; reason = inst.LastError; end
result = finish_measurement(run, cfg, inst, result, status, reason);
end

function p = local_defaults(cfg)
% Fallbacks only; config/default_config.m defines cfg.retention in full.
p = struct('interval_s', 10, 'max_hold_s', 1800, 'drift_limit', 0.50, 'rest_between_s', 30);
p.states = struct('label', {'SET', 'RESET'}, 'amplitude_V', {1.2, -1.2}, 'width_s', {10e-3, 10e-3}, 'n_pulses', {5, 5});
if isfield(cfg, 'retention') && isstruct(cfg.retention)
    f = fieldnames(cfg.retention);
    for i = 1:numel(f); p.(f{i}) = cfg.retention.(f{i}); end
end
end
