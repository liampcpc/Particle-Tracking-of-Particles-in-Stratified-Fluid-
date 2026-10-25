%% GLYCERINE_TERMINAL_VELOCITY_CALCULATOR
% Interactive calculator: type in a glycerine percentage
clear; clc;

%% INPUTS
glycerinePercent = ask('Glycerine volume percentage, 0-100 %% (by volume)', [], @(x) x >= 0 && x <= 100);
ballDiameterMm   = ask('Ball diameter, mm', [], @(x) x > 0);
temperatureC     = ask('Temperature, degC', 20, @(x) true);

rhoSteel = 7850;  % steel density, kg/m^3
g        = 9.81;  % gravity, m/s^2
frac     = 0.99;  % fraction of terminal velocity for the distance estimate

%% CALCULATE
R  = (ballDiameterMm/1000)/2;
phi = glycerinePercent/100;  % glycerine VOLUME fraction (of pure-component volumes)
rhoG0 = rho_glycerol(temperatureC);
rhoW0 = rho_water(temperatureC);
Cm = phi*rhoG0 / (phi*rhoG0 + (1-phi)*rhoW0);

mu   = mu_mixture(Cm, temperatureC);
rhoF = rho_mixture(Cm, temperatureC);

vInf = terminal_velocity_general(mu, rhoF, R, rhoSteel, g);
Re   = rhoF*vInf*(2*R)/mu;
xf   = frac_distance_general(mu, rhoF, R, rhoSteel, g, frac, vInf);

%% OUTPUT
fprintf('\n================ RESULT ================\n');
fprintf('Ball diameter        : %.2f mm\n', ballDiameterMm);
fprintf('Glycerine            : %.2f %% by volume (%.2f %% by mass)\n', glycerinePercent, Cm*100);
fprintf('Temperature          : %.1f degC\n', temperatureC);
fprintf('Mixture viscosity    : %.3f mPa.s\n', mu*1000);
fprintf('Mixture density      : %.1f kg/m^3\n', rhoF);
fprintf('----------------------------------------\n');
fprintf('TERMINAL VELOCITY    : %.2f mm/s  (%.4f m/s)\n', vInf*1000, vInf);
fprintf('Reynolds number      : %.3g\n', Re);
if isinf(xf)
    fprintf('Distance to %.0f%% v_t : not reached within time window\n', frac*100);
else
    fprintf('Distance to %.0f%% v_t : %.1f mm\n', frac*100, xf*1000);
end
fprintf('========================================\n');
if Re > 1000
    fprintf('WARNING: Re > 1000 is beyond the Schiller-Naumann valid range; result is approximate.\n');
end

%% LOCAL FUNCTIONS
function val = ask(prompt, defaultVal, isValid)
% Prompt until a valid number is entered (Enter accepts the default, if any)
    while true
        if isempty(defaultVal)
            s = input(sprintf([prompt ': ']), 's');
        else
            s = input(sprintf([prompt ' [%g]: '], defaultVal), 's');
        end
        if isempty(strtrim(s)) && ~isempty(defaultVal)
            val = defaultVal; return;
        end
        v = str2double(s);
        if isscalar(v) && isfinite(v) && isValid(v)
            val = v; return;
        end
        fprintf('  Invalid input, please try again.\n');
    end
end

function Cd = Cd_schiller_naumann(Re)
    Re = max(Re, 1e-9);
    Cd = (24./Re) .* (1 + 0.15*Re.^0.687);
    Cd(Re > 1000) = 0.44;
end

function vInf = terminal_velocity_general(mu, rhoF, R, rhoSteel, g)
    A = g*(rhoSteel - rhoF)/rhoSteel;
    resid = @(v) A - (3*Cd_schiller_naumann(rhoF.*v.*(2*R)./mu).*rhoF./(8*R*rhoSteel)).*v.^2;
    vStokes = 2*R^2*g*(rhoSteel-rhoF)/(9*mu);
    vLo = 1e-9;
    vHi = max(vStokes, 1e-6) * 5;
    while resid(vHi) > 0 && vHi < 1e6
        vHi = vHi * 2;
    end
    vInf = fzero(resid, [vLo, vHi], optimset('TolX',1e-12,'Display','off'));
end

function xf = frac_distance_general(mu, rhoF, R, rhoSteel, g, frac, vInf)
    A = g*(rhoSteel - rhoF)/rhoSteel;
    odefun = @(t,y) ball_ode(t, y, mu, rhoF, R, rhoSteel, A);
    vTarget = frac*vInf;
    eventFn = @(t,y) reach_frac_event(t, y, vTarget);
    tMax = 50 * vInf / A;
    opts = odeset('Events', eventFn, 'RelTol',1e-9, 'AbsTol',1e-12);
    [~, ~, te, ye, ~] = ode45(odefun, [0, tMax], [0; 0], opts);
    if isempty(te), xf = Inf; else, xf = ye(1,2); end
end

function dydt = ball_ode(~, y, mu, rhoF, R, rhoSteel, A)
    v = y(1);
    Re = rhoF*abs(v)*(2*R)/mu;
    Cd = Cd_schiller_naumann(Re);
    dydt = [A - (3*Cd*rhoF/(8*R*rhoSteel))*v^2; v];
end

function [value, isterminal, direction] = reach_frac_event(~, y, vTarget)
    value = y(1) - vTarget; isterminal = 1; direction = 1;
end

function mu = mu_mixture(Cm, T)
% Cheng (2008) glycerol-water viscosity, Pa.s
    muW = 1.79e-3 * exp( ((-1230 - T).*T) ./ (36100 + 360*T) );
    muG = 12.1    * exp( ((-1233 + T).*T) ./ (9900 + 70*T)  );
    a = 0.705 - 0.0017*T;
    b = (4.9 + 0.036*T) .* a.^2.5;
    alpha = 1 - Cm + (a.*b.*Cm.*(1-Cm)) ./ (a.*Cm + b.*(1-Cm));
    mu = muW.^alpha .* muG.^(1-alpha);
end

function rho = rho_mixture(Cm, T)
    rho = 1 ./ ( Cm./rho_glycerol(T) + (1-Cm)./rho_water(T) );
end

function rho = rho_water(T)
    rho = 999.842594 + 6.793952e-2*T - 9.095290e-3*T.^2 ...
        + 1.001685e-4*T.^3 - 1.120083e-6*T.^4 + 6.536332e-9*T.^5;
end

function rho = rho_glycerol(T)
    rho = 1273.3 - 0.6121*T;
end
