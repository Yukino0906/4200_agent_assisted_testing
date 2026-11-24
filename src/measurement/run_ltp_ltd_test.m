function result = run_ltp_ltd_test(cfg, inst)
%RUN_LTP_LTD_TEST  Repeated identical-pulse potentiation/depression traces.
%
%   result = RUN_LTP_LTD_TEST(cfg) measures how the conductance evolves under
%   a train of IDENTICAL pulses, which is what a neuromorphic weight update
%   actually looks like:
%
%       initialise to HRS
%       apply N identical SET pulses, reading G after each     -> LTP trace
%       apply N identical RESET pulses, reading G after each   -> LTD trace
%       repeat for cfg.ltp_ltd.num_cycles
%
%   It is run for a weak, a medium and a strong pulse amplitude
%   (cfg.ltp_ltd.set_amplitudes / .reset_amplitudes) so that the speed,
%   granularity and overshoot of each can be compared.
%
%   What the resulting traces answer:
%       - how many pulses are needed to cross the window
%       - where the trace saturates at each end
%       - whether LTP and LTD are symmetric (they usually are not)
%       - how reproducible the trace is over cycles
%
%   Note the difference from RUN_SINGLE_PULSE_MAP: here consecutive pulses
%   deliberately start from different states. That is the point -- this is a trajectory,
%   not a repeatability measurement.
%
%   Inputs:
%       cfg  - configuration struct
%       inst - optional InstrumentSession
%
%   Outputs:
%       result - struct with .status, .run_id, .run_dir, .traces (struct
%                array, one per amplitude/cycle/branch) and .summary:
%                   .n_traces, .n_pulses_total
%                   .ltp_range_mean_S, .ltd_range_mean_S
%                   .symmetry_ratio      LTP range / LTD range
%                   .ltp_saturation_pulse_mean, .ltd_saturation_pulse_mean
%
%   CSV columns:
%       device_id, run_id, amplitude_index, cycle_id, branch, pulse_index,
%       timestamp_s, pulse_voltage_V, pulse_width_s, pulse_width_measured_s,
%       compliance_A, peak_current_A, average_current_A,
%       estimated_pulse_energy_J, read_voltage_V, G_before_S, G_after_S,
%       delta_G_S, normalized_delta_G, saturated, instrument_status
%
%   Instrument side effects: long trains of SET/RESET pulses.
%
%   Exceptions: propagates configuration errors.
%
%   See also RUN_SINGLE_PULSE_MAP, INITIALIZE_TO_STATE.

narginchk(1, 2);
if nargin < 2; inst = []; end

% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
[run, inst, guard] = begin_measurement(cfg, 'ltp_ltd_test', inst); %#ok<ASGLU>

result = struct('traces', struct([]), 'summary', struct());
status = 'completed';
reason = '';

