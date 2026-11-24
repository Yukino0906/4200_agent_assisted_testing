function result = run_relaxation_test(cfg, inst)
%RUN_RELAXATION_TEST  Short-term conductance drift after a successful write.
%
%   result = RUN_RELAXATION_TEST(cfg) writes the device to a target state,
%   then reads it at logarithmically spaced times
%
%       cfg.relaxation.sample_times = [0 10ms 100ms 1s 10s 100s 1000s]
%
%   and records G(t) relative to G(0). The 0 s entry means "as early as
%   possible", i.e. immediately after the verify read completes; the actual
%   elapsed time of every read is recorded, because the achievable first
%   sample is limited by the read duration, not by the schedule.
%
%   Why this matters more than long-term retention: adaptive programming
%   verifies a state and then moves on. If the state has already left the
%   target window a few hundred milliseconds later, the verification was
%   meaningless. This test measures exactly that window.
%
%   Read economy: each read is itself a small disturbance, so the schedule is
%   logarithmic and no extra reads are inserted between the scheduled ones.
%   Compare the outcome with RUN_READ_NOISE_TEST (repeated reads with no
%   write) to separate relaxation from read-induced drift.
%
%   Inputs:
%       cfg  - configuration struct (cfg.relaxation.*)
%       inst - optional InstrumentSession
%
%   Outputs:
%       result - struct with .status, .run_id, .run_dir, .traces and .summary:
%                   .n_traces, .n_states
%                   .mean_drift_at_1s, .mean_drift_at_100s, .mean_drift_final
%                   .worst_drift_fraction
%                   .fraction_leaving_tolerance   traces that left the
%                                                 initialisation window
%
%   CSV columns:
%       device_id, run_id, state_index, target_conductance_S, repeat_id,
%       sample_index, scheduled_time_s, actual_time_s, read_voltage_V,
%       measured_current_A, conductance_S, resistance_Ohm, G_zero_S,
%       relative_drift, within_tolerance, instrument_status
%
%   Instrument side effects: initialisation pulses plus periodic reads. A
%   full schedule reaching 1000 s takes ~17 minutes PER trace; budget the
%   time or trim cfg.relaxation.sample_times.
%
%   Exceptions: propagates configuration errors.
%
%   See also RUN_READ_NOISE_TEST, RUN_RETENTION_HOLD_TEST, INITIALIZE_TO_STATE.

narginchk(1, 2);
if nargin < 2; inst = []; end

% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
[run, inst, guard] = begin_measurement(cfg, 'relaxation_test', inst); %#ok<ASGLU>

result = struct('traces', struct([]), 'summary', struct());
status = 'completed';
reason = '';

try
    [G_hrs, G_lrs, src] = get_conductance_window(cfg);
    if strcmp(src, 'placeholder') && ~inst.Simulate
        error('run_relaxation_test:NoWindow', ...
            'Run run_dc_cycle_test first, or set cfg.device.G_hrs_S / G_lrs_S.');
    end
    targets  = resolve_state_targets(cfg, G_hrs, G_lrs, cfg.relaxation.states_normalized);
    times    = cfg.relaxation.sample_times;
    repeats  = cfg.relaxation.repeats;
    perTrace = max(times);
    total    = perTrace * numel(targets) * repeats;

    ok = confirm_step(cfg, 'Short-term relaxation characterisation', { ...
        sprintf('device_id   : %s', cfg.device.device_id), ...
        sprintf('states      : [%s] S', strjoin(arrayfun(@(x) sprintf('%.3g', x), ...
                targets, 'UniformOutput', false), ' ')), ...
        sprintf('sample times: [%s] s', num2str(times, '%.4g ')), ...
        sprintf('repeats     : %d per state', repeats), ...
        sprintf('time budget : ~%.0f s per trace, ~%.0f s (%.1f h) total', ...
                perTrace, total, total/3600), ...
        sprintf('safety limit: cfg.safety.max_test_duration = %.0f s', ...
                cfg.safety.max_test_duration)});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', ...
            'operator declined the relaxation checkpoint');
        return;
    end

    if total > cfg.safety.max_test_duration
        log_message(run, 'WARN', ...
            ['Estimated duration %.0f s exceeds cfg.safety.max_test_duration = %.0f s. ' ...
             'The run will stop when the limit is reached.'], ...
            total, cfg.safety.max_test_duration);
    end

    traces = struct([]);

    for si = 1:numel(targets)
        target = targets(si);
        for rep = 1:repeats
            if inst.Aborted; break; end
            fprintf('\n  state %d/%d (%.4g S), repeat %d/%d -- up to %.0f s\n', ...
                si, numel(targets), target, rep, repeats, perTrace);

            initRes = initialize_to_state(inst, cfg, target, struct('verbose', false));
            if ~initRes.success
                % G(t)/G(0) is referenced to the FIRST read of the trace, not
                % to the nominal target, so a trace from a slightly different
                % starting state is still a valid relaxation measurement.
                if local_require_init(cfg, 'relaxation')
                    log_message(run, 'WARN', ...
                        'State %d repeat %d: initialisation failed (%s); skipping.', ...
                        si, rep, initRes.status);
                    continue;
                end
                log_message(run, 'WARN', ...
                    ['State %d repeat %d: initialisation missed the target (%s); ' ...
                     'tracing relaxation from the state reached (G = %.4g S).'], ...
                    si, rep, initRes.status, initRes.G_final_S);
            end

            tr = local_trace(inst, cfg, run, si, target, rep, times, initRes);
            if isempty(traces); traces = tr; else; traces(end+1) = tr; end %#ok<AGROW>
        end
        if inst.Aborted; break; end
    end

    result.traces  = traces;
    result.summary = local_summarize(traces, cfg);

catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_relaxation_test failed: %s', reason);
    emergency_shutdown(inst, reason);
    finish_measurement(run, cfg, inst, result, 'failed', reason);
    rethrow(err);
end

if inst.Aborted && strcmp(status, 'completed')
    status = 'aborted';
    reason = inst.LastError;
end
result = finish_measurement(run, cfg, inst, result, status, reason);
end

% ========================================================================
function tr = local_trace(inst, cfg, run, si, target, rep, times, initRes)
%LOCAL_TRACE  One relaxation trace: read at the scheduled times after a write.
tr = struct('state_index', si, 'target_conductance_S', target, 'repeat_id', rep, ...
    'times_s', [], 'G_S', [], 'relative_drift', [], 'G_zero_S', NaN, ...
    'first_sample_time_s', NaN, 'left_tolerance', false, ...
    'init_pulse_count', initRes.pulse_count);

configure_instruments(inst, cfg, 'read');

t0 = tic;                       % clock starts the instant the write finished
G0 = NaN;
tAct = nan(1, numel(times));
G    = nan(1, numel(times));
drift = nan(1, numel(times));
tolerance = cfg.initial_states.tolerance;

for k = 1:numel(times)
    if inst.Aborted; break; end

    % Wait until the scheduled instant (the first sample is taken at once).
    target_t = times(k);
    while toc(t0) < target_t
        remaining = target_t - toc(t0);
        pause(min(remaining, 0.5));
        if inst.Aborted; break; end
        if inst.elapsed() > cfg.safety.max_test_duration
            emergency_shutdown(inst, ...
                'relaxation trace exceeded cfg.safety.max_test_duration');
            break;
        end
    end
    if inst.Aborted; break; end

    tAct(k) = toc(t0);
    [Gk, info] = measure_conductance(inst, cfg);
    G(k) = Gk;

    if k == 1
        G0 = Gk;
        tr.first_sample_time_s = tAct(k);
    end
    if isfinite(G0) && G0 ~= 0
        drift(k) = (Gk - G0) / G0;
    end

    within = isfinite(drift(k)) && abs(drift(k)) <= tolerance;
    if ~within && isfinite(drift(k))
        tr.left_tolerance = true;
    end

    row = struct( ...
        'device_id',            cfg.device.device_id, ...
        'run_id',               run.run_id, ...
        'state_index',          si, ...
        'target_conductance_S', target, ...
        'repeat_id',            rep, ...
        'sample_index',         k, ...
        'scheduled_time_s',     times(k), ...
        'actual_time_s',        tAct(k), ...
        'read_voltage_V',       info.read_voltage_V, ...
        'measured_current_A',   info.current_A, ...
        'conductance_S',        Gk, ...
        'resistance_Ohm',       info.resistance_Ohm, ...
        'G_zero_S',             G0, ...
        'relative_drift',       drift(k), ...
        'within_tolerance',     within, ...
        'instrument_status',    info.status);
    append_measurement_row(run.data_csv, row);

    fprintf('    t = %8.3f s (scheduled %8.4g): G = %.5g S, drift %+.2f%%\n', ...
        tAct(k), times(k), Gk, 100*drift(k));
end

tr.times_s        = tAct;
tr.G_S            = G;
tr.relative_drift = drift;
tr.G_zero_S       = G0;
end

% ========================================================================
function s = local_summarize(traces, cfg)
s = struct('n_traces', numel(traces));
if isempty(traces); return; end

s.n_states = numel(unique([traces.state_index]));
times = cfg.relaxation.sample_times;

s.mean_drift_at_1s   = local_at(traces, times, 1);
s.mean_drift_at_100s = local_at(traces, times, 100);
s.mean_drift_final   = local_at(traces, times, max(times));

all = [];
for i = 1:numel(traces)
    d = traces(i).relative_drift;
    all = [all, d(isfinite(d))]; %#ok<AGROW>
end
if isempty(all)
    s.worst_drift_fraction = NaN;
else
    s.worst_drift_fraction = max(abs(all));
end
s.fraction_leaving_tolerance = mean([traces.left_tolerance]);
s.first_sample_time_s        = local_nm([traces.first_sample_time_s]);
end

function m = local_at(traces, times, targetTime)
[~, k] = min(abs(times - targetTime));
vals = nan(1, numel(traces));
for i = 1:numel(traces)
    d = traces(i).relative_drift;
    if numel(d) >= k; vals(i) = d(k); end
end
m = local_nm(vals);
end

function m = local_nm(x)
x = x(isfinite(x));
if isempty(x); m = NaN; else; m = mean(x); end
end
