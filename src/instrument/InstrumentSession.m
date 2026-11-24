classdef InstrumentSession < handle
%INSTRUMENTSESSION  Mutable state of one KXCI connection to the Keithley 4200A-SCS.
%
%   A handle object is used deliberately: the session carries safety counters
%   (pulse count, compliance hits, abort flag) and, in simulation mode, the
%   virtual device state. Passing it by value would silently lose those
%   updates, which is exactly the class of bug that burns a real device.
%   Using a handle object also avoids global variables entirely.
%
%   The object is created by CONNECT_INSTRUMENTS and consumed by every
%   function in src/instrument and src/measurement.
%
%   Hardware model (see docs/01_setup.md):
%       SMU<n>      DC source/measure for reads and DC sweeps. Its output
%                   reaches the device through the SMU input of one RPM.
%       PMU card    pulse source/measure (4225-PMU), one or two channels,
%                   each through its own 4225-RPM.
%       RPM path    each RPM connects the device either to the PMU ('pulse')
%                   or to the SMU ('smu'). Path tracks which one is active.
%
%   Properties are grouped as:
%       connection  - Dev, Transport, Resource, Connected, Identity, ...
%       modes       - Simulate, DryRun
%       state       - OutputOn, LastVoltage, Compliance, Path, UserMode, ...
%       safety      - PulseCount, ComplianceHits, Aborted, LastError, TStart
%       context     - Cfg, Sim, LogFile, DryRunCommands
%
%   See also CONNECT_INSTRUMENTS, DISCONNECT_INSTRUMENTS, EMERGENCY_SHUTDOWN.

    properties
        % --- connection -------------------------------------------------
        Dev            = []       % visadev / tcpclient / KxciMock, [] when simulated
        Transport      = ''       % 'visa' | 'tcpclient' | 'mock' | 'simulated'
        Resource       = ''       % VISA resource string (or host:port) actually used
        Connected      = false
        Identity       = ''       % raw *IDN? response
        Model          = ''
        Serial         = ''
        Firmware       = ''
        AckMode        = true     % every KXCI command returns a reply (Ethernet)

        % --- modes ------------------------------------------------------
        Simulate       = true     % no instrument at all; virtual RRAM
        DryRun         = true     % never enable an output; log commands

        % --- channels / state -------------------------------------------
        Smu            = 1        % SMU number used for reads and DC sweeps
        Channel        = 'SMU1'   % label for logs and metadata
        GroundChannel  = 'GNDU'   % label of the current return
        PmuCard        = 1
        PmuForce       = 1        % PMU channel driving the device
        PmuSense       = 0        % PMU channel on the return side, 0 = none
        Path           = ''       % 'smu' | 'pulse' | '' (unknown)
        UserMode       = false    % KXCI SMU user mode ('US') entered
        PmuInitialised = false    % ':PMU:INIT 1' sent this session
        PmuOutputsOn   = zeros(1,0) % PMU channels whose output is enabled
        OutputOn       = false    % SMU output state
        LastVoltage    = 0
        Compliance     = NaN
        Mode           = ''       % 'read'|'dc'|'pulse', set by
                                  % configure_instruments. Compliance means
                                  % different things in different modes.

        % --- safety counters --------------------------------------------
        PulseCount     = 0
        ComplianceHits = 0
        ConsecutiveComplianceHits = 0
        Aborted        = false
        LastError      = ''
        ReplyErrors    = 0        % command replies that were not an acknowledge
        TStart         = []       % tic reference for max_test_duration

        % --- context ----------------------------------------------------
        Cfg            = struct()
        Sim            = []       % RramSimulator when Simulate == true
        LogFile        = ''
        DryRunCommands = {}       % commands that WOULD have been sent
        CommandCount   = 0
    end

    methods
        function obj = InstrumentSession(cfg)
            %INSTRUMENTSESSION  Construct an unconnected session from cfg.
            if nargin > 0
                obj.Cfg       = cfg;
                obj.Simulate  = cfg.mode.simulate_instrument;
                obj.DryRun    = cfg.mode.dry_run;
                obj.Transport = char(cfg.instrument.transport);
                obj.Resource  = char(cfg.instrument.resource);
                obj.AckMode   = cfg.instrument.ack_mode;
                obj.Smu       = cfg.instrument.smu;
                obj.Channel   = sprintf('SMU%d', cfg.instrument.smu);
                obj.GroundChannel = upper(char(cfg.instrument.return_path));
                obj.PmuCard   = cfg.pmu.card;
                obj.PmuForce  = cfg.pmu.force_channel;
                obj.PmuSense  = cfg.pmu.sense_channel;
            end
            obj.TStart = tic;
        end

        function tf = isLive(obj)
            %ISLIVE  True only when commands actually reach an instrument
            %   (real hardware or the KXCI mock).
            tf = obj.Connected && ~obj.Simulate;
        end

        function tf = canDrive(obj)
            %CANDRIVE  True when the session may apply a bias.
            %   Dry-run blocks only REAL output; a simulated session always
            %   drives its virtual device so every code path is exercised.
            tf = ~obj.Aborted && (~obj.DryRun || obj.Simulate);
        end

        function s = elapsed(obj)
            %ELAPSED  Seconds since the session was created.
            if isempty(obj.TStart); s = 0; else; s = toc(obj.TStart); end
        end

        function noteCommand(obj, cmd)
            %NOTECOMMAND  Record a command (always) and store it in dry-run.
            obj.CommandCount = obj.CommandCount + 1;
            if obj.DryRun
                obj.DryRunCommands{end+1} = char(cmd);
            end
        end

        function delete(obj)
            %DELETE  Destructor: never leave a real instrument driving.
            try
                if obj.isLive()
                    safe_output_off(obj);
                end
            catch
                % Destructors must not throw.
            end
            try
                if ~isempty(obj.Dev) && ~isa(obj.Dev, 'KxciMock')
                    delete(obj.Dev);
                end
            catch
            end
            obj.Dev = [];
            obj.Connected = false;
        end
    end
end
