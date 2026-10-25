%% ValidateGaRe_Uncertainty
% Ga-Re_p validation plot with PROPAGATED measurement uncertainty
clear; clc; close all;

%% CONFIGURATION (everything you may want to change is here)
GLYCERIN_PERCENTAGE = 0.46;  % fraction glycerol, 0-1
TEMPERATURE_C       = 17;  % fluid temperature, C
BALL_DIAMS_MM       = [2 3 4 5];
RHO_STEEL           = 7794.3;  % kg/m^3

% measurement uncertainties (all +-, same units as the quantity)
DELTA_D_MM       = 0.01;  % ball diameter, mm
DELTA_T_C        = 1;  % temperature, C
DELTA_GLYC       = 0.01;  % glycerine fraction, ABSOLUTE (0.01 = +-1 %)
DELTA_RHO_STEEL  = 10;  % steel density, kg/m^3

% which error bars to DISPLAY on the plot (true/false each)
SHOW_RSS = true;  % root-sum-square (tolerances used as given)
SHOW_MAX = false;  % maximum (worst-case linear sum)
SHOW_GUM = false;  % GUM expanded uncertainty, U = k * u_c

% GUM settings
GUM_K = 2;  % coverage factor (2 -> ~95 %)
GUM_RECT_DIVISOR = sqrt(3);
GUM_USE_STD_ERROR = false;  % false: drop scatter = std across drops (same as the RSS/MAX bars). true

% velocity systematic terms
FPS_REL_UNCERTAINTY = 0.001;  % relative frame-timing uncertainty (0.1 %)
USE_CALIB_SCALE_DRIFT = true;  % |pre/post scale drift %| as relative error
USE_CALIB_POSITION    = true;  % calibration RMSE (mm) -> velocity error over the averaging window: du

FALLBACK_SCALE_DRIFT_PCT = 0;  % Fallbacks if calibration.mat cannot be read (set these by hand then)
FALLBACK_RMSE_MM         = 0;

SCRIPT_DIR   = fileparts(mfilename('fullpath'));
if isempty(SCRIPT_DIR), SCRIPT_DIR = pwd; end
RESULTS_DIR  = SCRIPT_DIR;  % folder containing mean_vx_results_Xmm.mat
FILE_PATTERN = 'mean_vx_results_%dmm.mat';
CALIB_FILE   = fullfile(SCRIPT_DIR, 'calibration.mat');

G = 9.81;

%% CALIBRATION-DERIVED SYSTEMATICS
scaleRel = 0;  rmse_mm = 0;
calibOK = false;
if exist(CALIB_FILE, 'file') == 2
    try
        C = load(CALIB_FILE, 'calib'); calib = C.calib;
        scaleDriftPct = abs(calib.drift.scale_pct);
        rmse_mm = max(calib.pre.rmse_mm, calib.post.rmse_mm);
        calibOK = true;
    catch ME
        warning('Could not read calibration fields (%s). Using fallbacks.', ME.message);
    end
end
if ~calibOK
    scaleDriftPct = FALLBACK_SCALE_DRIFT_PCT;
    rmse_mm       = FALLBACK_RMSE_MM;
end
if USE_CALIB_SCALE_DRIFT, scaleRel = scaleDriftPct/100; end
if ~USE_CALIB_POSITION,   rmse_mm = 0; end
fprintf('Calibration systematics: scale drift %.3f %% | RMSE %.4f mm (%s)\n', ...
    scaleDriftPct, rmse_mm, ternary(calibOK, 'from calibration.mat', 'FALLBACK values'));

%% NOMINAL FLUID PROPERTIES
[nu0, rhoF0] = fluid_props(GLYCERIN_PERCENTAGE, TEMPERATURE_C);
fprintf('Glycerin %.1f %%, T = %.1f C -> nu = %.4e m^2/s, rho_f = %.1f kg/m^3\n', ...
    GLYCERIN_PERCENTAGE*100, TEMPERATURE_C, nu0, rhoF0);

ReModel = @(x) x(1) * x(2) / fluid_nu(x(5), x(4));
GaModel = @(x) sqrt(abs(x(3)/fluid_rho(x(5), x(4)) - 1) * G) * x(2)^1.5 / fluid_nu(x(5), x(4));

inputNames = {'u','D','rho_p','T','phi'};

