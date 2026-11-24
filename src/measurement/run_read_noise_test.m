function result = run_read_noise_test(cfg, inst)
%RUN_READ_NOISE_TEST  Measurement noise of the read itself, p(G_read | G_true).
%
%   result = RUN_READ_NOISE_TEST(cfg) writes the device to several
%   conductance states and, at each one, reads it cfg.read_noise.num_reads
%   times (500-1000) WITHOUT applying any write pulse in between. The spread
%   of those readings is the read noise floor: any dG smaller than this
%   cannot be resolved by the programming loop, so it sets the practical
%   limit on write-verify precision.
%
%   Distinguishing noise from drift
%   -------------------------------
%   Pure noise scatters symmetrically about a constant mean. A monotonic
%   trend across the read sequence is NOT noise -- it is read disturb or
%   relaxation. The test therefore fits a straight line to G vs read index
%   and reports the slope and its significance, so the two are never
%   confused. A significant trend is flagged in the log and in .summary.
%
%   Inputs:
%       cfg  - configuration struct (cfg.read_noise.*)
%       inst - optional InstrumentSession
%
%   Outputs:
%       result - struct with .status, .run_id, .run_dir, .states and .summary:
%                   .n_states, .n_reads_per_state
%                   .worst_cv, .median_cv
%                   .n_states_with_trend
%                   .noise_floor_S       smallest resolvable dG (worst state)
%
%                Per state: .mean_G_S .std_G_S .cv .min_G_S .max_G_S
%                           .slope_S_per_read .trend_fraction_total
%                           .trend_significant
%
%   CSV columns:
%       device_id, run_id, state_index, target_conductance_S, read_index,
%       timestamp_s, read_voltage_V, measured_current_A, conductance_S,
%       resistance_Ohm, instrument_status
%
%   Instrument side effects: applies the read bias many times. No write
%   pulses other than the initial state preparation.
%
%   Exceptions: propagates configuration errors.
%
%   See also RUN_READ_DISTURB_TEST, RUN_RELAXATION_TEST, MEASURE_CONDUCTANCE.

narginchk(1, 2);
if nargin < 2; inst = []; end

% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
[run, inst, guard] = begin_measurement(cfg, 'read_noise_test', inst); %#ok<ASGLU>

result = struct('states', struct([]), 'summary', struct());
status = 'completed';
reason = '';

