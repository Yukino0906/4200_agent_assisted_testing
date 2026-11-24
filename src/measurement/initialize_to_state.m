function result = initialize_to_state(inst, cfg, target_G, opts)
%INITIALIZE_TO_STATE  Write the device to a target conductance by write-verify.
%
%   result = INITIALIZE_TO_STATE(inst, cfg, target_G) drives the device into
%   the window target_G*(1 +/- cfg.initial_states.tolerance) using a simple
%   coarse/fine write-verify loop, so that repeated single-pulse trials all
%   start from (nominally) the same state. This is a TEST FIXTURE, not an
%   optimised programming algorithm.
%
%   Algorithm (deliberately simple and auditable):
%       repeat until inside the window or a budget is exhausted
%           read G
%           if G < window   -> SET pulse   (positive)
%           if G > window   -> RESET pulse (negative)
%           amplitude/width = coarse while |G-target|/target > fine_threshold,
%                             fine otherwise
%       stop on: success | max_iterations | max_polarity_flips |
%                session abort | pulse budget
%
%   Overshoot is handled naturally: crossing the window flips the polarity and
%   the loop corrects with a weak pulse. cfg.initial_states.max_polarity_flips
%   caps the oscillation so a device that cannot be tuned does not absorb the
%   whole pulse budget.
%
%   EVERY step of the initialisation is returned in result.history and should
%   be written to disk by the caller: a failed or slow initialisation is
%   itself data about the device.
%
%   Inputs:
%       inst     - InstrumentSession
%       cfg      - configuration struct
%       target_G - [S] target conductance
%       opts     - optional struct:
%                    .tolerance      override cfg.initial_states.tolerance
%                    .max_iterations override cfg.initial_states.max_iterations
%                    .verbose        logical (default cfg.mode.verbose)
%
%   Outputs:
%       result - struct:
%           .success          logical
%           .target_G_S, .tolerance
%           .G_final_S, .R_final_Ohm, .relative_error
%           .pulse_count      pulses used
%           .polarity_flips
%           .status           'ok' | 'max_iterations' | 'max_flips' |
%                             'aborted' | 'read_failed' | 'dry_run'
%           .history          struct array, one entry per iteration:
%                             .iteration .G_before_S .polarity .amplitude_V
%                             .width_s .stage ('coarse'/'fine') .G_after_S
%                             .peak_current_A .energy_J
%           .elapsed_s
%
%   Instrument side effects: applies SET/RESET pulses and read biases. Leaves
%   the output at 0 V (still ON).
%
%   Exceptions: none for ordinary failures (reported through .status).
%
%   See also MEASURE_CONDUCTANCE, APPLY_VOLTAGE_PULSE, RUN_SINGLE_PULSE_MAP.

narginchk(3, 4);
if nargin < 4 || isempty(opts); opts = struct(); end

is  = cfg.initial_states;
tol     = local_opt(opts, 'tolerance',      is.tolerance);
maxIter = local_opt(opts, 'max_iterations', is.max_iterations);
verbose = local_opt(opts, 'verbose',        cfg.mode.verbose);

result = struct('success', false, 'target_G_S', target_G, 'tolerance', tol, ...
    'G_final_S', NaN, 'R_final_Ohm', NaN, 'relative_error', NaN, ...
    'pulse_count', 0, 'polarity_flips', 0, 'status', 'ok', ...
    'history', struct([]), 'elapsed_s', 0);

if ~isfinite(target_G) || target_G <= 0
    error('initialize_to_state:BadTarget', 'target_G must be finite and > 0 S.');
end

t0 = tic;
gLo = target_G * (1 - tol);
gHi = target_G * (1 + tol);
lastPolarity = 0;
flips = 0;
resetDumps = 0;
lastRailGap = Inf;   % |log10(G/target)| the last time a rail pulse was chosen

if verbose
    fprintf('  init -> target %.4g S  window [%.4g, %.4g] S\n', target_G, gLo, gHi);
end

