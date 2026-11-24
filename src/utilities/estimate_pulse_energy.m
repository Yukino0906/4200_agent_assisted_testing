function [energy_J, info] = estimate_pulse_energy(v_pulse, i_samples, t_samples, width_s, method)
%ESTIMATE_PULSE_ENERGY  Energy delivered to the device during one write pulse.
%
%   [energy_J, info] = ESTIMATE_PULSE_ENERGY(v_pulse, i_samples, t_samples,
%   width_s, method) estimates
%
%       E = integral V(t) I(t) dt          ('waveform_integral')
%       E ~ V_pulse * mean(|I|) * width    ('average_current')
%
%   Normal write pulses take one spot-mean current on the flat top (the PMU
%   records a waveform only when asked to verify the shape), so the
%   rectangular estimate is the usual one. Which formula was used is
%   recorded in `info` and must be propagated into the run metadata.
%
%   Inputs:
%       v_pulse   - [V] pulse amplitude (scalar); pass the measured top
%                        voltage when one exists
%       i_samples - [A] vector of current samples taken during the pulse
%                        (may be empty)
%       t_samples - [s] matching timestamps, monotonically increasing.
%                        Pass [] to fall back to average-current.
%       width_s   - [s] programmed (or measured) pulse width
%       method    - 'average_current' (default) | 'waveform_integral'
%
%   Outputs:
%       energy_J - [J] estimated energy. NaN if no current data available.
%       info     - struct with fields:
%                    .method_used     char, actual method applied
%                    .peak_current_A  max(|I|)
%                    .avg_current_A   mean(|I|)
%                    .n_samples       number of samples used
%                    .is_approximate  logical, true for average_current
%
%   Instrument side effects: none.
%
%   Exceptions: none. Degrades gracefully to NaN when data are missing.
%
%   See also APPLY_VOLTAGE_PULSE.

if nargin < 5 || isempty(method); method = 'average_current'; end
if nargin < 4; width_s = NaN; end
if nargin < 3; t_samples = []; end

i_samples = i_samples(:);
i_samples = i_samples(isfinite(i_samples));

info = struct( ...
    'method_used',    method, ...
    'peak_current_A', NaN, ...
    'avg_current_A',  NaN, ...
    'n_samples',      numel(i_samples), ...
    'is_approximate', true);

if isempty(i_samples)
    energy_J = NaN;
    info.method_used = 'none';
    return;
end

info.peak_current_A = max(abs(i_samples));
info.avg_current_A  = mean(abs(i_samples));

useIntegral = strcmpi(method, 'waveform_integral') && ...
              numel(i_samples) >= 2 && numel(t_samples) == numel(i_samples);

if useIntegral
    t = t_samples(:);
    t = t - t(1);
    if all(diff(t) >= 0) && t(end) > 0
        % V is held constant during the pulse -> V comes out of the integral.
        energy_J = abs(v_pulse) * trapz(t, abs(i_samples));
        info.method_used    = 'waveform_integral';
        info.is_approximate = false;
        return;
    end
end

% Fallback / default: rectangular approximation.
if ~isfinite(width_s)
    energy_J = NaN;
    info.method_used = 'none';
    return;
end
energy_J = abs(v_pulse) * info.avg_current_A * width_s;
info.method_used    = 'average_current';
info.is_approximate = true;
end
