function T = load_run_csv(src, file_name)
%LOAD_RUN_CSV  Read one CSV of a measurement run into a table.
%
%   T = LOAD_RUN_CSV(result)          reads <result.run_dir>/measurement_data.csv
%   T = LOAD_RUN_CSV(run_dir)         same, from a run-directory path
%   T = LOAD_RUN_CSV(src, file_name)  reads another CSV in the run directory,
%                                     e.g. 'cycle_summary.csv'
%
%   Always use this instead of a bare readtable(csv): when some columns are
%   empty (for example every V_set is NaN), readtable's automatic detection
%   mistakes the header line for data and names the columns Var1, Var2, ...
%   Here the first line is always taken as the column names.
%
%   Inputs:
%       src       - result struct with .run_dir, or a run-directory path
%       file_name - optional, default 'measurement_data.csv'
%
%   Outputs:
%       T - table, column names exactly as written by the test
%
%   Instrument side effects: none.
%
%   Exceptions:
%       load_run_csv:NotFound  the file does not exist
%
%   See also APPEND_MEASUREMENT_ROW.

narginchk(1, 2);
if nargin < 2 || isempty(file_name); file_name = 'measurement_data.csv'; end
if isstruct(src); src = src.run_dir; end

csv = fullfile(char(src), file_name);
if exist(csv, 'file') ~= 2
    error('load_run_csv:NotFound', 'No file "%s".', csv);
end

T = readtable(csv, 'NumHeaderLines', 0, 'ReadVariableNames', true, ...
    'Delimiter', ',', 'VariableNamingRule', 'preserve');
end
