function reply = kxci_transact(dev, cmd, expect_reply)
%KXCI_TRANSACT  Lowest-level KXCI exchange: write one command, optionally read one reply.
%
%   reply = KXCI_TRANSACT(dev, cmd, expect_reply) writes `cmd` with the
%   transport's configured terminator and, when expect_reply is true, reads
%   exactly one reply line. It works unchanged for a visadev object, a
%   tcpclient object and the KxciMock stand-in, because all three provide
%   writeline/readline.
%
%   Callers never use this directly: KXCI_WRITE and KXCI_QUERY add logging,
%   dry-run handling, acknowledge checking and failure handling on top.
%
%   Inputs:
%       dev          - visadev | tcpclient | KxciMock
%       cmd          - char command
%       expect_reply - logical
%
%   Outputs:
%       reply - trimmed char reply ('' when no reply was requested)
%
%   Instrument side effects: executes `cmd`.
%
%   Exceptions:
%       kxci_transact:Timeout  a reply was expected and none arrived. Some
%                              transports return empty on timeout instead of
%                              throwing; both cases end up here, so a missing
%                              reply can never be mistaken for an empty one.
%
%   See also KXCI_WRITE, KXCI_QUERY.

narginchk(3, 3);
writeline(dev, cmd);
reply = '';
if ~expect_reply
    return;
end
raw = readline(dev);
if isempty(raw)
    error('kxci_transact:Timeout', 'No reply to "%s" within the transport timeout.', cmd);
end
% Strip any leftover NUL or line-end characters the terminator setting kept.
reply = strtrim(strrep(char(raw), char(0), ''));
end
