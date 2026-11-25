function info = instrument_lock(action, lockFile, who, allowStale, isAlive)
%INSTRUMENT_LOCK  One controller at a time: claim or release the 4200A for this MATLAB.
%
%   Several people use this PC, each from their own session. KXCI serves one
%   controller; a second one either gets "connection refused" or, worse,
%   interleaves its commands with the first. This lock turns that rule
%   (AGENTS.md rule 17) into a check. CONNECT_INSTRUMENTS claims it before it
%   opens a real transport; DISCONNECT_INSTRUMENTS releases it. The simulator
%   and KxciMock never touch it.
%
%   info = INSTRUMENT_LOCK('acquire', lockFile, who) creates lockFile
%   atomically and writes the holder into it (JSON: user, os_user, host,
%   pid, since, note). It refuses when
%       - another MATLAB that is still running holds it
%         (instrument_lock:InUse), or a MATLAB on another computer holds it;
%       - the holder no longer runs, i.e. it was killed or crashed
%         (instrument_lock:Stale). Its outputs may still be on.
%   A lock already held by this MATLAB is accepted (re-entrant).
%
%   info = INSTRUMENT_LOCK('acquire', lockFile, who, true) takes a stale lock
%   over instead of refusing. Only TEST_INSTRUMENT_CONNECTION does this: it is
%   the prescribed first step after a killed MATLAB and turns every output off.
%   A lock held by a running MATLAB is never taken over.
%
%   INSTRUMENT_LOCK('release', lockFile) deletes lockFile when this MATLAB
%   holds it, and leaves it alone otherwise.
%
%   info = INSTRUMENT_LOCK('status', lockFile) returns the holder, or [] when
%   the instrument is free. info.alive tells whether the holder still runs.
%
%   Inputs:
%       action     - 'acquire' | 'release' | 'status'
%       lockFile   - char, path of the lock file (cfg.instrument.lock_file)
%       who        - struct with optional .user (users/ folder, '' = kit) and
%                    .note (free text, e.g. the run id)
%       allowStale - logical, take over a stale lock (default false)
%       isAlive    - optional function handle @(holder) -> logical, used by
%                    test_dry_run instead of the process table
%
%   Outputs:
%       info - struct describing the holder (after 'acquire': this MATLAB,
%              with .took_over_stale and .previous)
%
%   Instrument side effects: none.
%
%   Exceptions:
%       instrument_lock:InUse     another running controller holds the lock
%       instrument_lock:Stale     the holder is gone; run test_instrument_connection
%       instrument_lock:BadAction unknown action
%
%   See also CONNECT_INSTRUMENTS, DISCONNECT_INSTRUMENTS, TEST_INSTRUMENT_CONNECTION.

narginchk(2, 5);
if nargin < 3 || isempty(who);   who = struct(); end
if nargin < 4 || isempty(allowStale); allowStale = false; end
if nargin < 5 || isempty(isAlive);    isAlive = @local_is_alive; end
lockFile = char(lockFile);
me = local_me(who);

switch lower(char(action))
    case 'status'
        info = local_read(lockFile);
        if ~isempty(info)
            info.alive = isAlive(info);
        end

    case 'release'
        info = local_read(lockFile);
        if ~isempty(info) && local_is_me(info, me)
            delete(lockFile);
        end

    case 'acquire'
        holder = [];
        if ~local_create(lockFile)
            holder = local_read(lockFile);
            if isempty(holder)
                % Exists but unreadable: being written right now, or damaged.
                error('instrument_lock:InUse', ...
                    ['The 4200A lock file exists but cannot be read: %s\n' ...
                     'Another session may be connecting right now. Wait and retry; if it ' ...
                     'persists, check that no MATLAB is driving the 4200A, then delete the file.'], ...
                    lockFile);
            end
            if local_is_me(holder, me)
                info = me;
                info.took_over_stale = false;
                info.previous = [];
                return;   % this MATLAB already holds it
            end
            if isAlive(holder)
                error('instrument_lock:InUse', ...
                    ['The 4200A is in use by user "%s" (Windows user %s, computer %s, ' ...
                     'MATLAB PID %d) since %s. One controller at a time: wait until that ' ...
                     'session disconnects.'], local_or(holder.user, 'kit'), holder.os_user, ...
                    holder.host, holder.pid, holder.since);
            end
            if ~allowStale
                error('instrument_lock:Stale', ...
                    ['The 4200A was last claimed by user "%s" (MATLAB PID %d, since %s), ' ...
                     'and that MATLAB is no longer running: it was killed or crashed, so ' ...
                     'outputs may still be on. Run test_instrument_connection first; it turns ' ...
                     'every output off and clears this lock (%s).'], ...
                    local_or(holder.user, 'kit'), holder.pid, holder.since, lockFile);
            end
        end
        local_write(lockFile, me);
        info = me;
        info.took_over_stale = ~isempty(holder);
        info.previous = holder;

    otherwise
        error('instrument_lock:BadAction', ...
            'Unknown action "%s" (acquire | release | status).', action);
