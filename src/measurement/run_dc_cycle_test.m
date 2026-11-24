function result = run_dc_cycle_test(cfg, inst)
%RUN_DC_CYCLE_TEST  Bipolar DC I-V cycling and cycle-to-cycle statistics.
%
%   result = RUN_DC_CYCLE_TEST(cfg) runs cfg.dc.num_cycles bipolar sweeps
%
%       0 V -> +cfg.dc.v_positive_max -> 0 V -> cfg.dc.v_negative_max -> 0 V
%
%   recording (t, V, I) at every point, and reads HRS and LRS at
%   cfg.read.voltage after the negative and positive halves of each cycle.
%   It then extracts, per cycle: V_set, V_reset, HRS, LRS and the on/off
%   ratio, and reports their cycle-to-cycle spread.
%
%   THRESHOLD DEFINITION -- READ THIS BEFORE COMPARING WITH THE LITERATURE
%   ---------------------------------------------------------------------
%   A gradually switching device has no current jump to anchor a threshold
%   on: the conductive channel forms and dissolves progressively. V_set and
%   V_reset are therefore defined as the voltages at
%   which the state transition COMPLETES, detected as the point where the
%   outbound and return branches of the hysteresis loop merge again (see
%   LOCAL_CLOSURE_VOLTAGE). These values are systematically HIGHER than the
%   conventional definition based on the ONSET of a current jump. The
%   definition is recorded in every run's metadata and in cycle_summary.csv;
%   always quote it alongside the numbers.
%
%   THIS IS THE TEST THAT DEFINES THE CONDUCTANCE WINDOW. Every later test
%   places its target states between the G_HRS and G_LRS measured here, so
%   run it first on each new device.
%
%   result = RUN_DC_CYCLE_TEST(cfg, inst) reuses an open session.
%
%   Sweep engine: a point-by-point loop on the laptop (SMU user mode: DV,
%   wait cfg.dc.delay, TI). Every point is written to disk as it is measured
%   and passes through the same voltage, compliance and abort checks as any
%   other bias. The 4145-style system-mode sweep is not used: it sweeps one
%   linear staircase per run, so a bipolar loop would need four separate
%   sweeps, and the output level between them has not been verified.
%
%   START WITH cfg.dc.num_cycles = 5. Confirm the polarity, the current
%   magnitude, that compliance behaves, and that the device survived, before
%   raising it to 50 or 100.
%
%   Inputs:
%       cfg  - configuration struct
%       inst - optional InstrumentSession
%
%   Outputs:
%       result - struct with .status, .run_id, .run_dir, .cycles (struct
%                array per cycle) and .summary:
%                   .G_hrs_S, .G_lrs_S, .on_off_ratio
%                   .hrs_cv, .lrs_cv, .n_cycles_completed
%                   .V_set_complete_mean_V,   .V_set_complete_std_V
%                   .V_reset_complete_mean_V, .V_reset_complete_std_V
%                   .set_r_max_mean, .reset_r_max_mean
%                   .n_set_extracted, .n_reset_extracted
%                   .n_set_manual_review, .n_reset_manual_review
%                   .set_confidence_worst, .reset_confidence_worst
%                   .threshold_definition
%
%   CSV columns (measurement_data.csv) -- one row per sweep point:
%       device_id, run_id, cycle_id, segment, point_id, timestamp_s,
%       applied_voltage_V, measured_current_A, compliance_A,
%       estimated_resistance_Ohm, estimated_conductance_S, instrument_status
%
%   CSV columns (cycle_summary.csv) -- one row per cycle:
%       device_id, run_id, cycle_id,
%       V_set_complete_V, V_reset_complete_V, set_r_max, reset_r_max,
%       set_confidence, reset_confidence, set_manual_review,
%       reset_manual_review, set_failure_reason, reset_failure_reason,
%       G_hrs_S, G_lrs_S, on_off_ratio, compliance_A, compliance_hits,
%       set_branch_clamped, reset_branch_clamped, closure_ratio_threshold,
%       search_start_abs_voltage_V, current_noise_floor_A,
%       threshold_definition, instrument_status
%
%   Instrument side effects: sweeps to +/-cfg.dc.v_*_max under
%   cfg.dc.compliance. Returns to 0 V with the output off at the end.
%
%   Exceptions: propagates configuration errors; measurement faults abort the
%   run safely and are reported through result.status.
%
%   See also RUN_LOW_VOLTAGE_IV_TEST, MEASURE_CONDUCTANCE, RESOLVE_STATE_TARGETS.

narginchk(1, 2);
if nargin < 2; inst = []; end

% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
% `guard` must stay in scope for the whole test: releasing it fires the
% onCleanup that forces the output to 0 V and turns it off. Do not
% "simplify" it away.
[run, inst, guard] = begin_measurement(cfg, 'dc_cycle_test', inst); %#ok<ASGLU> %#ok<ASGLU>

result  = struct('cycles', struct([]), 'summary', struct());
status  = 'completed';
reason  = '';

