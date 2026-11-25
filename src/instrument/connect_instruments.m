function inst = connect_instruments(cfg, run)
%CONNECT_INSTRUMENTS  Open a KXCI session to the Keithley 4200A-SCS.
%
%   inst = CONNECT_INSTRUMENTS(cfg) creates an InstrumentSession. Depending
%   on cfg.mode and cfg.instrument.transport it either
%       (a) builds a fully virtual session (cfg.mode.simulate_instrument),
%       (b) opens the software stand-in KxciMock (transport = 'mock'),
%       (c) opens a raw-socket session over Ethernet with visadev
%           (transport = 'visa', resource "TCPIP0::<ip>::<port>::SOCKET"),
%           or a GPIB session (resource "GPIB0::<addr>::INSTR"),
%       (d) opens a plain TCP socket with tcpclient (transport = 'tcpclient',
%           no NI-VISA needed).
%
%   inst = CONNECT_INSTRUMENTS(cfg, run) additionally routes logging into the
%   run directory created by CREATE_RUN_DIRECTORY.
%
%   The KXCI application must already be running on the 4200A, configured
%   in KCon for the same interface and port (docs/01_setup.md). Clarius must
%   not be driving the hardware at the same time.
%
%   Connection procedure:
%       claim the instrument lock (real transports only, INSTRUMENT_LOCK)
%       -> open transport -> terminator (NUL over Ethernet) -> timeout
%       -> BC, *RST (when cfg.instrument.reset_on_connect) -> *IDN?
%   Nothing is driven here: no SMU level is set and no PMU output is enabled.
%   The lock is released again when opening or setting up fails, and by
%   DISCONNECT_INSTRUMENTS.
%
%   Inputs:
%       cfg - configuration struct (must have passed validate_config)
%       run - optional run struct from create_run_directory
%
%   Outputs:
%       inst - InstrumentSession, .Connected true on success
%
%   Instrument side effects: resets the instrument (outputs off).
%
%   Exceptions:
%       connect_instruments:NoTransport  visadev / tcpclient unavailable
%       connect_instruments:AllFailed    no candidate resource responded
%       instrument_lock:InUse            another running session controls the 4200A
%       instrument_lock:Stale            a killed MATLAB left the lock; run
%                                        test_instrument_connection first
%
%   See also CONFIGURE_INSTRUMENTS, DISCONNECT_INSTRUMENTS, SAFE_OUTPUT_OFF.

narginchk(1, 2);
if nargin < 2; run = []; end

inst = InstrumentSession(cfg);
if ~isempty(run)
    inst.LogFile = run.instrument_log;
end

% ---------------------------------------------------------------- simulate
if cfg.mode.simulate_instrument
    inst.Simulate  = true;
    inst.Transport = 'simulated';
    inst.Connected = true;
    inst.Sim       = RramSimulator(cfg);
    inst.Identity  = 'SIMULATED,4200A-like,0000000,virtual';
    inst.Model     = 'SIMULATED-4200A';
    inst.Serial    = '0000000';
    inst.Firmware  = 'virtual';
    inst.Resource  = 'SIMULATED';
    log_message(inst, 'INFO', ...
        'SIMULATION MODE: no instrument session opened. Virtual RRAM G=%.4g S.', ...
        inst.Sim.conductance());
    return;
end

% ---------------------------------------------------------------- claim
% One controller at a time (AGENTS.md rule 17): several people share this PC.
% The software stand-in needs no lock.
transport = lower(char(cfg.instrument.transport));
lockFile  = '';
if ~strcmp(transport, 'mock') && isfield(cfg.instrument, 'lock_file') && ...
        ~isempty(cfg.instrument.lock_file)
    lockFile   = char(cfg.instrument.lock_file);
    allowStale = isfield(cfg.instrument, 'lock_allow_stale') && cfg.instrument.lock_allow_stale;
    who = struct('user', local_field(cfg, 'user'), 'note', local_field(run, 'run_id'));
    li  = instrument_lock('acquire', lockFile, who, allowStale);
    if li.took_over_stale
        log_message(inst, 'WARN', ['Took over a stale 4200A lock left by user "%s" ' ...
            '(MATLAB PID %d, since %s); that MATLAB is no longer running.'], ...
            li.previous.user, li.previous.pid, li.previous.since);
    end
    log_message(inst, 'INFO', 'Instrument lock claimed: %s', lockFile);
end

% ---------------------------------------------------------------- open
dev = [];
usedResource = '';
lastErr = '';