%% LOAD DATA + PROPAGATE
nD = numel(BALL_DIAMS_MM);
GaVal = nan(nD,1); ReVal = nan(nD,1);
dRe_RSS = nan(nD,1); dRe_MAX = nan(nD,1);
dGa_RSS = nan(nD,1); dGa_MAX = nan(nD,1);
dRe_GUM = nan(nD,1); dGa_GUM = nan(nD,1);
stdOnlyRe = nan(nD,1);
uMean = nan(nD,1); uStd = nan(nD,1); nDrops = zeros(nD,1);
du_RSS = nan(nD,1); du_MAX = nan(nD,1); du_GUM = nan(nD,1);
valid = false(nD,1);
contribRe = nan(nD, numel(inputNames));
contribGa = nan(nD, numel(inputNames));

for k = 1:nD
    d_mm = BALL_DIAMS_MM(k);
    fname = fullfile(RESULTS_DIR, sprintf(FILE_PATTERN, d_mm));
    if exist(fname, 'file') ~= 2
        warning('Missing %s - skipping %d mm.', fname, d_mm); continue
    end
    S = load(fname, 'meanVx_ms', 'included', 'winStart_s', 'winEnd_s');
    sel = S.included & ~isnan(S.meanVx_ms);
    vx = S.meanVx_ms(sel);
    if isempty(vx), warning('No included drops for %d mm.', d_mm); continue; end

    u    = mean(vx);
    sd   = std(vx);
    win  = mean(S.winEnd_s(sel) - S.winStart_s(sel));

    % velocity uncertainty, components
    du_rand = sd;
    du_scale= u * scaleRel;
    du_fps  = u * FPS_REL_UNCERTAINTY;
    if rmse_mm > 0 && win > 0
        du_pos = sqrt(2) * (rmse_mm*1e-3) / win;
    else
        du_pos = 0;
    end
    du_RSS(k) = sqrt(du_rand^2 + du_scale^2 + du_fps^2 + du_pos^2);
    du_MAX(k) = du_rand + du_scale + du_fps + du_pos;

    if GUM_USE_STD_ERROR
        du_rand_gum = sd / sqrt(numel(vx));
    else
        du_rand_gum = sd;
    end
    du_GUM(k) = sqrt(du_rand_gum^2 + (du_scale/GUM_RECT_DIVISOR)^2 + ...
                     (du_fps/GUM_RECT_DIVISOR)^2 + du_pos^2);

    % nominal inputs and uncertainty vectors
    D   = d_mm*1e-3;
    x0  = [u, D, RHO_STEEL, TEMPERATURE_C, GLYCERIN_PERCENTAGE];
    dxR = [du_RSS(k), DELTA_D_MM*1e-3, DELTA_RHO_STEEL, DELTA_T_C, DELTA_GLYC];
    dxM = [du_MAX(k), DELTA_D_MM*1e-3, DELTA_RHO_STEEL, DELTA_T_C, DELTA_GLYC];

    [ReVal(k), dRe_RSS(k), dRe_MAX(k), cRe] = propagate(ReModel, x0, dxR, dxM);
    [GaVal(k), dGa_RSS(k), dGa_MAX(k), cGa] = propagate(GaModel, x0, dxR, dxM);
    contribRe(k,:) = cRe; contribGa(k,:) = cGa;

    dxG = [du_GUM(k), DELTA_D_MM*1e-3/GUM_RECT_DIVISOR, DELTA_RHO_STEEL/GUM_RECT_DIVISOR, ...
           DELTA_T_C/GUM_RECT_DIVISOR, DELTA_GLYC/GUM_RECT_DIVISOR];
    [~, ucRe] = propagate(ReModel, x0, dxG, dxG);
    [~, ucGa] = propagate(GaModel, x0, dxG, dxG);
    dRe_GUM(k) = GUM_K * ucRe;
    dGa_GUM(k) = GUM_K * ucGa;

    stdOnlyRe(k) = sd * D / nu0;
    uMean(k) = u; uStd(k) = sd; nDrops(k) = numel(vx);
    valid(k) = true;

    fprintf('\n%d mm (n=%d): Re_p = %.3f, Ga = %.2f\n', d_mm, numel(vx), ReVal(k), GaVal(k));
    fprintf('   du: random %.4f | scale %.4f | fps %.4f | calib-pos %.4f m/s  -> RSS %.4f, MAX %.4f\n', ...
        du_rand, du_scale, du_fps, du_pos, du_RSS(k), du_MAX(k));
    fprintf('   dRe: RSS %.3f (%.1f %%) | MAX %.3f (%.1f %%) | GUM U(k=%g) %.3f (%.1f %%) | old std-only %.3f\n', ...
        dRe_RSS(k), 100*dRe_RSS(k)/ReVal(k), dRe_MAX(k), 100*dRe_MAX(k)/ReVal(k), ...
        GUM_K, dRe_GUM(k), 100*dRe_GUM(k)/ReVal(k), stdOnlyRe(k));
    fprintf('   dGa: RSS %.3f (%.1f %%) | MAX %.3f (%.1f %%) | GUM U(k=%g) %.3f (%.1f %%)\n', ...
        dGa_RSS(k), 100*dGa_RSS(k)/GaVal(k), dGa_MAX(k), 100*dGa_MAX(k)/GaVal(k), ...
        GUM_K, dGa_GUM(k), 100*dGa_GUM(k)/GaVal(k));
    shareRe = [inputNames; num2cell(100*cRe)];
    shareGa = [inputNames; num2cell(100*cGa)];
    fprintf('   RSS share of dRe^2:  '); fprintf('%s %.0f%%  ', shareRe{:}); fprintf('\n');
    fprintf('   RSS share of dGa^2:  '); fprintf('%s %.0f%%  ', shareGa{:}); fprintf('\n');