try
    [G_hrs, G_lrs, src] = get_conductance_window(cfg);
    if strcmp(src, 'placeholder') && ~inst.Simulate
        error('run_read_noise_test:NoWindow', ...
            'Run run_dc_cycle_test first, or set cfg.device.G_hrs_S / G_lrs_S.');
    end
    targets = resolve_state_targets(cfg, G_hrs, G_lrs, cfg.read_noise.states_normalized);
    nReads  = cfg.read_noise.num_reads;

    ok = confirm_step(cfg, 'Read-noise characterisation', { ...
        sprintf('device_id  : %s', cfg.device.device_id), ...
        sprintf('states     : [%s] S', strjoin(arrayfun(@(x) sprintf('%.3g', x), ...
                targets, 'UniformOutput', false), ' ')), ...
        sprintf('reads      : %d per state (%d total)', nReads, nReads*numel(targets)), ...
        sprintf('read bias  : %+.3f V, %d sample(s) averaged per read', ...
                cfg.read.voltage, cfg.read.num_average_reads), ...
        'No write pulses are applied except to prepare each state.'});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', ...
            'operator declined the read-noise checkpoint');
        return;
    end

    states = struct([]);

    for si = 1:numel(targets)
        if inst.Aborted; break; end
        target = targets(si);
        fprintf('\n  state %d/%d: target %.4g S, %d reads\n', si, numel(targets), target, nReads);

        initRes = initialize_to_state(inst, cfg, target, struct('verbose', false));
        if ~initRes.success
            % Skipping here is what reduced a 3-state noise measurement to a
            % single state on the previous device. Read noise is a property
            % of whatever state the device is actually IN, and that state is
            % measured, so an imperfect landing still yields valid data.
            if local_require_init(cfg, 'read_noise')
                log_message(run, 'WARN', ...
                    'State %d: initialisation failed (%s); skipping.', si, initRes.status);
                continue;
            end
            log_message(run, 'WARN', ...
                ['State %d: initialisation missed the target (%s); measuring the ' ...
                 'state actually reached (G = %.4g S).'], ...
                si, initRes.status, initRes.G_final_S);
        end

        configure_instruments(inst, cfg, 'read');
        G = nan(1, nReads);
        t0 = tic;

        for k = 1:nReads
            if inst.Aborted; break; end
            [Gk, info] = measure_conductance(inst, cfg);
            G(k) = Gk;

            row = struct( ...
                'device_id',            cfg.device.device_id, ...
                'run_id',               run.run_id, ...
                'state_index',          si, ...
                'target_conductance_S', target, ...
                'read_index',           k, ...
                'timestamp_s',          toc(t0), ...
                'read_voltage_V',       info.read_voltage_V, ...
                'measured_current_A',   info.current_A, ...
                'conductance_S',        Gk, ...
                'resistance_Ohm',       info.resistance_Ohm, ...
                'instrument_status',    info.status);
            append_measurement_row(run.data_csv, row);

            if mod(k, 100) == 0
                fprintf('    %d/%d reads, G = %.5g S\n', k, nReads, Gk);
            end
        end

        st = local_stats(G);
        st.state_index          = si;
        st.target_conductance_S = target;
        if isempty(states); states = st; else; states(end+1) = st; end %#ok<AGROW>

        fprintf('    -> mean %.5g S, std %.3g S, CV %.4f\n', ...
            st.mean_G_S, st.std_G_S, st.cv);
        if st.trend_significant
            fprintf(2, ['    -> TREND detected: %.2f%% total drift over %d reads. ' ...
                        'This is disturb/relaxation, not noise.\n'], ...
                100*st.trend_fraction_total, st.n_valid);
            log_message(run, 'WARN', ...
                ['State %d (%.4g S) drifted %.2f%% monotonically over %d reads at %+.3f V. ' ...
                 'Lower |cfg.read.voltage| or check relaxation before trusting this read voltage.'], ...
                si, target, 100*st.trend_fraction_total, st.n_valid, cfg.read.voltage);
        end
    end

    result.states  = states;
    result.summary = local_summarize(states, nReads);

catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_read_noise_test failed: %s', reason);
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
function s = local_stats(G)
g = G(isfinite(G));
s = struct('n_valid', numel(g), 'mean_G_S', NaN, 'std_G_S', NaN, 'cv', NaN, ...
    'min_G_S', NaN, 'max_G_S', NaN, 'slope_S_per_read', NaN, ...
    'trend_fraction_total', NaN, 'trend_significant', false, ...
    'state_index', NaN, 'target_conductance_S', NaN);
if isempty(g); return; end

s.mean_G_S = mean(g);
s.min_G_S  = min(g);
s.max_G_S  = max(g);
if numel(g) > 1
    s.std_G_S = std(g);
    if s.mean_G_S ~= 0
        s.cv = s.std_G_S / abs(s.mean_G_S);
    end
end

if numel(g) >= 10
    x = (1:numel(g)).';
    p = polyfit(x, g(:), 1);
    s.slope_S_per_read = p(1);
    total = p(1) * numel(g);
    if s.mean_G_S ~= 0
        s.trend_fraction_total = total / abs(s.mean_G_S);
    end
    % A trend counts as real only if the systematic drift over the whole
    % sequence is larger than the random scatter of a single read.
    s.trend_significant = isfinite(s.trend_fraction_total) && ...
        abs(total) > 2 * s.std_G_S;
end
end

% ========================================================================
function s = local_summarize(states, nReads)
s = struct('n_states', numel(states), 'n_reads_per_state', nReads);
if isempty(states); return; end

cv = [states.cv];
cvv = cv(isfinite(cv));
if isempty(cvv)
    s.worst_cv = NaN; s.median_cv = NaN;
else
    s.worst_cv  = max(cvv);
    s.median_cv = median(cvv);
end
s.n_states_with_trend = sum([states.trend_significant]);

% The smallest conductance change that a single read can resolve: 3 sigma of
% the noisiest state.
sd = [states.std_G_S];
sd = sd(isfinite(sd));
if isempty(sd); s.noise_floor_S = NaN; else; s.noise_floor_S = 3 * max(sd); end
end
