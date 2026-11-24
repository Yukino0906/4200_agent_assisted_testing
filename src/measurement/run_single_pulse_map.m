function result = run_single_pulse_map(cfg, inst)
%RUN_SINGLE_PULSE_MAP  dG = f(G_before, V_pulse, t_pulse, polarity).
%
%   This is the core dataset for a pulse-programming (compact) model:
%
%       dG = f(G_before, V_pulse, t_pulse, polarity)   and   p(dG | G,V,t)
%
%   result = RUN_SINGLE_PULSE_MAP(cfg) loops over
%       initial states x pulse amplitudes (SET and RESET) x pulse widths
%   and, for every combination, repeats this cycle cfg.single_pulse.repeats
%   times:
%
%       1. write-verify the device back to the SAME target initial state
%       2. wait cfg.initial_states.settle_time
%       3. read 3x, average            -> G_before
%       4. apply EXACTLY ONE test pulse
%       5. wait cfg.read.delay_after_write
%       6. read 3x, average            -> G_after
%       7. append one row to disk
%
%   The re-initialisation in step 1 is what makes the repeats statistically
%   meaningful. Applying 20 identical pulses back-to-back and calling them 20
%   repeats would be wrong: each pulse would start from a different state,
%   so the spread would mix pulse-to-pulse randomness with state dependence.
%
%   A failed initialisation does NOT produce a data row for the pulse; the
%   attempt is recorded with initialization_success = 0 and the trial is
%   skipped. cfg.safety.max_consecutive_init_failures consecutive failures
%   abandon the current condition and move to the next one.
%
%   Inputs:
%       cfg  - configuration struct. The matrix size is controlled by
%              cfg.initial_states.normalized, cfg.pulse.set_amplitudes,
%              cfg.pulse.reset_amplitudes, cfg.pulse.widths,
%              cfg.single_pulse.repeats / .num_states / .amplitudes_subset.
%       inst - optional InstrumentSession
%
%   Outputs:
%       result - struct with .status, .run_id, .run_dir, .trials (all rows)
%                and .summary:
%                   .n_conditions, .n_trials, .n_init_failures
%                   .mean_abs_delta_G_S, .median_abs_delta_G_S
%                   .set_mean_delta_G_S, .reset_mean_delta_G_S
%                   .asymmetry_ratio     |mean dG_set| / |mean dG_reset|
%                   .total_pulses, .total_energy_J
%
%   CSV columns: see the `row` struct in local_write_trial (units are in
%   every column name).
%
%   Instrument side effects: many SET/RESET pulses. Budget-checked against
%   cfg.safety.max_total_pulses and cfg.safety.max_test_duration.
%
%   Exceptions: propagates configuration errors; measurement faults abort
%   safely and are reported through result.status.
%
%   See also INITIALIZE_TO_STATE, APPLY_VOLTAGE_PULSE, RUN_LTP_LTD_TEST.

narginchk(1, 2);
if nargin < 2; inst = []; end

% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
[run, inst, guard] = begin_measurement(cfg, 'single_pulse_map', inst); %#ok<ASGLU>

result = struct('trials', struct([]), 'summary', struct());
status = 'completed';
reason = '';