try
    % ---- checkpoint ----------------------------------------------------
    ok = confirm_step(cfg, 'First DC sweep on this device', { ...
        sprintf('device_id      : %s', cfg.device.device_id), ...
        sprintf('sweep          : 0 -> %+.2f V -> 0 -> %+.2f V -> 0', ...
                cfg.dc.v_positive_max, cfg.dc.v_negative_max), ...
        sprintf('step / delay   : %.3f V / %.4g s', cfg.dc.v_step, cfg.dc.delay), ...
        sprintf('compliance     : %.4g A   <-- this protects the device', cfg.dc.compliance), ...
        sprintf('cycles         : %d', cfg.dc.num_cycles), ...
        sprintf('read voltage   : %+.3f V', cfg.read.voltage), ...
        sprintf('mode           : %s', local_mode(inst))});
    if ~ok
        status = 'stopped_by_user';
        reason = 'operator declined the DC sweep checkpoint';
        result = finish_measurement(run, cfg, inst, result, status, reason);
        return;
    end

    % ---- sweep vector --------------------------------------------------
    [V, segment] = local_build_sweep(cfg);
    nPts = numel(V);
    log_message(run, 'INFO', 'Sweep vector: %d points, %+.3f .. %+.3f V.', ...
        nPts, min(V), max(V));

    configure_instruments(inst, cfg, 'dc');

    cycles = struct([]);

    for c = 1:cfg.dc.num_cycles
        if inst.Aborted
            status = 'aborted';
            reason = inst.LastError;
            break;
        end

        fprintf('  DC cycle %d/%d ...\n', c, cfg.dc.num_cycles);
        cyc = struct('cycle_id', c, ...
                     'V_set_complete_V', NaN, 'V_reset_complete_V', NaN, ...
                     'set_r_max', NaN, 'reset_r_max', NaN, ...
                     'set_confidence', 'none', 'reset_confidence', 'none', ...
                     'set_manual_review', true, 'reset_manual_review', true, ...
                     'set_failure_reason', '', 'reset_failure_reason', '', ...
                     'G_hrs_S', NaN, 'G_lrs_S', NaN, 'on_off_ratio', NaN, ...
                     'compliance_hits', 0, 'set_branch_clamped', false, ...
                     'reset_branch_clamped', false, 'status', 'ok');

        [~, Vm, Im, sweepStatus] = local_sweep_pointwise(inst, cfg, V, segment, run, c);
        cyc.status = sweepStatus;

        % ---- HRS / LRS reads --------------------------------------------
        configure_instruments(inst, cfg, 'read');
        if cfg.dc.read_after_cycle
            [Ghrs, hInfo] = measure_conductance(inst, cfg);
            cyc.G_hrs_S = Ghrs;
            local_write_read_row(run, cfg, c, 'read_hrs', hInfo, Ghrs);
        end

        % ---- switching thresholds (hysteresis closure) -------------------
        [sw, cyc.G_lrs_S, clampFlags] = local_extract_switching(Vm, Im, segment, cfg);
        f = fieldnames(sw);
        for fi = 1:numel(f)
            cyc.(f{fi}) = sw.(f{fi});
        end
        cyc.set_branch_clamped   = clampFlags.set_branch;
        cyc.reset_branch_clamped = clampFlags.reset_branch;

        % Both rails must be real positive conductances before a ratio means
        % anything; a negative or zero rail is a failed measurement, not a
        % small one.
        if isfinite(cyc.G_hrs_S) && isfinite(cyc.G_lrs_S) && ...
                cyc.G_hrs_S > 0 && cyc.G_lrs_S > 0
            cyc.on_off_ratio = cyc.G_lrs_S / cyc.G_hrs_S;
        end
        cyc.compliance_hits = sum(abs(Im) >= 0.99 * cfg.dc.compliance);

        fprintf('    V_set(complete)  = %s V  [r_max = %s, %s]%s\n', ...
            local_fmt(cyc.V_set_complete_V), local_fmt(cyc.set_r_max), ...
            cyc.set_confidence, local_why(cyc.set_failure_reason));
        fprintf('    V_reset(complete)= %s V  [r_max = %s, %s]%s\n', ...
            local_fmt(cyc.V_reset_complete_V), local_fmt(cyc.reset_r_max), ...
            cyc.reset_confidence, local_why(cyc.reset_failure_reason));
        fprintf('    HRS = %s S, LRS = %s S, ratio = %s\n', ...
            local_fmt(cyc.G_hrs_S), local_fmt(cyc.G_lrs_S), local_fmt(cyc.on_off_ratio));

        if cyc.set_manual_review
            log_message(run, 'WARN', 'Cycle %d: V_set not extracted -- %s', ...
                c, cyc.set_failure_reason);
        end
        if cyc.reset_manual_review
            log_message(run, 'WARN', 'Cycle %d: V_reset not extracted -- %s', ...
                c, cyc.reset_failure_reason);
        end

        local_write_cycle_row(run, cfg, cyc);

        if isempty(cycles); cycles = cyc; else; cycles(end+1) = cyc; end %#ok<AGROW>
        configure_instruments(inst, cfg, 'dc');
    end

    result.cycles  = cycles;
    result.summary = local_summarize(cycles, cfg);

    if ~isempty(fieldnames(result.summary))
        s = result.summary;
        fprintf('\n  Conductance window from %d cycle(s): G_HRS = %.4g S, G_LRS = %.4g S, ratio = %.1f\n', ...
            s.n_cycles_completed, s.G_hrs_S, s.G_lrs_S, s.on_off_ratio);
        if isfinite(s.G_lrs_S) && s.G_lrs_S > 0
            fprintf('  Suggested cfg.safety.min_resistance: %.4g Ohm (0.5 x measured LRS resistance)\n', ...
                0.5 / s.G_lrs_S);
        else
            fprintf(2, ['  NO VALID LRS MEASURED in any cycle. The device did not reach a\n' ...
                        '  low-resistance state, or the return branch sat in the noise floor.\n' ...
                        '  A too-low compliance is the usual cause -- raise cfg.dc.compliance.\n']);
        end

        fprintf('\n  Switching thresholds (hysteresis closure = TRANSITION COMPLETE):\n');
        fprintf('    V_set  = %s +/- %s V   (%d/%d cycles, r_max %s, worst confidence %s)\n', ...
            local_fmt(s.V_set_complete_mean_V), local_fmt(s.V_set_complete_std_V), ...
            s.n_set_extracted, s.n_cycles_completed, ...
            local_fmt(s.set_r_max_mean), s.set_confidence_worst);
        fprintf('    V_reset= %s +/- %s V   (%d/%d cycles, r_max %s, worst confidence %s)\n', ...
            local_fmt(s.V_reset_complete_mean_V), local_fmt(s.V_reset_complete_std_V), ...
            s.n_reset_extracted, s.n_cycles_completed, ...
            local_fmt(s.reset_r_max_mean), s.reset_confidence_worst);
        fprintf(['    These are TRANSITION-COMPLETION voltages, systematically higher\n' ...
                 '    than a current-jump onset threshold. Quote the definition when\n' ...
                 '    comparing with the literature.\n']);

        if s.n_set_manual_review > 0 || s.n_reset_manual_review > 0
            fprintf(2, '    MANUAL REVIEW: %d SET and %d RESET extraction(s) failed; see cycle_summary.csv.\n', ...
                s.n_set_manual_review, s.n_reset_manual_review);
        end

        if isfinite(s.G_lrs_S) && s.G_lrs_S > 0
            local_warn_if_clamped(run, cfg, s, 'set');
            local_warn_if_clamped(run, cfg, s, 'reset');
        end
    end

