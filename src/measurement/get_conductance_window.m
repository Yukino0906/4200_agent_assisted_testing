function [G_hrs, G_lrs, source] = get_conductance_window(cfg)
%GET_CONDUCTANCE_WINDOW  Resolve the device's HRS/LRS conductance window.
%
%   [G_hrs, G_lrs, source] = GET_CONDUCTANCE_WINDOW(cfg) returns the window
%   that every pulse test uses to place its target states, resolved in this
%   order of preference:
%
%       1. cfg.device.G_hrs_S / cfg.device.G_lrs_S  -- set them explicitly
%          when you already know the device.
%       2. the most recent dc_cycle_test metadata for THIS device_id in
%          cfg.metadata_root (written by run_dc_cycle_test).
%       3. the cfg.sim placeholder range, with source = 'placeholder'.
%
%   A caller running on real hardware must refuse to continue when
%   source = 'placeholder': targeting states inside a guessed window produces
%   data that cannot be used for model extraction.
%
%   Inputs:
%       cfg - configuration struct
%
%   Outputs:
%       G_hrs  - [S] high-resistance-state conductance
%       G_lrs  - [S] low-resistance-state conductance
%       source - 'config' | 'dc_metadata:<run_id>' | 'placeholder'
%
%   Instrument side effects: none.
%
%   Exceptions: none.
%
%   See also RUN_DC_CYCLE_TEST, RESOLVE_STATE_TARGETS.

narginchk(1, 1);

% ---- 1. explicit configuration -----------------------------------------
if isfinite(cfg.device.G_hrs_S) && isfinite(cfg.device.G_lrs_S) && ...
        cfg.device.G_lrs_S > cfg.device.G_hrs_S && cfg.device.G_hrs_S > 0
    G_hrs  = cfg.device.G_hrs_S;
    G_lrs  = cfg.device.G_lrs_S;
    source = 'config';
    return;
end

% ---- 2. most recent DC cycling metadata for this device -----------------
try
    files = dir(fullfile(cfg.metadata_root, '*dc_cycle_test.json'));
    if ~isempty(files)
        [~, order] = sort([files.datenum], 'descend');
        files = files(order);
        for i = 1:numel(files)
            txt  = fileread(fullfile(files(i).folder, files(i).name));
            meta = jsondecode(txt);
            if ~isfield(meta, 'device') || ...
                    ~strcmp(local_get(meta.device, 'device_id', ''), cfg.device.device_id)
                continue;
            end
            s = local_get(meta, 'result_summary', []);
            if isempty(s); continue; end
            gh = local_get(s, 'G_hrs_S', NaN);
            gl = local_get(s, 'G_lrs_S', NaN);
            if isfinite(gh) && isfinite(gl) && gl > gh && gh > 0
                G_hrs  = gh;
                G_lrs  = gl;
                source = sprintf('dc_metadata:%s', local_get(meta, 'run_id', '?'));
                return;
            end
        end
    end
catch
    % fall through to the placeholder
end

% ---- 3. placeholder ------------------------------------------------------
G_hrs  = cfg.sim.G_hrs;
G_lrs  = cfg.sim.G_lrs;
source = 'placeholder';
end

% ------------------------------------------------------------------------
function v = local_get(s, name, default)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = default;
end
end
