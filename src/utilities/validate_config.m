function [cfg, report] = validate_config(cfg)
%VALIDATE_CONFIG  Type, range and logic checks on the configuration struct.
%
%   [cfg, report] = VALIDATE_CONFIG(cfg) verifies that every parameter used
%   by the measurement layer exists, has the right type, and is physically
%   sensible. It also enforces the mandatory safety confirmation gates before
%   any REAL-instrument measurement is permitted.
%
%   Inputs:
%       cfg - configuration struct from default_config()
%
%   Outputs:
%       cfg    - the same struct, with derived/normalised fields filled in
%       report - struct with .errors {cellstr}, .warnings {cellstr}, .ok
%
%   Instrument side effects: none.
%
%   Exceptions:
%       validate_config:Invalid       one or more hard checks failed
%       validate_config:NotConfirmed  real-hardware run attempted while
%                                     cfg.safety.compliance_confirmed or
%                                     cfg.safety.limits_confirmed is false
%
%   See also DEFAULT_CONFIG, CHECK_VOLTAGE_LIMIT.

narginchk(1, 1);
errors   = {};
warnings = {};

    function req(cond, fmt, varargin)
        if ~cond; errors{end+1} = sprintf(fmt, varargin{:}); end
    end
    function warn(cond, fmt, varargin)
        if ~cond; warnings{end+1} = sprintf(fmt, varargin{:}); end
    end

% ---- structural -------------------------------------------------------
needed = {'project_root','data_root','instrument','device','read','dc', ...
          'pulse','pmu','initial_states','single_pulse','ltp_ltd','read_noise', ...
          'relaxation','endurance','retention','safety','mode','sim'};
for i = 1:numel(needed)
    req(isfield(cfg, needed{i}), 'cfg.%s is missing.', needed{i});
end
if ~isempty(errors)
    report = local_report(errors, warnings);
    error('validate_config:Invalid', '%s', local_text(report));
end

% The KXCI mock is software: it needs no confirmation gates.
isRealRun = ~cfg.mode.simulate_instrument && ...
            ~strcmpi(cfg.instrument.transport, 'mock');

% ---- safety block ------------------------------------------------------
s = cfg.safety;
req(isnumeric(s.max_abs_voltage) && isscalar(s.max_abs_voltage) && ...
    s.max_abs_voltage > 0 && s.max_abs_voltage <= 20, ...
    'cfg.safety.max_abs_voltage must be a scalar in (0, 20] V.');
req(isnumeric(s.max_abs_current) && isscalar(s.max_abs_current) && ...
    s.max_abs_current > 0 && s.max_abs_current <= 1.5, ...
    'cfg.safety.max_abs_current must be a scalar in (0, 1.5] A.');
req(s.min_resistance > 0, 'cfg.safety.min_resistance must be > 0 Ohm.');
req(s.max_resistance > s.min_resistance, ...
    'cfg.safety.max_resistance must exceed min_resistance.');
req(s.max_total_pulses  >= 1,  'cfg.safety.max_total_pulses must be >= 1.');
req(iscellstr(s.compliance_abort_modes) || isstring(s.compliance_abort_modes), ...
    'cfg.safety.compliance_abort_modes must be a cellstr of measurement modes.');
req(s.max_test_duration >  0,  'cfg.safety.max_test_duration must be > 0 s.');

warn(s.max_abs_voltage <= 3.0, ...
    ['cfg.safety.max_abs_voltage = %g V is above the kit default of 3 V. ' ...
     'Make sure the device owner approved this ceiling.'], s.max_abs_voltage);

% Kit rule: nothing above 5 V, whatever the configuration says.
req(s.max_abs_voltage <= 5.0, ...
    ['cfg.safety.max_abs_voltage = %g V is above the hard ceiling of 5 V. ' ...
     'Refusing to run.'], s.max_abs_voltage);

% ---- voltages against the safety ceiling ------------------------------
vLim = s.max_abs_voltage;
    function checkV(vals, name)
        vals = vals(:);
        vals = vals(isfinite(vals));
        if isempty(vals); return; end
        req(max(abs(vals)) <= vLim + eps(vLim), ...
            '%s reaches %.3f V, exceeding cfg.safety.max_abs_voltage = %.3f V.', ...
            name, max(abs(vals)), vLim);
    end

