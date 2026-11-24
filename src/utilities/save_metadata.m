function meta = save_metadata(run, cfg, inst, extra)
%SAVE_METADATA  Write the complete provenance record for one run.
%
%   meta = SAVE_METADATA(run, cfg, inst, extra) collects everything needed to
%   reproduce a measurement (environment, instrument identity, configuration,
%   device information, completion status) and writes it to
%       <run.dir>\metadata.json   (human readable / Python readable)
%       <run.dir>\metadata.mat    (lossless MATLAB copy)
%   It also mirrors the JSON into cfg.metadata_root for easy indexing.
%
%   Call it TWICE: once right after create_run_directory (so a crashed run
%   still has metadata) and once at the end with extra.completed = true.
%
%   Inputs:
%       run   - struct from create_run_directory()
%       cfg   - configuration struct
%       inst  - InstrumentSession (may be [] before connection)
%       extra - optional struct of additional fields to merge in, e.g.
%                 .completed          logical
%                 .safety_stop        logical
%                 .abort_reason       char
%                 .n_rows             numeric
%                 .notes              char
%
%   Outputs:
%       meta - the assembled metadata struct.
%
%   Instrument side effects: none (reads cached identity from inst).
%
%   Exceptions: JSON encoding failures are caught and reported as warnings;
%   the .mat file is always written so no provenance is ever lost.
%
%   See also CREATE_RUN_DIRECTORY, VALIDATE_CONFIG.

narginchk(2, 4);
if nargin < 3; inst  = []; end
if nargin < 4; extra = struct(); end

meta = struct();

% ---- run identity ------------------------------------------------------
meta.test_name  = run.test_name;
meta.run_id     = run.run_id;
meta.start_time = run.started;
meta.end_time   = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
if isfield(run, 'started_tic')
    meta.elapsed_s = toc(run.started_tic);
else
    meta.elapsed_s = NaN;
end
meta.run_directory = run.dir;

% ---- environment -------------------------------------------------------
meta.matlab_version   = version();
meta.matlab_release   = local_release();
meta.computer         = computer();
meta.os               = local_os();
meta.user             = local_user();
meta.code_version     = local_code_version(cfg);

% ---- instrument --------------------------------------------------------
if isempty(inst)
    meta.instrument = struct('connected', false, ...
                             'resource', char(cfg.instrument.resource), ...
                             'model_configured', cfg.instrument.model);
else
    meta.instrument = struct( ...
        'connected',        logical(inst.Connected), ...
        'simulated',        logical(inst.Simulate), ...
        'dry_run',          logical(inst.DryRun), ...
        'resource',         char(inst.Resource), ...
        'idn',              char(inst.Identity), ...
        'model',            char(inst.Model), ...
        'serial',           char(inst.Serial), ...
        'firmware',         char(inst.Firmware), ...
        'channel',          char(inst.Channel), ...
        'ground_channel',   char(inst.GroundChannel), ...
        'pmu_force_channel', inst.PmuForce, ...
        'pmu_sense_channel', inst.PmuSense, ...
        'language',         'KXCI', ...
        'interface',        char(inst.Transport), ...
        'total_pulses',     inst.PulseCount, ...
        'compliance_hits',  inst.ComplianceHits, ...
        'aborted',          logical(inst.Aborted), ...
        'last_error',       char(inst.LastError));
end

% ---- device ------------------------------------------------------------
meta.device = cfg.device;

% ---- key measurement parameters (duplicated for quick lookup) ----------
meta.key_parameters = struct( ...
    'read_voltage_V',         cfg.read.voltage, ...
    'read_num_average',       cfg.read.num_average_reads, ...
    'verify_delay_s',         cfg.read.delay_after_write, ...
    'dc_compliance_A',        cfg.dc.compliance, ...
    'pulse_compliance_A',     cfg.pulse.compliance, ...
    'read_compliance_A',      cfg.read.compliance, ...
    'pulse_rise_time_s',      cfg.pulse.rise_time, ...
    'pulse_fall_time_s',      cfg.pulse.fall_time, ...
    'pulse_timing_source',    cfg.pulse.timing_source, ...
    'pulse_energy_method',    cfg.pulse.energy_method, ...
    'pmu_rise_time_s',        cfg.pmu.rise_time, ...
    'pmu_fall_time_s',        cfg.pmu.fall_time, ...
    'pmu_current_range_A',    cfg.pmu.current_range_A, ...
    'pmu_max_current_A',      cfg.pmu.max_current_A, ...
    'pmu_series_resistance_Ohm', cfg.pmu.series_resistance_Ohm, ...
    'pmu_width_definition',   'FWHM of the programmed trapezoid', ...
    'return_path',            cfg.instrument.return_path, ...
    'max_abs_voltage_V',      cfg.safety.max_abs_voltage, ...
    'max_abs_current_A',      cfg.safety.max_abs_current, ...
    'min_resistance_Ohm',     cfg.safety.min_resistance, ...
    'polarity_convention',    '+V = SET, -V = RESET', ...
    'closure_ratio_threshold',     cfg.dc.closure_ratio_threshold, ...
    'search_start_abs_voltage_V',  cfg.dc.search_start_abs_voltage_V, ...
    'current_noise_floor_A',       cfg.dc.current_noise_floor_A, ...
    'switching_threshold_definition', local_threshold_note());

