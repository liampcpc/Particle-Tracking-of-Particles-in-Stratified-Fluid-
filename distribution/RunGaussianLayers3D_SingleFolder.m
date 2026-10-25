%% RunGaussianLayers3D_SingleFolder
% The original, ONE-FOLDER version of RunGaussianLayers3D.m
close all; clear; clc

% Dropper locations (mm): Stratified S1 [-1.988 -0.093], S2 [-1.588 -1.533]; SingleLayer S1 [-2.624 -0.472], S2 [-2.588 -3.533]
SESSION_FOLDER = 'SingleLayerResults/Session2';  % ONE session's folder of heightResults*.mat
FILE_PATTERN   = 'heightResults*.mat';

% Plot options
N_SIGMA         = 4;  % plotted window = mean +/- N_SIGMA std (common to a ball size's layers)
SHOW_POINTS     = true;  % individual drops as black dots on the bell
SHOW_EMPIRICAL  = true;  % measured x / y histograms as gray steps on the walls
DROP_DUPLICATES = false;  % false = count every row, even exact copies
REQUIRE_IN_BOUNDS = true;  % true = skip rows the tracker flagged inBounds = false (it lost the ball)
ORIGIN_CELL     = '';  % grid cell whose CENTRE becomes (0, 0) in every figure, e.g. 'AW50'
ORIGIN_MM       = [-2.588 -3.533];  % OR an exact origin in mm, [x y], e.g. the dropper location

SAVE_FIGURES = true;
OUT_DIR = fullfile(SESSION_FOLDER, 'combined_gaussians');

%% FIND SESSION FILES
if exist(SESSION_FOLDER, 'dir') ~= 7
    error(['Cannot find folder "%s".\nRun  pwd  and  dir  to check you are ' ...
        'in the right place, or set SESSION_FOLDER to a full path.'], SESSION_FOLDER);
end

listing = dir(fullfile(SESSION_FOLDER, FILE_PATTERN));
if isempty(listing)
    error('GaussianLayers3D:noFiles', ...
        'No files matching "%s" found in "%s".', FILE_PATTERN, SESSION_FOLDER);
end

sessionFiles = fullfile({listing.folder}, {listing.name});

fprintf('Found %d session file(s) in "%s":\n', numel(sessionFiles), SESSION_FOLDER);
for i = 1:numel(sessionFiles)
    fprintf('  %s\n', sessionFiles{i});
end

%% BUILD THE FIGURES
results = GaussianLayers3D(sessionFiles, 'saveFigures', SAVE_FIGURES, 'outDir', OUT_DIR, ...
    'nSigma', N_SIGMA, 'showPoints', SHOW_POINTS, 'showEmpirical', SHOW_EMPIRICAL, ...
    'dropDuplicates', DROP_DUPLICATES, 'requireInBounds', REQUIRE_IN_BOUNDS, ...
    'originCell', ORIGIN_CELL, 'originMm', ORIGIN_MM);