end
end

% ========================================================================
function me = local_me(who)
me = struct();
me.user    = '';
if isfield(who, 'user') && ~isempty(who.user); me.user = char(who.user); end
me.os_user = local_or(getenv('USERNAME'), getenv('USER'));
me.host    = local_or(getenv('COMPUTERNAME'), getenv('HOSTNAME'));
me.pid     = local_pid();
me.since   = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
me.note    = '';
if isfield(who, 'note') && ~isempty(who.note); me.note = char(who.note); end
end

function tf = local_is_me(holder, me)
tf = isfield(holder, 'pid') && isfield(holder, 'host') && ...
     isequal(double(holder.pid), double(me.pid)) && strcmpi(char(holder.host), me.host);
end

function ok = local_create(lockFile)
% Atomic create: true only for the caller that made the file.
d = fileparts(lockFile);
if ~isempty(d) && exist(d, 'dir') ~= 7; mkdir(d); end
try
    ok = java.io.File(lockFile).createNewFile();
catch
    % No JVM: small race window, still refuses an existing lock.
    ok = exist(lockFile, 'file') ~= 2;
    if ok
        fid = fopen(lockFile, 'w');
        if fid > 0; fclose(fid); else; ok = false; end
    end
end
ok = logical(ok);
end

function local_write(lockFile, me)
fid = fopen(lockFile, 'w');
if fid < 0
    error('instrument_lock:WriteFailed', 'Cannot write the lock file %s.', lockFile);
end
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(me, 'PrettyPrint', true));
end

function holder = local_read(lockFile)
holder = [];
if exist(lockFile, 'file') ~= 2; return; end
try
    txt = fileread(lockFile);
    if isempty(strtrim(txt)); return; end
    holder = jsondecode(txt);
    if ~all(isfield(holder, {'pid', 'host'})); holder = []; return; end
    for f = {'user', 'os_user', 'since', 'note'}
        if ~isfield(holder, f{1}) || isempty(holder.(f{1})); holder.(f{1}) = ''; end
    end
catch
    holder = [];
end
end

function tf = local_is_alive(holder)
% A holder on another computer cannot be checked here: treat it as alive.
if ~strcmpi(char(holder.host), local_or(getenv('COMPUTERNAME'), getenv('HOSTNAME')))
    tf = true;
    return;
end
pid = double(holder.pid);
if ispc
    [~, out] = system(sprintf('tasklist /FI "PID eq %d" /FO CSV /NH', pid));
    tf = contains(out, sprintf('"%d"', pid)) && contains(lower(out), 'matlab');
else
    [st, out] = system(sprintf('ps -p %d -o comm=', pid));
    tf = st == 0 && contains(lower(out), 'matlab');
end
end

function pid = local_pid()
% matlabProcessID exists in recent releases; older ones use the JVM's "pid@host".
if exist('matlabProcessID') > 0 %#ok<EXIST>
    pid = double(matlabProcessID);
else
    name = char(java.lang.management.ManagementFactory.getRuntimeMXBean().getName());
    pid  = str2double(strtok(name, '@'));
end
end

function s = local_or(a, b)
if isempty(a); s = char(b); else; s = char(a); end
end