try
    % ---- resolve the state grid ----------------------------------------
    [G_hrs, G_lrs, src] = get_conductance_window(cfg);
    if strcmp(src, 'placeholder') && ~inst.Simulate
        error('run_single_pulse_map:NoWindow', ...
            ['The HRS/LRS window has not been measured for device "%s". ' ...
             'Run run_dc_cycle_test first, or set cfg.device.G_hrs_S / G_lrs_S.'], ...
            cfg.device.device_id);
    end

    norm = cfg.initial_states.normalized;
    if isfinite(cfg.single_pulse.num_states) && ...
            cfg.single_pulse.num_states < numel(norm)
        norm = local_pick(norm, cfg.single_pulse.num_states);
    end
    [targets, winfo] = resolve_state_targets(cfg, G_hrs, G_lrs, norm);

    setAmps   = local_pick(cfg.pulse.set_amplitudes,   cfg.single_pulse.amplitudes_subset);
    resetAmps = local_pick(cfg.pulse.reset_amplitudes, cfg.single_pulse.amplitudes_subset);
    amps      = [setAmps, resetAmps];
    widths    = cfg.pulse.widths;
    repeats   = cfg.single_pulse.repeats;

    nCond   = numel(targets) * numel(amps) * numel(widths);
    nTrials = nCond * repeats;
    % Each trial costs one test pulse plus the initialisation pulses.
    estPulses = nTrials * (1 + 6);

    ok = confirm_step(cfg, 'Single-pulse response map', { ...
        sprintf('device_id     : %s', cfg.device.device_id), ...
        sprintf('window        : %.4g .. %.4g S (ratio %.0f, source: %s)', ...
                winfo.G_hrs, winfo.G_lrs, winfo.ratio, src), ...
        sprintf('states        : %d  [%s] S', numel(targets), ...
                strjoin(arrayfun(@(x) sprintf('%.3g', x), targets, 'UniformOutput', false), ' ')), ...
        sprintf('SET amps      : [%s] V', num2str(setAmps, '%.2f ')), ...
        sprintf('RESET amps    : [%s] V', num2str(resetAmps, '%.2f ')), ...
        sprintf('widths        : [%s] s', num2str(widths, '%.4g ')), ...
        sprintf('repeats       : %d per condition', repeats), ...
        sprintf('conditions    : %d   trials: %d', nCond, nTrials), ...
        sprintf('pulse estimate: ~%d (budget %d)', estPulses, cfg.safety.max_total_pulses), ...
        sprintf('compliance    : %.4g A', cfg.pulse.compliance), ...
        sprintf('verify delay  : %.4g s   read: %+.3f V', ...
                cfg.read.delay_after_write, cfg.read.voltage), ...
        'THIS IS A LONG RUN. Data is written to disk after every pulse.'});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', ...
            'operator declined the single-pulse map checkpoint');
        return;
    end

    if estPulses > cfg.safety.max_total_pulses
        log_message(run, 'WARN', ...
            ['Estimated %d pulses exceeds cfg.safety.max_total_pulses = %d. ' ...
             'The run will stop when the budget is reached; raise the budget or ' ...
             'shrink the matrix to cover it fully.'], estPulses, cfg.safety.max_total_pulses);
    end

    % ---- the matrix ------------------------------------------------------
    trials    = struct([]);
    trialId   = 0;
    condIndex = 0;
    nInitFail = 0;
    t0        = tic;

    % When write-verify cannot reliably land inside the tolerance window --
    % which is the normal situation on a device with strong post-write
    % relaxation -- demanding an exact starting state throws away most trials.
    % The measurement dG = f(G_before, ...) does not actually need the target
    % to be hit: it needs G_before to be MEASURED, which it always is. So the
    % trial proceeds from whatever state was reached, initialization_success
    % records whether the target was met, and the analysis bins on the actual
    % G_before column rather than on the nominal target.
    requireInit = true;
    if isfield(cfg.single_pulse, 'require_initialization')
        requireInit = cfg.single_pulse.require_initialization;
    end
    if ~requireInit
        log_message(run, 'INFO', ...
            ['Approximate targeting enabled: trials proceed from the state actually ' ...
             'reached and are binned on the measured G_before, not on the target.']);
    end

    for si = 1:numel(targets)
        target = targets(si);
        for ai = 1:numel(amps)
            amp = amps(ai);
            for wi = 1:numel(widths)
                width = widths(wi);
                condIndex = condIndex + 1;

                if inst.Aborted; break; end

                fprintf('\n  [%d/%d] target %.4g S | %+.2f V | %.4g s | %d repeats\n', ...
                    condIndex, nCond, target, amp, width, repeats);

                consecutiveFail = 0;

                for rep = 1:repeats
                    if inst.Aborted; break; end
                    trialId = trialId + 1;

                    % ---- 1. re-initialise to the SAME starting state -----
                    initRes = initialize_to_state(inst, cfg, target, ...
                        struct('verbose', false));

                    if ~initRes.success
                        nInitFail = nInitFail + 1;
                        consecutiveFail = consecutiveFail + 1;

                        if requireInit
                            local_write_trial(run, cfg, trialId, target, ...
                                NaN, NaN, amp, width, ...
                                struct('status', 'skipped', 'error_code', ...
                                       ['init:' initRes.status], ...
                                       'peak_current_A', NaN, 'avg_current_A', NaN, ...
                                       'energy_J', NaN, 'width_measured_s', NaN), ...
                                NaN, NaN, initRes, 'initialisation failed');
                            if consecutiveFail >= cfg.safety.max_consecutive_init_failures
                                log_message(run, 'WARN', ...
                                    ['%d consecutive initialisation failures at target %.4g S. ' ...
                                     'Abandoning this condition.'], consecutiveFail, target);
                                break;
                            end
                            continue;
                        end
                        % Otherwise fall through and use the state we actually
                        % reached. See cfg.single_pulse.require_initialization.
                    else
                        consecutiveFail = 0;
                    end

                    % ---- 2/3. settle, then read G_before -----------------
                    configure_instruments(inst, cfg, 'read');
                    [Gbefore, bInfo] = measure_conductance(inst, cfg);
                    if ~isfinite(Gbefore)
                        log_message(run, 'WARN', ...
                            'Trial %d: G_before read failed (%s); skipping.', ...
                            trialId, bInfo.status);
                        continue;
                    end

                    % ---- 4. exactly ONE pulse ---------------------------
                    configure_instruments(inst, cfg, 'pulse');
                    pr = apply_voltage_pulse(inst, cfg, amp, width, ...
                        struct('label', sprintf('map:s%d:a%d:w%d', si, ai, wi)));

                    % ---- 5. verify delay --------------------------------
                    if cfg.read.delay_after_write > 0
                        pause(cfg.read.delay_after_write);
                    end

                    % ---- 6. read G_after --------------------------------
                    configure_instruments(inst, cfg, 'read');
                    [Gafter, aInfo] = measure_conductance(inst, cfg);

                    % ---- 7. persist -------------------------------------
                    local_write_trial(run, cfg, trialId, target, ...
                        Gbefore, bInfo.resistance_Ohm, amp, width, pr, ...
                        Gafter, aInfo.resistance_Ohm, initRes, '');

                    rec = struct('trial_id', trialId, 'state_index', si, ...
                        'target_G_S', target, 'amplitude_V', amp, 'width_s', width, ...
                        'G_before_S', Gbefore, 'G_after_S', Gafter, ...
                        'delta_G_S', Gafter - Gbefore, 'energy_J', pr.energy_J, ...
                        'status', pr.status);
                    if isempty(trials); trials = rec; else; trials(end+1) = rec; end %#ok<AGROW>

                    if mod(rep, 5) == 0 || rep == repeats
                        fprintf('      %2d/%2d  G %.4g -> %.4g S  (dG = %+.3g S)\n', ...
                            rep, repeats, Gbefore, Gafter, Gafter - Gbefore);
                    end

                    if any(strcmp(pr.status, {'aborted', 'limit_exceeded'}))
                        status = 'aborted';
                        reason = inst.LastError;
                        break;
                    end
                end
            end
            if inst.Aborted; break; end
        end
        if inst.Aborted; break; end
    end

    result.trials  = trials;
    result.summary = local_summarize(trials, nCond, nInitFail, inst, toc(t0));

catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_single_pulse_map failed: %s', reason);
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
function local_write_trial(run, cfg, trialId, target, Gb, Rb, amp, width, pr, ...
                           Ga, Ra, initRes, notes)
%LOCAL_WRITE_TRIAL  Append one trial. Called after EVERY pulse, never batched.
dG  = Ga - Gb;
if isfinite(dG) && isfinite(Gb) && Gb ~= 0
    ndG = dG / Gb;
else
    ndG = NaN;
end

if amp > 0
    polarity = 'SET';
elseif amp < 0
    polarity = 'RESET';
else
    polarity = 'ZERO';
end

row = struct( ...
    'device_id',                    cfg.device.device_id, ...
    'run_id',                       run.run_id, ...
    'trial_id',                     trialId, ...
    'target_initial_conductance_S', target, ...
    'initial_tolerance',            cfg.initial_states.tolerance, ...
    'G_before_S',                   Gb, ...
    'R_before_Ohm',                 Rb, ...
    'pulse_polarity',               polarity, ...
    'pulse_voltage_V',              amp, ...
    'pulse_width_s',                width, ...
    'pulse_width_measured_s',       local_f(pr, 'width_measured_s', NaN), ...
    'pulse_rise_time_s',            cfg.pulse.rise_time, ...
    'pulse_fall_time_s',            cfg.pulse.fall_time, ...
    'compliance_A',                 cfg.pulse.compliance, ...
    'peak_current_A',               local_f(pr, 'peak_current_A', NaN), ...
    'average_current_A',            local_f(pr, 'avg_current_A', NaN), ...
    'estimated_pulse_energy_J',     local_f(pr, 'energy_J', NaN), ...
    'pulse_energy_method',          local_f(pr, 'energy_method', 'none'), ...
    'compliance_hit',               local_f(pr, 'compliance_hit', false), ...
    'verify_delay_s',               cfg.read.delay_after_write, ...
    'read_voltage_V',               cfg.read.voltage, ...
    'G_after_S',                    Ga, ...
    'R_after_Ohm',                  Ra, ...
    'delta_G_S',                    dG, ...
    'normalized_delta_G',           ndG, ...
    'initialization_pulse_count',   initRes.pulse_count, ...
    'initialization_success',       initRes.success, ...
    'instrument_status',            local_f(pr, 'status', 'unknown'), ...
    'error_code',                   local_f(pr, 'error_code', ''), ...
    'notes',                        notes);

