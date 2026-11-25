function cfg = apply_user_folder(cfg, user)
%APPLY_USER_FOLDER  Save a run's data under users/<user>/data/ instead of data/.
%
%   cfg = APPLY_USER_FOLDER(cfg, user) records the owner in cfg.user and
%   points cfg.data_root, cfg.raw_root, cfg.metadata_root and cfg.log_root
%   at <kit>/users/<user>/data/... . Every other field is left alone.
%   A device file calls it right after default_config(); see
%   config/device_TEMPLATE.m and users/README.md.
%
%   cfg = APPLY_USER_FOLDER(cfg, '') keeps the kit's own data/ folder, for
%   kit-level runs such as the resistor bring-up.
%
%   A file stored under users/<name>/ must pass that same <name>. The call
%   refuses otherwise, so a copied device file cannot send its data to
%   another user's folder or to the kit's data/.
%
%   Inputs:
%       cfg  - configuration struct (default_config)
%       user - char or string: a folder name under users/, a letter followed
%              by letters, digits or underscores (e.g. 'alice', 'wang_l');
%              '' for a kit-level run
%
%   Outputs:
%       cfg  - the same struct with cfg.user set and the data paths moved
%
%   Instrument side effects: none.
%
%   Exceptions:
%       apply_user_folder:BadName   user is not a valid folder name
%       apply_user_folder:NoFolder  users/<user>/ does not exist
%       apply_user_folder:Mismatch  the calling file lives in another user's folder
%
%   See also SETUP_PATHS, DEFAULT_CONFIG, CREATE_RUN_DIRECTORY.

narginchk(2, 2);
user      = char(user);
usersRoot = fullfile(cfg.project_root, 'users');

% ---- the caller's folder must agree with the owner ------------------------
callerOwner = local_caller_owner(usersRoot);
if ~isempty(callerOwner) && ~strcmp(callerOwner, user)
    error('apply_user_folder:Mismatch', ...
        ['This file is in users/%s/ but names the owner ''%s''. ' ...
         'Use apply_user_folder(cfg, ''%s'').'], callerOwner, user, callerOwner);
end

cfg.user = user;
if isempty(user)
    return;   % kit-level run: keep data/ from default_config
end

if isempty(regexp(user, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
    error('apply_user_folder:BadName', ...
        'User "%s" is not a valid folder name (a letter, then letters, digits or _).', user);
end
userDir = fullfile(usersRoot, user);
if exist(userDir, 'dir') ~= 7
    error('apply_user_folder:NoFolder', ...
        'Folder %s does not exist. Copy users/_TEMPLATE to users/%s first.', userDir, user);
end

cfg.data_root     = fullfile(userDir, 'data');
cfg.raw_root      = fullfile(cfg.data_root, 'raw');
cfg.metadata_root = fullfile(cfg.data_root, 'metadata');
cfg.log_root      = fullfile(cfg.data_root, 'logs');
end

% ========================================================================
function owner = local_caller_owner(usersRoot)
% Name of the users/<name>/ folder holding the file that called
% apply_user_folder, or '' when the caller is elsewhere or the command line.
owner = '';
st = dbstack('-completenames');
% st(1) = this function, st(2) = apply_user_folder, st(3) = its caller
if numel(st) < 3; return; end
callerFile = st(3).file;
prefix     = [usersRoot filesep];
if ~strncmpi(callerFile, prefix, numel(prefix)); return; end
parts = strsplit(callerFile(numel(prefix)+1:end), filesep);
if numel(parts) >= 2          % users/<name>/.../file.m
    owner = parts{1};
end
end
