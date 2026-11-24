function result = apply_voltage_pulse(inst, cfg, v_pulse, width_s, opts)
%APPLY_VOLTAGE_PULSE  Apply exactly ONE write pulse and report what happened.
%
%   result = APPLY_VOLTAGE_PULSE(inst, cfg, v_pulse, width_s) drives the
%   device to v_pulse for width_s seconds, measures the current during the
%   pulse, returns to 0 V, and reports the delivered width, the measured
%   voltage and current, and the estimated energy.
%
%   PULSE ENGINES (cfg.pulse.timing_source)
%   ---------------------------------------
%   'pmu' (default)
%       A trapezoid (PMU_BUILD_PULSE) is downloaded to the 4225-PMU as a
%       segment-ARB sequence and executed by the PMU hardware through the
%       4225-RPM (PMU_RUN_SEQUENCE). width_s is the FWHM; the host is not
%       in the timing loop. The current is the spot mean over the flat top.
%       result.width_measured_s holds the FWHM of the programmed trapezoid
%       (result.width_basis = 'pmu_programmed_fwhm'): the PMU times segments
%       in hardware, and TEST_SINGLE_SAFE_PULSE verifies the delivered shape
%       once per setup with a waveform capture (opts.capture = 'waveform',
%       width_basis = 'pmu_waveform_fwhm').
%       The PMU drives through a 50 Ohm output and has NO SMU-style current
%       compliance. result.v_measured_V is the voltage the PMU measured on
%       the top -- record it next to the programmed amplitude. A current
%       above cfg.pmu.max_current_A ends the run (after the fact).
%
%   'pc'
%       SMU level set by the host (DV), held with pause, measured with TI,
%       returned to 0 V. Network round-trips make anything below ~20 ms
%       unreliable; validate_config rejects that combination. Uses the SMU
%       compliance cfg.pulse.compliance.
%
%   Inputs:
%       inst    - InstrumentSession
%       cfg     - configuration struct
%       v_pulse - [V] pulse amplitude, signed (+ = SET, - = RESET)
%       width_s - [s] programmed pulse width (FWHM for the PMU)
%       opts    - optional struct:
%                   .n_samples  current samples inside the pulse ('pc' only;
%                               default cfg.pulse.samples_in_pulse)
%                   .label      char, copied into result.label
%                   .capture    'spot' (default) | 'waveform' (PMU only)
%                   .g_before_S conductance read before the pulse, used for
%                               the energy fallback when no current exists
%
%   Outputs:
%       result - struct:
%           .applied            logical, false in dry-run or when refused
%           .status             'ok' | 'dry_run' | 'aborted' |
%                               'instrument_error' | 'limit_exceeded'
%           .error_code         '' or an MException-style identifier
%           .v_pulse_V, .v_measured_V, .width_programmed_s, .width_measured_s
%           .width_basis, .rise_time_s, .fall_time_s
%           .i_samples_A, .t_samples_s, .baseline_current_A
%           .peak_current_A, .avg_current_A
%           .compliance_A, .compliance_hit   (SMU engine; NaN/false for PMU)
%           .energy_J, .energy_method
%           .timing_source, .pulse_index, .label
%           .waveform           struct(t_s, V_V, I_A) for opts.capture = 'waveform'
%
%   Instrument side effects: drives the device at v_pulse for width_s, then
%   returns the level to 0 V. For the PMU the RPM is switched to the pulse
%   path and the PMU output is disabled again after the pulse.
%
%   Exceptions:
%       check_voltage_limit:Exceeded  amplitude outside the safe envelope
%       apply_voltage_pulse:BadWidth  width not finite and positive
%       pmu_build_pulse:TooShort      width cannot hold the edges
%
%   See also SET_VOLTAGE, MEASURE_CONDUCTANCE, PMU_BUILD_PULSE, PMU_RUN_SEQUENCE.

narginchk(4, 5);
if nargin < 5 || isempty(opts); opts = struct(); end
nSamples = local_opt(opts, 'n_samples', cfg.pulse.samples_in_pulse);
label    = local_opt(opts, 'label', '');
capture  = local_opt(opts, 'capture', 'spot');
engine   = lower(char(cfg.pulse.timing_source));

