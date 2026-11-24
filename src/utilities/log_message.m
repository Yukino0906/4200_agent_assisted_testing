function log_message(ctx, level, fmt, varargin)
%LOG_MESSAGE  Timestamped logging to console and (optionally) a log file.
%
%   LOG_MESSAGE(ctx, level, fmt, ...) formats a message and writes it to the
%   console and, when a log file is available, appends it to that file.
%
%   LOG_MESSAGE('flush') writes every buffered line to disk immediately.
%
%   BUFFERING
%   ---------
%   Instrument traffic is verbose: a single conductance read issues half a
%   dozen KXCI commands. Opening and closing the log file for each of them
%   costs milliseconds per line, which is dead weight in a run that applies
%   thousands of pulses. Lines are therefore buffered per file and flushed
%   when any of these happens:
%
%       - the buffer reaches LOCAL_FLUSH_AT lines
%       - the level is WARN, ERROR or SAFETY (anything worth diagnosing)
%       - LOG_MESSAGE('flush') is called explicitly
%
%   Measurement DATA is never buffered -- append_measurement_row still opens,
%   writes and closes on every row, so a crash costs at most the row in
%   flight. The command log is diagnostic, so trading a little of its
%   tail-end durability for speed is the right call.
%
%   Inputs:
%       ctx   - one of:
%                 []                    console only
%                 char/string           path of a log file to append to
%                 struct with .log_file or .error_log field (run directory)
%                 InstrumentSession     uses its LogFile property
%       level - 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'SAFETY' | 'CMD'
%       fmt   - printf-style format string
%       ...   - format arguments
%
%   Outputs: none.
%
%   Instrument side effects: none.
%
%   Exceptions: never throws for I/O problems; if the log file cannot be
%   opened the message still reaches the console and a one-time warning is
%   issued. This is deliberate: logging must never abort a measurement.
%
%   See also CREATE_RUN_DIRECTORY, APPEND_MEASUREMENT_ROW.

persistent warnedAboutFile bufPaths bufLines

if isempty(bufPaths); bufPaths = {}; bufLines = {}; end

% ---- explicit flush ----------------------------------------------------
if nargin == 1 && (ischar(ctx) || isstring(ctx)) && strcmpi(ctx, 'flush')
    for i = 1:numel(bufPaths)
        local_flush(bufPaths{i}, bufLines{i});
    end
    bufPaths = {}; bufLines = {};
    return;
end

if nargin < 3
    error('log_message:BadArgs', 'Usage: log_message(ctx, level, fmt, ...)');
end

FLUSH_AT = 200;

msg   = sprintf(fmt, varargin{:});
stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'); %#ok<TNOW1,DATST>
line  = sprintf('[%s] %-6s %s', stamp, upper(level), msg);
lvl   = upper(level);

% ---- console -----------------------------------------------------------
switch lvl
    case {'ERROR', 'SAFETY'}
        fprintf(2, '%s\n', line);
    case {'DEBUG', 'CMD'}
        % Command traffic and debug lines are quiet on the console but are
        % still written to the log file, which is where they are useful.
    otherwise
        fprintf('%s\n', line);
end

% ---- resolve log file --------------------------------------------------
logFile = local_resolve_logfile(ctx, level);
if isempty(logFile)
    return;
end

% ---- buffer ------------------------------------------------------------
k = find(strcmp(bufPaths, logFile), 1);
if isempty(k)
    bufPaths{end+1} = logFile;
    bufLines{end+1} = {};
    k = numel(bufPaths);
end
bufLines{k}{end+1} = line;

mustFlush = numel(bufLines{k}) >= FLUSH_AT || ...
            any(strcmp(lvl, {'WARN', 'ERROR', 'SAFETY'}));

if ~mustFlush
    return;
end

ok = local_flush(logFile, bufLines{k});
bufLines{k} = {};

if ~ok && isempty(warnedAboutFile)
    warning('log_message:CannotOpen', ...
        'Cannot append to log file "%s"; logging to console only.', logFile);
    warnedAboutFile = true;
end
end

% ------------------------------------------------------------------------
function ok = local_flush(logFile, lines)
ok = true;
if isempty(lines); return; end
fid = fopen(logFile, 'a');
if fid < 0
    ok = false;
    return;
end
closer = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', lines{:});
end

% ------------------------------------------------------------------------
function logFile = local_resolve_logfile(ctx, level)
logFile = '';
if isempty(ctx)
    return;
end

if ischar(ctx) || (isstring(ctx) && isscalar(ctx))
    logFile = char(ctx);
    return;
end

if isobject(ctx) && isprop(ctx, 'LogFile')
    logFile = ctx.LogFile;
    return;
end

if isstruct(ctx)
    % Errors go to error_log when the run directory provides one.
    if any(strcmpi(level, {'ERROR', 'SAFETY'})) && isfield(ctx, 'error_log')
        logFile = ctx.error_log;
        return;
    end
    if isfield(ctx, 'log_file')
        logFile = ctx.log_file;
    elseif isfield(ctx, 'instrument_log')
        logFile = ctx.instrument_log;
    end
end
end
