function [ok, msg, verdict] = check_resistance_limit(r_meas, cfg, inst)
%CHECK_RESISTANCE_LIMIT  Detect suspected hard shorts and open circuits.
%
%   CHECK_RESISTANCE_LIMIT(r_meas, cfg, inst) classifies a measured device
%   resistance. A value below cfg.safety.min_resistance is treated as a
%   suspected permanent short (device destroyed / probes touching) and
%   triggers an emergency shutdown plus an error. A value above
%   cfg.safety.max_resistance is reported as a suspected open circuit
%   (bad contact) -- that is a warning, not a shutdown, because a fresh
%   unformed device legitimately looks open.
%
%   [ok, msg, verdict] = CHECK_RESISTANCE_LIMIT(...) returns the verdict
%   instead of throwing (an unsafe short still forces the shutdown).
%
%   Inputs:
%       r_meas - [Ohm] scalar or vector of measured resistances
%       cfg    - configuration struct
%       inst   - InstrumentSession (optional; [] to skip shutdown)
%
%   Outputs (only when requested):
%       ok      - logical, false only for a suspected short
%       msg     - char, empty when nothing notable
%       verdict - 'ok' | 'suspected_short' | 'suspected_open' | 'no_data'
%
%   Instrument side effects: on a suspected short, calls EMERGENCY_SHUTDOWN.
%
%   Exceptions:
%       check_resistance_limit:SuspectedShort
%
%   See also CHECK_CURRENT_LIMIT, EMERGENCY_SHUTDOWN.

narginchk(2, 3);
if nargin < 3; inst = []; end

ok      = true;
msg     = '';
verdict = 'ok';

vals = r_meas(:);
vals = vals(isfinite(vals) & vals > 0);
if isempty(vals)
    verdict = 'no_data';
    return;
end

rmin = min(vals);
rmax = max(vals);

if rmin < cfg.safety.min_resistance
    ok      = false;
    verdict = 'suspected_short';
    msg = sprintf(['SAFETY: resistance %.4g Ohm is below ' ...
                   'cfg.safety.min_resistance = %.4g Ohm ' ...
                   '(suspected permanent short / probe contact fault).'], ...
                   rmin, cfg.safety.min_resistance);
    if ~isempty(inst)
        emergency_shutdown(inst, msg);
    end
    if nargout == 0
        error('check_resistance_limit:SuspectedShort', '%s', msg);
    end
    return;
end

if rmax > cfg.safety.max_resistance
    verdict = 'suspected_open';
    msg = sprintf(['Resistance %.4g Ohm exceeds cfg.safety.max_resistance = %.4g Ohm ' ...
                   '(suspected open circuit / lifted probe).'], ...
                   rmax, cfg.safety.max_resistance);
    if nargout == 0
        warning('check_resistance_limit:SuspectedOpen', '%s', msg);
    end
end
end