for iter = 1:maxIter
    if inst.Aborted
        result.status = 'aborted';
        break;
    end

    % ---- read the present state ---------------------------------------
    configure_instruments(inst, cfg, 'read');
    [G, rinfo] = measure_conductance(inst, cfg);

    if strcmp(rinfo.status, 'dry_run')
        result.status = 'dry_run';
        break;
    end
    if ~isfinite(G)
        result.status = 'read_failed';
        log_message(inst, 'WARN', ...
            'initialize_to_state: read failed (%s) at iteration %d.', rinfo.status, iter);
        break;
    end

    result.G_final_S      = G;
    result.R_final_Ohm    = rinfo.resistance_Ohm;
    result.relative_error = (G - target_G) / target_G;

    % ---- inside the window? -------------------------------------------
    if G >= gLo && G <= gHi
        result.success = true;
        result.status  = 'ok';
        if verbose
            fprintf('  init OK after %d pulse(s): G = %.4g S (%.1f%% from target)\n', ...
                result.pulse_count, G, 100*result.relative_error);
        end
        break;
    end

    % ---- choose the pulse ---------------------------------------------
    % Three tiers, not two. With a gentle step of ~1.13x per pulse, crossing
    % two decades of conductance needs ~38 pulses -- more than any sensible
    % iteration budget, so a target high in the window is simply unreachable
    % and every trial there is lost. The extra "rush" tier uses a strong
    % amplitude while still far below the target and hands over to the gentle
    % tiers for the approach, which is how the pulse-window probe reaches the
    % top of the range in ~25 pulses.
    % isfield guards: a caller may be running against a configuration built
    % before these fields existed, in which case the two-tier behaviour is
    % the correct fallback.
    rushThr = local_field(is, 'rush_threshold',    NaN);
    rushAmp = local_field(is, 'rush_amplitude_set', NaN);
    ratio = G / target_G;                 % <1 means below the target
    if isfinite(rushThr) && isfinite(rushAmp) && ratio < rushThr
        stage = 'rush';
        width = is.coarse_width;
        ampSet   = rushAmp;
        ampReset = is.coarse_amplitude_reset;
    elseif abs(G - target_G) / target_G > is.fine_threshold
        stage = 'coarse';
        width = is.coarse_width;
        ampSet   = is.coarse_amplitude_set;
        ampReset = is.coarse_amplitude_reset;
    else
        stage = 'fine';
        width = is.fine_width;
        ampSet   = is.fine_amplitude_set;
        ampReset = is.fine_amplitude_reset;
    end

    if G < gLo
        polarity  = +1;              % conductance too low -> SET
        amplitude = ampSet;
    else
        polarity  = -1;              % conductance too high -> RESET
        amplitude = ampReset;
    end

    railPol = local_rail_polarity(is);
    if railPol ~= 0
        % ---- rail-then-approach ----------------------------------------
        % For a device where ONE polarity is single-shot (it slams the state
        % to a rail) and the other is gradual, alternate nudging CANNOT
        % converge: every rail pulse overshoots past the target to the end of
        % the range, the gradual direction walks back past it, and the loop
        % oscillates until a limit stops it.
        %
        % So the rail direction is used ONLY to return to its rail, and every
        % approach to the target is made with the gradual direction.
        % Overshooting costs one rail pulse plus a fresh approach -- slower,
        % but it lands.
        %
        % WHICH polarity is the rail is a measured property, not a constant:
        % some devices are abrupt in RESET and gradual in SET, others are
        % exactly the reverse. Set cfg.initial_states.rail_polarity from
        % your own pulse measurements.
        if polarity == railPol
            % The budget counts WASTED rail pulses, not rail pulses. On some
            % devices a single rail pulse reaches the rail; on others the
            % rail direction jumps once and then climbs gradually, so a
            % target high in the window legitimately needs many consecutive
            % rail pulses, and charging each of them would abandon valid
            % targets. A rail pulse is charged only when it failed to move
            % the state CLOSER to the target (in log distance) than the
            % previous rail decision point.
            gap = Inf;
            if isfinite(G) && G > 0
                gap = abs(log10(G / target_G));
            end
            if ~(gap < lastRailGap - 1e-9)
                resetDumps = resetDumps + 1;
                if resetDumps > is.max_reset_dumps
                    result.status = 'max_reset_dumps';
                    log_message(inst, 'WARN', ...
                        ['initialize_to_state: %d WASTED rail pulses (limit %d) ' ...
                         'without approaching %.4g S. Giving up on this state.'], ...
                        resetDumps, is.max_reset_dumps, target_G);
                    break;
                end
            end
            lastRailGap = gap;
            stage = 'rail_pulse';
            if railPol > 0
                amplitude = is.coarse_amplitude_set;
            else
                amplitude = is.coarse_amplitude_reset;
            end
            width = is.coarse_width;
        end
        result.polarity_flips = resetDumps;
    else
        % ---- symmetric bidirectional nudging ---------------------------
        if lastPolarity ~= 0 && polarity ~= lastPolarity
            flips = flips + 1;
            result.polarity_flips = flips;
            if flips > is.max_polarity_flips
                result.status = 'max_flips';
                log_message(inst, 'WARN', ...
                    ['initialize_to_state: %d polarity flips (limit %d) without ' ...
                     'settling on %.4g S. Giving up on this state.'], ...
                    flips, is.max_polarity_flips, target_G);
                break;
            end
        end
        lastPolarity = polarity;
    end

    % ---- apply ---------------------------------------------------------
    configure_instruments(inst, cfg, 'pulse');
    pr = apply_voltage_pulse(inst, cfg, amplitude, width, ...
        struct('label', sprintf('init:%s', stage)));
    result.pulse_count = result.pulse_count + 1;

    if any(strcmp(pr.status, {'aborted', 'limit_exceeded'}))
        result.status = 'aborted';
        break;
    end
    if strcmp(pr.status, 'dry_run')
        result.status = 'dry_run';
        break;
    end

    if cfg.read.delay_after_write > 0
        pause(cfg.read.delay_after_write);
    end

    entry = struct('iteration', iter, 'G_before_S', G, 'polarity', polarity, ...
        'amplitude_V', amplitude, 'width_s', width, 'stage', stage, ...
        'G_after_S', NaN, 'peak_current_A', pr.peak_current_A, ...
        'energy_J', pr.energy_J);
    if isempty(result.history)
        result.history = entry;
    else
        result.history(end+1) = entry;
    end
