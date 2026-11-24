function [i_A, info] = measure_current(inst, cfg, n_samples)
%MEASURE_CURRENT  Measure device current at the level presently applied.
%
%   [i_A, info] = MEASURE_CURRENT(inst, cfg) triggers one SMU current reading
%   with the KXCI user-mode command TI<smu> -- a single-point measurement --
%   and returns it in amperes. The reply is parsed by KXCI_PARSE_READING,
%   which also returns the 4145-style status letter when the reply has one;
%   'C' (this unit in compliance) counts as a compliance hit.
%
%   [i_A, info] = MEASURE_CURRENT(inst, cfg, n_samples) takes n_samples
%   readings and returns their mean, with the individual samples in
%   info.samples.
%
%   The measurement is checked against cfg.safety.max_abs_current; exceeding
%   it triggers an emergency shutdown before the value is returned.
%
%   Inputs:
%       inst      - InstrumentSession (output must be ON for a real reading)
%       cfg       - configuration struct
%       n_samples - optional, default 1
%
%   Outputs:
%       i_A  - [A] mean measured current, NaN when unavailable (dry-run,
%              communication failure, unparsable reply)
%       info - struct:
%                .samples        [A] vector of raw samples
%                .timestamps     [s] host-side timestamps of each sample
%                .status         'ok' | 'dry_run' | 'parse_error' |
%                                'comm_error' | 'aborted'
%                .compliance_hit logical, |I| within 1% of the compliance
%                .voltage        [V] the level in force during the reading
%                .n_valid        number of usable samples
%
%   Instrument side effects: triggers a measurement (the source level is not
%   changed).
%
%   Exceptions: none for ordinary failures -- they are reported through
%   info.status so that a long unattended run is not aborted by one bad read.
%   A current above the safety limit DOES abort the session.
%
%   See also MEASURE_CONDUCTANCE, SET_VOLTAGE, CHECK_CURRENT_LIMIT.

narginchk(2, 3);
if nargin < 3 || isempty(n_samples); n_samples = 1; end
n_samples = max(1, round(n_samples));

info = struct('samples', [], 'timestamps', [], 'status', 'ok', ...
              'compliance_hit', false, 'voltage', inst.LastVoltage, ...
              'n_valid', 0);
i_A = NaN;

if inst.Aborted
    info.status = 'aborted';
    return;
end

samples = nan(1, n_samples);
stamps  = nan(1, n_samples);
hit     = false;
t0      = tic;

% --------------------------------------------------------------- simulate
if inst.Simulate
    dt = max(cfg.read.pulse_width / n_samples, 1e-6);
    for k = 1:n_samples
        [samples(k), h] = inst.Sim.readCurrent(inst.LastVoltage, inst.Compliance, dt);
        hit = hit || h;
        stamps(k) = toc(t0);
    end

% --------------------------------------------------------------- dry run
elseif inst.DryRun
    log_message(inst, 'INFO', ...
        'DRY-RUN: would measure %d current sample(s) at %+.4f V.', ...
        n_samples, inst.LastVoltage);
    info.status = 'dry_run';
    return;

% --------------------------------------------------------------- real
else
    if ~inst.OutputOn
        log_message(inst, 'WARN', ...
            'measure_current called with the output OFF; the reading will be ~0 A.');
    end
    if ~strcmp(inst.Path, 'smu')
        log_message(inst, 'WARN', ...
            'measure_current called with the RPM on the "%s" path; the SMU does not see the device.', ...
            inst.Path);
    end
    cmd = sprintf('TI%d', inst.Smu);
    for k = 1:n_samples
        [resp, ok] = kxci_query(inst, cmd);
        stamps(k) = toc(t0);
        if ~ok
            info.status = 'comm_error';
            continue;
        end
        [val, st, okVal] = kxci_parse_reading(resp);
        if ~okVal
            % Covers both unparsable text and overflow codes.
            info.status = 'parse_error';
            log_message(inst, 'WARN', 'Unusable current reply: "%s"', resp);
            continue;
        end
        hit = hit || strcmp(st, 'C');
        samples(k) = val;
    end
end

valid = samples(isfinite(samples));
info.samples    = samples;
info.timestamps = stamps;
info.n_valid    = numel(valid);

if isempty(valid)
    if strcmp(info.status, 'ok'); info.status = 'comm_error'; end
    return;
end

i_A = mean(valid);

% ---- compliance detection ---------------------------------------------
if isfinite(inst.Compliance) && inst.Compliance > 0
    hit = hit || (max(abs(valid)) >= 0.99 * inst.Compliance);
end
info.compliance_hit = hit;

if hit
    inst.ComplianceHits = inst.ComplianceHits + 1;
    inst.ConsecutiveComplianceHits = inst.ConsecutiveComplianceHits + 1;

    % Whether sustained compliance is a fault depends on what we are doing.
    % Past V_set a DC sweep is SUPPOSED to sit in compliance -- that is the
    % entire purpose of the limit, and aborting there would kill every
    % normal sweep. During a read or a pulse it means the device is shorted,
    % the read voltage is wrong, or the state ran away, so it must abort.
    abortModes = cfg.safety.compliance_abort_modes;
    guarded = isempty(inst.Mode) || any(strcmpi(inst.Mode, abortModes));

    if guarded
        log_message(inst, 'WARN', ...
            'Compliance hit at %+.4f V in mode "%s" (|I| = %.4g A, limit %.4g A). Consecutive: %d.', ...
            inst.LastVoltage, inst.Mode, max(abs(valid)), inst.Compliance, ...
            inst.ConsecutiveComplianceHits);
        if inst.ConsecutiveComplianceHits >= cfg.safety.max_compliance_hits
            emergency_shutdown(inst, sprintf( ...
                ['Compliance hit %d times in a row during mode "%s" ' ...
                 '(limit cfg.safety.max_compliance_hits = %d).'], ...
                inst.ConsecutiveComplianceHits, inst.Mode, cfg.safety.max_compliance_hits));
            info.status = 'aborted';
            return;
        end
    else
        log_message(inst, 'DEBUG', ...
            'Compliance at %+.4f V in mode "%s" (expected in this mode).', ...
            inst.LastVoltage, inst.Mode);
    end
else
    inst.ConsecutiveComplianceHits = 0;
end

% ---- hard safety limit -------------------------------------------------
[safeOk, safeMsg] = check_current_limit(valid, cfg, inst);
if ~safeOk
    info.status = 'aborted';
    log_message(inst, 'SAFETY', '%s', safeMsg);
end
end
