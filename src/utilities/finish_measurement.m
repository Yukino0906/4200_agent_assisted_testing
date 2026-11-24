function result = finish_measurement(run, cfg, inst, result, status, reason)
%FINISH_MEASUREMENT  Common shutdown sequence shared by every run_*_test.
%
%   result = FINISH_MEASUREMENT(run, cfg, inst, result, status, reason)
%       1. brings the output to 0 V and turns it off
%       2. writes the final metadata (completion flag, abort reason, counts)
%       3. writes a human-readable run_summary.txt
%       4. stamps the outcome into the returned result struct
%
%   Inputs:
%       run    - run struct from create_run_directory
%       cfg    - configuration struct
%       inst   - InstrumentSession
%       result - the test's result struct (returned, augmented)
%       status - 'completed' | 'aborted' | 'stopped_by_user' | 'failed'
%       reason - optional char explaining a non-completed status
%
%   Outputs:
%       result - the same struct with .status, .run_id, .run_dir,
%                .elapsed_s, .n_rows and .metadata filled in
%
%   Instrument side effects: output to 0 V and OFF (the session stays open;
%   begin_measurement's guard closes it when appropriate).
%
%   Exceptions: none -- this runs on the failure path too, so every step is
%   individually protected.
%
%   See also BEGIN_MEASUREMENT, SAVE_METADATA.

narginchk(4, 6);
if nargin < 5 || isempty(status); status = 'completed'; end
if nargin < 6; reason = ''; end

try
    safe_output_off(inst);
catch
end

% Buffered command-log lines must reach the log file before the summary is
% written, so the run directory is self-consistent when the test returns.
try
    log_message('flush');
catch
end

nRows = NaN;
try
    if exist(run.data_csv, 'file')
        nRows = local_count_rows(run.data_csv);
    end
catch
end

result.status    = status;
result.run_id    = run.run_id;
result.run_dir   = run.dir;
result.elapsed_s = toc(run.started_tic);
result.n_rows    = nRows;

extra = struct( ...
    'completed',    strcmp(status, 'completed'), ...
    'safety_stop',  ~isempty(inst) && isvalid(inst) && inst.Aborted, ...
    'abort_reason', reason, ...
    'n_rows',       nRows);

% Expose the test's own headline numbers in the metadata so later tests can
% look them up (get_conductance_window reads result_summary).
if isfield(result, 'summary') && isstruct(result.summary) && ...
        ~isempty(fieldnames(result.summary))
    extra.result_summary = result.summary;
end

try
    result.metadata = save_metadata(run, cfg, inst, extra);
catch mErr
    warning('finish_measurement:MetadataFailed', ...
        'Could not write final metadata: %s', mErr.message);
end

% ---- MAT mirror of the CSV --------------------------------------------
if cfg.mode.save_mat
    try
        if exist(run.data_csv, 'file')
            data = readtable(run.data_csv, 'VariableNamingRule', 'preserve');
            save(run.data_mat, 'data', '-v7.3');
        end
    catch sErr
        warning('finish_measurement:MatFailed', ...
            'Could not write the .mat mirror: %s', sErr.message);
    end
end

% ---- summary -----------------------------------------------------------
try
    local_write_summary(run, cfg, inst, result, status, reason);
catch
end

fprintf('\n----------------------------------------------------------------\n');
fprintf(' TEST     : %s\n', run.test_name);
fprintf(' STATUS   : %s%s\n', upper(status), local_paren(reason));
fprintf(' ELAPSED  : %.1f s\n', result.elapsed_s);
fprintf(' ROWS     : %s\n', local_num(nRows));
fprintf(' DATA     : %s\n', run.dir);
fprintf('----------------------------------------------------------------\n\n');
end

% ------------------------------------------------------------------------
function local_write_summary(run, cfg, inst, result, status, reason)
fid = fopen(run.summary, 'w');
if fid < 0; return; end
c = onCleanup(@() fclose(fid));

fprintf(fid, 'RUN SUMMARY\n');
fprintf(fid, '===========\n\n');
fprintf(fid, 'test_name      : %s\n', run.test_name);
fprintf(fid, 'run_id         : %s\n', run.run_id);
fprintf(fid, 'device_id      : %s\n', cfg.device.device_id);
fprintf(fid, 'started        : %s\n', run.started);
fprintf(fid, 'finished       : %s\n', datestr(now, 'yyyy-mm-ddTHH:MM:SS')); %#ok<TNOW1,DATST>
fprintf(fid, 'elapsed_s      : %.2f\n', result.elapsed_s);
fprintf(fid, 'status         : %s\n', status);
if ~isempty(reason)
    fprintf(fid, 'reason         : %s\n', reason);
end
fprintf(fid, 'rows_written   : %s\n', local_num(result.n_rows));
fprintf(fid, '\n');

if ~isempty(inst) && isvalid(inst)
    fprintf(fid, 'INSTRUMENT\n');
    fprintf(fid, 'identity       : %s\n', inst.Identity);
    fprintf(fid, 'resource       : %s\n', inst.Resource);
    fprintf(fid, 'simulated      : %d\n', inst.Simulate);
    fprintf(fid, 'dry_run        : %d\n', inst.DryRun);
    fprintf(fid, 'channel        : %s\n', inst.Channel);
    fprintf(fid, 'commands sent  : %d\n', inst.CommandCount);
    fprintf(fid, 'pulses applied : %d\n', inst.PulseCount);
    fprintf(fid, 'compliance hits: %d\n', inst.ComplianceHits);
    fprintf(fid, 'aborted        : %d\n', inst.Aborted);
    if ~isempty(inst.LastError)
        fprintf(fid, 'last_error     : %s\n', inst.LastError);
    end
    fprintf(fid, '\n');
end

fprintf(fid, 'KEY PARAMETERS\n');
fprintf(fid, 'read_voltage_V    : %+.4f\n', cfg.read.voltage);
fprintf(fid, 'read_averages     : %d\n',    cfg.read.num_average_reads);
fprintf(fid, 'verify_delay_s    : %.4g\n',  cfg.read.delay_after_write);
fprintf(fid, 'dc_compliance_A   : %.4g\n',  cfg.dc.compliance);
fprintf(fid, 'pulse_compliance_A: %.4g\n',  cfg.pulse.compliance);
fprintf(fid, 'max_abs_voltage_V : %.4g\n',  cfg.safety.max_abs_voltage);
fprintf(fid, 'max_abs_current_A : %.4g\n',  cfg.safety.max_abs_current);
fprintf(fid, '\n');

% Test-specific highlights, if the test provided any.
if isfield(result, 'summary') && isstruct(result.summary)
    fprintf(fid, 'RESULTS\n');
    f = fieldnames(result.summary);
    for i = 1:numel(f)
        v = result.summary.(f{i});
        if isnumeric(v) && isscalar(v)
            fprintf(fid, '%-22s: %.6g\n', f{i}, v);
        elseif isnumeric(v)
            fprintf(fid, '%-22s: %s\n', f{i}, mat2str(v, 6));
        elseif ischar(v) || isstring(v)
            fprintf(fid, '%-22s: %s\n', f{i}, char(v));
        elseif islogical(v)
            fprintf(fid, '%-22s: %d\n', f{i}, v);
        end
    end
end
end

% ------------------------------------------------------------------------
function n = local_count_rows(path)
n = 0;
fid = fopen(path, 'r');
if fid < 0; return; end
c = onCleanup(@() fclose(fid));
while ~feof(fid)
    l = fgetl(fid);
    if ischar(l) && ~isempty(strtrim(l)); n = n + 1; end
end
n = max(0, n - 1);   % subtract the header
end

function s = local_num(v)
if isnan(v); s = '<unknown>'; else; s = sprintf('%d', v); end
end

function s = local_paren(r)
if isempty(r); s = ''; else; s = sprintf(' (%s)', r); end
end
