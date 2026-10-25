    %% density_viscosity_glycerine_mix
    % modified following Andreas Volk's latest modifications this code takes VOLUME fraction as input
    T = 19;
    fraction_glyc = 0.60;

    [rho,eta]=density_viscosity_glycerine_mix1(fraction_glyc,T)

    %% Reynolds number of the steel ball
    d_mm       = 4;  % ball diameter [mm]
    rho_ball   = 7794.3;  % steel density [kg/m^3] (about 7800-7850)
    V_measured = [572];  % measured fall speed [mm/s]

    [Re,V_mm_s,Cd] = ball_reynolds(d_mm,rho_ball,rho,eta,V_measured)

    Ga = galileo_number(d_mm,rho_ball,rho,eta)

    %% Glycerine + salt layer designer
    drho_target = 27.084;  % desired density increase from salt [kg/m^3]
    salt        = 'NaCl';  % 'NaCl' or 'KI'
    batch_L     = 1.0;  % batch size for the recipe printout [litres]
    cal.rho = 1.0;  % calibration factors, leave at 1 until you have
    cal.eta = 1.0;  % measured a test batch

    phi0 = fraction_glyc;
    [rho0, eta0] = mix_props(phi0, 0, T, salt, cal);
    rho_target   = rho0 + drho_target;

    fprintf('\nSalt: %s,  T = %.1f C\n', salt, T);
    fprintf('Starting fluid : %.3f vol frac glycerol, rho = %.1f kg/m^3, eta = %.2f mPa.s\n', ...
            phi0, rho0, 1e3*eta0);
    fprintf('Target         : rho = %.1f kg/m^3, eta = %.2f mPa.s\n\n', rho_target, 1e3*eta0);

    phiA = phi0; rhoA = NaN; etaA = NaN;
    wsA = salt_for_density(phi0, rho_target, T, salt, cal);
    if isnan(wsA)
        fprintf('Option A: target density not reachable within salt solubility limit.\n\n');
    else
        [rhoA, etaA] = mix_props(phi0, wsA, T, salt, cal);
        fprintf('Option A - salt only (glycerol unchanged):\n');
        fprintf('  glycerol vol frac = %.4f, salt = %.2f wt%%\n', phi0, 100*wsA);
        fprintf('  rho = %.1f kg/m^3, eta = %.2f mPa.s (%+.1f%% vs start)\n\n', ...
                rhoA, 1e3*etaA, 100*(etaA/eta0 - 1));
        print_recipe(phi0, wsA, rhoA, T, batch_L);
    end

    phiB = NaN; wsB = NaN; rhoB = NaN; etaB = NaN;
    visc_err = @(phi) viscosity_error(phi, rho_target, eta0, T, salt, cal);
    phis = max(0.01, phi0-0.30) : 0.0025 : min(0.99, phi0+0.20);
    errs = arrayfun(visc_err, phis);
    idx  = find(~isnan(errs(1:end-1)) & ~isnan(errs(2:end)) & ...
                sign(errs(1:end-1)) ~= sign(errs(2:end)));
    if isempty(idx)
        fprintf('Option B: no glycerol/salt combination found that matches both targets.\n\n');
    else
        [~, k] = min(abs(phis(idx) - phi0));
        phiB   = fzero(visc_err, phis(idx(k) + [0 1]));
        wsB    = salt_for_density(phiB, rho_target, T, salt, cal);
        [rhoB, etaB] = mix_props(phiB, wsB, T, salt, cal);
        fprintf('Option B - viscosity matched:\n');
        fprintf('  glycerol vol frac = %.4f (was %.4f), salt = %.2f wt%%\n', phiB, phi0, 100*wsB);
        fprintf('  rho = %.1f kg/m^3, eta = %.2f mPa.s (%+.1f%% vs start)\n\n', ...
                rhoB, 1e3*etaB, 100*(etaB/eta0 - 1));
        print_recipe(phiB, wsB, rhoB, T, batch_L);
    end

    %% Summary: all fluids, same ball
    [Re0,V0] = ball_reynolds(d_mm,rho_ball,rho0,eta0,[]);
    fprintf('Ball: %.2f mm, steel %.0f kg/m^3\n', d_mm, rho_ball);
    Ga0 = galileo_number(d_mm,rho_ball,rho0,eta0);
    fprintf('%-26s %9s %8s %11s %12s %10s %8s %8s\n', 'Fluid', 'Glyc vol', 'Salt wt%', ...
            'rho kg/m^3', 'eta mPa.s', 'V mm/s', 'Re', 'Ga');
    fprintf('%-26s %9.4f %8.2f %11.1f %12.3f %10.1f %8.1f %8.1f\n', 'Top (glycerine only)', ...
            phi0, 0, rho0, 1e3*eta0, V0, Re0, Ga0);

    labs = {'Salt layer A (salt only)', 'Salt layer B (visc matched)'};
    phis_ = [phiA phiB];  wss_ = [wsA wsB];
    rhos_ = [rhoA rhoB];  etas_ = [etaA etaB];
    for i = 1:2
        if isnan(rhos_(i))
            fprintf('%-26s not available (see messages above)\n', labs{i});
        else
            [ReS,VS] = ball_reynolds(d_mm,rho_ball,rhos_(i),etas_(i),[]);
            GaS = galileo_number(d_mm,rho_ball,rhos_(i),etas_(i));
            fprintf('%-26s %9.4f %8.2f %11.1f %12.3f %10.1f %8.1f %8.1f\n', labs{i}, ...
                    phis_(i), 100*wss_(i), rhos_(i), 1e3*etas_(i), VS, ReS, GaS);
            fprintf('   vs top: drho = %+.1f kg/m^3, eta %+.1f%%, Re %+.1f%%, Ga %+.1f%%\n', ...
                    rhos_(i)-rho0, 100*(etas_(i)/eta0-1), 100*(ReS/Re0-1), 100*(GaS/Ga0-1));
        end
    end

    %% Ga-Re_p reference figure
    Ga_lin = linspace(50, 150, 400);
    Re_num = Ga_lin.^2 .* (22.5 + Ga_lin.^1.364) ./ ...
        (0.0258*Ga_lin.^2.6973 + 2.81*Ga_lin.^2.0306 + 18*Ga_lin.^1.364 + 405);

    ptNames = {'Top (glycerine only)', 'Salt layer A (salt only)', 'Salt layer B (visc matched)'};
    ptRho = [rho0 rhos_];  ptEta = [eta0 etas_];
    ptGa  = nan(1,3);      ptRe  = nan(1,3);
    for i = 1:3
        if ~isnan(ptRho(i))
            ptGa(i) = galileo_number(d_mm,rho_ball,ptRho(i),ptEta(i));
            ptRe(i) = ball_reynolds(d_mm,rho_ball,ptRho(i),ptEta(i),[]);
        end
    end

    figure('Color','w','Name','Ga-Re_p: mixture options');
    hold on; grid on; box on;
    hCurve = plot(Ga_lin, Re_num, 'k-', 'LineWidth', 1.5, ...
        'DisplayName', 'Eq. (5), Cabrera-Booman et al. (2024)');
    ptMarkers = {'o','s','^'};
    ptColors  = lines(3);
    hPts = gobjects(0);
    for i = 1:3
        if isnan(ptGa(i)), continue; end
        hPts(end+1) = plot(ptGa(i), ptRe(i), ptMarkers{i}, 'MarkerSize', 7, ...
            'MarkerFaceColor', ptColors(i,:), 'Color', ptColors(i,:), ...
            'DisplayName', sprintf('%s (Ga = %.1f, Re = %.1f)', ptNames{i}, ptGa(i), ptRe(i)));  %#ok<SAGROW>
    end
    xlabel('Ga'); ylabel('Re_p');
    legend([hCurve, hPts], 'Location', 'northwest');
    title(sprintf('Terminal Re_p vs Ga: %.0f mm ball (glycerin %.0f%%, T = %.1f C, %s)', ...
        d_mm, fraction_glyc*100, T, salt), 'FontSize', 10);
    xlim([50 max(150, 1.1*max(ptGa(~isnan(ptGa))))]);
    try
        saveas(gcf, fullfile(fileparts(mfilename('fullpath')), 'GaRe_mixture_options.png'));
    catch
    end

    function[rho,eta]=density_viscosity_glycerine_mix1(fraction_glyc,T)

    volume_glycerol=fraction_glyc;
    volume_water=1-fraction_glyc;

    total_volume=volume_glycerol+volume_water;
    volume_fraction=volume_glycerol/total_volume;

    density_glycerol=1273.3-0.6121*T;  % UPDATED following Andreas Volk's suggestion

    density_water=1000*(1-((abs(T-3.98))/615)^1.71);

    mass_glycerol=density_glycerol*volume_glycerol;
    mass_water=density_water*volume_water;
    total_mass=mass_glycerol+mass_water;
    mass_fraction=mass_glycerol/total_mass;

    viscosity_glycerol=0.001*12100*exp((-1233+T)*T/(9900+70*T));
    viscosity_water=0.001*1.790*exp((-1230-T)*T/(36100+360*T));

    a=0.705-0.0017*T;
    b=(4.9+0.036*T)*a^2.5;
    alpha=1-mass_fraction+(a*b*mass_fraction*(1-mass_fraction))/(a*mass_fraction+b*(1-mass_fraction));
    A=log(viscosity_water/viscosity_glycerol);
    viscosity_mix=viscosity_glycerol*exp(A*alpha);

    c=1.78E-6*T.^2-1.82E-4*T+1.41E-2;
    contraction=1+(c.*sin((mass_fraction).^1.31.*pi).^0.81);

    density_mix=(density_glycerol*fraction_glyc+density_water*(1-fraction_glyc))*contraction;

    eta=viscosity_mix;
    rho=density_mix;
    end

    function Ga = galileo_number(d_mm,rho_ball,rho,eta)
    % Galileo number as defined in ValidateGaRe_Uncertainty.m: Ga = sqrt((rho_p/rho_f - 1)*g) * D^1.5 / nu, nu
    g  = 9.81;  % m/s^2
    D  = d_mm/1000;
    nu = eta/rho;  % m^2/s
    Ga = sqrt(abs(rho_ball/rho - 1)*g) * D^1.5 / nu;
    end

    function [Re,V_mm_s,Cd] = ball_reynolds(d_mm,rho_ball,rho,eta,V_measured)
    % Reynolds number Re = rho*V*d/eta of a sphere falling through the fluid
    g = 9.81;  % m/s^2
    d = d_mm/1000;

    if nargin>=5 && ~isempty(V_measured)
        V = V_measured/1000;  % m/s
        Re = rho*V*d/eta;
    else
        K = (4/3)*g*d^3*rho*(rho_ball-rho)/eta^2;
        if K<=0
            error('Ball is not denser than the fluid - it will not sink.');
        end
        CdRe2 = @(R) (R<1000).*24.*R.*(1+0.15*R.^0.687) + (R>=1000).*0.44.*R.^2;
        Re = fzero(@(R) CdRe2(R)-K, [1e-8 1e7]);
        V = Re*eta/(rho*d);
    end

    if Re<1000
        Cd = 24/Re*(1+0.15*Re^0.687);
    else
        Cd = 0.44;
    end
    V_mm_s = V*1000;
    end