% ---- status ------------------------------------------------------------
meta.completed    = false;
meta.safety_stop  = false;
meta.abort_reason = '';
meta.n_rows       = NaN;
meta.notes        = cfg.device.notes;

f = fieldnames(extra);
for i = 1:numel(f)
    meta.(f{i}) = extra.(f{i});
end

% ---- full configuration ------------------------------------------------
meta.config = cfg;

% ---- write -------------------------------------------------------------
save(run.metadata_mat, 'meta', '-v7.3');

try
    txt = jsonencode(local_jsonsafe(meta), 'PrettyPrint', true);
catch
    try
        txt = jsonencode(local_jsonsafe(meta));
    catch encErr
        warning('save_metadata:JsonFailed', ...
            'Could not encode metadata as JSON (%s); .mat file was still written.', ...
            encErr.message);
        return;
    end
end

local_write_text(run.metadata_json, txt);
local_write_text(fullfile(cfg.metadata_root, [run.run_id '.json']), txt);
end

% ------------------------------------------------------------------------
function s = local_threshold_note()
%LOCAL_THRESHOLD_NOTE  Definition of V_set / V_reset, carried in every run.
%
%   This travels with the data on purpose. The numbers are meaningless -- and
%   quietly wrong when compared with published values -- without it.
s = ['V_set / V_reset are extracted as STATE TRANSITION COMPLETION voltages ' ...
     'by hysteresis closure: the voltage at which the outbound and return ' ...
     'branches of the bipolar sweep merge again (symmetric current ratio ' ...
     'r <= closure_ratio_threshold), having first been open at lower |V|. ' ...
     'This suits a gradually switching device whose conductive channel forms and ' ...
     'dissolves progressively and therefore shows no current jump. ' ...
     'THESE VALUES ARE SYSTEMATICALLY HIGHER than thresholds defined by the ' ...
     'ONSET of a current jump. When comparing with the literature, state ' ...
     'which definition was used.'];
end

% ------------------------------------------------------------------------
function local_write_text(path, txt)
fid = fopen(path, 'w');
if fid < 0
    warning('save_metadata:WriteFailed', 'Cannot write "%s".', path);
    return;
end
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s', txt);
end

% ------------------------------------------------------------------------
function s = local_jsonsafe(s)
% jsonencode chokes on string arrays inside nested structs and on function
% handles; convert everything questionable to plain char / cellstr.
if isstruct(s) && isscalar(s)
    f = fieldnames(s);
    for i = 1:numel(f)
        s.(f{i}) = local_jsonsafe(s.(f{i}));
    end
elseif isstring(s)
    if isscalar(s); s = char(s); else; s = cellstr(s(:)'); end
elseif iscell(s)
    for i = 1:numel(s); s{i} = local_jsonsafe(s{i}); end
elseif isa(s, 'function_handle')
    s = func2str(s);
elseif isobject(s) && ~isnumeric(s) && ~islogical(s) && ~ischar(s)
    s = class(s);
end
end

% ------------------------------------------------------------------------
function r = local_release()
% matlabRelease exists from R2020b; ver is the fallback for older installs,
% which this project still needs to tolerate (visadev requires R2021a, but a
% dry run can legitimately be done on an older machine).
try
    r = char(matlabRelease().Release);
    return;
catch
end
try
    v = ver('MATLAB'); %#ok<VERMATLAB>
    r = v(1).Release;
catch
    r = 'unknown';
end
end

function o = local_os()
try
    if ispc
        [st, o] = system('ver');
        if st ~= 0; o = 'Windows (unknown build)'; end
    elseif ismac
        [~, o] = system('sw_vers -productVersion');
    else
        [~, o] = system('uname -a');
    end
    o = strtrim(regexprep(o, '[\r\n]+', ' '));
catch
    o = computer();
end
end

function u = local_user()
u = getenv('USERNAME');
if isempty(u); u = getenv('USER'); end
if isempty(u); u = 'unknown'; end
end

function v = local_code_version(cfg)
% Prefer a git commit if the project is under version control; otherwise
% fall back to a hash of the source tree's modification times.
v = 'not-versioned';
try
    old = pwd;
    c = onCleanup(@() cd(old));
    cd(cfg.project_root);
    [st, out] = system('git rev-parse --short HEAD');
    if st == 0 && ~isempty(strtrim(out))
        v = ['git:' strtrim(out)];
        [~, dirty] = system('git status --porcelain');
        if ~isempty(strtrim(dirty)); v = [v '+dirty']; end
        return;
    end
catch
    % fall through
end
try
    d = dir(fullfile(cfg.project_root, 'src', '**', '*.m'));
    if ~isempty(d)
        v = sprintf('srcmtime:%s(%d files)', ...
            datestr(max([d.datenum]), 'yyyymmdd-HHMMSS'), numel(d)); %#ok<DATST>
    end
catch
end
end
