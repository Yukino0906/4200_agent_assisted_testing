function root = setup_paths(user)
%SETUP_PATHS  Put every kit folder (and one user's folders) on the MATLAB path. Run this first.
%
%   root = SETUP_PATHS() adds config/, src/ (recursively), examples/ and
%   tests/ to the MATLAB search path and returns the kit root. It does NOT
%   save the path, so it leaves the user's environment untouched between
%   sessions -- call it once per MATLAB session.
%
%   root = SETUP_PATHS(user) also adds that user's own folders,
%   users/<user>/config, users/<user>/tests and users/<user>/analysis (each
%   with its subfolders), and removes any other user's folders left on the
%   path by an earlier call. The kit's folders stay in front: when a user
%   file has the same name as a kit function, the kit's version runs and a
%   warning names the clash. Rename the user file.
%
%   Usage:
%       cd <path to>\4200A_agent_kit
%       setup_paths              % kit only
%       setup_paths('alice')     % kit + users/alice
%       test_dry_run             % simulation only, no instrument
%
%   Inputs:
%       user - optional char, folder name under users/ (see users/README.md)
%   Outputs: root - char, absolute kit root.
%   Instrument side effects: none.
%   Exceptions:
%       setup_paths:MissingFolder if a required folder is absent.
%       setup_paths:BadUser       if user is not a valid name or users/<user>/ is absent.

if nargin < 1; user = ''; end
user = char(user);
root = fileparts(mfilename('fullpath'));

folders = { ...
    fullfile(root, 'config'), ...
    fullfile(root, 'src'), ...
    fullfile(root, 'examples'), ...
    fullfile(root, 'tests')};

for i = 1:numel(folders)
    if exist(folders{i}, 'dir') ~= 7
        error('setup_paths:MissingFolder', ...
            'Required folder "%s" does not exist.', folders{i});
    end
end

% ---- user folders -------------------------------------------------------
% Drop every users/* entry first, so switching user in one MATLAB session
% never leaves the previous user's device files reachable.
usersRoot = fullfile(root, 'users');
entries   = strsplit(path, pathsep);
stale     = entries(strncmpi(entries, [usersRoot filesep], numel(usersRoot) + 1));
if ~isempty(stale)
    rmpath(stale{:});
end

userFolders = {};
if ~isempty(user)
    if isempty(regexp(user, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
        error('setup_paths:BadUser', ...
            'User "%s" is not a valid folder name (a letter, then letters, digits or _).', user);
    end
    userDir = fullfile(usersRoot, user);
    if exist(userDir, 'dir') ~= 7
        error('setup_paths:BadUser', ...
            'Folder %s does not exist. Copy users/_TEMPLATE to users/%s first.', userDir, user);
    end
    for sub = {'config', 'tests', 'analysis'}
        d = fullfile(userDir, sub{1});
        if exist(d, 'dir') ~= 7; mkdir(d); end
        userFolders = [userFolders, local_split(genpath(d))]; %#ok<AGROW>
    end
    % Added before the kit folders, so the kit ends up in front of them.
    addpath(userFolders{:});
end

% ---- kit folders --------------------------------------------------------
addpath(fullfile(root, 'config'));
addpath(genpath(fullfile(root, 'src')));
addpath(fullfile(root, 'examples'));
addpath(fullfile(root, 'tests'));

if ~isempty(userFolders)
    kitFolders = [{root}, folders([1 3 4]), local_split(genpath(folders{2}))];
    clash = intersect(local_mfiles(userFolders), local_mfiles(kitFolders));
    if ~isempty(clash)
        warning('setup_paths:UserShadowed', ...
            ['users/%s has files named like kit functions; the kit''s versions run: %s. ' ...
             'Rename the user files.'], user, strjoin(clash(:)', ', '));
    end
end

% Data folders are created lazily, but make sure the roots exist.
for d = {fullfile(root,'data'), fullfile(root,'data','raw'), ...
         fullfile(root,'data','metadata'), fullfile(root,'data','logs')}
    if exist(d{1}, 'dir') ~= 7
        mkdir(d{1});
    end
end

if nargout == 0
    fprintf('Kit paths configured. Root: %s\n', root);
    if ~isempty(user)
        fprintf('User folder on the path: %s\n', fullfile(usersRoot, user));
    end
    clear root;
end
end

% ========================================================================
function c = local_split(p)
% Path string -> cell array of folders, without empty entries.
c = strsplit(p, pathsep);
c = c(~cellfun(@isempty, c));
end

function names = local_mfiles(dirs)
% Function names (file names without .m) of the .m files directly in dirs.
names = {};
for i = 1:numel(dirs)
    f = dir(fullfile(dirs{i}, '*.m'));
    names = [names, cellfun(@(n) n(1:end-2), {f.name}, 'UniformOutput', false)]; %#ok<AGROW>
end
names = unique(names);
end