catch err
    status = 'failed';
    reason = sprintf('%s: %s', err.identifier, err.message);
    log_message(run, 'ERROR', 'run_dc_cycle_test failed: %s', reason);
    emergency_shutdown(inst, reason);
    finish_measurement(run, cfg, inst, result, status, reason);
    rethrow(err);
end

if inst.Aborted && strcmp(status, 'completed')
    status = 'aborted';
    reason = inst.LastError;
end

result = finish_measurement(run, cfg, inst, result, status, reason);
end

% ========================================================================
function [V, segment] = local_build_sweep(cfg)
%LOCAL_BUILD_SWEEP  0 -> +Vmax -> 0 -> -Vmax -> 0 with segment labels.
s  = abs(cfg.dc.v_step);
vp = cfg.dc.v_positive_max;
vn = cfg.dc.v_negative_max;

up1   = 0:s:vp;                       % 0 -> +Vmax
down1 = (vp - s):-s:0;                % +Vmax -> 0
down2 = -s:-s:vn;                     % 0 -> -Vmax
up2   = (vn + s):s:0;                 % -Vmax -> 0

V = [up1, down1, down2, up2];
segment = [ ...
    repmat({'up_pos'},   1, numel(up1)), ...
    repmat({'down_pos'}, 1, numel(down1)), ...
    repmat({'down_neg'}, 1, numel(down2)), ...
    repmat({'up_neg'},   1, numel(up2))];
end

% ========================================================================
function [t, Vm, Im, status] = local_sweep_pointwise(inst, cfg, V, segment, run, cycleId)
%LOCAL_SWEEP_POINTWISE  Host loop; writes every point to disk as measured.
nPts   = numel(V);
status = 'ok';
t = nan(1, nPts); Vm = V; Im = nan(1, nPts);
t0 = tic;

for k = 1:nPts
    if inst.Aborted
        status = 'aborted';
        break;
    end
    if ~set_voltage(inst, cfg, V(k))
        status = 'dry_run';
        break;
    end
    if cfg.dc.delay > 0
        pause(cfg.dc.delay);
    end
    [ik, minfo] = measure_current(inst, cfg, 1);
    Im(k) = ik;
    t(k)  = toc(t0);

    local_write_one(run, cfg, cycleId, segment{k}, k, t(k), V(k), ik, minfo.status);

    if strcmp(minfo.status, 'aborted')
        status = 'aborted';
        break;
    end