append_measurement_row(run.data_csv, row);
end

% ========================================================================
function v = local_f(s, name, default)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = default;
end
end

function out = local_pick(vec, n)
%LOCAL_PICK  Evenly spaced subset of length n (all of vec when n >= numel).
if isempty(vec) || ~isfinite(n) || n >= numel(vec)
    out = vec;
    return;
end
n = max(1, round(n));
idx = unique(round(linspace(1, numel(vec), n)));
out = vec(idx);
end

% ========================================================================
function s = local_summarize(trials, nCond, nInitFail, inst, elapsed)
s = struct();
s.n_conditions   = nCond;
s.n_init_failures = nInitFail;
s.total_pulses   = inst.PulseCount;
s.elapsed_s      = elapsed;

if isempty(trials)
    s.n_trials = 0;
    return;
end

dG   = [trials.delta_G_S];
amp  = [trials.amplitude_V];
en   = [trials.energy_J];

s.n_trials             = numel(trials);
s.mean_abs_delta_G_S   = local_nm(abs(dG));
s.median_abs_delta_G_S = local_nmed(abs(dG));
s.set_mean_delta_G_S   = local_nm(dG(amp > 0));
s.reset_mean_delta_G_S = local_nm(dG(amp < 0));
if isfinite(s.reset_mean_delta_G_S) && s.reset_mean_delta_G_S ~= 0
    s.asymmetry_ratio = abs(s.set_mean_delta_G_S) / abs(s.reset_mean_delta_G_S);
else
    s.asymmetry_ratio = NaN;
end
e = en(isfinite(en));
if isempty(e); s.total_energy_J = NaN; else; s.total_energy_J = sum(e); end
end

function m = local_nm(x)
x = x(isfinite(x));
if isempty(x); m = NaN; else; m = mean(x); end
end

function m = local_nmed(x)
x = x(isfinite(x));
if isempty(x); m = NaN; else; m = median(x); end
end