function [rho, eta, mass_frac_gly] = glycerol_water(phi, T)
% Original glycerol-water model (volume fraction input), unchanged
volume_glycerol = phi;
volume_water    = 1 - phi;

density_glycerol = 1273.3 - 0.6121*T;
density_water    = 1000*(1 - ((abs(T-3.98))/615)^1.71);

mass_glycerol = density_glycerol*volume_glycerol;
mass_water    = density_water*volume_water;
mass_frac_gly = mass_glycerol/(mass_glycerol + mass_water);

viscosity_glycerol = 0.001*12100*exp((-1233+T)*T/(9900+70*T));
viscosity_water    = 0.001*1.790*exp((-1230-T)*T/(36100+360*T));

a = 0.705 - 0.0017*T;
b = (4.9 + 0.036*T)*a^2.5;
cm = mass_frac_gly;
alpha = 1 - cm + (a*b*cm*(1-cm))/(a*cm + b*(1-cm));
A   = log(viscosity_water/viscosity_glycerol);
eta = viscosity_glycerol*exp(A*alpha);

c = 1.78E-6*T.^2 - 1.82E-4*T + 1.41E-2;
contraction = 1 + (c.*sin((cm).^1.31.*pi).^0.81);
rho = (density_glycerol*phi + density_water*(1-phi))*contraction;
end