end

%% SUMMARY TABLE
summaryTable = table(BALL_DIAMS_MM(:), nDrops, uMean, uStd, du_RSS, du_MAX, du_GUM, ...
    GaVal, dGa_RSS, dGa_MAX, dGa_GUM, ReVal, dRe_RSS, dRe_MAX, dRe_GUM, stdOnlyRe, valid, ...
    'VariableNames', {'diameter_mm','nDrops','u_mean_m_s','u_std_m_s','du_RSS_m_s','du_MAX_m_s','du_GUM_std_m_s', ...
    'Ga','dGa_RSS','dGa_MAX','dGa_GUM_U','Re_p','dRe_RSS','dRe_MAX','dRe_GUM_U','dRe_oldStdOnly','valid'});
disp(summaryTable);
writetable(summaryTable, fullfile(SCRIPT_DIR, 'uncertainty_summary.csv'));

%% THEORETICAL CURVE (Eq. 5, Cabrera-Booman et al. 2024)
Ga_lin = linspace(0, 500, 400);
Re_num = Ga_lin.^2 .* (22.5 + Ga_lin.^1.364) ./ ...
    (0.0258*Ga_lin.^2.6973 + 2.81*Ga_lin.^2.0306 + 18*Ga_lin.^1.364 + 405);

%% PLOT
% error-bar methods, listed outermost first (drawing order)
methodTag  = {'MAX','GUM','RSS'};
methodOn   = [SHOW_MAX, SHOW_GUM, SHOW_RSS];
methodDesc = {'Maximum error', ...
              sprintf('GUM expanded uncertainty (k = %g)', GUM_K), ...
              'Root-sum-square'};
bgLight    = [0.45 0.25 0];  % blend toward white for bars drawn BEHIND
lineW      = [1 1.4 1.8];
capSz      = [11 8 5];
ErrRe = [dRe_MAX, dRe_GUM, dRe_RSS];  % nD x 3, same order as methodTag
ErrGa = [dGa_MAX, dGa_GUM, dGa_RSS];
idxOn = find(methodOn);

if isempty(idxOn), tag = 'none'; else, tag = strjoin(methodTag(idxOn), '_'); end
outPng = ['ReferenceStudy_Uncertainty_' tag '.png'];

figure('Color','w','Name','Ga-Re_p validation with propagated uncertainty');
hold on; grid on; box on;

hCurve = plot(Ga_lin, Re_num, 'k-', 'LineWidth', 1.5, ...
    'DisplayName', 'Eq. (5), Cabrera-Booman et al. (2024)');

markers = {'o','s','^','d','v','p','h','x'};
colors  = lines(nD);
hPts = gobjects(0);

for k = 1:nD
    if ~valid(k), continue; end
    mk   = markers{mod(k-1, numel(markers)) + 1};
    c    = colors(k,:);
    name = sprintf('%d mm', BALL_DIAMS_MM(k));

    if isempty(idxOn)
        hPts(end+1) = plot(GaVal(k), ReVal(k), mk, 'MarkerSize', 6, ...
            'MarkerFaceColor', c, 'Color', c, 'DisplayName', name);  %#ok<SAGROW>
        continue
    end

    for j = idxOn(1:end-1)
        errorbar(GaVal(k), ReVal(k), ErrRe(k,j), ErrRe(k,j), ErrGa(k,j), ErrGa(k,j), ...
            'LineStyle','none', 'Color', (1-bgLight(j))*c + bgLight(j), ...
            'LineWidth', lineW(j), 'CapSize', capSz(j), 'HandleVisibility','off');
    end
    j = idxOn(end);
    hPts(end+1) = errorbar(GaVal(k), ReVal(k), ErrRe(k,j), ErrRe(k,j), ErrGa(k,j), ErrGa(k,j), ...
        mk, 'MarkerSize', 6, 'MarkerFaceColor', c, 'Color', c, ...
        'LineWidth', lineW(j), 'CapSize', capSz(j), 'DisplayName', name);  %#ok<SAGROW>