try
    [G_hrs, G_lrs, src] = get_conductance_window(cfg);
    if strcmp(src, 'placeholder') && ~inst.Simulate
        error('run_ltp_ltd_test:NoWindow', ...
            'Run run_dc_cycle_test first, or set cfg.device.G_hrs_S / G_lrs_S.');
    end

    setAmps   = cfg.ltp_ltd.set_amplitudes;
    resetAmps = cfg.ltp_ltd.reset_amplitudes;
    nAmp      = min(numel(setAmps), numel(resetAmps));
    nPulses   = cfg.ltp_ltd.num_pulses;
    nCycles   = cfg.ltp_ltd.num_cycles;
    width     = cfg.ltp_ltd.width;

    % Targets for the two ends of each trace: just inside the window, so the
    % write-verify loop can actually reach them.
    gStart = resolve_state_targets(cfg, G_hrs, G_lrs, 0.05);
    gEnd   = resolve_state_targets(cfg, G_hrs, G_lrs, 0.95);

    estPulses = nAmp * nCycles * 2 * nPulses * 1.3;

    ok = confirm_step(cfg, 'LTP / LTD pulse-train characterisation', { ...
        sprintf('device_id   : %s', cfg.device.device_id), ...
        sprintf('window      : %.4g .. %.4g S (source: %s)', G_hrs, G_lrs, src), ...
        sprintf('SET amps    : [%s] V', num2str(setAmps(1:nAmp), '%.2f ')), ...
        sprintf('RESET amps  : [%s] V', num2str(resetAmps(1:nAmp), '%.2f ')), ...
        sprintf('width       : %.4g s', width), ...
        sprintf('pulses      : %d per branch', nPulses), ...
        sprintf('cycles      : %d per amplitude', nCycles), ...
        sprintf('pulse est.  : ~%d (budget %d)', round(estPulses), cfg.safety.max_total_pulses), ...
        sprintf('compliance  : %.4g A', cfg.pulse.compliance)});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', ...
            'operator declined the LTP/LTD checkpoint');
        return;
    end

    % A branch whose write-verify missed is still a usable pulse train: the
    % state it actually started from is recorded per pulse in G_before_S,
    % and the branch shape is what LTP/LTD is about. On a device whose
    % deep-reset states read below cfg.read.min_valid_current, every
    % initialisation "fails" and skipping every miss yields ZERO traces.
    % Set cfg.ltp_ltd.require_initialization = false to keep them; see
    % LOCAL_REQUIRE_INIT.
    needInit = local_require_init(cfg, 'ltp_ltd');

    traces = struct([]);

    for ai = 1:nAmp
        vSet   = setAmps(ai);
        vReset = resetAmps(ai);

        for c = 1:nCycles
            if inst.Aborted; break; end
            fprintf('\n  amplitude %d/%d (%+.2f / %+.2f V), cycle %d/%d\n', ...
                ai, nAmp, vSet, vReset, c, nCycles);

            % ---- LTP branch: start from (near) HRS ----------------------
            initRes = initialize_to_state(inst, cfg, gStart, struct('verbose', false));
            if ~initRes.success && needInit
                log_message(run, 'WARN', ...
                    'LTP cycle %d: could not initialise to %.4g S (%s); skipping.', ...
                    c, gStart, initRes.status);
            else
                if ~initRes.success
                    log_message(run, 'WARN', ...
                        ['LTP cycle %d: initialisation to %.4g S missed (%s); ' ...
                         'running the train from the state the device is ' ...
                         'actually in (G_before_S is recorded per pulse).'], ...
                        c, gStart, initRes.status);
                end
                tr = local_train(inst, cfg, run, ai, c, 'LTP', vSet, width, nPulses);
                if isempty(traces); traces = tr; else; traces(end+1) = tr; end %#ok<AGROW>
            end

            if inst.Aborted; break; end

            % ---- LTD branch: start from (near) LRS ----------------------
            initRes = initialize_to_state(inst, cfg, gEnd, struct('verbose', false));
            if ~initRes.success && needInit
                log_message(run, 'WARN', ...
                    'LTD cycle %d: could not initialise to %.4g S (%s); skipping.', ...
                    c, gEnd, initRes.status);
            else
                if ~initRes.success
                    log_message(run, 'WARN', ...
                        ['LTD cycle %d: initialisation to %.4g S missed (%s); ' ...
                         'running the train from the state the device is ' ...
                         'actually in (G_before_S is recorded per pulse).'], ...
                        c, gEnd, initRes.status);
                end
                tr = local_train(inst, cfg, run, ai, c, 'LTD', vReset, width, nPulses);
                if isempty(traces); traces = tr; else; traces(end+1) = tr; end %#ok<AGROW>
            end
        end
        if inst.Aborted; break; end
    end

    result.traces  = traces;
    result.summary = local_summarize(traces, inst);

catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_ltp_ltd_test failed: %s', reason);
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
function tr = local_train(inst, cfg, run, ampIndex, cycleId, branch, v, width, nPulses)
%LOCAL_TRAIN  One branch of identical pulses with a read after each.
tr = struct('amplitude_index', ampIndex, 'cycle_id', cycleId, 'branch', branch, ...
            'pulse_voltage_V', v, 'pulse_width_s', width, ...
            'G_trace_S', [], 'saturated_at', NaN, 'range_S', NaN, ...
            'n_pulses', 0);

configure_instruments(inst, cfg, 'read');
[G, ~] = measure_conductance(inst, cfg);
trace = G;
flat  = 0;
t0 = tic;

