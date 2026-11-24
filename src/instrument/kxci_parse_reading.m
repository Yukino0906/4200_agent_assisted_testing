function [value, status, ok] = kxci_parse_reading(str)
%KXCI_PARSE_READING  Extract the number and its status letter from one KXCI reading.
%
%   [value, status, ok] = KXCI_PARSE_READING(str) accepts both a bare number
%   ("1.234E-06") and the HP 4145-style prefixed form ("NAI+1.234E-06":
%   status letter, channel letter, measured quantity, value). The exact form
%   the 4200A returns for TI/TV has not been confirmed for this kit, so the
%   parser takes the LAST number in the reply and treats any letters in
%   front of it as a prefix. test_instrument_connection prints the raw reply
%   so the form can be checked once.
%
%   Status letter (4145 convention, UNVERIFIED on the 4200A):
%       N normal, C this unit in compliance, T another unit in compliance,
%       V over range, X oscillation, L interval too short.
%
%   Inputs:
%       str - char/string reply
%
%   Outputs:
%       value  - double, NaN when no number was found or it is an overflow
%                code (|value| > 1e30)
%       status - char status letter ('' when the reply had no prefix)
%       ok     - logical, true when value is a usable number
%
%   Instrument side effects: none.
%
%   Exceptions: none.
%
%   See also MEASURE_CURRENT, KXCI_PARSE_PMU_DATA.

value  = NaN;
status = '';
ok     = false;

s = strtrim(char(str));
if isempty(s)
    return;
end

tok = regexp(s, '([A-Za-z]*)\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s*$', ...
    'tokens', 'once');
if isempty(tok)
    return;
end

if ~isempty(tok{1})
    status = upper(tok{1}(1));
end
v = str2double(tok{2});
if ~isfinite(v) || abs(v) > 1e30
    return;
end
value = v;
ok = true;
end
