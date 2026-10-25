%% GLYCERINE_MIXTURE_TERMINAL_VELOCITY
% Problem: A steel ball bearing is dropped (from rest) into a water/glycerine mixture
clear; clc; close all;

%% USER-ADJUSTABLE INPUTS
R_ball      = 2e-3;  % Ball radius (m)
rho_steel   = 7850;  % Steel ball density (kg/m^3)
D_target    = 0.25;  % Target fall distance to reach frac_target*v_inf (m)
frac_target = 0.99;  % Fraction of terminal velocity to reach (0.99 = 99%)
g           = 9.81;  % Gravitational acceleration (m/s^2)

DRAG_MODEL  = 'general';  % 'stokes' (fast, valid Re<<1 only) or 'general' (Schiller-Naumann, valid Re<~1000)

T_range = (12:1:25)';

N_SCAN = 400;  % Number of grid points used to search for a sign change in x_frac(Cm)

nT = numel(T_range);
Cm_sol   = nan(nT,1);
mu_sol   = nan(nT,1);
rho_sol  = nan(nT,1);
vinf_sol = nan(nT,1);
Re_sol   = nan(nT,1);

Cm_lo = 1e-6;
Cm_hi = 0.9999;
Cm_grid = linspace(Cm_lo, Cm_hi, N_SCAN);

for i = 1:nT
    T = T_range(i);

    f = @(Cm) frac_distance(Cm, T, R_ball, rho_steel, g, frac_target, DRAG_MODEL) - D_target;

    f_grid = arrayfun(f, Cm_grid);

    bracket_idx = find(sign(f_grid(1:end-1)) .* sign(f_grid(2:end)) < 0, 1, 'first');

    if isempty(bracket_idx)
        x_grid   = f_grid + D_target;  % actual x_frac across the scan
        [x_max, i_max] = max(x_grid);
        [x_min, i_min] = min(x_grid);
        warning(['No solution found for T = %g degC: x_%.0f%% ranges from ' ...
                  '%.1f mm (at %.1f%% glycerine) to %.1f mm (at %.1f%% ' ...
                  'glycerine) across the full 0-100%% glycerine sweep, and ' ...
                  'never crosses your %.1f mm target. The largest distance ' ...
                  'this ball can take to reach %.0f%% of terminal velocity, ' ...
                  'at ANY glycerine percentage, is %.1f mm - so D_target is ' ...
                  'simply unreachable for this R_ball. Try a smaller ' ...
                  'D_target, a larger R_ball, or a lower frac_target.'], ...
                  T, frac_target*100, x_min*1000, Cm_grid(i_min)*100, ...
                  x_max*1000, Cm_grid(i_max)*100, D_target*1000, ...
                  frac_target*100, x_max*1000);
        continue;
    end

    Cm_bracket = [Cm_grid(bracket_idx), Cm_grid(bracket_idx+1)];

    opts = optimset('TolX',1e-10,'Display','off');
    Cm_root = fzero(f, Cm_bracket, opts);

    Cm_sol(i)  = Cm_root;
    mu_sol(i)  = mu_mixture(Cm_root, T);
    rho_sol(i) = rho_mixture(Cm_root, T);

    switch DRAG_MODEL
        case 'stokes'
            A = g*(rho_steel - rho_sol(i))/rho_steel;
            B = 9*mu_sol(i) / (2*R_ball^2*rho_steel);
            vinf_sol(i) = A/B;
        case 'general'
            vinf_sol(i) = terminal_velocity_general(mu_sol(i), rho_sol(i), R_ball, rho_steel, g);
        otherwise
            error('DRAG_MODEL must be ''stokes'' or ''general''.');
    end

    Re_sol(i) = rho_sol(i) * vinf_sol(i) * (2*R_ball) / mu_sol(i);
end

%% DISPLAY RESULTS TABLE
GlycerinePercent = Cm_sol*100;
ResultsTable = table(T_range, GlycerinePercent, rho_sol, mu_sol*1000, ...
                      vinf_sol, Re_sol, ...
    'VariableNames', {'Temp_degC','Glycerine_pct','Density_kgm3', ...
                       'Viscosity_mPas','TerminalVel_ms','Reynolds'});