checkV(cfg.dc.v_positive_max,        'cfg.dc.v_positive_max');
checkV(cfg.dc.v_negative_max,        'cfg.dc.v_negative_max');
checkV(cfg.read.voltage,             'cfg.read.voltage');
checkV(cfg.pulse.set_amplitudes,     'cfg.pulse.set_amplitudes');
checkV(cfg.pulse.reset_amplitudes,   'cfg.pulse.reset_amplitudes');
checkV(cfg.ltp_ltd.set_amplitudes,   'cfg.ltp_ltd.set_amplitudes');
checkV(cfg.ltp_ltd.reset_amplitudes, 'cfg.ltp_ltd.reset_amplitudes');
checkV([cfg.endurance.set_amplitude_V, cfg.endurance.reset_amplitude_V], ...
       'cfg.endurance amplitudes');
checkV([cfg.retention.states.amplitude_V], 'cfg.retention.states amplitudes');
checkV(cfg.initial_states.rush_amplitude_set, 'cfg.initial_states.rush_amplitude_set');
checkV([cfg.initial_states.coarse_amplitude_set, ...
        cfg.initial_states.fine_amplitude_set, ...
        cfg.initial_states.coarse_amplitude_reset, ...
        cfg.initial_states.fine_amplitude_reset], 'cfg.initial_states amplitudes');
checkV(cfg.safety.contact_check.voltage, 'cfg.safety.contact_check.voltage');

% ---- polarity convention ----------------------------------------------
req(all(cfg.pulse.set_amplitudes   > 0), ...
    'cfg.pulse.set_amplitudes must all be POSITIVE (+V = SET).');
req(all(cfg.pulse.reset_amplitudes < 0), ...
    'cfg.pulse.reset_amplitudes must all be NEGATIVE (-V = RESET).');
req(cfg.endurance.set_amplitude_V > 0 && cfg.endurance.reset_amplitude_V < 0, ...
    'cfg.endurance.set_amplitude_V must be > 0 and reset_amplitude_V < 0.');
for k = 1:numel(cfg.retention.states)
    st = cfg.retention.states(k);
    req(st.amplitude_V ~= 0 && st.n_pulses >= 1 && st.width_s > 0, ...
        'cfg.retention.states(%d) needs a non-zero amplitude, n_pulses >= 1 and width_s > 0.', k);
end
req(all(cfg.ltp_ltd.set_amplitudes   > 0), 'cfg.ltp_ltd.set_amplitudes must be > 0.');
req(all(cfg.ltp_ltd.reset_amplitudes < 0), 'cfg.ltp_ltd.reset_amplitudes must be < 0.');
req(cfg.initial_states.coarse_amplitude_set   > 0 && ...
    cfg.initial_states.fine_amplitude_set     > 0, ...
    'cfg.initial_states SET amplitudes must be > 0.');
req(cfg.initial_states.coarse_amplitude_reset < 0 && ...
    cfg.initial_states.fine_amplitude_reset   < 0, ...
    'cfg.initial_states RESET amplitudes must be < 0.');
req(cfg.dc.v_positive_max > 0 && cfg.dc.v_negative_max < 0, ...
    'cfg.dc.v_positive_max must be > 0 and v_negative_max < 0.');

% ---- compliance --------------------------------------------------------
comps = [cfg.dc.compliance, cfg.pulse.compliance, cfg.read.compliance];
req(all(isfinite(comps)) && all(comps > 0), ...
    'All compliance values must be finite and > 0 A.');
req(all(comps <= s.max_abs_current + eps), ...
    'A compliance value (max %.4g A) exceeds cfg.safety.max_abs_current = %.4g A.', ...
    max(comps), s.max_abs_current);
warn(max([cfg.dc.compliance, cfg.pulse.compliance]) <= 5e-3, ...
    ['Write compliance up to %.4g A. High compliance risks hard breakdown; ' ...
     'raise it only when a lower value demonstrably clamps the device.'], ...
    max([cfg.dc.compliance, cfg.pulse.compliance]));

% ---- read block --------------------------------------------------------
req(cfg.read.voltage ~= 0, 'cfg.read.voltage must be non-zero.');
req(cfg.read.num_average_reads >= 1, 'cfg.read.num_average_reads must be >= 1.');
req(cfg.read.delay_after_write >= 0, 'cfg.read.delay_after_write must be >= 0 s.');
warn(abs(cfg.read.voltage) <= 0.3, ...
    'cfg.read.voltage = %.3f V is large for a non-disturbing read.', cfg.read.voltage);
if cfg.read.voltage > 0
    warnings{end+1} = sprintf(['cfg.read.voltage is POSITIVE (%+.3f V), i.e. the SET direction. ' ...
        'Confirm with run_read_noise_test that repeated reads do not drift ' ...
        'before trusting long read sequences.'], cfg.read.voltage);
