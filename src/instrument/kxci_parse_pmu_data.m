function data = kxci_parse_pmu_data(str, n_fields)
%KXCI_PARSE_PMU_DATA  Parse a ':PMU:DATA:GET' reply into a numeric matrix.
%
%   data = KXCI_PARSE_PMU_DATA(str) splits the reply into points on ';' and
%   each point into fields on ','. Keithley's segARB examples document four
%   fields per point: voltage, current, timestamp, status. The meaning of
%   the status field is not documented in those examples; it is kept as a
%   number and logged, never interpreted.
%
%   data = KXCI_PARSE_PMU_DATA(str, n_fields) expects n_fields per point.
%   Points with a different field count are dropped (and counted in the
%   caller's log), never padded.
%
%   Inputs:
%       str      - char/string reply
%       n_fields - optional, default 4
%
%   Outputs:
%       data - N x n_fields double, columns [V_V, I_A, t_s, status]
%
%   Instrument side effects: none.
%
%   Exceptions: none; an unparsable reply gives an empty matrix.
%
%   See also PMU_RUN_SEQUENCE, KXCI_PARSE_READING.

if nargin < 2 || isempty(n_fields); n_fields = 4; end

data = zeros(0, n_fields);
s = strtrim(char(str));
if isempty(s)
    return;
end

points = strsplit(s, ';');
rows = nan(numel(points), n_fields);
keep = false(numel(points), 1);
for k = 1:numel(points)
    p = strtrim(points{k});
    if isempty(p); continue; end
    f = str2double(strsplit(p, ','));
    if numel(f) == n_fields && all(isfinite(f(1:min(3, n_fields))))
        rows(k, :) = f;
        keep(k) = true;
    end
end
data = rows(keep, :);
end