function p = salt_params(salt)
% Empirical fits to aqueous data at ~20 C, ws = salt MASS fraction: rho_ratio = 1 + k1*ws + k2*ws^2 eta_ratio
switch upper(salt)
    case 'NACL'
        p.k1 = 0.7075; p.k2 = 0.215;
        p.c1 = 1.29;   p.c2 = 4.5;
        p.ws_max = 0.20;  % conservative solubility limit in glycerol-water
    case 'KI'
        p.k1 = 0.7195; p.k2 = 0.605;
        p.c1 = -0.15;  p.c2 = 0.10;  % KI slightly LOWERS water viscosity
        p.ws_max = 0.40;
    otherwise
        error('Unknown salt "%s". Use ''NaCl'' or ''KI''.', salt);
end
end

function [rho, eta] = mix_props(phi, ws, T, salt, cal)
% Density and viscosity of glycerol-water (vol frac phi) + salt (mass frac ws)
[rho_gw, eta_gw] = glycerol_water(phi, T);
p   = salt_params(salt);
rho = rho_gw * (1 + cal.rho*(p.k1*ws + p.k2*ws^2));
eta = eta_gw * exp(cal.eta*(p.c1*ws + p.c2*ws^2));
end

function ws = salt_for_density(phi, rho_target, T, salt, cal)
% Salt mass fraction needed to hit rho_target at glycerol vol frac phi
p = salt_params(salt);
g = @(w) mix_props(phi, w, T, salt, cal) - rho_target;
if g(0) > 0 || g(p.ws_max) < 0
    ws = NaN;