disp(ResultsTable);

fprintf('\nDrag model used: %s\n', DRAG_MODEL);
switch DRAG_MODEL
    case 'stokes'
        if any(Re_sol > 1)
            fprintf(['WARNING: Reynolds number exceeds 1 for some rows above.\n' ...
                     '         Stokes'' law assumption is not valid there -\n' ...
                     '         switch DRAG_MODEL to ''general'' for a\n' ...
                     '         physically consistent answer.\n']);
        else
            fprintf('All solutions have Re < 1: Stokes'' law is valid throughout.\n');
        end
    case 'general'
        if any(Re_sol > 1000)
            fprintf(['WARNING: Reynolds number exceeds ~1000 for some rows above.\n' ...
                     '         This is beyond the Schiller-Naumann correlation''s\n' ...
                     '         validated range; results there are approximate.\n']);
        else
            fprintf('All solutions have Re < 1000: within the Schiller-Naumann valid range.\n');
        end
end

%% PLOTS
figure('Name','Glycerine % vs Temperature','Color','w');
plot(T_range, GlycerinePercent, '-o','LineWidth',1.5,'MarkerFaceColor','b');
xlabel('Temperature (\circC)');
ylabel('Glycerine mass percentage (%)');
title(sprintf('Glycerine %% required for %.0f%% of v_{term} within %.0f mm\n(R = %.2f mm, steel \\rho = %d kg/m^3, drag model: %s)', ...
      frac_target*100, D_target*1000, R_ball*1000, rho_steel, DRAG_MODEL));
grid on;

figure('Name','Mixture properties vs Temperature','Color','w');
subplot(2,1,1);
plot(T_range, mu_sol*1000, '-s','LineWidth',1.5,'Color',[0.85 0.33 0.1]);
xlabel('Temperature (\circC)'); ylabel('Viscosity (mPa \cdot s)');
title('Required mixture viscosity vs Temperature'); grid on;

subplot(2,1,2);
plot(T_range, rho_sol, '-^','LineWidth',1.5,'Color',[0.1 0.5 0.3]);
xlabel('Temperature (\circC)'); ylabel('Density (kg/m^3)');
title('Required mixture density vs Temperature'); grid on;

figure('Name','Terminal velocity and Reynolds number vs Temperature','Color','w');
yyaxis left
plot(T_range, vinf_sol*1000, '-o','LineWidth',1.5);
ylabel('Terminal velocity (mm/s)');
yyaxis right
plot(T_range, Re_sol, '-d','LineWidth',1.5);
ylabel('Reynolds number (-)');
xlabel('Temperature (\circC)');
title(sprintf('Terminal velocity & Reynolds number of solution (%s drag)', DRAG_MODEL));
grid on;

%% LOCAL FUNCTIONS
function xf = frac_distance(Cm, T, R, rho_steel, g, frac, drag_model)
% Dispatches to the closed-form Stokes solution or the numerical Schiller-Naumann solution

    mu    = mu_mixture(Cm, T);
    rho_f = rho_mixture(Cm, T);

    switch drag_model
        case 'stokes'
            xf = frac_distance_stokes(mu, rho_f, R, rho_steel, g, frac);
        case 'general'
            xf = frac_distance_general(mu, rho_f, R, rho_steel, g, frac);
        otherwise
            error('drag_model must be ''stokes'' or ''general''.');
    end
end

function xf = frac_distance_stokes(mu, rho_f, R, rho_steel, g, frac)
% Distance travelled (from rest) for a sphere under STOKES drag to reach a given fraction

    A = g*(rho_steel - rho_f)/rho_steel;
    B = 9*mu / (2*R^2*rho_steel);
    v_inf = A/B;

    xf = (v_inf/B) * ( -log(1-frac) - frac );
end

function Cd = Cd_schiller_naumann(Re)
% Schiller-Naumann drag correlation, valid for Re up to ~1000
    Re = max(Re, 1e-9);
    Cd = (24./Re) .* (1 + 0.15*Re.^0.687);
    Cd(Re > 1000) = 0.44;