result = struct( ...
    'applied',            false, ...
    'status',             'ok', ...
    'error_code',         '', ...
    'v_pulse_V',          v_pulse, ...
    'v_measured_V',       NaN, ...
    'width_programmed_s', width_s, ...
    'width_measured_s',   NaN, ...
    'width_basis',        '', ...
    'rise_time_s',        NaN, ...
    'fall_time_s',        NaN, ...
    'i_samples_A',        [], ...
    't_samples_s',        [], ...
    'baseline_current_A', NaN, ...
    'peak_current_A',     NaN, ...
    'avg_current_A',      NaN, ...
    'compliance_A',       cfg.pulse.compliance, ...
    'compliance_hit',     false, ...
    'energy_J',           NaN, ...
    'energy_method',      'none', ...
    'timing_source',      engine, ...
    'pulse_index',        inst.PulseCount + 1, ...
    'n_samples_requested', nSamples, ...
    'n_samples_taken',    0, ...
    'label',              label, ...
    'waveform',           []);
if strcmp(engine, 'pmu')
    result.compliance_A = NaN;   % the PMU has no SMU-style compliance
end

% ---- gates -------------------------------------------------------------
check_voltage_limit(v_pulse, cfg);

if ~isfinite(width_s) || width_s <= 0
    error('apply_voltage_pulse:BadWidth', 'width_s must be finite and > 0.');
end

if inst.Aborted
    result.status     = 'aborted';
    result.error_code = 'apply_voltage_pulse:Aborted';
    log_message(inst, 'SAFETY', 'Refusing pulse %+.3f V: session aborted (%s).', ...
        v_pulse, inst.LastError);
    return;
end

if inst.PulseCount >= cfg.safety.max_total_pulses
    emergency_shutdown(inst, sprintf( ...
        'Pulse budget exhausted: cfg.safety.max_total_pulses = %d.', ...
        cfg.safety.max_total_pulses));
    result.status     = 'aborted';
    result.error_code = 'apply_voltage_pulse:PulseBudget';
    return;
end

if inst.elapsed() > cfg.safety.max_test_duration
    emergency_shutdown(inst, sprintf( ...
        'Session exceeded cfg.safety.max_test_duration = %g s.', ...
        cfg.safety.max_test_duration));
    result.status     = 'aborted';
    result.error_code = 'apply_voltage_pulse:Timeout';
    return;
end

if inst.DryRun && ~inst.Simulate
    log_message(inst, 'INFO', ...
        'DRY-RUN: would apply %+.4f V for %.4g s (%s).', v_pulse, width_s, engine);
    result.status = 'dry_run';
    return;
end

inst.PulseCount = inst.PulseCount + 1;
log_message(inst, 'INFO', 'Pulse #%d: %+.4f V, %.4g s, engine = %s.', ...
    inst.PulseCount, v_pulse, width_s, engine);

% ---- execute -----------------------------------------------------------
if inst.Simulate
    result = local_pulse_simulated(inst, cfg, v_pulse, width_s, nSamples, result);
elseif strcmp(engine, 'pmu')
    result = local_pulse_pmu(inst, cfg, v_pulse, width_s, capture, result);
else
    result = local_pulse_pc(inst, cfg, v_pulse, width_s, nSamples, result);
end

% ---- derived quantities -----------------------------------------------
iv = result.i_samples_A(isfinite(result.i_samples_A));
if ~isempty(iv)
    result.peak_current_A = max(abs(iv));
    result.avg_current_A  = mean(abs(iv));
    if isfinite(result.compliance_A)
        result.compliance_hit = result.compliance_hit || ...
            (result.peak_current_A >= 0.99 * result.compliance_A);
    end
end

wForEnergy = result.width_measured_s;
if ~isfinite(wForEnergy); wForEnergy = width_s; end
vForEnergy = result.v_measured_V;
if ~isfinite(vForEnergy); vForEnergy = v_pulse; end
[result.energy_J, eInfo] = estimate_pulse_energy(vForEnergy, result.i_samples_A, ...
    result.t_samples_s, wForEnergy, cfg.pulse.energy_method);
