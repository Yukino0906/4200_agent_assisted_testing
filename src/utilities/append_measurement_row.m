function append_measurement_row(csv_path, row)
%APPEND_MEASUREMENT_ROW  Crash-safe incremental append of one data row to CSV.
%
%   APPEND_MEASUREMENT_ROW(csv_path, row) appends a single measurement record
%   to a CSV file, writing the header line automatically on first use. The
%   file is opened, written and closed on every call, so all data acquired
%   before a crash / Ctrl-C / power loss survives on disk.
%
%   Inputs:
%       csv_path - absolute path to the CSV file
%       row      - scalar struct. Field names become column headers (they
%                  should already carry units, e.g. pulse_voltage_V).
%                  Values may be numeric scalar, logical, char, or string.
%                  NaN / [] are written as empty cells.
%                  Struct arrays are written as multiple rows.
%
%   Outputs: none.
%
%   Instrument side effects: none.
%
%   Exceptions:
%       append_measurement_row:OpenFailed   file cannot be opened for append
%       append_measurement_row:FieldMismatch
%           the row's fields differ from the header already on disk. This is
%           an error, not a warning: silently shifting columns would corrupt
%           the dataset used for model extraction.
%
%   See also CREATE_RUN_DIRECTORY, SAVE_METADATA.

narginchk(2, 2);
if ~isstruct(row)
    error('append_measurement_row:BadArgs', 'row must be a struct.');
end
if isempty(row)
    return;
end

names   = fieldnames(row);
newFile = ~exist(csv_path, 'file');

if ~newFile
    existing = local_read_header(csv_path);
    if ~isempty(existing) && ~isequal(existing(:), names(:))
        error('append_measurement_row:FieldMismatch', ...
            ['Row fields do not match the existing header in "%s".\n' ...
             '  header: %s\n  row   : %s'], csv_path, ...
            strjoin(existing(:)', ','), strjoin(names(:)', ','));
    end
end

fid = fopen(csv_path, 'a');
if fid < 0
    error('append_measurement_row:OpenFailed', ...
        'Cannot open "%s" for append.', csv_path);
end
closer = onCleanup(@() fclose(fid));

if newFile
    fprintf(fid, '%s\n', strjoin(names(:)', ','));
end

for k = 1:numel(row)
    parts = cell(1, numel(names));
    for i = 1:numel(names)
        parts{i} = local_format(row(k).(names{i}));
    end
    fprintf(fid, '%s\n', strjoin(parts, ','));
end
end

% ------------------------------------------------------------------------
function names = local_read_header(csv_path)
names = {};
fid = fopen(csv_path, 'r');
if fid < 0; return; end
c = onCleanup(@() fclose(fid));
hdr = fgetl(fid);
if ~ischar(hdr); return; end
names = strtrim(strsplit(hdr, ','));
names = names(:);
end

% ------------------------------------------------------------------------
function s = local_format(v)
% Format one value as a CSV field. Full double precision is preserved
% (%.17g) for currents and conductances that later feed model fitting.
if isempty(v)
    s = '';
elseif islogical(v)
    s = sprintf('%d', v(1));
elseif isnumeric(v)
    if ~isscalar(v)
        v = v(1);   % defensive: only scalars belong in a flat CSV
    end
    if isnan(v)
        s = '';
    elseif v == fix(v) && abs(v) < 1e15
        s = sprintf('%d', v);
    else
        s = sprintf('%.17g', v);
    end
elseif ischar(v) || isstring(v)
    s = char(v);
    s = strrep(s, '"', '''');
    s = regexprep(s, '[\r\n]', ' ');
    if contains(s, ',')
        s = ['"' s '"'];
    end
else
    s = ['<' class(v) '>'];
end
end
