classdef RramSimulator < handle
%RRAMSIMULATOR  Minimal virtual RRAM used by dry-run / simulation mode.
%
%   This is NOT a compact model and is not meant to be physically accurate.
%   Its only job is to exercise every code path (loops, write-verify
%   convergence, saturation, noise statistics, relaxation, compliance hits,
%   file writing, abort handling) without touching real hardware.
%
%   Behaviour, in normalised log-conductance w in [0,1]:
%       G(w)   = G_hrs * (G_lrs/G_hrs)^w
%       SET    (V > +v_set)  : dw = +k(V) * (dt/t_ref) * (1 - w)
%       RESET  (V < -|v_reset|): dw = -k(V) * (dt/t_ref) * w
%       k(V)   = ((|V| - v_th)/v_th)^alpha
%   plus multiplicative update noise, read noise, a small read-disturb term
%   that grows with |V_read|, and an exponential short-term relaxation that
%   pulls w partway back toward its pre-write value.
%
%   Sign convention: +V = SET, -V = RESET.
%
%   Instrument side effects: none, by construction.
%
%   See also INSTRUMENTSESSION, CONNECT_INSTRUMENTS.

    properties
        Ghrs, Glrs
        Vset, Vreset, Alpha, Tref
        SigmaUpdate, SigmaRead
        RelaxTau, RelaxFrac
        W          = 0.02      % normalised state
        Wprev      = 0.02      % state before the last write (relaxation anchor)
        LastWriteT = 0         % [s] time of last write, on the T0 clock
        T0                     % tic reference
        DisturbGain = 2e-5     % read-disturb strength per volt^3 per second
        Nonlinearity = 0.8     % I = G*V*(1 + b*V^2) at low bias
    end

    methods
        function obj = RramSimulator(cfg)
            s = cfg.sim;
            obj.Ghrs        = s.G_hrs;
            obj.Glrs        = s.G_lrs;
            obj.Vset        = s.v_set;
            obj.Vreset      = abs(s.v_reset);
            obj.Alpha       = s.alpha;
            obj.Tref        = s.width_ref;
            obj.SigmaUpdate = s.sigma_update;
            obj.SigmaRead   = s.sigma_read;
            obj.RelaxTau    = s.relax_tau;
            obj.RelaxFrac   = s.relax_frac;
            obj.T0          = tic;
            rng(s.rng_seed, 'twister');
            obj.W     = 0.02;
            obj.Wprev = 0.02;
        end

        % ---- state <-> conductance ------------------------------------
        function G = conductance(obj)
            %CONDUCTANCE  Present conductance [S], including relaxation.
            G = obj.Ghrs * (obj.Glrs/obj.Ghrs)^obj.effectiveW();
        end

        function w = effectiveW(obj)
            %EFFECTIVEW  State after short-term relaxation toward Wprev.
            dt = toc(obj.T0) - obj.LastWriteT;
            if dt < 0; dt = 0; end
            frac = obj.RelaxFrac * (1 - exp(-dt / obj.RelaxTau));
            w = obj.W - frac * (obj.W - obj.Wprev);
            w = min(max(w, 0), 1);
        end

        % ---- measurement ----------------------------------------------
        function [I, hitCompliance] = readCurrent(obj, V, compliance, dt)
            %READCURRENT  Current [A] at bias V, with noise and read disturb.
            %   The bias is held for dt while the measurement is taken, so the
            %   state evolves during it. That matters: a DC sweep is nothing
            %   but a sequence of biased measurements, and if reads did not
            %   evolve the state the simulated sweep would never switch and
            %   the V_set / V_reset extraction would go untested.
            if nargin < 4 || isempty(dt); dt = 1e-3; end
            if nargin < 3 || isempty(compliance); compliance = Inf; end

            obj.evolve(V, dt);

            G  = obj.conductance();
            I  = G * V * (1 + obj.Nonlinearity * V^2);
            I  = I * (1 + obj.SigmaRead * randn());
            I  = I + 1e-13 * randn();            % instrument noise floor

            hitCompliance = abs(I) > compliance;
            if hitCompliance
                I = sign(I) * compliance;
            end
        end

        % ---- write -----------------------------------------------------
        function hitCompliance = applyBias(obj, V, dt, compliance)
            %APPLYBIAS  Write pulse: evolve the state and anchor relaxation.
            if nargin < 4 || isempty(compliance); compliance = Inf; end

            % Collapse any pending relaxation into the state, then use it as
            % the anchor the state will partially relax back toward.
            wOld      = obj.effectiveW();
            obj.W     = wOld;
            obj.Wprev = wOld;

            obj.evolve(V, dt);
            obj.LastWriteT = toc(obj.T0);

            % Peak current during the pulse, for the compliance flag.
            G = obj.Ghrs * (obj.Glrs/obj.Ghrs)^obj.W;
            hitCompliance = abs(G * V) > compliance;
        end

        function evolve(obj, V, dt)
            %EVOLVE  Advance the state under bias V held for dt seconds.
            %   Above threshold: switching kinetics, saturating at the far
            %   boundary. Below threshold: the much weaker disturb term.
            if dt <= 0 || V == 0; return; end

            w = obj.W;

            if V > obj.Vset
                k  = ((V - obj.Vset) / obj.Vset) ^ obj.Alpha;
                dw = 0.55 * k * (dt / obj.Tref) * (1 - w);
            elseif V < -obj.Vreset
                k  = ((abs(V) - obj.Vreset) / obj.Vreset) ^ obj.Alpha;
                dw = -0.55 * k * (dt / obj.Tref) * w;
            else
                obj.applyDisturb(V, dt);
                return;
            end

            dw = dw * (1 + obj.SigmaUpdate * randn());
            obj.W = min(max(w + dw, 0), 1);
        end

        function applyDisturb(obj, V, dt)
            %APPLYDISTURB  Sub-threshold bias slowly nudges the state.
            if V == 0 || dt <= 0; return; end
            d = obj.DisturbGain * sign(V) * abs(V)^3 * (dt / obj.Tref);
            if V > 0
                d = d * (1 - obj.W);
            else
                d = d * obj.W;
            end
            obj.W = min(max(obj.W + d, 0), 1);
        end

        function reset(obj, w0)
            %RESET  Force the virtual device into a known state.
            if nargin < 2; w0 = 0.02; end
            obj.W = min(max(w0, 0), 1);
            obj.Wprev = obj.W;
            obj.LastWriteT = toc(obj.T0);
        end
    end
end
