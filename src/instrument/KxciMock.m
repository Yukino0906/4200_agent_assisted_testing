classdef KxciMock < handle
%KXCIMOCK  Software stand-in for a 4200A running KXCI, for testing the command layer.
%
%   dev = KXCIMOCK(cfg) behaves like the transport object of a KXCI
%   connection: it has writeline, readline and flush. Every command is
%   parsed, checked and answered the way this kit EXPECTS the 4200A to
%   answer, and a virtual RRAM (RramSimulator) stands behind the SMU and
%   PMU so readings respond to pulses.
%
%   Select it with cfg.instrument.transport = 'mock' and
%   cfg.mode.simulate_instrument = false. The whole KXCI code path then
%   runs -- command formatting, acknowledge handling, reply parsing, RPM
%   path switching, PMU sequence download and read-back -- with no hardware.
%
%   WHAT IT PROVES AND WHAT IT DOES NOT
%   The mock encodes this kit's assumptions about KXCI (reply formats,
%   acknowledge text, RPM path codes, segARB argument order). It proves that
%   the code is internally consistent with those assumptions and that the
%   ORDER of operations is safe. It cannot prove the assumptions are right:
%   that is what docs/07_bring_up.md does on the real instrument.
%
%   Order rules it enforces (recorded in .Violations):
%       - TI/TV while the force RPM is not on the SMU path
%       - :PMU:EXECUTE while the force RPM is not on the pulse path
%       - an RPM switched to the pulse path while the SMU holds a non-zero level
%       - an RPM switched to the SMU path while its PMU output is on
%       - a segARB sequence whose arrays differ in length
%       - any |V| above cfg.safety.max_abs_voltage reaching the device
%
%   See also CONNECT_INSTRUMENTS, KXCI_TRANSACT, RRAMSIMULATOR.

    properties
        Cfg
        Sim                           % RramSimulator behind the probes
        AckMode    = true
        AckText    = 'ACK'
        Replies    = {}               % queued replies, oldest first
        Log        = {}               % every command received
        Violations = {}               % order/safety rules broken
        Errors     = 0                % commands answered with an error
        UserMode   = false
        SmuLevel   = 0
        SmuOn      = false
        SmuComp    = 1e-3
        PmuInit    = false
        RpmPath                       % containers.Map 'PMU1-1' -> 'pulse'|'smu'
        OutputState = [false false]   % PMU channel outputs
        Seq                           % struct array per channel
        Data       = {zeros(0,4), zeros(0,4)}
        Range      = [1e-3 1e-3]
        SeriesOhm  = 50               % PMU output impedance
    end

    methods
        function obj = KxciMock(cfg)
            obj.Cfg     = cfg;
            obj.Sim     = RramSimulator(cfg);
            obj.AckMode = cfg.instrument.ack_mode;
            obj.RpmPath = containers.Map();
            obj.resetState();
        end

        % ---- transport interface --------------------------------------
        function writeline(obj, cmd)
            cmd = strtrim(char(cmd));
            obj.Log{end+1} = cmd;
            [isQuery, reply, ok] = obj.handle(cmd);
            if ~ok
                obj.Errors = obj.Errors + 1;
                if obj.AckMode || isQuery
                    obj.Replies{end+1} = reply;
                end
                return;
            end
            if isQuery
                obj.Replies{end+1} = reply;
            elseif obj.AckMode
                obj.Replies{end+1} = obj.AckText;
            end
        end

        function r = readline(obj)
            if isempty(obj.Replies)
                r = '';               % mimics a timeout
                return;
            end
            r = obj.Replies{1};
            obj.Replies(1) = [];
        end

        function flush(obj, varargin)
            obj.Replies = {};
        end

        function resetState(obj)
            obj.UserMode = false;
            obj.SmuLevel = 0;
            obj.SmuOn    = false;
            obj.PmuInit  = false;
            obj.OutputState = [false false];
            obj.Seq  = repmat(struct('time', [], 'startv', [], 'stopv', [], ...
                'meastype', [], 'measstart', [], 'measstop', [], 'list', []), 1, 2);
            obj.Data = {zeros(0,4), zeros(0,4)};
            obj.RpmPath = containers.Map();
            for ch = 1:2
                obj.RpmPath(sprintf('PMU%d-%d', obj.Cfg.pmu.card, ch)) = 'pulse';
            end
        end
    end

    methods (Access = private)
        function [isQuery, reply, ok] = handle(obj, cmd)
            isQuery = false; reply = ''; ok = true;
            u = upper(cmd);
            nums = @(s) str2double(regexp(s, '[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?', 'match'));

            if any(strcmp(u, {'BC', '*RST'}))
                if strcmp(u, '*RST'); obj.resetState(); end
                return;
            end
            if strcmp(u, '*IDN?')
                isQuery = true;
                reply = 'KEITHLEY INSTRUMENTS,MOCK-4200A-SCS,0000000,mock';
                return;
            end
            if strcmp(u, 'US')
                obj.UserMode = true;
                return;
            end

            % ---- SMU user mode ----------------------------------------
            tok = regexp(u, '^DV(\d)(.*)$', 'tokens', 'once');
            if ~isempty(tok)
                if ~obj.UserMode
                    [reply, ok] = obj.err('DV outside user mode'); return;
                end
                a = nums(tok{2});
                if isempty(a)
                    obj.SmuOn = false; obj.SmuLevel = 0;        % "DVn" = off
                    return;
                end
                if numel(a) ~= 3
                    [reply, ok] = obj.err('DV needs range, level, compliance'); return;
                end
                obj.checkV(a(2), 'SMU');
                obj.SmuLevel = a(2); obj.SmuComp = a(3); obj.SmuOn = true;
                return;
            end
            tok = regexp(u, '^T([IV])(\d)$', 'tokens', 'once');
            if ~isempty(tok)
                isQuery = true;
                if ~obj.UserMode
                    [reply, ok] = obj.err('T? outside user mode'); return;
                end
                rpm = obj.forceRpm();
                if ~strcmp(obj.RpmPath(rpm), 'smu')
                    obj.violate(sprintf('%s measured while %s is on the pulse path', cmd, rpm));
                end
                [I, hit] = obj.smuCurrent();
                status = 'N';
                if hit; status = 'C'; end
                if tok{1} == 'I'
                    reply = sprintf('%sAI%+.6E', status, I);
                else
                    reply = sprintf('%sAV%+.6E', status, obj.SmuLevel * obj.SmuOn);
                end
                return;
            end

            % ---- PMU ---------------------------------------------------
            if startsWith(u, ':PMU:INIT')
                obj.PmuInit = true;
                return;
            end
            tok = regexp(u, '^:PMU:RPM:CONFIGURE\s+(PMU\d-\d)\s*,\s*(\d+)$', 'tokens', 'once');
            if ~isempty(tok)
                code = str2double(tok{2});
                if code == obj.Cfg.pmu.rpm_code_pulse
                    if obj.SmuOn && obj.SmuLevel ~= 0 && strcmp(tok{1}, obj.forceRpm())
                        obj.violate(sprintf('%s switched to pulse with the SMU at %+.3f V', ...
                            tok{1}, obj.SmuLevel));
                    end
                    obj.RpmPath(tok{1}) = 'pulse';
                elseif code == obj.Cfg.pmu.rpm_code_smu
                    ch = str2double(tok{1}(end));
                    if obj.OutputState(ch)
                        obj.violate(sprintf('%s switched to SMU with PMU output %d on', tok{1}, ch));
                    end
                    obj.RpmPath(tok{1}) = 'smu';
                else
                    [reply, ok] = obj.err('unknown RPM path code');
                end
                return;
            end
            tok = regexp(u, '^:PMU:MEASURE:RANGE\s+(.*)$', 'tokens', 'once');
            if ~isempty(tok)
                a = nums(tok{1});
                if numel(a) ~= 3; [reply, ok] = obj.err('RANGE needs 3 args'); return; end
                obj.Range(a(1)) = a(3);
                return;
            end
            tok = regexp(u, '^:PMU:SARB:SEQ:(TIME|STARTV|STOPV|MEAS:TYPE|MEAS:START|MEAS:STOP)\s+(.*)$', ...
                'tokens', 'once');
            if ~isempty(tok)
                a = nums(tok{2});
                if numel(a) < 3; [reply, ok] = obj.err('sequence needs values'); return; end
                f = lower(strrep(tok{1}, 'MEAS:', 'meas'));
                obj.Seq(a(1)).(f) = a(3:end);
                return;
            end
            tok = regexp(u, '^:PMU:SARB:WFM:SEQ:LIST\s+(.*)$', 'tokens', 'once');
            if ~isempty(tok)
                a = nums(tok{1});
                obj.Seq(a(1)).list = a(2:end);
                return;
            end
            tok = regexp(u, '^:PMU:OUTPUT:STATE\s+(\d)\s*,\s*(\d)$', 'tokens', 'once');
            if ~isempty(tok)
                obj.OutputState(str2double(tok{1})) = str2double(tok{2}) == 1;
                return;
            end
            if strcmp(u, ':PMU:EXECUTE')
                [reply, ok] = obj.execute();
                return;
            end
            if strcmp(u, ':PMU:TEST:STATUS?')
                isQuery = true; reply = '0'; return;
            end
            tok = regexp(u, '^:PMU:DATA:COUNT\?\s+(\d)$', 'tokens', 'once');
            if ~isempty(tok)
                isQuery = true;
                reply = sprintf('%d', size(obj.Data{str2double(tok{1})}, 1));
                return;
            end
            tok = regexp(u, '^:PMU:DATA:GET\s+(.*)$', 'tokens', 'once');
            if ~isempty(tok)
                isQuery = true;
                a = nums(tok{1});
                d = obj.Data{a(1)};
                first = 0; cnt = size(d, 1);
                if numel(a) >= 3; first = a(2); cnt = a(3); end
                rows = d(first+1:min(first+cnt, size(d, 1)), :);
                parts = arrayfun(@(k) sprintf('%.6E,%.6E,%.6E,%d', rows(k,1), rows(k,2), ...
                    rows(k,3), rows(k,4)), 1:size(rows, 1), 'UniformOutput', false);
                reply = strjoin(parts, ';');
                return;
            end

            isQuery = endsWith(u, '?');
            [reply, ok] = obj.err(sprintf('unrecognised command "%s"', cmd));
        end

        function [reply, ok] = execute(obj)
            reply = ''; ok = true;
            if ~obj.PmuInit
                [reply, ok] = obj.err('EXECUTE before :PMU:INIT'); return;
            end
            fch = obj.Cfg.pmu.force_channel;
            sch = obj.Cfg.pmu.sense_channel;
            s = obj.Seq(fch);
            L = [numel(s.time), numel(s.startv), numel(s.stopv), numel(s.meastype), ...
                 numel(s.measstart), numel(s.measstop)];
            if any(L ~= L(1)) || L(1) == 0
                obj.violate('segARB arrays of unequal length');
                [reply, ok] = obj.err('sequence arrays differ in length'); return;
            end
            if ~strcmp(obj.RpmPath(obj.forceRpm()), 'pulse')
                obj.violate('PMU executed while the force RPM is on the SMU path');
            end
            reaches = obj.OutputState(fch) && strcmp(obj.RpmPath(obj.forceRpm()), 'pulse');
            obj.checkV([s.startv s.stopv], 'PMU');

            % Device response: hold each flat non-zero segment on the device.
            for k = 1:numel(s.time)
                if reaches && s.startv(k) == s.stopv(k) && s.startv(k) ~= 0
                    obj.Sim.applyBias(s.startv(k), s.time(k), Inf);
                end
            end
            G = obj.Sim.conductance();
            divider = 1 / (1 + obj.SeriesOhm * G);   % 50 Ohm source into the device

            % Build the records the PMU would return.
            obj.Data = {zeros(0,4), zeros(0,4)};
            tStart = [0 cumsum(s.time(1:end-1))];
            fRows = zeros(0, 4); sRows = zeros(0, 4);
            for k = 1:numel(s.time)
                switch s.meastype(k)
                    case 1
                        tm = tStart(k) + (s.measstart(k) + s.measstop(k)) / 2;
                        frac = (s.measstart(k) + s.measstop(k)) / (2 * s.time(k));
                        tq = tm; fq = frac;
                    case 2
                        fq = linspace(0, 1, 11);
                        tq = tStart(k) + fq * s.time(k);
                    otherwise
                        continue;
                end
                vSet = s.startv(k) + fq * (s.stopv(k) - s.startv(k));
                vDev = vSet * divider * reaches;
                iDev = G * vDev .* (1 + 0.01 * randn(size(vDev)));
                fRows = [fRows; [vDev(:), iDev(:), tq(:), zeros(numel(tq), 1)]]; %#ok<AGROW>
                sRows = [sRows; [zeros(numel(tq), 1), -iDev(:), tq(:), zeros(numel(tq), 1)]]; %#ok<AGROW>
            end
            obj.Data{fch} = fRows;
            if sch > 0
                obj.Data{sch} = sRows;
            end
        end

        function [I, hit] = smuCurrent(obj)
            if ~obj.SmuOn || ~strcmp(obj.RpmPath(obj.forceRpm()), 'smu')
                I = 1e-14 * randn(); hit = false;      % open: the SMU sees nothing
                return;
            end
            [I, hit] = obj.Sim.readCurrent(obj.SmuLevel, obj.SmuComp, 1e-3);
        end

        function r = forceRpm(obj)
            r = sprintf('PMU%d-%d', obj.Cfg.pmu.card, obj.Cfg.pmu.force_channel);
        end

        function checkV(obj, v, who)
            if any(abs(v) > obj.Cfg.safety.max_abs_voltage + 1e-9)
                obj.violate(sprintf('%s level %.3f V above the safety ceiling', who, max(abs(v))));
            end
        end

        function violate(obj, msg)
            obj.Violations{end+1} = msg;
        end

        function [reply, ok] = err(~, msg)
            reply = ['ERROR: ' msg];
            ok = false;
        end
    end
end