end

legHandles = [hCurve, hPts];
if numel(idxOn) > 1
    for j = idxOn
        gray = 0.2 + 0.8*bgLight(j);
        legHandles(end+1) = plot(nan, nan, '-', 'Color', gray*[1 1 1], ...
            'LineWidth', lineW(j), 'DisplayName', methodDesc{j});  %#ok<SAGROW>
    end
end

if isempty(idxOn)
    barLabel = 'no error bars';
else
    barLabel = strjoin(lower(methodDesc(idxOn)), ' + ');
    barLabel = strrep(barLabel, 'gum expanded', 'GUM expanded');
end

xlabel('Ga'); ylabel('Re_p');
legend(legHandles, 'Location', 'northwest');
title(sprintf('Terminal Re_p vs Ga: %s (glycerin %.0f%%, T = %.0f C)', ...
    barLabel, GLYCERIN_PERCENTAGE*100, TEMPERATURE_C), 'FontSize', 10);
saveas(gcf, fullfile(SCRIPT_DIR, outPng));
fprintf('\nSaved %s and uncertainty_summary.csv in %s\n', outPng, SCRIPT_DIR);

%% LOCAL FUNCTIONS
function [F0, dRSS, dMAX, shareRSS] = propagate(model, x0, dxRSS, dxMAX)
% Numerical partials of model(x) by central difference, then RSS: sqrt(sum (dF/dx_i * dx_i)^2) MAX
    F0 = model(x0);
    n  = numel(x0);
    dFdx = zeros(1, n);
    for i = 1:n
        h  = 1e-4 * max(abs(x0(i)), 1e-3);
        xp = x0; xp(i) = x0(i) + h;
        xm = x0; xm(i) = x0(i) - h;
        dFdx(i) = (model(xp) - model(xm)) / (2*h);
    end
    termR = dFdx .* dxRSS;
    termM = dFdx .* dxMAX;
    dRSS  = sqrt(sum(termR.^2));
    dMAX  = sum(abs(termM));
    shareRSS = termR.^2 / dRSS^2;
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

function [nu_mix, rho_mix] = fluid_props(glycerinFrac, T)
% Returns kinematic viscosity (m^2/s) and density (kg/m^3)
    nu_mix  = fluid_nu(glycerinFrac, T);
    rho_mix = fluid_rho(glycerinFrac, T);
end

function nu = fluid_nu(glycerinFrac, T)
    [nu, ~] = mixture_props(1 - glycerinFrac, T);
end

function rho = fluid_rho(glycerinFrac, T)
    [~, rho_gcm3] = mixture_props(1 - glycerinFrac, T);
    rho = rho_gcm3 * 1e3;
end

function [nu_mix, density_mix] = mixture_props(water_ratio, T)
% Identical physics to get_nu() in ValidateGaRe.m
    glyc_ratio = 1 - water_ratio;

    side_length = 19.9E-2;
    height = 35E-2;
    total_vol = 3*sqrt(3)/2*side_length^2*height;

    water_vol = water_ratio*total_vol*1E6;
    glyc_vol  = glyc_ratio*total_vol*1E6;

    rho_water = 1 - (abs(T-4)/622)^1.7;
    rho_glyc  = (1273.3-0.6121*T)/1000;

    mass_water = water_vol*rho_water;
    mass_glyc  = glyc_vol*rho_glyc;
    mass_tot   = mass_glyc + mass_water;
    mass_fraction = mass_glyc/mass_tot;
    vol_fraction  = glyc_vol/(glyc_vol + water_vol);

    contraction_av = 1 - (3.520e-8*(mass_fraction*100))^3 ...
                       + (1.027e-6*(mass_fraction*100))^2 ...
                       + 2.5e-4*(mass_fraction*100) ...
                       - 1.691e-4;
    contraction = 1 + contraction_av/100;

    density_mix = (rho_glyc*vol_fraction + rho_water*(1-vol_fraction)) * contraction;

    glycerolVisc = 0.001*12100*exp((-1233+T)*T/(9900+70*T));
    waterVisc    = 0.001*1.790*exp((-1230-T)*T/(36100+360*T));

    a = 0.705 - 0.0017*T;
    b = (4.9 + 0.036*T) * a^2.5;
    alpha = 1 - mass_fraction + (a*b*mass_fraction*(1-mass_fraction)) / (a*mass_fraction + b*(1-mass_fraction));
    A = log(waterVisc/glycerolVisc);

    mu_mix = glycerolVisc*exp(A*alpha);
    nu_mix = mu_mix/(density_mix*1E3);
end