end

% ---- DC block ----------------------------------------------------------
req(cfg.dc.v_step > 0, 'cfg.dc.v_step must be > 0 V.');
req(cfg.dc.v_step <= 0.5, 'cfg.dc.v_step = %g V is too coarse.', cfg.dc.v_step);
req(cfg.dc.num_cycles >= 1 && cfg.dc.num_cycles == fix(cfg.dc.num_cycles), ...
    'cfg.dc.num_cycles must be a positive integer.');
req(cfg.dc.delay >= 0, 'cfg.dc.delay must be >= 0 s.');
warn(cfg.dc.num_cycles <= 10, ...
    'cfg.dc.num_cycles = %d. Run 5 cycles and inspect the data before long cycling.', ...
    cfg.dc.num_cycles);

% ---- pulse block -------------------------------------------------------
req(~isempty(cfg.pulse.widths) && all(cfg.pulse.widths > 0), ...
    'cfg.pulse.widths must be non-empty and > 0 s.');
req(any(strcmpi(cfg.pulse.timing_source, {'pmu','pc'})), ...
    'cfg.pulse.timing_source must be ''pmu'' or ''pc''.');
req(any(strcmpi(cfg.pulse.energy_method, {'average_current','waveform_integral'})), ...
    'cfg.pulse.energy_method must be ''average_current'' or ''waveform_integral''.');