end

set_voltage(inst, cfg, 0);
end

function local_write_one(run, cfg, cycleId, segment, pointId, t, v, i, status)
R = NaN; G = NaN;
if isfinite(i) && i ~= 0 && isfinite(v) && v ~= 0
    R = v / i;
    G = i / v;
end
row = struct( ...
    'device_id',                 cfg.device.device_id, ...
    'run_id',                    run.run_id, ...
    'cycle_id',                  cycleId, ...
    'segment',                   segment, ...
    'point_id',                  pointId, ...
    'timestamp_s',               t, ...
    'applied_voltage_V',         v, ...
    'measured_current_A',        i, ...
    'compliance_A',              cfg.dc.compliance, ...
    'estimated_resistance_Ohm',  R, ...
    'estimated_conductance_S',   G, ...
    'instrument_status',         status);
append_measurement_row(run.data_csv, row);
end

function local_write_cycle_row(run, cfg, cyc)
%LOCAL_WRITE_CYCLE_ROW  One row per cycle in cycle_summary.csv.
%
%   The point-wise CSV has one schema for every row, so the per-cycle
%   extraction results live in their own file rather than being repeated
%   against every sweep point.
path = fullfile(run.dir, 'cycle_summary.csv');
row = struct( ...
    'device_id',                 cfg.device.device_id, ...
    'run_id',                    run.run_id, ...
    'cycle_id',                  cyc.cycle_id, ...
    'V_set_complete_V',          cyc.V_set_complete_V, ...
    'V_reset_complete_V',        cyc.V_reset_complete_V, ...
    'set_r_max',                 cyc.set_r_max, ...
    'reset_r_max',               cyc.reset_r_max, ...
    'set_confidence',            cyc.set_confidence, ...
    'reset_confidence',          cyc.reset_confidence, ...
    'set_manual_review',         cyc.set_manual_review, ...
    'reset_manual_review',       cyc.reset_manual_review, ...
    'set_failure_reason',        cyc.set_failure_reason, ...
    'reset_failure_reason',      cyc.reset_failure_reason, ...
    'G_hrs_S',                   cyc.G_hrs_S, ...
    'G_lrs_S',                   cyc.G_lrs_S, ...
    'on_off_ratio',              cyc.on_off_ratio, ...
    'compliance_A',              cfg.dc.compliance, ...
    'compliance_hits',           cyc.compliance_hits, ...
    'set_branch_clamped',        cyc.set_branch_clamped, ...
    'reset_branch_clamped',      cyc.reset_branch_clamped, ...
    'closure_ratio_threshold',   cfg.dc.closure_ratio_threshold, ...
    'search_start_abs_voltage_V', cfg.dc.search_start_abs_voltage_V, ...
    'current_noise_floor_A',     cfg.dc.current_noise_floor_A, ...
    'threshold_definition',      'hysteresis_closure_transition_complete', ...
    'instrument_status',         cyc.status);
append_measurement_row(path, row);
end

function local_write_read_row(run, cfg, cycleId, tag, info, G)
row = struct( ...
    'device_id',                 cfg.device.device_id, ...
    'run_id',                    run.run_id, ...
    'cycle_id',                  cycleId, ...
    'segment',                   tag, ...
    'point_id',                  0, ...
    'timestamp_s',               info.timestamp_s, ...
    'applied_voltage_V',         info.read_voltage_V, ...
    'measured_current_A',        info.current_A, ...
    'compliance_A',              cfg.read.compliance, ...
    'estimated_resistance_Ohm',  info.resistance_Ohm, ...
    'estimated_conductance_S',   G, ...
    'instrument_status',         info.status);
append_measurement_row(run.data_csv, row);
end

% ========================================================================
function [sw, gLrs, clamped] = local_extract_switching(V, I, segment, cfg)
%LOCAL_EXTRACT_SWITCHING  Switching thresholds and LRS from one bipolar cycle.
%
%   Returns `sw`, a struct with the hysteresis-closure results for both
%   polarities (see LOCAL_CLOSURE_VOLTAGE), plus the LRS conductance and the
%   compliance-clamp flags.
sw = struct( ...
    'V_set_complete_V',    NaN, 'V_reset_complete_V',   NaN, ...
    'set_r_max',           NaN, 'reset_r_max',          NaN, ...
    'set_confidence',      'none', 'reset_confidence',  'none', ...
    'set_manual_review',   true,   'reset_manual_review', true, ...
    'set_failure_reason',  'not evaluated', ...
    'reset_failure_reason','not evaluated');
gLrs = NaN;
clamped = struct('set_branch', false, 'reset_branch', false);

if isempty(V) || isempty(I) || all(~isfinite(I))
    sw.set_failure_reason   = 'no data';
    sw.reset_failure_reason = 'no data';
    return;
end

