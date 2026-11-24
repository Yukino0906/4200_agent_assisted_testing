function result = run_endurance_test(cfg, inst)
%RUN_ENDURANCE_TEST  Cycle SET/RESET trains and watch the window until it collapses.
%
%   result = RUN_ENDURANCE_TEST(cfg) repeats, up to cfg.endurance.max_cycles times:
%       1. n identical SET pulses  -> read G_set
%       2. n identical RESET pulses -> read G_reset
%   and records the window ratio G_set / G_reset per cycle. The initial window is
%   the median ratio of the first cfg.endurance.baseline_cycles cycles; the test
%   stops when the ratio falls below cfg.endurance.stop_ratio_min (absolute) or
%   below cfg.endurance.stop_frac_min x the initial ratio, when a read is invalid,
%   or at max_cycles. The output is the device's window-vs-cycle record.
%
%   cfg.endurance fields (defaults in config/default_config.m):
%       set_amplitude_V, reset_amplitude_V, width_s, pulses_per_train,
%       max_cycles, baseline_cycles, stop_ratio_min, stop_frac_min, report_every
%
%   CSV columns: device_id, run_id, cycle_index, timestamp_s, set_amplitude_V,
%       reset_amplitude_V, width_s, pulses_per_train, read_voltage_V, G_set_S,
%       G_reset_S, window_ratio, ratio_vs_initial, stop_reason, instrument_status
%
%   Outputs: result.summary (n_cycles, initial_ratio, final_ratio, min_ratio,
%            stop_reason, pulses_applied).
%
%   See also RUN_RETENTION_HOLD_TEST, RUN_LTP_LTD_TEST, APPLY_VOLTAGE_PULSE.

narginchk(1, 2);
if nargin < 2; inst = []; end
p = local_defaults(cfg);

[run, inst, guard] = begin_measurement(cfg, 'endurance_test', inst); %#ok<ASGLU>
result = struct('summary', struct());
status = 'completed'; reason = '';

try
    ok = confirm_step(cfg, 'Endurance (SET train / RESET train cycles until the window collapses)', { ...
        sprintf('device_id  : %s', cfg.device.device_id), ...
        sprintf('trains     : %d x %+.2f V | %d x %+.2f V, %.3g s', p.pulses_per_train, p.set_amplitude_V, p.pulses_per_train, p.reset_amplitude_V, p.width_s), ...
        sprintf('cycles     : up to %d; stop at ratio < %.1f or < %.0f %% of the initial (median of first %d)', p.max_cycles, p.stop_ratio_min, 100 * p.stop_frac_min, p.baseline_cycles), ...
        sprintf('read       : %.3f V', cfg.read.voltage)});
    if ~ok
        result = finish_measurement(run, cfg, inst, result, 'stopped_by_user', 'operator declined');
        return;
    end

    t0 = tic;
    ratios = nan(1, p.max_cycles);
    initial = NaN; stopReason = ''; nPulses = 0;
    for c = 1:p.max_cycles
        if inst.Aborted; stopReason = 'aborted'; break; end
        configure_instruments(inst, cfg, 'pulse');
        for k = 1:p.pulses_per_train
            apply_voltage_pulse(inst, cfg, p.set_amplitude_V, p.width_s, struct('label', sprintf('endurance:c%d:set%d', c, k)));
        end
        nPulses = nPulses + p.pulses_per_train;
        if cfg.read.delay_after_write > 0; pause(cfg.read.delay_after_write); end
        configure_instruments(inst, cfg, 'read');
        [Gs, infoS] = measure_conductance(inst, cfg);
        configure_instruments(inst, cfg, 'pulse');
        for k = 1:p.pulses_per_train
            apply_voltage_pulse(inst, cfg, p.reset_amplitude_V, p.width_s, struct('label', sprintf('endurance:c%d:reset%d', c, k)));
        end
        nPulses = nPulses + p.pulses_per_train;
        if cfg.read.delay_after_write > 0; pause(cfg.read.delay_after_write); end
        configure_instruments(inst, cfg, 'read');
        [Gr, infoR] = measure_conductance(inst, cfg);

        valid = isfinite(Gs) && isfinite(Gr) && Gs > 0 && Gr > 0;
        ratio = NaN;
        if valid; ratio = Gs / Gr; end
        ratios(c) = ratio;
        if c == p.baseline_cycles
            initial = median(ratios(1:c), 'omitnan');
        end
        rel = NaN;
        if isfinite(initial) && initial > 0; rel = ratio / initial; end
        if ~valid
            stopReason = 'read_invalid';
        elseif c > p.baseline_cycles && (ratio < p.stop_ratio_min || (isfinite(rel) && rel < p.stop_frac_min))
            stopReason = 'window_collapsed';
        elseif c == p.max_cycles
            stopReason = 'max_cycles';
        end
        st = infoS.status;
        if ~strcmp(infoR.status, 'ok'); st = infoR.status; end
        row = struct('device_id', cfg.device.device_id, 'run_id', run.run_id, ...
            'cycle_index', c, 'timestamp_s', toc(t0), ...
            'set_amplitude_V', p.set_amplitude_V, 'reset_amplitude_V', p.reset_amplitude_V, ...
            'width_s', p.width_s, 'pulses_per_train', p.pulses_per_train, ...
            'read_voltage_V', cfg.read.voltage, 'G_set_S', Gs, 'G_reset_S', Gr, ...
            'window_ratio', ratio, 'ratio_vs_initial', rel, ...
            'stop_reason', stopReason, 'instrument_status', st);
        append_measurement_row(run.data_csv, row);
        if mod(c, p.report_every) == 1 || ~isempty(stopReason)
            fprintf('    cycle %4d  G_set %.3g  G_reset %.3g  ratio %.2f  (vs initial %.2f)\n', c, Gs, Gr, ratio, rel);
        end
        if ~isempty(stopReason); break; end
    end
    used = ratios(isfinite(ratios));
    finalRatio = NaN; minRatio = NaN;
    if ~isempty(used); finalRatio = used(end); minRatio = min(used); end
    result.summary = struct('n_cycles', c, 'initial_ratio', initial, 'final_ratio', finalRatio, ...
        'min_ratio', minRatio, 'stop_reason', stopReason, 'pulses_applied', nPulses, ...
        'elapsed_s', toc(t0));
    fprintf('    -> endurance: %d cycles (%d pulses), initial ratio %.2f, final %.2f, min %.2f (%s)\n', ...
        c, nPulses, initial, finalRatio, minRatio, stopReason);
catch err
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_endurance_test failed: %s', reason);
    emergency_shutdown(inst, reason);
    finish_measurement(run, cfg, inst, result, 'failed', reason);
    rethrow(err);
end
if inst.Aborted && strcmp(status, 'completed'); status = 'aborted'; reason = inst.LastError; end
result = finish_measurement(run, cfg, inst, result, status, reason);
end

function p = local_defaults(cfg)
% Fallbacks only; config/default_config.m defines cfg.endurance in full.
p = struct('set_amplitude_V', 1.2, 'reset_amplitude_V', -1.2, 'width_s', 10e-3, ...
    'pulses_per_train', 5, 'max_cycles', 100, 'baseline_cycles', 5, ...
    'stop_ratio_min', 2.0, 'stop_frac_min', 0.3, 'report_every', 10);
if isfield(cfg, 'endurance') && isstruct(cfg.endurance)
    f = fieldnames(cfg.endurance);
    for i = 1:numel(f); p.(f{i}) = cfg.endurance.(f{i}); end
end
end
