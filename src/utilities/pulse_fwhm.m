function [fwhm_s, info] = pulse_fwhm(t_s, v_V)
%PULSE_FWHM  Full width at half maximum of one sampled pulse.
%
%   [fwhm_s, info] = PULSE_FWHM(t_s, v_V) finds the pulse top as the median
%   of the samples within 10% of the largest |V|, then the first rising and
%   last falling crossing of half that level, each interpolated linearly
%   between the two samples that bracket it. Works for either polarity.
%
%   Used to check that the PMU delivers the programmed width
%   (TEST_SINGLE_SAFE_PULSE). Reports NaN, never a guess, when the record
%   does not contain both edges.
%
%   Inputs:
%       t_s - [s] sample times, increasing
%       v_V - [V] samples
%
%   Outputs:
%       fwhm_s - [s] width at half maximum, NaN if not found
%       info   - struct: .v_top, .t_rise_s, .t_fall_s, .n_top
%
%   Instrument side effects: none.
%
%   Exceptions: none.
%
%   See also APPLY_VOLTAGE_PULSE.

t = t_s(:);
v = v_V(:);
ok = isfinite(t) & isfinite(v);
t = t(ok);
v = v(ok);

fwhm_s = NaN;
info = struct('v_top', NaN, 't_rise_s', NaN, 't_fall_s', NaN, 'n_top', 0);
if numel(v) < 3
    return;
end

[~, iMax] = max(abs(v));
s = sign(v(iMax));
if s == 0
    return;
end
a = s * v;                                   % positive-going pulse
onTop = a >= 0.9 * a(iMax);
info.n_top = nnz(onTop);
top = median(a(onTop));
info.v_top = s * top;
half = top / 2;

above = a >= half;
iUp = find(above, 1, 'first');
iDn = find(above, 1, 'last');
if isempty(iUp) || iUp == 1 || iDn == numel(a)
    return;                                  % an edge is outside the record
end

info.t_rise_s = local_cross(t(iUp-1), t(iUp), a(iUp-1), a(iUp), half);
info.t_fall_s = local_cross(t(iDn), t(iDn+1), a(iDn), a(iDn+1), half);
fwhm_s = info.t_fall_s - info.t_rise_s;
end

% ------------------------------------------------------------------------
function tc = local_cross(t1, t2, a1, a2, level)
if a2 == a1
    tc = t1;
else
    tc = t1 + (level - a1) * (t2 - t1) / (a2 - a1);
end
end