seg = segment(1:min(numel(segment), numel(V)));
V = V(1:numel(seg)); I = I(1:numel(seg));

% ---- split the sweep into four monotonic, single-polarity branches ------
br = local_split_branches(V, seg);

% ---- V_set: positive outbound vs the positive return that follows it ----
set_res = local_closure_voltage( ...
    V(br.pos_out), I(br.pos_out), V(br.pos_ret), I(br.pos_ret), +1, cfg);

sw.V_set_complete_V   = set_res.voltage_V;
sw.set_r_max          = set_res.r_max;
sw.set_confidence     = set_res.confidence;
sw.set_manual_review  = set_res.manual_review;
sw.set_failure_reason = set_res.failure_reason;

% ---- V_reset: negative outbound vs the negative return that follows it --
reset_res = local_closure_voltage( ...
    V(br.neg_out), I(br.neg_out), V(br.neg_ret), I(br.neg_ret), -1, cfg);

sw.V_reset_complete_V   = reset_res.voltage_V;
sw.reset_r_max          = reset_res.r_max;
sw.reset_confidence     = reset_res.confidence;
sw.reset_manual_review  = reset_res.manual_review;
sw.reset_failure_reason = reset_res.failure_reason;

% ---- compliance clamping, reported alongside the thresholds -------------
if isfinite(cfg.dc.compliance) && cfg.dc.compliance > 0
    lim = 0.99 * cfg.dc.compliance;
    clamped.set_branch   = any(abs(I(br.pos_out)) >= lim) || ...
                           any(abs(I(br.pos_ret)) >= lim);
    clamped.reset_branch = any(abs(I(br.neg_out)) >= lim) || ...
                           any(abs(I(br.neg_ret)) >= lim);
end

% LRS conductance from the return branch (+Vmax -> 0), sampled at the point
% whose |V| is CLOSEST TO THE READ VOLTAGE among points whose current is
% real. Two failure modes shaped this choice:
%   - sampling at the smallest non-zero |V| (0.05 V) floor-limits any
%     megaohm-class device: a 10-100 MOhm LRS gives single-pA currents
%     there, and the "LRS" collapses into the noise even though the state
%     is perfectly measurable at the read bias;
%   - a raw "closest to read voltage" pick can land on V = 0 when v_step is
%     coarse, and on a device that never SET the whole branch sits in the
%     noise, where readings can come back negative. A negative "LRS" and a
%     negative on/off ratio then poison every downstream fit.
% So: restrict to |V| above half a step, current above the configured noise
% floor and G > 0, then take the candidate nearest the read bias. If nothing
% qualifies, LRS stays NaN and the caller says "no LRS measured" instead of
% reporting a confident wrong number.
Vd = V(br.pos_ret); Id = I(br.pos_ret);
ok = isfinite(Vd) & isfinite(Id) & abs(Vd) > 0.5*cfg.dc.v_step & ...
     abs(Id) > cfg.dc.current_noise_floor_A & (Id ./ Vd) > 0;
if any(ok)
    Vd = Vd(ok); Id = Id(ok);
    [~, j] = min(abs(abs(Vd) - abs(cfg.read.voltage)));
    gLrs = Id(j) / Vd(j);
end
end

% ========================================================================
function br = local_split_branches(V, seg)
%LOCAL_SPLIT_BRANCHES  Cut 0 -> +Vmax -> 0 -> -Vmax -> 0 into four branches.
%
%   The split is driven by the MEASURED voltage, not by the programmed
%   segment labels: when the sweep is executed inside the SMU the returned
%   source values are what actually happened, and that is what the closure
%   analysis must be based on. The labels are used only as a fallback.
%
%   Splitting rule: cut into monotonic runs, then cut each run again at its
%   zero crossings. For a bipolar sweep the monotonic runs are
%       up   (0 -> +Vmax)
%       down (+Vmax -> -Vmax)   <- spans BOTH the positive return and the
%       up   (-Vmax -> 0)          negative outbound, hence the zero cut
%
%   Outputs a struct of logical masks:
%       .pos_out  0 -> +Vmax   (rising, V > 0)
%       .pos_ret  +Vmax -> 0   (falling, V > 0)
%       .neg_out  0 -> -Vmax   (falling, V < 0)
%       .neg_ret  -Vmax -> 0   (rising, V < 0)
n = numel(V);
br = struct('pos_out', false(1,n), 'pos_ret', false(1,n), ...
            'neg_out', false(1,n), 'neg_ret', false(1,n));

good = isfinite(V);
if sum(good) < 4
    br = local_branches_from_labels(seg, n);
    return;
end

