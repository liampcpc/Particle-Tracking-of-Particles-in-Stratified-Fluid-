function [heightMm, info] = glycerineMixtureTerminalVelocity(ballDiameterMm, glycerinePercent, temperatureC, varargin)
% GLYCERINEMIXTURETERMINALVELOCITY Fall distance

p = inputParser;
addRequired(p, 'ballDiameterMm', @(x) isnumeric(x) && isscalar(x) && x > 0);
addRequired(p, 'glycerinePercent', @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);
addRequired(p, 'temperatureC', @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'fracTarget', 0.99, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
addParameter(p, 'dragModel', 'general', @(x) ischar(x) || isstring(x));
addParameter(p, 'rhoSteel', 7850, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'g', 9.81, @(x) isnumeric(x) && isscalar(x) && x > 0);
parse(p, ballDiameterMm, glycerinePercent, temperatureC, varargin{:});
opt = p.Results;
dragModel = char(opt.dragModel);

R = (opt.ballDiameterMm / 1000) / 2;
Cm = opt.glycerinePercent / 100;  % percent -> mass fraction (0-1)
T = opt.temperatureC;

mu = mu_mixture(Cm, T);
rhoF = rho_mixture(Cm, T);

switch dragModel
    case 'stokes'
        [xf, vInf] = frac_distance_stokes(mu, rhoF, R, opt.rhoSteel, opt.g, opt.fracTarget);
    case 'general'
        [xf, vInf] = frac_distance_general(mu, rhoF, R, opt.rhoSteel, opt.g, opt.fracTarget);
    otherwise
        error('glycerineMixtureTerminalVelocity:badDragModel', ...
            'dragModel must be ''stokes'' or ''general'' (got ''%s'').', dragModel);
end

if isinf(xf)
    warning('glycerineMixtureTerminalVelocity:notReached', ...
        ['%g%% of terminal velocity was not reached within a generous time ' ...
         'window for a %g mm ball at %g%% glycerine, %g degC -- returning NaN.'], ...
        opt.fracTarget*100, opt.ballDiameterMm, opt.glycerinePercent, T);
    heightMm = NaN;
else
    heightMm = xf * 1000;  % m -> mm
end

if nargout > 1
    Re = rhoF * vInf * (2*R) / mu;
    info = struct();
    info.viscosityPaS   = mu;
    info.densityKgM3    = rhoF;
    info.terminalVelMmS = vInf * 1000;
    info.reynolds       = Re;
    switch dragModel
        case 'stokes'
            info.validDragRange = (Re < 1);
        case 'general'
            info.validDragRange = (Re < 1000);
    end
end

end

%% LOCAL FUNCTIONS
function [xf, vInf] = frac_distance_stokes(mu, rhoF, R, rhoSteel, g, frac)
% Closed-form distance (from rest) under linear Stokes drag to reach frac*v_inf
    A = g*(rhoSteel - rhoF)/rhoSteel;
    B = 9*mu / (2*R^2*rhoSteel);
    vInf = A/B;
    xf = (vInf/B) * ( -log(1-frac) - frac );
end

function Cd = Cd_schiller_naumann(Re)
% Schiller-Naumann drag correlation, valid for Re up to ~1000
    Re = max(Re, 1e-9);
    Cd = (24./Re) .* (1 + 0.15*Re.^0.687);
    Cd(Re > 1000) = 0.44;
end

function vInf = terminal_velocity_general(mu, rhoF, R, rhoSteel, g)
% Implicit solve for terminal velocity under Schiller-Naumann drag
    A = g*(rhoSteel - rhoF)/rhoSteel;
    resid = @(v) A - (3*Cd_schiller_naumann(rhoF.*v.*(2*R)./mu).*rhoF./(8*R*rhoSteel)).*v.^2;

    vStokes = 2*R^2*g*(rhoSteel-rhoF)/(9*mu);
    vLo = 1e-9;
    vHi = max(vStokes, 1e-6) * 5;
    while resid(vHi) > 0 && vHi < 1e6
        vHi = vHi * 2;
    end

    opts = optimset('TolX', 1e-12, 'Display', 'off');
    vInf = fzero(resid, [vLo, vHi], opts);
end

function [xf, vInf] = frac_distance_general(mu, rhoF, R, rhoSteel, g, frac)
% Distance travelled (from rest) under Schiller-Naumann drag to reach frac*v_inf, via numerical integration
    vInf = terminal_velocity_general(mu, rhoF, R, rhoSteel, g);
    A = g*(rhoSteel - rhoF)/rhoSteel;

    odefun = @(t,y) ball_ode(t, y, mu, rhoF, R, rhoSteel, A);
    vTarget = frac * vInf;
    eventFn = @(t,y) reach_frac_event(t, y, vTarget);

    tScale = vInf / A;
    tMax = 50 * tScale;

    y0 = [0; 0];
    opts = odeset('Events', eventFn, 'RelTol', 1e-9, 'AbsTol', 1e-12);

    [~, ~, te, ye, ~] = ode45(odefun, [0, tMax], y0, opts);

    if isempty(te)
        xf = Inf;
    else
        xf = ye(1,2);
    end
end

function dydt = ball_ode(~, y, mu, rhoF, R, rhoSteel, A)
    v = y(1);
    Re = rhoF*abs(v)*(2*R)/mu;
    Cd = Cd_schiller_naumann(Re);
    dvdt = A - (3*Cd*rhoF/(8*R*rhoSteel))*v^2;
    dxdt = v;
    dydt = [dvdt; dxdt];
end

function [value, isterminal, direction] = reach_frac_event(~, y, vTarget)
    value = y(1) - vTarget;
    isterminal = 1;
    direction = 1;
end

function mu = mu_mixture(Cm, T)
% Cheng (2008) correlation for the viscosity of a glycerol-water mixture
    muW = 1.79e-3 * exp( ((-1230 - T).*T) ./ (36100 + 360*T) );
    muG = 12.1    * exp( ((-1233 + T).*T) ./ (9900 + 70*T)  );

    a = 0.705 - 0.0017*T;
    b = (4.9 + 0.036*T) .* a.^2.5;

    alpha = 1 - Cm + (a.*b.*Cm.*(1-Cm)) ./ (a.*Cm + b.*(1-Cm));

    mu = muW.^alpha .* muG.^(1-alpha);
end

function rho = rho_mixture(Cm, T)
% Ideal volume-mixing density of a glycerol-water mixture
    rhoW = rho_water(T);
    rhoG = rho_glycerol(T);
    rho = 1 ./ ( Cm./rhoG + (1-Cm)./rhoW );
end

function rho = rho_water(T)
    rho = 999.842594 + 6.793952e-2*T - 9.095290e-3*T.^2 ...
        + 1.001685e-4*T.^3 - 1.120083e-6*T.^4 + 6.536332e-9*T.^5;
end

function rho = rho_glycerol(T)
    rho = 1273.3 - 0.6121*T;
end