result.energy_method = eInfo.method_used;

% Without any in-pulse current, fall back to the conductance the caller
% measured just before the pulse: E ~ V^2 * G_before * t. This over- or
% under-estimates whenever the state moves during the pulse, which is exactly
% what a write pulse does -- hence it is labelled distinctly and never
% silently mixed with the measured-current estimates.
gBefore = local_opt(opts, 'g_before_S', NaN);
if ~isfinite(result.energy_J) && isfinite(gBefore) && gBefore > 0
    result.energy_J      = vForEnergy^2 * gBefore * wForEnergy;
    result.energy_method = 'conductance_estimate_from_G_before';
    result.avg_current_A = abs(vForEnergy) * gBefore;
end

if result.compliance_hit
    inst.ComplianceHits = inst.ComplianceHits + 1;
    log_message(inst, 'WARN', 'Pulse #%d hit compliance (%.4g A).', ...
        inst.PulseCount, result.compliance_A);
end

% Hard current limit -- this can abort the session.
if ~isempty(iv) && ~strcmp(result.status, 'limit_exceeded')
    [safeOk, safeMsg] = check_current_limit(iv, cfg, inst);
    if ~safeOk
        result.status     = 'limit_exceeded';
        result.error_code = 'check_current_limit:Exceeded';
        log_message(inst, 'SAFETY', '%s', safeMsg);
    end
end

if cfg.pulse.inter_pulse_delay > 0
    pause(cfg.pulse.inter_pulse_delay);
end
end

% ========================================================================
function result = local_pulse_simulated(inst, cfg, v, w, n, result)
comp = cfg.pulse.compliance;
if strcmpi(cfg.pulse.timing_source, 'pmu')
    comp = Inf;                     % no compliance on the pulse path
    result.rise_time_s = cfg.pmu.rise_time;
    result.fall_time_s = cfg.pmu.fall_time;
    result.width_basis = 'simulated';
end
hit = inst.Sim.applyBias(v, w, comp);

% Sample the current the way the real path does: during the pulse.
iS = nan(1, n); tS = nan(1, n);
for k = 1:n
    G = inst.Sim.conductance();
    ik = G * v;
    if abs(ik) > comp
        ik = sign(ik) * comp;
        hit = true;
    end
    iS(k) = ik * (1 + 0.02*randn());
    tS(k) = w * (k - 0.5) / n;
end

result.applied          = true;
result.i_samples_A      = iS;
result.t_samples_s      = tS;
result.n_samples_taken  = n;
result.v_measured_V     = v;
result.width_measured_s = w;      % perfect timing in simulation
result.compliance_hit   = hit && isfinite(comp);
result.status           = 'ok';
pause(min(w, 0.02));              % keep simulated runs from being instant
end

% ========================================================================
function result = local_pulse_pmu(inst, cfg, v, w, capture, result)
%LOCAL_PULSE_PMU  Hardware-timed trapezoid on the 4225-PMU through the RPM.
seq = pmu_build_pulse(cfg, v, w, capture);
result.rise_time_s = seq.rise_time_s;
result.fall_time_s = seq.fall_time_s;

kxci_select_path(inst, cfg, 'pulse');
out = pmu_run_sequence(inst, cfg, seq);
if ~strcmp(out.status, 'ok')
    result.status     = 'instrument_error';
    result.error_code = ['pmu_run_sequence:' out.status];
    log_message(inst, 'ERROR', 'PMU pulse failed (%s): %s', out.status, out.message);
    return;
end
result.applied = true;

% The device current: measured on the force channel, or -- with a sense
% channel on the other terminal -- the current flowing INTO that channel,
% sign-flipped so that +V gives +I in both wirings.
if isempty(out.sense)
    cur = out.force;
    sgn = 1;
else
    cur = out.sense;
    sgn = -1;
end