% Direction of travel at each sample (ignore flat spots by carrying forward).
d = sign(diff(V(:).'));
for k = 2:numel(d)
    if d(k) == 0; d(k) = d(k-1); end
end
if isempty(d) || all(d == 0)
    br = local_branches_from_labels(seg, n);
    return;
end
d = [d(1) d];               % direction attributed to each sample

rising  = d > 0;
falling = d < 0;
positive = V(:).' > 0;
negative = V(:).' < 0;

br.pos_out = good(:).' & rising  & positive;
br.pos_ret = good(:).' & falling & positive;
br.neg_out = good(:).' & falling & negative;
br.neg_ret = good(:).' & rising  & negative;

% If the monotonicity split produced an unusable branch (a truncated or
% non-standard sweep), fall back to the programmed labels.
if nnz(br.pos_out) < 3 || nnz(br.pos_ret) < 3 || ...
   nnz(br.neg_out) < 3 || nnz(br.neg_ret) < 3
    br = local_branches_from_labels(seg, n);
end
end

function br = local_branches_from_labels(seg, n)
br = struct( ...
    'pos_out', local_mask(seg, 'up_pos',   n), ...
    'pos_ret', local_mask(seg, 'down_pos', n), ...
    'neg_out', local_mask(seg, 'down_neg', n), ...
    'neg_ret', local_mask(seg, 'up_neg',   n));
end

function m = local_mask(seg, name, n)
m = false(1, n);
if isempty(seg); return; end
k = strcmp(seg, name);
m(1:numel(k)) = k;
end

% ========================================================================
function res = local_closure_voltage(Vout, Iout, Vret, Iret, polarity, cfg)
%LOCAL_CLOSURE_VOLTAGE  Threshold = the voltage at which the hysteresis loop closes.
%
%   WHAT THIS MEASURES
%   ------------------
%   A GRADUALLY switching device has no current jump to anchor a threshold
%   on: the conductive channel forms and dissolves progressively. Instead
%   the threshold is defined as the voltage at which
%   the state transition has COMPLETED -- observable as the point where the
%   outbound and return branches of the hysteresis loop merge again on their
%   way out to the sweep endpoint.
%
%   The two branches are compared through the symmetric ratio
%
%       r(V) = max( |I_out| / |I_ret| , |I_ret| / |I_out| )  >= 1
%
%   r = 1 means the branches lie on top of each other (loop closed);
%   r >> 1 means the device is in a different state on the way out than on
%   the way back (loop open).
%
%   The threshold is the first voltage, scanning outward from
%   cfg.dc.search_start_abs_voltage_V toward the endpoint, at which
%   r <= cfg.dc.closure_ratio_threshold -- but ONLY if the loop was open at
%   some lower |V| first. "Opened, then closed" is what marks a completed
%   transition; a loop that was never open never switched.
%
%   BEWARE WHEN COMPARING WITH THE LITERATURE
%   -----------------------------------------
%   This is the transition-COMPLETION voltage. It is systematically HIGHER
%   than the conventional threshold defined by the ONSET of a current jump.
%   Always state which definition you used.
%
%   Inputs:
%       Vout, Iout - outbound branch (0 -> +/-Vmax)
%       Vret, Iret - the return branch that follows it (+/-Vmax -> 0)
%       polarity   - +1 to search V > 0 (SET), -1 to search V < 0 (RESET)
%       cfg        - configuration struct; uses cfg.dc.closure_ratio_threshold,
%                    cfg.dc.search_start_abs_voltage_V, cfg.dc.current_noise_floor_A
%
%   Output:
%       res - struct:
%           .voltage_V      [V] closure voltage with its original sign, or NaN
%           .r_max          largest r seen before closure (NaN on failure)
%           .confidence     'high' (r_max >= 10) | 'medium' (>= 4) | 'low' | 'none'
%           .manual_review  logical, true whenever a threshold could not be
%                           extracted
%           .failure_reason char, '' on success
%           .n_points       number of points in the search window

thr   = cfg.dc.closure_ratio_threshold;
vMin  = abs(cfg.dc.search_start_abs_voltage_V);
floorA = abs(cfg.dc.current_noise_floor_A);

res = struct('voltage_V', NaN, 'r_max', NaN, 'confidence', 'none', ...
             'manual_review', true, 'failure_reason', '', 'n_points', 0);

Vout = Vout(:).'; Iout = Iout(:).';
Vret = Vret(:).'; Iret = Iret(:).';

% ---- restrict to the correct polarity and to |V| >= search start --------
% Below the search start the two branches meet trivially, simply because the
% device passes through the same near-zero bias on the way out and back.
keepOut = isfinite(Vout) & isfinite(Iout) & ...
          sign(Vout) == polarity & abs(Vout) >= vMin;
keepRet = isfinite(Vret) & isfinite(Iret) & sign(Vret) == polarity;

if nnz(keepOut) < 2 || nnz(keepRet) < 2
    res.failure_reason = sprintf( ...
        'insufficient data above |V| = %.3g V (outbound %d pts, return %d pts)', ...
        vMin, nnz(keepOut), nnz(keepRet));
    return;
end

Vo = Vout(keepOut); Io = Iout(keepOut);
Vr = Vret(keepRet); Ir = Iret(keepRet);

% Search outward from the start voltage toward the sweep endpoint.
[~, order] = sort(abs(Vo), 'ascend');
Vo = Vo(order); Io = Io(order);

% ---- put the return branch onto the outbound sampling voltages ----------
IretOnVo = local_interp_current(Vr, Ir, Vo, floorA);

valid = isfinite(IretOnVo);
if nnz(valid) < 2
    res.failure_reason = 'return branch does not overlap the outbound branch';
    return;
end
Vo = Vo(valid); Io = Io(valid); IretOnVo = IretOnVo(valid);
res.n_points = numel(Vo);

% ---- symmetric ratio ----------------------------------------------------
% Floor both magnitudes at the noise level so a reading in the noise cannot
% produce an arbitrarily large (meaningless) ratio.
a = max(abs(Io),       floorA);
b = max(abs(IretOnVo), floorA);
r = max(a./b, b./a);

% ---- "opened, then closed" ---------------------------------------------
opened = r > thr;
closed = r <= thr;

kFirstOpen = find(opened, 1, 'first');
if isempty(kFirstOpen)
    res.r_max = max(r);
    res.failure_reason = sprintf( ...
        ['hysteresis never opened: r stayed <= %.3g over the whole search range ' ...
         '(|V| = %.3g .. %.3g V, r_max = %.3g). No switching observed.'], ...
        thr, min(abs(Vo)), max(abs(Vo)), res.r_max);
    return;
end

kClose = kFirstOpen - 1 + find(closed(kFirstOpen:end), 1, 'first');
if isempty(kClose)
    res.r_max = max(r(kFirstOpen:end));
    res.failure_reason = sprintf( ...
        ['hysteresis opened (r_max = %.3g) but never re-closed by the sweep ' ...
         'endpoint |V| = %.3g V. The transition did not complete within this ' ...
         'sweep range -- extend cfg.dc.v_%s_max.'], ...
        res.r_max, max(abs(Vo)), local_polarity_word(polarity));
    return;
end

% ---- success ------------------------------------------------------------
res.voltage_V     = Vo(kClose);            % original polarity preserved
res.r_max         = max(r(1:kClose-1));    % peak opening before closure
res.manual_review = false;
res.failure_reason = '';

if res.r_max >= 10
    res.confidence = 'high';
elseif res.r_max >= 4
    res.confidence = 'medium';
else
    res.confidence = 'low';
end
end

% ------------------------------------------------------------------------
function w = local_polarity_word(polarity)
if polarity > 0; w = 'positive'; else; w = 'negative'; end
end

% ------------------------------------------------------------------------
function Iq = local_interp_current(Vsrc, Isrc, Vq, floorA)
%LOCAL_INTERP_CURRENT  Interpolate |I| onto query voltages, log-linear hybrid.
%
%   Between two samples that are both above the noise floor the current is
%   interpolated in log10|I|, because RRAM currents span decades and linear
%   interpolation across a decade is badly wrong. If either bracketing sample
%   sits at or below the noise floor its logarithm is meaningless, so a plain
%   linear interpolation of the current is used for that interval instead.
%
%   Returns MAGNITUDES: the ratio test compares |I| only. The sign of the
%   voltage is preserved by the caller.
Vsrc = reshape(Vsrc, 1, []);
Isrc = reshape(Isrc, 1, []);
[Vs, idx] = sort(Vsrc, 2, 'ascend');
Is = Isrc(idx);

% Collapse duplicate voltages (an SMU can return the same source value twice).
keep = [true, diff(Vs) > 0];
Vs = Vs(keep); Is = Is(keep);

Iq = nan(1, numel(Vq));
if numel(Vs) < 2
    return;
end

for k = 1:numel(Vq)
    v = Vq(k);
    if v < Vs(1) || v > Vs(end)
        continue;                       % outside the return branch: no value
    end
    j = find(Vs <= v, 1, 'last');
    if j >= numel(Vs)
        Iq(k) = abs(Is(end));
        continue;
    end
    v1 = Vs(j);   v2 = Vs(j+1);
    a1 = abs(Is(j)); a2 = abs(Is(j+1));
    if v2 == v1
        Iq(k) = a1;
        continue;
    end
    f = (v - v1) / (v2 - v1);
    if a1 > floorA && a2 > floorA
        Iq(k) = 10 ^ (log10(a1) + f * (log10(a2) - log10(a1)));
    else
        Iq(k) = a1 + f * (a2 - a1);
    end
end
end

% ========================================================================
function s = local_summarize(cycles, cfg)
s = struct();
if isempty(cycles); return; end

vset  = [cycles.V_set_complete_V];
vrst  = [cycles.V_reset_complete_V];
hrs   = [cycles.G_hrs_S];
lrs   = [cycles.G_lrs_S];
ratio = [cycles.on_off_ratio];

s.n_cycles_completed = numel(cycles);
% Average only over cycles that produced a physically valid rail. Averaging a
% noise-floor artefact in with real values silently corrupts the window that
% every later test places its target states inside.
s.G_hrs_S            = local_nanmean(hrs(hrs > 0));
s.G_lrs_S            = local_nanmean(lrs(lrs > 0));
s.on_off_ratio       = local_nanmean(ratio(ratio > 0));
s.n_cycles_with_lrs  = sum(isfinite(lrs) & lrs > 0);
s.hrs_cv             = local_nanstd(hrs) / abs(local_nanmean(hrs));
s.lrs_cv             = local_nanstd(lrs) / abs(local_nanmean(lrs));
s.total_compliance_hits = sum([cycles.compliance_hits]);

% ---- hysteresis-closure extraction, aggregated -------------------------
% The threshold definition travels WITH the numbers. These voltages are the
% transition-COMPLETION voltages and are systematically higher than the
% conventional current-jump onset definition; anyone comparing them with the
% literature has to know which definition produced them.
s.threshold_definition = ['hysteresis closure: voltage at which the outbound ' ...
    'and return branches merge (r <= closure_ratio_threshold) after having ' ...
    'been open. This is the STATE TRANSITION COMPLETION voltage, which is ' ...
    'systematically HIGHER than a current-jump onset threshold. State the ' ...
    'definition when comparing with published values.'];
s.V_set_complete_mean_V   = local_nanmean(vset);
s.V_set_complete_std_V    = local_nanstd(vset);
s.V_reset_complete_mean_V = local_nanmean(vrst);
s.V_reset_complete_std_V  = local_nanstd(vrst);
s.set_r_max_mean          = local_nanmean([cycles.set_r_max]);
s.reset_r_max_mean        = local_nanmean([cycles.reset_r_max]);
s.n_set_extracted         = sum(isfinite(vset));
s.n_reset_extracted       = sum(isfinite(vrst));
s.n_set_manual_review     = sum([cycles.set_manual_review]);
s.n_reset_manual_review   = sum([cycles.reset_manual_review]);
s.set_confidence_worst    = local_worst_confidence({cycles.set_confidence});
s.reset_confidence_worst  = local_worst_confidence({cycles.reset_confidence});
s.closure_ratio_threshold    = cfg.dc.closure_ratio_threshold;
s.search_start_abs_voltage_V = cfg.dc.search_start_abs_voltage_V;
s.current_noise_floor_A      = cfg.dc.current_noise_floor_A;

% How often each branch was pinned at the compliance limit. When a branch is
% clamped both curves can sit on the limit together, which makes the loop look
% closed for a reason that has nothing to do with the device -- the caller
% warns about this.
s.set_branch_clamped_fraction   = mean([cycles.set_branch_clamped]);
s.reset_branch_clamped_fraction = mean([cycles.reset_branch_clamped]);
end

function local_warn_if_clamped(run, cfg, s, which)
%LOCAL_WARN_IF_CLAMPED  Flag a branch that spent most of the sweep in compliance.
%
%   Closure analysis compares the outbound and return branches. If BOTH are
%   pinned at the compliance limit over part of the sweep they coincide there
%   for a reason that has nothing to do with the device, so the loop can look
%   closed early and the threshold can be reported too low.
frac = s.([which '_branch_clamped_fraction']);
if ~(frac > 0.5)
    return;
end
msg = sprintf( ...
    ['The %s branch was current-limited in %.0f%% of cycles (compliance = %.4g A, ' ...
     'LRS resistance = %.4g Ohm). Where both the outbound and return branches sit ' ...
     'at the limit they coincide for instrumental reasons, so the hysteresis loop ' ...
     'can appear closed before the device has finished switching and V_%s may be ' ...
     'reported too low. To measure it properly, raise cfg.dc.compliance above the ' ...
     'LRS current at the threshold (and re-confirm cfg.safety.compliance_confirmed).'], ...
    upper(which), 100*frac, cfg.dc.compliance, 1/s.G_lrs_S, which);
fprintf(2, '\n  NOTE: %s\n', msg);
log_message(run, 'WARN', '%s', msg);
end

function c = local_worst_confidence(list)
%LOCAL_WORST_CONFIDENCE  Lowest confidence seen across the cycles.
order = {'none', 'low', 'medium', 'high'};
best = numel(order);
for i = 1:numel(list)
    k = find(strcmp(order, list{i}), 1);
    if isempty(k); k = 1; end
    best = min(best, k);
end
c = order{best};
end

function m = local_nanmean(x)
x = x(isfinite(x));
if isempty(x); m = NaN; else; m = mean(x); end
end

function s = local_nanstd(x)
x = x(isfinite(x));
if numel(x) < 2; s = NaN; else; s = std(x); end
end

function s = local_fmt(v)
if isfinite(v); s = sprintf('%.4g', v); else; s = 'n/a'; end
end

function s = local_why(reason)
if isempty(reason); s = ''; else; s = sprintf('  <- %s', reason); end
end

function m = local_mode(inst)
if inst.Simulate
    m = 'SIMULATED';
elseif inst.DryRun
    m = 'REAL instrument, DRY-RUN (no output)';
else
    m = 'REAL instrument, LIVE';
end
end
