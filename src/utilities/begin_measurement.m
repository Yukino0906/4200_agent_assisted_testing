function [run, inst, guard, owns] = begin_measurement(cfg, test_name, inst)
%BEGIN_MEASUREMENT  Common start-up sequence shared by every run_*_test.
%
%   [run, inst, guard, owns] = BEGIN_MEASUREMENT(cfg, test_name, inst)
%       1. validates the configuration (hard gate for real-hardware runs)
%       2. creates a timestamped run directory
%       3. connects to the instrument, unless a live session was passed in
%       4. builds an onCleanup guard that forces the output to 0 V / OFF
%          however the caller exits -- normal return, error, or Ctrl-C
%       5. writes a first metadata record, so even a crashed run is traceable
%
%   THE GUARD MUST BE KEPT ALIVE BY THE CALLER. Assign it to a local
%   variable and do not clear it; when the caller's workspace is destroyed
%   the guard fires. This is what guarantees the output is never left on.
%
%   Inputs:
%       cfg       - configuration struct
%       test_name - short test identifier for the run directory
%       inst      - optional existing InstrumentSession. Pass [] to open a
%                   new one (which this function will also close).
%
%   Outputs:
%       run   - run struct from create_run_directory
%       inst  - InstrumentSession
%       guard - onCleanup object; keep it in scope
%       owns  - logical, true when this call opened the session and the
%               caller should disconnect it at the end
%
%   Instrument side effects: may connect and reset the instrument. Leaves the
%   output OFF at 0 V.
%
%   Exceptions: propagates validate_config and connect_instruments errors.
%
%   See also FINISH_MEASUREMENT, CREATE_RUN_DIRECTORY, CONNECT_INSTRUMENTS.

narginchk(2, 3);
if nargin < 3; inst = []; end

cfg  = validate_config(cfg);
run  = create_run_directory(cfg, test_name);

owns = isempty(inst) || ~isvalid(inst) || ~inst.Connected;
if owns
    inst = connect_instruments(cfg, run);
else
    inst.LogFile = run.instrument_log;
end

guard = onCleanup(@() local_guard(inst, owns));

save_metadata(run, cfg, inst, struct('completed', false, ...
    'abort_reason', 'run started, not yet finished'));

log_message(run, 'INFO', 'Test "%s" started (run_id = %s).', test_name, run.run_id);
end

% ------------------------------------------------------------------------
function local_guard(inst, owns)
try
    if isempty(inst) || ~isvalid(inst)
        return;
    end
    safe_output_off(inst);
    if owns
        disconnect_instruments(inst);
    end
catch
    % A cleanup handler must never throw.
end
end
