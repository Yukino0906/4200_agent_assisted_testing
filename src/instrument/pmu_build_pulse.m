function seq = pmu_build_pulse(cfg, v_pulse, width_s, measure)
%PMU_BUILD_PULSE  Segment-ARB description of one trapezoidal write pulse.
%
%   seq = PMU_BUILD_PULSE(cfg, v_pulse, width_s) returns the five-segment
%   sequence that PMU_RUN_SEQUENCE sends to the 4225-PMU:
%
%       seg 1  pre      0 V              cfg.pmu.pre_time
%       seg 2  rise     0 -> V           cfg.pmu.rise_time
%       seg 3  top      V                width_s - (rise + fall)/2
%       seg 4  fall     V -> 0           cfg.pmu.fall_time
%       seg 5  post     0 V              cfg.pmu.post_time
%
%   width_s is the full width at half maximum (FWHM) of that trapezoid, so a
%   width means the same thing whatever the rise and fall times are.
%
%   seq = PMU_BUILD_PULSE(cfg, v_pulse, width_s, measure) chooses what is
%   measured:
%       'spot'     (default) spot mean over cfg.pmu.measure_window of the
%                  top segment, plus a spot mean of the pre segment as a
%                  0 V baseline when cfg.pmu.baseline_measure is true
%       'waveform' the whole sequence sampled, to verify the delivered shape
%
%   Measure-type codes 0 = none, 1 = spot mean, 2 = waveform follow
%   Keithley's KXCI segARB examples. Measure start/stop times are relative
%   to the start of each segment.
%
%   The sense channel (cfg.pmu.sense_channel > 0) gets the same timing at
%   0 V, so it measures the current leaving the device's other terminal.
%
%   Inputs:
%       cfg     - configuration struct
%       v_pulse - [V] amplitude, signed (+ = SET, - = RESET)
%       width_s - [s] FWHM
%       measure - optional 'spot' | 'waveform'
%
%   Outputs:
%       seq - struct:
%           .force   struct with .time, .startv, .stopv, .meastype,
%                    .measstart, .measstop (1 x 5 each)
%           .sense   same at 0 V, or [] without a sense channel
%           .width_fwhm_s, .top_time_s, .rise_time_s, .fall_time_s
%           .top_index (3), .baseline_index (1 or 0), .measure
%
%   Instrument side effects: none.
%
%   Exceptions:
%       pmu_build_pulse:TooShort  the top segment would be shorter than
%                                 cfg.pmu.min_segment_time
%
%   See also PMU_RUN_SEQUENCE, APPLY_VOLTAGE_PULSE.

narginchk(3, 4);
if nargin < 4 || isempty(measure); measure = 'spot'; end

p   = cfg.pmu;
tr  = p.rise_time;
tf  = p.fall_time;
top = width_s - (tr + tf) / 2;
if top < p.min_segment_time
    error('pmu_build_pulse:TooShort', ...
        ['Width %.4g s with rise %.4g s and fall %.4g s leaves a %.4g s top segment, ' ...
         'below cfg.pmu.min_segment_time = %.4g s. Use shorter edges or a longer width.'], ...
        width_s, tr, tf, top, p.min_segment_time);
end

f.time   = [p.pre_time, tr, top, tf, p.post_time];
f.startv = [0, 0, v_pulse, v_pulse, 0];
f.stopv  = [0, v_pulse, v_pulse, 0, 0];

switch lower(measure)
    case 'spot'
        f.meastype  = [0 0 1 0 0];
        f.measstart = zeros(1, 5);
        f.measstop  = zeros(1, 5);
        f.measstart(3) = p.measure_window(1) * top;
        f.measstop(3)  = p.measure_window(2) * top;
        baseIdx = 0;
        if p.baseline_measure
            f.meastype(1)  = 1;
            f.measstart(1) = p.measure_window(1) * p.pre_time;
            f.measstop(1)  = p.measure_window(2) * p.pre_time;
            baseIdx = 1;
        end
    case 'waveform'
        f.meastype  = 2 * ones(1, 5);
        f.measstart = zeros(1, 5);
        f.measstop  = f.time;
        baseIdx = 0;
    otherwise
        error('pmu_build_pulse:BadMeasure', 'measure must be ''spot'' or ''waveform''.');
end

seq.force = f;
seq.sense = [];
if p.sense_channel > 0
    s = f;
    s.startv = zeros(1, 5);
    s.stopv  = zeros(1, 5);
    seq.sense = s;
end
seq.width_fwhm_s   = top + (tr + tf) / 2;
seq.top_time_s     = top;
seq.rise_time_s    = tr;
seq.fall_time_s    = tf;
seq.top_index      = 3;
seq.baseline_index = baseIdx;
seq.measure        = lower(measure);
end
