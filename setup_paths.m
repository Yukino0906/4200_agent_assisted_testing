function root = setup_paths()
%SETUP_PATHS  Put every kit folder on the MATLAB path. Run this first.
%
%   root = SETUP_PATHS() adds config/, src/ (recursively), examples/ and
%   tests/ to the MATLAB search path and returns the kit root. It does NOT
%   save the path, so it leaves the user's environment untouched between
%   sessions -- call it once per MATLAB session.
%
%   Usage:
%       cd <path to>\4200A_agent_kit
%       setup_paths
%       test_dry_run            % simulation only, no instrument
%
%   Inputs: none.
%   Outputs: root - char, absolute kit root.
%   Instrument side effects: none.
%   Exceptions: setup_paths:MissingFolder if a required folder is absent.

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

addpath(fullfile(root, 'config'));
addpath(genpath(fullfile(root, 'src')));
addpath(fullfile(root, 'examples'));
addpath(fullfile(root, 'tests'));

% Data folders are created lazily, but make sure the roots exist.
for d = {fullfile(root,'data'), fullfile(root,'data','raw'), ...
         fullfile(root,'data','metadata'), fullfile(root,'data','logs')}
    if exist(d{1}, 'dir') ~= 7
        mkdir(d{1});
    end
end

if nargout == 0
    fprintf('Kit paths configured. Root: %s\n', root);
    clear root;
end
end