for k = 1:nPulses
    if inst.Aborted; break; end

    Gbefore = trace(end);

    configure_instruments(inst, cfg, 'pulse');
    pr = apply_voltage_pulse(inst, cfg, v, width, ...
        struct('label', sprintf('%s:a%d:c%d:p%d', branch, ampIndex, cycleId, k)));

    if cfg.read.delay_after_write > 0
        pause(cfg.read.delay_after_write);
    end

    configure_instruments(inst, cfg, 'read');
    [Gafter, aInfo] = measure_conductance(inst, cfg);
    trace(end+1) = Gafter; %#ok<AGROW>

    dG = Gafter - Gbefore;
    if isfinite(Gbefore) && Gbefore ~= 0
        ndG = dG / Gbefore;
    else
        ndG = NaN;
    end

    % ---- saturation detection ------------------------------------------
    saturated = false;
    if isfinite(ndG) && abs(ndG) < cfg.ltp_ltd.saturation_tol
        flat = flat + 1;
    else
        flat = 0;
    end
    if flat >= cfg.ltp_ltd.saturation_patience
        saturated = true;
        if ~isfinite(tr.saturated_at); tr.saturated_at = k; end
    end

    row = struct( ...
        'device_id',                cfg.device.device_id, ...
        'run_id',                   run.run_id, ...
        'amplitude_index',          ampIndex, ...
        'cycle_id',                 cycleId, ...
        'branch',                   branch, ...
        'pulse_index',              k, ...
        'timestamp_s',              toc(t0), ...
        'pulse_voltage_V',          v, ...
        'pulse_width_s',            width, ...
        'pulse_width_measured_s',   pr.width_measured_s, ...
        'compliance_A',             cfg.pulse.compliance, ...
        'peak_current_A',           pr.peak_current_A, ...
        'average_current_A',        pr.avg_current_A, ...
        'estimated_pulse_energy_J', pr.energy_J, ...
        'read_voltage_V',           cfg.read.voltage, ...
        'G_before_S',               Gbefore, ...
        'G_after_S',                Gafter, ...
        'delta_G_S',                dG, ...
        'normalized_delta_G',       ndG, ...
        'saturated',                saturated, ...
        'instrument_status',        local_worst(pr.status, aInfo.status));
    append_measurement_row(run.data_csv, row);

    if mod(k, 10) == 0
        fprintf('    %s pulse %3d/%3d: G = %.4g S\n', branch, k, nPulses, Gafter);
    end

    if saturated && cfg.ltp_ltd.stop_on_saturation
        fprintf('    %s saturated after %d pulses (|dG|/G < %.3g for %d pulses).\n', ...
            branch, k, cfg.ltp_ltd.saturation_tol, cfg.ltp_ltd.saturation_patience);
        break;
    end
    if any(strcmp(pr.status, {'aborted', 'limit_exceeded'}))
        break;
    end
end

tr.G_trace_S = trace;
tr.n_pulses  = numel(trace) - 1;
g = trace(isfinite(trace));
if numel(g) >= 2
    tr.range_S = max(g) - min(g);
end
end

% ========================================================================
function s = local_worst(a, b)
order = {'ok', 'dry_run', 'parse_error', 'comm_error', 'open_circuit', ...
         'instrument_error', 'limit_exceeded', 'aborted'};
ia = find(strcmp(order, a), 1); if isempty(ia); ia = 1; end
ib = find(strcmp(order, b), 1); if isempty(ib); ib = 1; end
if ia >= ib; s = a; else; s = b; end
end

% ========================================================================
function s = local_summarize(traces, inst)
s = struct();
s.n_traces       = numel(traces);
s.n_pulses_total = inst.PulseCount;
if isempty(traces); return; end

isLtp = strcmp({traces.branch}, 'LTP');
rng   = [traces.range_S];
sat   = [traces.saturated_at];

s.ltp_range_mean_S = local_nm(rng(isLtp));
s.ltd_range_mean_S = local_nm(rng(~isLtp));
if isfinite(s.ltd_range_mean_S) && s.ltd_range_mean_S ~= 0
    s.symmetry_ratio = s.ltp_range_mean_S / s.ltd_range_mean_S;
else
    s.symmetry_ratio = NaN;
end
s.ltp_saturation_pulse_mean = local_nm(sat(isLtp));
s.ltd_saturation_pulse_mean = local_nm(sat(~isLtp));
end

function m = local_nm(x)
x = x(isfinite(x));
if isempty(x); m = NaN; else; m = mean(x); end
end
