function [ok, msg] = check_voltage_limit(v, cfg)
%CHECK_VOLTAGE_LIMIT  Reject any voltage outside the configured safe envelope.
%
%   CHECK_VOLTAGE_LIMIT(v, cfg) throws when |v| exceeds
%   cfg.safety.max_abs_voltage, or when v is not a finite real scalar/vector.
%   This is the last gate before a level is ever sent to the SMU.
%
%   [ok, msg] = CHECK_VOLTAGE_LIMIT(v, cfg) returns the verdict instead of
%   throwing, for callers that want to decide themselves.
%
%   Inputs:
%       v   - [V] scalar or vector of voltages about to be applied
%       cfg - configuration struct
%
%   Outputs (only when requested):
%       ok  - logical
%       msg - char, empty when ok
%
%   Instrument side effects: none.
%
%   Exceptions:
%       check_voltage_limit:NotFinite
%       check_voltage_limit:Exceeded
%
%   See also CHECK_CURRENT_LIMIT, SET_VOLTAGE, VALIDATE_CONFIG.

narginchk(2, 2);
ok  = true;
msg = '';
id  = '';

if ~isnumeric(v) || ~isreal(v) || isempty(v) || any(~isfinite(v(:)))
    ok  = false;
    msg = 'Voltage must be finite, real and non-empty.';
    id  = 'check_voltage_limit:NotFinite';
else
    lim = cfg.safety.max_abs_voltage;
    [mx, k] = max(abs(v(:)));
    if mx > lim + 1e-9
        ok  = false;
        msg = sprintf(['Voltage %+.4f V (element %d) exceeds ' ...
                       'cfg.safety.max_abs_voltage = %.4f V. Refusing to output.'], ...
                       v(k), k, lim);
        id  = 'check_voltage_limit:Exceeded';
    end
end

if ~ok && nargout == 0
    error(id, '%s', msg);
end
end
