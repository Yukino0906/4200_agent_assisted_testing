function [ok, msg] = check_current_limit(i_meas, cfg, inst)
%CHECK_CURRENT_LIMIT  Abort when a measured current exceeds the safe maximum.
%
%   CHECK_CURRENT_LIMIT(i_meas, cfg, inst) inspects a freshly measured
%   current. If |I| exceeds cfg.safety.max_abs_current the session is shut
%   down immediately (output to 0 V, output off, Aborted flag set) and an
%   error is thrown. This is the runaway / hard-breakdown guard.
%
%   [ok, msg] = CHECK_CURRENT_LIMIT(...) returns the verdict instead of
%   throwing, but STILL performs the emergency shutdown when unsafe.
%
%   Inputs:
%       i_meas - [A] scalar or vector of measured currents
%       cfg    - configuration struct
%       inst   - InstrumentSession (optional; pass [] to skip shutdown)
%
%   Outputs (only when requested):
%       ok  - logical
%       msg - char, empty when ok
%
%   Instrument side effects: on violation, calls EMERGENCY_SHUTDOWN, which
%   sets 0 V and turns the output off.
%
%   Exceptions:
%       check_current_limit:Exceeded
%
%   See also EMERGENCY_SHUTDOWN, CHECK_RESISTANCE_LIMIT.

narginchk(2, 3);
if nargin < 3; inst = []; end

ok  = true;
msg = '';

vals = i_meas(:);
vals = vals(isfinite(vals));
if isempty(vals)
    return;   % nothing measurable; measure_current handles that case
end

lim = cfg.safety.max_abs_current;
[mx, k] = max(abs(vals));
if mx > lim
    ok  = false;
    msg = sprintf(['SAFETY: measured current %.6g A (element %d) exceeds ' ...
                   'cfg.safety.max_abs_current = %.6g A.'], vals(k), k, lim);
    if ~isempty(inst)
        emergency_shutdown(inst, msg);
    end
    if nargout == 0
        error('check_current_limit:Exceeded', '%s', msg);
    end
end
end
