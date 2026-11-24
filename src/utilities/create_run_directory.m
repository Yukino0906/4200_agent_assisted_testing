function run = create_run_directory(cfg, test_name)
%CREATE_RUN_DIRECTORY  Create a timestamped, self-contained directory for one run.
%
%   run = CREATE_RUN_DIRECTORY(cfg, test_name) creates
%       <cfg.raw_root>\<yyyy-mm-dd_HHMMSS>_device_<id>_<test_name>\
%   and returns a struct of absolute paths. Every measurement function writes
%   exclusively inside this directory so that a crash never mixes runs.
%
%   Inputs:
%       cfg       - configuration struct (default_config)
%       test_name - short test identifier, e.g. 'single_pulse_map'
%
%   Outputs:
%       run - struct with fields:
%           .run_id, .test_name, .device_id, .dir, .started
%           .data_csv, .data_mat, .metadata_json, .metadata_mat
%           .config_snapshot, .instrument_log, .error_log, .summary
%           .log_file (alias of .instrument_log, used by log_message)
%
%   Instrument side effects: none.
%
%   Exceptions:
%       create_run_directory:MkdirFailed  if the directory cannot be created.
%
%   See also SAVE_METADATA, APPEND_MEASUREMENT_ROW, LOG_MESSAGE.

narginchk(2, 2);

deviceId = cfg.device.device_id;
if isempty(deviceId)
    deviceId = 'UNKNOWN';
end
deviceId  = local_sanitize(deviceId);
test_name = local_sanitize(test_name);

stamp  = datestr(now, 'yyyy-mm-dd_HHMMSS'); %#ok<TNOW1,DATST>
runId  = sprintf('%s_device_%s_%s', stamp, deviceId, test_name);
runDir = fullfile(cfg.raw_root, runId);

if ~exist(runDir, 'dir')
    [ok, msg] = mkdir(runDir);
    if ~ok
        error('create_run_directory:MkdirFailed', ...
            'Could not create run directory "%s": %s', runDir, msg);
    end
end

% Make sure the shared metadata/log roots exist too.
for d = {cfg.metadata_root, cfg.log_root}
    if ~exist(d{1}, 'dir'); mkdir(d{1}); end
end

run = struct();
run.run_id          = runId;
run.test_name       = test_name;
run.device_id       = deviceId;
run.dir             = runDir;
run.started         = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
run.started_tic     = tic;
run.data_csv        = fullfile(runDir, 'measurement_data.csv');
run.data_mat        = fullfile(runDir, 'measurement_data.mat');
run.metadata_json   = fullfile(runDir, 'metadata.json');
run.metadata_mat    = fullfile(runDir, 'metadata.mat');
run.config_snapshot = fullfile(runDir, 'config_snapshot.mat');
run.instrument_log  = fullfile(runDir, 'instrument_log.txt');
run.error_log       = fullfile(runDir, 'error_log.txt');
run.summary         = fullfile(runDir, 'run_summary.txt');
run.log_file        = run.instrument_log;   % consumed by log_message()

% Snapshot the configuration immediately: if the run dies later we still know
% exactly which parameters were in force.
save(run.config_snapshot, 'cfg', '-v7.3');
local_write_config_text(fullfile(runDir, 'config_snapshot.txt'), cfg);

log_message(run, 'INFO', 'Run directory created: %s', runDir);
end

% ------------------------------------------------------------------------
function s = local_sanitize(s)
s = char(s);
s = regexprep(s, '[^A-Za-z0-9_\-]', '_');
if isempty(s); s = 'x'; end
end

% ------------------------------------------------------------------------
function local_write_config_text(path, cfg)
% Human-readable flat dump of the config, for quick eyeballing later.
fid = fopen(path, 'w');
if fid < 0; return; end
c = onCleanup(@() fclose(fid));
fprintf(fid, '%% Configuration snapshot written %s\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
local_dump(fid, cfg, 'cfg');
end

function local_dump(fid, s, prefix)
f = fieldnames(s);
for i = 1:numel(f)
    v = s.(f{i});
    name = sprintf('%s.%s', prefix, f{i});
    if isstruct(v) && isscalar(v)
        local_dump(fid, v, name);
    elseif ischar(v)
        fprintf(fid, '%-48s = ''%s''\n', name, v);
    elseif isstring(v)
        fprintf(fid, '%-48s = "%s"\n', name, strjoin(cellstr(v(:))', '", "'));
    elseif iscell(v)
        fprintf(fid, '%-48s = {%s}\n', name, ...
            strjoin(cellfun(@(x) char(string(x)), v(:)', 'UniformOutput', false), ', '));
    elseif islogical(v)
        fprintf(fid, '%-48s = %s\n', name, mat2str(v));
    elseif isnumeric(v)
        fprintf(fid, '%-48s = %s\n', name, mat2str(v, 8));
    else
        fprintf(fid, '%-48s = <%s>\n', name, class(v));
    end
end
end
