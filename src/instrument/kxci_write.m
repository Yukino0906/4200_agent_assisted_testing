function reply = kxci_write(inst, cmd, varargin)
%KXCI_WRITE  Send one KXCI command that returns no data, and check its acknowledge.
%
%   reply = KXCI_WRITE(inst, cmd) sends `cmd` when the session is live
%   (connected and not simulated) and records it in the session's command
%   log. In simulation mode nothing is transmitted; the command is only
%   recorded, which is what makes dry-run verification possible.
%
%   KXCI_WRITE(inst, fmt, a, b, ...) formats the command with sprintf first.
%
%   ACKNOWLEDGE (Ethernet)
%   ----------------------
%   With cfg.instrument.ack_mode = true the instrument answers every
%   command, data or not, so the reply is ALWAYS read here. Leaving it unread
%   would make the next query return this command's acknowledge instead of
%   its own data -- an off-by-one that silently corrupts every later reading.
%   A reply that does not match cfg.instrument.ack_pattern is counted in
%   inst.ReplyErrors and stored in inst.LastError; KXCI_CHECK_ERRORS reports
%   and clears the count. Over GPIB (ack_mode = false) nothing is read.
%
%   IMPORTANT: this function does NOT enforce the dry-run output ban. It is
%   safe for configuration commands (ranges, sequence definitions) which are
%   harmless with the outputs off. Any command that drives the device must go
%   through SET_VOLTAGE / APPLY_VOLTAGE_PULSE, which check inst.canDrive()
%   first.
%
%   The instrument speaks KXCI, not SCPI and not TSP
%   (see docs/04_kxci_cheatsheet.md).
%
%   Inputs:
%       inst - InstrumentSession
%       cmd  - char/string command, or sprintf format string
%
%   Outputs:
%       reply - the acknowledge text ('' in simulation or without ack mode)
%
%   Instrument side effects: executes `cmd` on the 4200A.
%
%   Exceptions:
%       kxci_write:NotConnected  session has no live device and is not simulated
%       kxci_write:WriteFailed   transport failure (session is marked aborted)
%
%   See also KXCI_QUERY, KXCI_CHECK_ERRORS, SET_VOLTAGE.

narginchk(2, inf);
if ~isempty(varargin)
    cmd = sprintf(char(cmd), varargin{:});
end
cmd = char(cmd);
reply = '';

inst.noteCommand(cmd);
log_message(inst, 'CMD', '>> %s', cmd);

if inst.Simulate
    return;
end

if ~inst.Connected || isempty(inst.Dev)
    error('kxci_write:NotConnected', ...
        'Cannot send "%s": no live instrument session.', cmd);
end

try
    reply = kxci_transact(inst.Dev, cmd, inst.AckMode);
catch err
    inst.LastError = err.message;
    emergency_shutdown(inst, sprintf('KXCI write failed for "%s": %s', cmd, err.message));
    error('kxci_write:WriteFailed', ...
        'KXCI write failed for "%s": %s', cmd, err.message);
end

if inst.AckMode
    log_message(inst, 'CMD', '<< %s', reply);
    if isempty(regexp(reply, inst.Cfg.instrument.ack_pattern, 'once'))
        inst.ReplyErrors = inst.ReplyErrors + 1;
        inst.LastError   = sprintf('"%s" answered "%s"', cmd, reply);
        log_message(inst, 'WARN', 'Unexpected reply to "%s": "%s"', cmd, reply);
    end
end
end
