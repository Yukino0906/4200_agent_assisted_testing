function ok = test_instrument_connection(cfg)
%TEST_INSTRUMENT_CONNECTION  Minimal, non-invasive 4200A check. RUN THIS FIRST.
%
%   ok = TEST_INSTRUMENT_CONNECTION() connects to the KXCI application on
%   the 4200A, asks who it is, shows the RAW reply to a harmless command,
%   turns every output off, and disconnects. Nothing else: no level other
%   than 0 V, no PMU test, no RPM switching. It is safe to run with probes
%   already landed on a device.
%
%   ok = TEST_INSTRUMENT_CONNECTION(cfg) uses a caller-supplied config. By
%   default the real instrument is used (simulate_instrument = false,
%   dry_run = true), because the entire point of this test is to prove the
%   connection works.
%
%   Steps
%     1. connect (transport, terminator, timeout, BC + *RST)
%     2. identity: *IDN?
%     3. acknowledge: send BC and print the raw reply. Over Ethernet KXCI
%        answers every command; cfg.instrument.ack_pattern must match this
%        reply, or every later command is counted as an error. See
%        docs/07_bring_up.md, item A.
%     4. outputs off: PMU channels off, SMU user mode, SMU 0 V, SMU off
%     5. disconnect
%
%   The identity and the raw acknowledge are written to
%       data\metadata\instrument_identity.json
%
%   Inputs:
%       cfg - optional configuration struct
%
%   Outputs:
%       ok - logical, true when every step succeeded
%
%   Instrument side effects: resets the instrument; leaves every output OFF.
%
%   Exceptions: none propagate -- failures are reported and `ok` is false.
%
%   See also CONNECT_INSTRUMENTS, TEST_READ_ONLY, TEST_DRY_RUN.

if nargin < 1 || isempty(cfg)
    cfg = default_config();
    cfg.mode.simulate_instrument = false;   % this test is about real hardware
    cfg.mode.dry_run             = true;    % never enable an output
end

fprintf('\n================================================================\n');
fprintf(' MINIMAL 4200A CONNECTION TEST (KXCI)\n');
fprintf('================================================================\n');
fprintf('  Mode          : %s\n', local_mode(cfg));
fprintf('  Transport     : %s\n', cfg.instrument.transport);
fprintf('  Resource      : %s\n', char(cfg.instrument.resource));
fprintf('  Expected model: %s\n', cfg.instrument.model);
fprintf('  KXCI must be running on the 4200A (not Clarius).\n');
fprintf('  This test applies 0 V only. No sweep, no pulse.\n\n');

ok   = false;
inst = [];
identity = struct();

% Guarantee every output is off no matter how this function exits.
cleanup = onCleanup(@() local_cleanup(inst));

try
    % ---- 1. connect ----------------------------------------------------
    fprintf('[1/5] Connecting ... ');
    if exist(cfg.log_root, 'dir') ~= 7; mkdir(cfg.log_root); end
    inst = connect_instruments(cfg, struct('instrument_log', ...
        fullfile(cfg.log_root, 'connection_test.log')));
    fprintf('OK (%s)\n', inst.Resource);

    % ---- 2. identity ---------------------------------------------------
    fprintf('[2/5] Identity ...\n');
    fprintf('        *IDN?    : %s\n', local_or(inst.Identity, '<no reply>'));
    fprintf('        model    : %s\n', local_or(inst.Model,    '<unknown>'));
    fprintf('        serial   : %s\n', local_or(inst.Serial,   '<unknown>'));
    fprintf('        firmware : %s\n', local_or(inst.Firmware, '<unknown>'));
    identity.idn        = inst.Identity;
    identity.model      = inst.Model;
    identity.serial     = inst.Serial;
    identity.firmware   = inst.Firmware;
    identity.resource   = inst.Resource;
    identity.transport  = inst.Transport;
    identity.queried_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>

    % ---- 3. acknowledge --------------------------------------------------
    fprintf('[3/5] Raw reply to "BC" (acknowledge check) ...\n');
    if inst.AckMode
        raw = kxci_write(inst, 'BC');
        matches = ~isempty(regexp(raw, cfg.instrument.ack_pattern, 'once'));
        fprintf('        reply    : "%s"\n', raw);
        fprintf('        matches cfg.instrument.ack_pattern "%s": %s\n', ...
            cfg.instrument.ack_pattern, local_yes(matches));
        identity.ack_reply   = raw;
        identity.ack_matches = matches;
        if ~matches
            fprintf(2, ['        Set cfg.instrument.ack_pattern so it matches this reply ' ...
                        '(docs/07_bring_up.md, item A) before any other test.\n']);
        end
        % The mismatch is reported above; do not let it fail step 4 too.
        inst.ReplyErrors = 0;
    else
        fprintf('        ack_mode is off (GPIB): nothing to check.\n');
    end

    % ---- 4. outputs off --------------------------------------------------
    fprintf('[4/5] Turning every output off (PMU, then SMU at 0 V) ... ');
    safe_output_off(inst);
    nErr = kxci_check_errors(inst);
    fprintf('done, %d command(s) not acknowledged\n', nErr);
    identity.safe_off_errors = nErr;
    if nErr > 0
        fprintf(2, '        Last: %s\n', inst.LastError);
    end

    % ---- 5. disconnect --------------------------------------------------
    fprintf('[5/5] Disconnecting ... ');
    disconnect_instruments(inst);
    fprintf('OK\n');

    ok = ~isempty(inst.Identity) && nErr == 0 && ...
         (~isfield(identity, 'ack_matches') || identity.ack_matches);