try
switch transport
    case 'mock'
        dev = KxciMock(cfg);
        usedResource = 'MOCK';
        log_message(inst, 'INFO', ['KXCI MOCK transport: commands go to a software ' ...
            'stand-in, not to an instrument.']);

    case 'tcpclient'
        if exist('tcpclient', 'file') ~= 2
            error('connect_instruments:NoTransport', ...
                'tcpclient is not available (MATLAB R2020b or later required).');
        end
        res = sprintf('%s:%d', cfg.instrument.host, cfg.instrument.port);
        log_message(inst, 'INFO', 'Opening TCP socket %s ...', res);
        try
            dev = tcpclient(cfg.instrument.host, cfg.instrument.port, ...
                'Timeout', cfg.instrument.timeout, 'ConnectTimeout', 10);
            configureTerminator(dev, cfg.instrument.terminator);
            usedResource = res;
        catch err
            lastErr = err.message;
            dev = [];
        end

    case 'visa'
        if exist('visadev', 'file') ~= 2
            error('connect_instruments:NoTransport', ...
                ['visadev is not available. Instrument Control Toolbox (R2021a+) and ' ...
                 'NI-VISA are required, or use cfg.instrument.transport = ''tcpclient''.']);
        end
        candidates = cfg.instrument.resource_candidates;
        if ischar(candidates) || isstring(candidates)
            candidates = cellstr(candidates);
        end
        for k = 1:numel(candidates)
            res = string(candidates{k});
            log_message(inst, 'INFO', 'Trying VISA resource %s ...', res);
            try
                dev = visadev(res);
                configureTerminator(dev, cfg.instrument.terminator);
                dev.Timeout = cfg.instrument.timeout;
                usedResource = char(res);
                break;
            catch err
                lastErr = err.message;
                log_message(inst, 'WARN', 'Resource %s failed: %s', res, err.message);
                dev = [];
            end
        end

    otherwise
        error('connect_instruments:NoTransport', ...
            'Unknown cfg.instrument.transport "%s" (visa | tcpclient | mock).', transport);
end
catch openErr
    local_release(lockFile);
    rethrow(openErr);
end

if isempty(dev)
    local_release(lockFile);
    error('connect_instruments:AllFailed', ...
        ['Could not open the KXCI connection (%s). Last error: %s\n' ...
         'Check: KXCI is running on the 4200A; KCon port/interface match; ' ...
         'the laptop IP is in the same subnet; no other program holds the socket.'], ...
        transport, lastErr);
end

inst.Dev       = dev;
inst.Transport = transport;
inst.Resource  = usedResource;
inst.Connected = true;
log_message(inst, 'INFO', 'KXCI session opened on %s.', usedResource);

% Everything below is wrapped: if any step throws we must not leave a freshly
% reset instrument half-configured with a dangling handle.
try

% ---- reset / clear -----------------------------------------------------
if cfg.instrument.reset_on_connect
    kxci_write(inst, 'BC');       % clear the reading buffer
    kxci_write(inst, '*RST');     % all modules to their default (outputs off)
end
inst.OutputOn       = false;
inst.LastVoltage    = 0;
inst.Path           = '';
inst.UserMode       = false;
inst.PmuInitialised = false;
inst.PmuOutputsOn   = zeros(1, 0);

% ---- identity ----------------------------------------------------------
[idn, ok] = kxci_query(inst, '*IDN?');
if ok && ~isempty(idn) && contains(idn, ',')
    inst.Identity = idn;
    parts = strsplit(idn, ',');
    if numel(parts) >= 2; inst.Model    = strtrim(parts{2}); end
    if numel(parts) >= 3; inst.Serial   = strtrim(parts{3}); end
    if numel(parts) >= 4; inst.Firmware = strtrim(parts{4}); end
else
    % Not every KXCI release is guaranteed to answer *IDN?; record what came
    % back instead of failing the connection on it.
    log_message(inst, 'WARN', '*IDN? reply was "%s"; identity not confirmed.', idn);
    inst.Identity = sprintf('Keithley 4200A-SCS (unconfirmed; *IDN? -> "%s")', idn);
    inst.Model    = cfg.instrument.model;
end
log_message(inst, 'INFO', 'Instrument identity: %s', inst.Identity);

if cfg.instrument.check_errors
    kxci_check_errors(inst);
end

catch setupErr
    % Leave nothing driving and no orphaned handle behind.
    emergency_shutdown(inst, ...
        sprintf('connect_instruments failed after opening the session: %s', ...
                setupErr.message));
    try
        if ~isa(inst.Dev, 'KxciMock'); delete(inst.Dev); end
    catch
    end
    inst.Dev = [];
    inst.Connected = false;
    local_release(lockFile);
    rethrow(setupErr);
end
end

% ========================================================================
function local_release(lockFile)
% Never throws: called on failure paths.
if isempty(lockFile); return; end
try
    instrument_lock('release', lockFile);
catch
end
end

function v = local_field(s, name)
% Text field of a struct, '' when the struct or the field is missing.
v = '';
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = char(s.(name));
end
end