else
    ws = fzero(g, [0 p.ws_max]);
end
end

function err = viscosity_error(phi, rho_target, eta0, T, salt, cal)
% Relative viscosity mismatch when salt is set to hit the target density
ws = salt_for_density(phi, rho_target, T, salt, cal);
if isnan(ws)
    err = NaN;
else
    [~, eta] = mix_props(phi, ws, T, salt, cal);
    err = eta/eta0 - 1;
end
end

function print_recipe(phi, ws, rho, T, batch_L)
% Masses and volumes of each ingredient for a batch of batch_L litres
[~, ~, wg] = glycerol_water(phi, T);
density_glycerol = 1273.3 - 0.6121*T;
density_water    = 1000*(1 - ((abs(T-3.98))/615)^1.71);

M_total = rho * batch_L/1000;
m_salt  = ws * M_total;
m_gly   = (1-ws) * wg * M_total;
m_water = (1-ws) * (1-wg) * M_total;

fprintf('  Recipe for %.2f L (final volume):\n', batch_L);
fprintf('    glycerol : %8.1f g  (%6.1f mL pure)\n', 1e3*m_gly,   1e6*m_gly/density_glycerol);
fprintf('    water    : %8.1f g  (%6.1f mL)\n',      1e3*m_water, 1e6*m_water/density_water);
fprintf('    salt     : %8.1f g\n\n',                1e3*m_salt);
end