catch err
    fprintf('\n');
    fprintf(2, 'CONNECTION TEST FAILED\n');
    fprintf(2, '  identifier : %s\n', err.identifier);
    fprintf(2, '  message    : %s\n', err.message);
    if ~isempty(err.stack)
        fprintf(2, '  location   : %s (line %d)\n', err.stack(1).name, err.stack(1).line);
    end
    fprintf(2, '\nTroubleshooting:\n');
    fprintf(2, '  - Is the KXCI application running on the 4200A (and Clarius closed)?\n');
    fprintf(2, '  - KCon > KXCI Settings: interface and port match cfg.instrument.*?\n');
    fprintf(2, '  - Can the laptop ping the 4200A? Same subnet, static IPs, firewall?\n');
    fprintf(2, '  - NI MAX: does the raw-socket resource "Validate" with KXCI open?\n');
    fprintf(2, '  - Terminator: NUL (0) over Ethernet; ack_mode false over GPIB.\n');
    fprintf(2, '  - Is another program (an earlier MATLAB session) holding the socket?\n');
    fprintf(2, '  - No hardware available? Use cfg.mode.simulate_instrument = true.\n');
    if ~isempty(inst) && isvalid(inst)
        emergency_shutdown(inst, 'connection test failed');
    end
end

% ---- persist the identity ----------------------------------------------
if ~isempty(fieldnames(identity))
    try
        if exist(cfg.metadata_root, 'dir') ~= 7; mkdir(cfg.metadata_root); end
        path = fullfile(cfg.metadata_root, 'instrument_identity.json');
        fid = fopen(path, 'w');
        if fid > 0
            c = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(identity, 'PrettyPrint', true));
            fprintf('\nInstrument identity written to:\n  %s\n', path);
        end
    catch wErr
        warning('test_instrument_connection:SaveFailed', ...
            'Could not save the identity file: %s', wErr.message);
    end
end

fprintf('\n----------------------------------------------------------------\n');
if ok
    fprintf(' RESULT: PASS. The KXCI connection works.\n');
    fprintf(' Next: docs/07_bring_up.md, then tests\\test_read_only.m on a resistor.\n');
else
    fprintf(2, ' RESULT: FAIL. Do not proceed to any measurement.\n');
end
fprintf('----------------------------------------------------------------\n\n');

if nargout == 0
    clear ok;
end
end

% ========================================================================
function local_cleanup(inst)
try
    if ~isempty(inst) && isvalid(inst) && inst.Connected
        safe_output_off(inst);
        disconnect_instruments(inst);
    end
catch
end
end

function s = local_or(v, fallback)
if isempty(v); s = fallback; else; s = char(v); end
end

function s = local_yes(tf)
if tf; s = 'yes'; else; s = 'NO'; end
end

function m = local_mode(cfg)
if cfg.mode.simulate_instrument
    m = 'SIMULATED (no hardware)';
elseif strcmpi(cfg.instrument.transport, 'mock')
    m = 'KXCI MOCK (software stand-in)';
elseif cfg.mode.dry_run
    m = 'REAL instrument, DRY-RUN (no output enabled)';
else
    m = 'REAL instrument, LIVE';
end
end
