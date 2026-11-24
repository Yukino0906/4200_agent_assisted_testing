function [targets_S, info] = resolve_state_targets(cfg, G_hrs, G_lrs, normalized)
%RESOLVE_STATE_TARGETS  Turn normalised state positions into target conductances.
%
%   [targets_S, info] = RESOLVE_STATE_TARGETS(cfg, G_hrs, G_lrs) maps
%   cfg.initial_states.normalized (values in (0,1)) onto absolute target
%   conductances between the measured HRS and LRS.
%
%   [targets_S, info] = RESOLVE_STATE_TARGETS(cfg, G_hrs, G_lrs, normalized)
%   uses a caller-supplied normalised vector instead.
%
%   Spacing (cfg.initial_states.spacing):
%       'log'    G(x) = G_hrs * (G_lrs/G_hrs)^x        <- default
%       'linear' G(x) = G_hrs + x*(G_lrs - G_hrs)
%
%   Log spacing is the right default: with an on/off ratio near 1e3 the
%   states span three decades, and linear spacing would crowd every point
%   except the last into the bottom decade.
%
%   If HRS/LRS have not been measured yet, cfg.sim values are used as a
%   placeholder and info.using_placeholder is set -- a caller running on real
%   hardware should refuse to continue in that case.
%
%   Inputs:
%       cfg        - configuration struct
%       G_hrs      - [S] measured high-resistance-state conductance
%       G_lrs      - [S] measured low-resistance-state conductance
%       normalized - optional vector in (0,1)
%
%   Outputs:
%       targets_S - [S] row vector of target conductances, ascending
%       info      - struct with .G_hrs, .G_lrs, .ratio, .spacing,
%                   .normalized, .using_placeholder
%
%   Instrument side effects: none.
%
%   Exceptions:
%       resolve_state_targets:BadRange  G_lrs <= G_hrs, or non-positive values
%
%   See also INITIALIZE_TO_STATE, RUN_DC_CYCLE_TEST.

narginchk(3, 4);
if nargin < 4 || isempty(normalized)
    normalized = cfg.initial_states.normalized;
end

usingPlaceholder = false;
if ~isfinite(G_hrs) || ~isfinite(G_lrs) || G_hrs <= 0 || G_lrs <= 0
    G_hrs = cfg.sim.G_hrs;
    G_lrs = cfg.sim.G_lrs;
    usingPlaceholder = true;
    warning('resolve_state_targets:Placeholder', ...
        ['HRS/LRS have not been measured; falling back to the placeholder ' ...
         'range %.3g .. %.3g S from cfg.sim. Run run_dc_cycle_test first.'], ...
        G_hrs, G_lrs);
end

if G_lrs <= G_hrs
    error('resolve_state_targets:BadRange', ...
        ['G_lrs (%.4g S) must exceed G_hrs (%.4g S). ' ...
         'Check the polarity convention and the DC cycling results.'], G_lrs, G_hrs);
end

normalized = normalized(:).';
if any(normalized <= 0) || any(normalized >= 1)
    error('resolve_state_targets:BadRange', ...
        'normalized positions must lie strictly inside (0, 1).');
end

switch lower(cfg.initial_states.spacing)
    case 'log'
        targets_S = G_hrs .* (G_lrs / G_hrs) .^ normalized;
    case 'linear'
        targets_S = G_hrs + normalized .* (G_lrs - G_hrs);
    otherwise
        error('resolve_state_targets:BadRange', ...
            'cfg.initial_states.spacing must be ''log'' or ''linear''.');
end

targets_S = sort(targets_S);

info = struct('G_hrs', G_hrs, 'G_lrs', G_lrs, 'ratio', G_lrs/G_hrs, ...
              'spacing', lower(cfg.initial_states.spacing), ...
              'normalized', normalized, ...
              'using_placeholder', usingPlaceholder);
end