if strcmp(seq.measure, 'waveform')
    if isempty(out.force)
        result.status     = 'instrument_error';
        result.error_code = 'pmu_run_sequence:NoData';
        return;
    end
    t = out.force(:, 3);
    V = out.force(:, 1);
    I = nan(size(t));
    if size(cur, 1) == numel(t)
        I = sgn * cur(:, 2);
    end
    result.waveform = struct('t_s', t, 'V_V', V, 'I_A', I);
    [fw, info] = pulse_fwhm(t, V);
    result.width_measured_s = fw;
    result.width_basis      = 'pmu_waveform_fwhm';
    result.v_measured_V     = info.v_top;
    onTop = abs(V) >= 0.9 * abs(info.v_top);
    result.i_samples_A = reshape(I(onTop), 1, []);
    result.t_samples_s = reshape(t(onTop), 1, []);
else
    % Spot means arrive in segment order: [baseline], top.
    nExpect = 1 + (seq.baseline_index > 0);
    if size(out.force, 1) < nExpect || size(cur, 1) < nExpect
        result.status     = 'instrument_error';
        result.error_code = 'pmu_run_sequence:MissingPoints';
        log_message(inst, 'ERROR', 'PMU returned %d/%d points, expected %d.', ...
            size(out.force, 1), size(cur, 1), nExpect);
        return;
    end
    top = nExpect;
    result.v_measured_V = out.force(top, 1);
    result.i_samples_A  = sgn * cur(top, 2);
    result.t_samples_s  = out.force(top, 3);
    if seq.baseline_index > 0
        result.baseline_current_A = sgn * cur(1, 2);
    end
    result.width_measured_s = seq.width_fwhm_s;
    result.width_basis      = 'pmu_programmed_fwhm';
end
result.n_samples_taken = numel(result.i_samples_A);

% ---- current checks ----------------------------------------------------
iTop = max(abs(result.i_samples_A));
if ~isempty(iTop) && iTop >= 0.98 * cfg.pmu.current_range_A
    log_message(inst, 'WARN', ...
        ['Pulse #%d: |I| = %.4g A is at the top of the fixed %.4g A PMU range; ' ...
         'the reading is a lower bound.'], inst.PulseCount, iTop, cfg.pmu.current_range_A);
end
if ~isempty(iTop) && iTop > cfg.pmu.max_current_A
    result.status     = 'limit_exceeded';
    result.error_code = 'apply_voltage_pulse:PmuCurrentLimit';
    emergency_shutdown(inst, sprintf( ...
        ['PMU pulse current %.4g A exceeded cfg.pmu.max_current_A = %.4g A. ' ...
         'The PMU has no hardware compliance; this check runs after the pulse.'], ...
        iTop, cfg.pmu.max_current_A));
end
end

% ========================================================================
function result = local_pulse_pc(inst, cfg, v, w, n, result)
%LOCAL_PULSE_PC  Host-timed SMU pulse (DV + pause). >= 20 ms only.
if ~set_voltage(inst, cfg, 0)
    result.status     = 'aborted';
    result.error_code = 'set_voltage:Refused';
    return;
end

iS = nan(1, n); tS = nan(1, n);
t0 = tic;
if ~set_voltage(inst, cfg, v)
    result.status     = 'aborted';
    result.error_code = 'set_voltage:Refused';
    return;
end

for k = 1:n
    if toc(t0) >= w; break; end
    [ik, sinfo] = measure_current(inst, cfg, 1);
    iS(k) = ik;
    tS(k) = toc(t0);
    result.compliance_hit = result.compliance_hit || sinfo.compliance_hit;
    if strcmp(sinfo.status, 'aborted')
        result.status = 'aborted';
        break;
    end
end

remaining = w - toc(t0);
if remaining > 0
    pause(remaining);
end
set_voltage(inst, cfg, 0);
result.width_measured_s = toc(t0);
result.width_basis      = 'host_timer';
result.v_measured_V     = v;

result.i_samples_A     = iS;
result.t_samples_s     = tS;
result.n_samples_taken = sum(isfinite(iS));
result.applied         = ~strcmp(result.status, 'aborted');
end

% ========================================================================
function val = local_opt(opts, name, default)
if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
    val = opts.(name);
else
    val = default;
end
end
