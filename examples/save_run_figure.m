function file = save_run_figure(fig, result, name)
%SAVE_RUN_FIGURE  Save a figure as PNG inside the run directory it belongs to.
%
%   file = SAVE_RUN_FIGURE(fig, result, name) writes <result.run_dir>/<name>.png
%   so that the plot travels with the data it was made from.
%
%   Inputs:
%       fig    - figure handle
%       result - result struct returned by a run_*_test (needs .run_dir)
%       name   - file name without extension
%
%   Outputs:
%       file - full path of the PNG
%
%   Instrument side effects: none.
%
%   See also LOAD_RUN_CSV.

narginchk(3, 3);
file = fullfile(result.run_dir, [char(name) '.png']);
exportgraphics(fig, file, 'Resolution', 150);
fprintf('  figure saved: %s\n', file);
end