end

% ---- final verification ------------------------------------------------
if strcmp(result.status, 'ok') && ~result.success
    result.status = 'max_iterations';
end

if result.success && is.settle_time > 0
    pause(is.settle_time);
    configure_instruments(inst, cfg, 'read');
    [Gf, rf] = measure_conductance(inst, cfg);
    if isfinite(Gf)
        result.G_final_S      = Gf;
        result.R_final_Ohm    = rf.resistance_Ohm;
        result.relative_error = (Gf - target_G) / target_G;
        % Relaxation during the settle time can push the state back out.
        result.success = (Gf >= gLo && Gf <= gHi);
        if ~result.success
            result.status = 'drifted_after_settle';
            log_message(inst, 'WARN', ...
                ['State drifted out of the window during the %.3g s settle time: ' ...
                 '%.4g S vs window [%.4g, %.4g] S.'], is.settle_time, Gf, gLo, gHi);
        end
    end
end

if ~isempty(result.history) && isfinite(result.G_final_S)
    result.history(end).G_after_S = result.G_final_S;
end

result.elapsed_s = toc(t0);

if ~result.success && verbose
    fprintf(2, '  init FAILED (%s): target %.4g S, reached %.4g S after %d pulse(s)\n', ...
        result.status, target_G, result.G_final_S, result.pulse_count);
end
end

% ------------------------------------------------------------------------
function p = local_rail_polarity(is)
%LOCAL_RAIL_POLARITY  Which polarity is the single-shot "rail", or 0 for none.
%   Explicit rail_polarity wins. 'reset_then_set' is kept as the historical
%   spelling for rail_polarity = -1 so existing device configs keep working.
p = 0;
if isfield(is, 'rail_polarity') && isfinite(is.rail_polarity) && is.rail_polarity ~= 0
    p = sign(is.rail_polarity);
elseif isfield(is, 'strategy') && strcmpi(is.strategy, 'reset_then_set')
    p = -1;
elseif isfield(is, 'strategy') && strcmpi(is.strategy, 'set_then_reset')
    p = +1;
end
end

% ------------------------------------------------------------------------
function v = local_field(s, name, default)
%LOCAL_FIELD  Read an optional config field without requiring it to exist.
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = default;
end
end

% ------------------------------------------------------------------------
function val = local_opt(opts, name, default)
if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
    val = opts.(name);
else
    val = default;
end
end
