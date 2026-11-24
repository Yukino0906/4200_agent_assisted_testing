function [G_S, info] = measure_conductance(inst, cfg, read_voltage)
%MEASURE_CONDUCTANCE  Read the device conductance with a low-bias read pulse.
%
%   [G_S, info] = MEASURE_CONDUCTANCE(inst, cfg) performs the standard read
%   used by every test in this kit:
%       1. drive the read bias (cfg.read.voltage)
%       2. wait cfg.read.settle_time
%       3. take cfg.read.num_average_reads current samples
%       4. optionally discard the single worst outlier (n >= 3)
%       5. return to 0 V
%       6. G = mean(I) / V_read
%
%   [G_S, info] = MEASURE_CONDUCTANCE(inst, cfg, read_voltage) overrides the
%   read bias (used by the read-disturb sweep over candidate voltages).
%
%   The read bias is left at 0 V afterwards so that the device is never
%   parked under bias between operations.
%
%   Inputs:
%       inst         - InstrumentSession
%       cfg          - configuration struct
%       read_voltage - optional [V] override, signed
%
%   Outputs:
%       G_S  - [S] conductance, NaN when the read failed
%       info - struct:
%           .current_A        [A] mean current used for G
%           .samples_A        [A] all raw samples (before outlier rejection)
%           .used_A           [A] samples that entered the mean
%           .std_A            [A] standard deviation of used samples
%           .cv               relative standard deviation of used samples
%           .resistance_Ohm   [Ohm] 1/G
%           .read_voltage_V   [V] bias actually used
%           .timestamp_s      [s] session time of the read
%           .status           'ok' | 'dry_run' | 'open_circuit' |
%                             'comm_error' | 'aborted'
%           .compliance_hit   logical
%           .n_used           number of samples averaged
%
%   Instrument side effects: applies the read bias briefly, returns to 0 V.
%
%   Exceptions: none for ordinary read failures (reported via info.status).
%   A current above cfg.safety.max_abs_current aborts the session.
%
%   See also MEASURE_CURRENT, INITIALIZE_TO_STATE, RUN_READ_NOISE_TEST.

narginchk(2, 3);
if nargin < 3 || isempty(read_voltage)
    read_voltage = cfg.read.voltage;
end

info = struct('current_A', NaN, 'samples_A', [], 'used_A', [], ...
              'std_A', NaN, 'cv', NaN, 'resistance_Ohm', NaN, ...
              'read_voltage_V', read_voltage, 'timestamp_s', inst.elapsed(), ...
              'status', 'ok', 'compliance_hit', false, 'n_used', 0);
G_S = NaN;

if inst.Aborted
    info.status = 'aborted';
    return;
end

check_voltage_limit(read_voltage, cfg);

n = max(1, round(cfg.read.num_average_reads));

if ~set_voltage(inst, cfg, read_voltage)
    if inst.DryRun && ~inst.Simulate
        info.status = 'dry_run';
    else
        info.status = 'aborted';
    end
    return;
end

if cfg.read.settle_time > 0
    pause(cfg.read.settle_time);
end

[~, mi] = measure_current(inst, cfg, n);
samples = mi.samples;
info.samples_A      = samples;
info.compliance_hit = mi.compliance_hit;

% Always return to 0 V, even if the read failed.
set_voltage(inst, cfg, 0);

if strcmp(mi.status, 'aborted')
    info.status = 'aborted';
    return;
end
if strcmp(mi.status, 'dry_run')
    info.status = 'dry_run';
    return;
end

valid = samples(isfinite(samples));
if isempty(valid)
    info.status = 'comm_error';
    return;
end

% ---- outlier rejection --------------------------------------------------
% With only 3 reads a robust estimator is not meaningful; dropping the single
% point furthest from the median is a deliberate, documented choice. All raw
% samples are still returned in info.samples_A so nothing is lost.
used = valid;
if cfg.read.reject_outliers && numel(valid) >= 3
    d = abs(valid - median(valid));
    [~, worst] = max(d);
    used(worst) = [];
end

info.used_A = used;
info.n_used = numel(used);
Imean = mean(used);
info.current_A = Imean;
if numel(used) > 1
    info.std_A = std(used);
    if Imean ~= 0
        info.cv = info.std_A / abs(Imean);
    end
end

if abs(Imean) < cfg.read.min_valid_current
    info.status = 'open_circuit';
    log_message(inst, 'WARN', ...
        'Read current %.4g A at %+.3f V is below cfg.read.min_valid_current (%.3g A): open circuit or lifted probe?', ...
        Imean, read_voltage, cfg.read.min_valid_current);
    return;
end

G_S = Imean / read_voltage;
if G_S ~= 0
    info.resistance_Ohm = 1 / G_S;
end

% A negative conductance means the current has the wrong sign for the applied
% bias -- normally a wiring or offset problem, worth flagging loudly.
if G_S < 0
    log_message(inst, 'WARN', ...
        'Negative conductance (%.4g S) at %+.3f V: check polarity/offset.', ...
        G_S, read_voltage);
end

check_resistance_limit(info.resistance_Ohm, cfg, inst);
if inst.Aborted
    info.status = 'aborted';
end
end