end

function v_inf = terminal_velocity_general(mu, rho_f, R, rho_steel, g)
% Solves implicitly for terminal velocity under Schiller-Naumann drag: (4/3)*pi*R^3*(rho_steel-rho_f)*g

    A = g*(rho_steel - rho_f)/rho_steel;

    resid = @(v) A - (3*Cd_schiller_naumann(rho_f.*v.*(2*R)./mu).*rho_f./(8*R*rho_steel)).*v.^2;

    v_stokes = 2*R^2*g*(rho_steel-rho_f)/(9*mu);
    v_lo = 1e-9;
    v_hi = max(v_stokes, 1e-6) * 5;
    while resid(v_hi) > 0 && v_hi < 1e6
        v_hi = v_hi * 2;  % expand bracket until sign changes
    end

    opts = optimset('TolX',1e-12,'Display','off');
    v_inf = fzero(resid, [v_lo, v_hi], opts);
end

function xf = frac_distance_general(mu, rho_f, R, rho_steel, g, frac)
% Distance travelled (from rest) for a sphere under SCHILLER-NAUMANN drag to reach a given fraction

    v_inf = terminal_velocity_general(mu, rho_f, R, rho_steel, g);
    A = g*(rho_steel - rho_f)/rho_steel;

    odefun = @(t,y) ball_ode(t, y, mu, rho_f, R, rho_steel, A);
    v_target = frac * v_inf;
    event_fn = @(t,y) reach_frac_event(t, y, v_target);

    t_scale = v_inf / A;
    t_max   = 50 * t_scale;

    y0 = [0; 0];
    opts = odeset('Events', event_fn, 'RelTol',1e-9, 'AbsTol',1e-12);

    [~, ~, te, ye, ~] = ode45(odefun, [0, t_max], y0, opts);

    if isempty(te)
        xf = Inf;
    else
        xf = ye(1,2);
    end
end

function dydt = ball_ode(~, y, mu, rho_f, R, rho_steel, A)
% State y = [v
    v = y(1);
    Re = rho_f*abs(v)*(2*R)/mu;
    Cd = Cd_schiller_naumann(Re);
    dvdt = A - (3*Cd*rho_f/(8*R*rho_steel))*v^2;
    dxdt = v;
    dydt = [dvdt; dxdt];
end

function [value, isterminal, direction] = reach_frac_event(~, y, v_target)
    value = y(1) - v_target;
    isterminal = 1;  % stop integration
    direction = 1;  % only trigger on increasing crossing
end

function mu = mu_mixture(Cm, T)
% Cheng (2008) correlation for the viscosity of a glycerol-water mixture

    mu_w = 1.79e-3 * exp( ((-1230 - T).*T) ./ (36100 + 360*T) );
    mu_g = 12.1    * exp( ((-1233 + T).*T) ./ (9900 + 70*T)  );

    a = 0.705 - 0.0017*T;
    b = (4.9 + 0.036*T) .* a.^2.5;

    alpha = 1 - Cm + (a.*b.*Cm.*(1-Cm)) ./ (a.*Cm + b.*(1-Cm));

    mu = mu_w.^alpha .* mu_g.^(1-alpha);
end

function rho = rho_mixture(Cm, T)
% Ideal volume-mixing density of a glycerol-water mixture

    rho_w = rho_water(T);
    rho_g = rho_glycerol(T);

    rho = 1 ./ ( Cm./rho_g + (1-Cm)./rho_w );
end

function rho = rho_water(T)
% Kell (1975)-type polynomial for water density, degC -> kg/m^3
    rho = 999.842594 + 6.793952e-2*T - 9.095290e-3*T.^2 ...
        + 1.001685e-4*T.^3 - 1.120083e-6*T.^4 + 6.536332e-9*T.^5;
end

function rho = rho_glycerol(T)
% Linear fit for pure glycerol density near room temperature, degC -> kg/m^3
    rho = 1273.3 - 0.6121*T;
end