% Every width any test can send to the pulse engine.
allWidths = [cfg.pulse.widths(:); cfg.initial_states.coarse_width; ...
             cfg.initial_states.fine_width; cfg.ltp_ltd.width; ...
             cfg.endurance.width_s; [cfg.retention.states.width_s]'];
allWidths = allWidths(isfinite(allWidths));
usePmu = strcmpi(cfg.pulse.timing_source, 'pmu');

if strcmpi(cfg.pulse.timing_source, 'pc') && any(allWidths < 20e-3)
    errors{end+1} = sprintf(['The ''pc'' engine times pulses from the laptop over the ' ...
        'network and cannot deliver widths below ~20 ms (min configured %.3g s). ' ...
        'Use cfg.pulse.timing_source = ''pmu'' or raise the widths.'], min(allWidths));
end

% ---- PMU block ---------------------------------------------------------
p = cfg.pmu;
if usePmu
    req(p.enabled, 'cfg.pulse.timing_source = ''pmu'' needs cfg.pmu.enabled = true.');
    edges = (p.rise_time + p.fall_time) / 2;
    req(p.rise_time >= p.min_segment_time && p.fall_time >= p.min_segment_time, ...
        'cfg.pmu.rise_time and fall_time must be >= cfg.pmu.min_segment_time (%.3g s).', ...
        p.min_segment_time);
    req(all(allWidths - edges >= p.min_segment_time), ...
        ['Width %.4g s is too short for %.3g s rise and %.3g s fall: the flat top ' ...
         'would be below cfg.pmu.min_segment_time.'], min(allWidths), p.rise_time, p.fall_time);
    req(all(allWidths <= p.max_width_s), ...
        ['Width %.4g s exceeds cfg.pmu.max_width_s = %.4g s. Long PMU pulses carry ' ...
         'energy with no compliance; raise the limit deliberately if intended.'], ...
        max(allWidths), p.max_width_s);
end
rpmRanges = [100e-9 1e-6 10e-6 100e-6 1e-3 10e-3];
req(any(abs(p.current_range_A - rpmRanges) <= 1e-12 + 1e-9 * p.current_range_A), ...
    'cfg.pmu.current_range_A = %.4g A is not one of the RPM ranges %s A.', ...
    p.current_range_A, mat2str(rpmRanges));
req(p.max_current_A > 0 && p.max_current_A <= s.max_abs_current, ...
    'cfg.pmu.max_current_A must be > 0 and <= cfg.safety.max_abs_current.');
% A reading cannot exceed its own range, so a limit at or above the range
% could never trip.
req(p.max_current_A <= 0.95 * p.current_range_A, ...
    ['cfg.pmu.max_current_A = %.4g A is not below the fixed range %.4g A; the ' ...
     'software limit could never trip. Use a larger range or a lower limit.'], ...
    p.max_current_A, p.current_range_A);
req(numel(p.measure_window) == 2 && p.measure_window(1) >= 0 && ...
    p.measure_window(2) <= 1 && p.measure_window(1) < p.measure_window(2), ...
    'cfg.pmu.measure_window must be [start stop] fractions with 0 <= start < stop <= 1.');
req(p.sense_channel == 0 || p.sense_channel ~= p.force_channel, ...
    'cfg.pmu.sense_channel must differ from force_channel (or be 0).');

% ---- connection and wiring ---------------------------------------------
req(any(strcmpi(cfg.instrument.transport, {'visa','tcpclient','mock'})), ...
    'cfg.instrument.transport must be ''visa'', ''tcpclient'' or ''mock''.');
req(any(strcmpi(cfg.instrument.return_path, {'gndu','pmu_sense'})), ...
    'cfg.instrument.return_path must be ''gndu'' or ''pmu_sense''.');
% The second terminal is wired either to the ground unit or to the sense
% RPM; the two settings must describe the same cable.
req(strcmpi(cfg.instrument.return_path, 'pmu_sense') == (p.sense_channel > 0), ...
    ['cfg.instrument.return_path = ''pmu_sense'' and cfg.pmu.sense_channel > 0 ' ...
     'go together: both describe the second probe on the sense RPM.']);

% ---- initial states ----------------------------------------------------
n = cfg.initial_states.normalized;
req(~isempty(n) && all(n > 0) && all(n < 1), ...
    'cfg.initial_states.normalized must lie strictly inside (0, 1).');
req(cfg.initial_states.tolerance > 0 && cfg.initial_states.tolerance < 1, ...
    'cfg.initial_states.tolerance must lie in (0, 1).');
req(cfg.initial_states.max_iterations >= 1, ...
    'cfg.initial_states.max_iterations must be >= 1.');
req(any(strcmpi(cfg.initial_states.spacing, {'log','linear'})), ...
    'cfg.initial_states.spacing must be ''log'' or ''linear''.');

% ---- relaxation --------------------------------------------------------
req(issorted(cfg.relaxation.sample_times) && all(cfg.relaxation.sample_times >= 0), ...
    'cfg.relaxation.sample_times must be sorted and >= 0 s.');

% ---- mode / paths ------------------------------------------------------
req(islogical(cfg.mode.dry_run) && islogical(cfg.mode.simulate_instrument), ...
    'cfg.mode.dry_run and cfg.mode.simulate_instrument must be logical.');
req(exist(cfg.project_root, 'dir') == 7, ...
    'cfg.project_root "%s" does not exist.', cfg.project_root);

% ---- device id ---------------------------------------------------------
if isRealRun
    req(~isempty(cfg.device.device_id), ...
        'cfg.device.device_id must be set before a real measurement.');
end

% ---- MANDATORY CONFIRMATION GATES (real hardware only) -----------------
if isRealRun
    if ~cfg.safety.compliance_confirmed
        errors{end+1} = [ ...
            'cfg.safety.compliance_confirmed is false. Review cfg.dc.compliance, ' ...
            'cfg.pulse.compliance and cfg.read.compliance against your device ' ...
            '(see docs/05_safety.md), then set the flag to true yourself.'];
    end
    if ~cfg.safety.limits_confirmed
        errors{end+1} = [ ...
            'cfg.safety.limits_confirmed is false. Review max_abs_voltage, ' ...
            'max_abs_current, min_resistance and every amplitude in the config ' ...
            '(see docs/05_safety.md), then set the flag to true yourself.'];
    end
    if usePmu && ~cfg.pmu.no_compliance_acknowledged
        errors{end+1} = [ ...
            'cfg.pmu.no_compliance_acknowledged is false. The PMU pulse path has ' ...
            'no current compliance. Read docs/05_safety.md section 3, set ' ...
            'cfg.pmu.max_current_A, then set the flag to true yourself.'];
    end
end

% ---- derived fields ----------------------------------------------------
cfg.read.voltage_sign = sign(cfg.read.voltage);
cfg.derived.validated_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>

report = local_report(errors, warnings);

for i = 1:numel(warnings)
    warning('validate_config:Warning', '%s', warnings{i});
end

if ~report.ok
    if isRealRun && all(cellfun(@(e) contains(e, 'confirmed is false') || ...
                                     contains(e, 'acknowledged is false'), errors))
        error('validate_config:NotConfirmed', '%s', local_text(report));
    end
    error('validate_config:Invalid', '%s', local_text(report));
end
end

% ------------------------------------------------------------------------
function r = local_report(errors, warnings)
r = struct('errors', {errors}, 'warnings', {warnings}, 'ok', isempty(errors));
end

function txt = local_text(r)
txt = sprintf('Configuration validation failed with %d error(s):\n', numel(r.errors));
for i = 1:numel(r.errors)
    txt = [txt sprintf('  [%d] %s\n', i, r.errors{i})]; %#ok<AGROW>
end
end
