function out = pmu_run_sequence(inst, cfg, seq)
%PMU_RUN_SEQUENCE  Download a segment-ARB pulse, execute it, and read the data back.
%
%   out = PMU_RUN_SEQUENCE(inst, cfg, seq) sends the sequence built by
%   PMU_BUILD_PULSE to the 4225-PMU and runs it once. Command order, per
%   channel (Keithley KXCI segARB examples):
%
%       :PMU:SARB:SEQ:TIME       ch, 1, t1, t2, ...
%       :PMU:SARB:SEQ:STARTV     ch, 1, v1, v2, ...
%       :PMU:SARB:SEQ:STOPV      ch, 1, ...
%       :PMU:SARB:SEQ:MEAS:TYPE  ch, 1, ...
%       :PMU:SARB:SEQ:MEAS:START ch, 1, ...
%       :PMU:SARB:SEQ:MEAS:STOP  ch, 1, ...
%       :PMU:SARB:WFM:SEQ:LIST   ch, 1, 1        (sequence 1, once)
%   then
%       :PMU:OUTPUT:STATE ch, 1   -> :PMU:EXECUTE -> poll :PMU:TEST:STATUS?
%       -> :PMU:DATA:COUNT? ch -> :PMU:DATA:GET ch, start, count (chunks)
%       -> :PMU:OUTPUT:STATE ch, 0
%
%   The pulse is timed by the PMU hardware; the host only starts it and
%   collects the result. Nothing is executed when any definition command
%   was not acknowledged: a half-accepted sequence would run the previous
%   pulse shape.
%
%   The caller (APPLY_VOLTAGE_PULSE) has already done every safety check and
%   selected the pulse path; this function must not be called from anywhere
%   else.
%
%   Inputs:
%       inst - InstrumentSession (live, on the 'pulse' path)
%       cfg  - configuration struct
%       seq  - struct from PMU_BUILD_PULSE
%
%   Outputs:
%       out - struct:
%           .status  'ok' | 'instrument_error' | 'timeout' | 'comm_error'
%           .force   N x 4 [V_V, I_A, t_s, status] of the force channel
%           .sense   same for the sense channel ([] without one)
%           .message diagnostic text when status ~= 'ok'
%
%   Instrument side effects: enables the PMU output(s), executes ONE pulse,
%   disables the output(s) again.
%
%   Exceptions: none for instrument faults (reported in out.status); a
%   status poll that never completes triggers EMERGENCY_SHUTDOWN.
%
%   See also PMU_BUILD_PULSE, APPLY_VOLTAGE_PULSE, KXCI_PARSE_PMU_DATA.

out = struct('status', 'ok', 'force', zeros(0, 4), 'sense', [], 'message', '');

chans = inst.PmuForce;
defs  = {seq.force};
if ~isempty(seq.sense)
    chans(end+1) = inst.PmuSense;
    defs{end+1}  = seq.sense;
end

% ---- define ------------------------------------------------------------
fields = {'time', 'TIME'; 'startv', 'STARTV'; 'stopv', 'STOPV'; ...
          'meastype', 'MEAS:TYPE'; 'measstart', 'MEAS:START'; 'measstop', 'MEAS:STOP'};
for c = 1:numel(chans)
    d = defs{c};
    for k = 1:size(fields, 1)
        kxci_write(inst, ':PMU:SARB:SEQ:%s %d, 1, %s', fields{k, 2}, chans(c), ...
            local_list(d.(fields{k, 1})));
    end
    kxci_write(inst, ':PMU:SARB:WFM:SEQ:LIST %d, 1, 1', chans(c));
end

nErr = kxci_check_errors(inst);
if nErr > 0
    out.status  = 'instrument_error';
    out.message = sprintf('Sequence definition not accepted: %s', inst.LastError);
    log_message(inst, 'ERROR', '%s Pulse NOT executed.', out.message);
    return;
end

% ---- execute -----------------------------------------------------------
for ch = chans
    if ~ismember(ch, inst.PmuOutputsOn)
        kxci_write(inst, ':PMU:OUTPUT:STATE %d, 1', ch);
        inst.PmuOutputsOn(end+1) = ch;
    end
end
kxci_write(inst, ':PMU:EXECUTE');

t0 = tic;
done = false;
while toc(t0) < cfg.pmu.status_timeout_s
    [s, ok] = kxci_query(inst, ':PMU:TEST:STATUS?');
    if ok && str2double(s) == 0
        done = true;
        break;
    end
    pause(cfg.pmu.poll_interval_s);
end
if ~done
    out.status  = 'timeout';
    out.message = sprintf('PMU test still running after %g s.', cfg.pmu.status_timeout_s);
    emergency_shutdown(inst, out.message);
    return;
end

% ---- read back ---------------------------------------------------------
data = cell(1, numel(chans));
for c = 1:numel(chans)
    [nStr, ok] = kxci_query(inst, ':PMU:DATA:COUNT? %d', chans(c));
    nPts = str2double(nStr);
    if ~ok || ~isfinite(nPts) || nPts < 1
        out.status  = 'comm_error';
        out.message = sprintf('Channel %d reported "%s" data points.', chans(c), nStr);
        log_message(inst, 'WARN', '%s', out.message);
        data{c} = zeros(0, 4);
        continue;
    end
    rows = zeros(0, 4);
    for first = 0:cfg.pmu.data_chunk:(nPts - 1)
        cnt = min(cfg.pmu.data_chunk, nPts - first);
        [r, okG] = kxci_query(inst, ':PMU:DATA:GET %d, %d, %d', chans(c), first, cnt);
        if ~okG; break; end
        rows = [rows; kxci_parse_pmu_data(r)]; %#ok<AGROW>
    end
    if size(rows, 1) ~= nPts
        log_message(inst, 'WARN', 'Channel %d: expected %d points, parsed %d.', ...
            chans(c), nPts, size(rows, 1));
    end
    data{c} = rows;
end

for ch = chans
    kxci_write(inst, ':PMU:OUTPUT:STATE %d, 0', ch);
end
inst.PmuOutputsOn = reshape(setdiff(inst.PmuOutputsOn, chans), 1, []);

out.force = data{1};
if numel(data) > 1
    out.sense = data{2};
end
end

% ========================================================================
function s = local_list(v)
s = strjoin(arrayfun(@(x) sprintf('%.9g', x), v, 'UniformOutput', false), ', ');
end
