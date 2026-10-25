%% RunCompileHeightHeatmaps
% Combines the heightResults*.mat files of one or more recording SESSIONS via CompileHeightHeatmaps.m
close all; clear; clc

%% WHAT TO COMBINE -- EDIT THESE
USE_SESSION_ORIGINS = true;  % true = combine the session folders below

FILE_PATTERN   = 'heightResults*.mat';  % matches every heightResults*.mat in each session folder

% Used when USE_SESSION_ORIGINS = true
DATASET_FOLDER = 'StratifiedResults';  % 'StratifiedResults' or 'SingleLayerResults'

% Dropper locations (mm): Stratified S1 [-1.988 -0.093], S2 [-1.588 -1.533]; SingleLayer S1 [-2.624 -0.472], S2 [-2.588 -3.533]
SESSIONS = struct( ...
    'name',     {'Matt',                'Charlie'}, ...
    'folder',   {'Session1',            'Session2'}, ...
    'originMm', {[-1.988 -0.093],       [-1.588 -1.533]});

% Used when USE_SESSION_ORIGINS = false
SESSION_FOLDER = 'StratifiedResults';  % where SplitAndTrackHeights.m saved heightResults.mat

% Where the synthetic "drop location" marker sits on the 3D stacked figure
START_MM        = [0 0];  % [x y] mm of the drop marker
START_CELL      = 'AW50';  % only used when START_MM = []
START_HEIGHT_MM = 330;  % [] = auto (one height-spacing above each ball size's own highest tracked height)

% Fluid conditions, for the red "terminal velocity reached" plane on the 3D stacked figure
SHOW_TERMINAL_VEL_PLANE = true;  % toggle the plane on/off
GLYCERINE_PERCENT       = 60;  % glycerine mass percentage of the fluid, 0-100
TEMPERATURE_C           = 18;  % fluid temperature, degrees C
TERMINAL_VEL_FRAC       = 0.99;  % 0.99 = plane marks 99% of terminal velocity

% Stratified-interface plane
SHOW_INTERFACE_PLANE = true;  % toggle the plane on/off (turn off for SingleLayerResults)
INTERFACE_HEIGHT_MM  = 180;  % mm above the tank base

% Zoom the heatmaps to the data (like the Gaussian code's nSigma)
USE_SIGMA_WINDOW = true;  % false = show the whole grid, as before
N_SIGMA          = 15;

SAVE_FIGURES = true;
if USE_SESSION_ORIGINS
    OUT_DIR = fullfile(DATASET_FOLDER, 'combined_height_heatmaps');
else
    OUT_DIR = fullfile(SESSION_FOLDER, 'combined_height_heatmaps');
end

%% FIND SESSION FILES
if USE_SESSION_ORIGINS
    [sessionFiles, sessionIdx, sessionNames, sessionOriginsMm] = ...
        gatherSessionFiles(DATASET_FOLDER, SESSIONS, FILE_PATTERN);
else
    if exist(SESSION_FOLDER, 'dir') ~= 7
        error(['Cannot find folder "%s".\nRun  pwd  and  dir  to check you are ' ...
            'in the right place, or set SESSION_FOLDER to a full path.'], SESSION_FOLDER);
    end

    listing = dir(fullfile(SESSION_FOLDER, FILE_PATTERN));
    if isempty(listing)
        error('CompileHeightHeatmaps:noFiles', ...
            'No files matching "%s" found in "%s".', FILE_PATTERN, SESSION_FOLDER);
    end

    sessionFiles = fullfile({listing.folder}, {listing.name});
    sessionIdx = []; sessionNames = {}; sessionOriginsMm = [];

    fprintf('Found %d session file(s) in "%s":\n', numel(sessionFiles), SESSION_FOLDER);
    for i = 1:numel(sessionFiles)
        fprintf('  %s\n', sessionFiles{i});
    end
end

%% COMPILE
if USE_SIGMA_WINDOW, nSigmaArg = N_SIGMA; else, nSigmaArg = []; end

results = CompileHeightHeatmaps(sessionFiles, 'saveFigures', SAVE_FIGURES, 'outDir', OUT_DIR, ...
    'startMm', START_MM, 'startCell', START_CELL, 'startHeightMm', START_HEIGHT_MM, ...
    'glycerinePercent', GLYCERINE_PERCENT, 'temperatureC', TEMPERATURE_C, ...
    'terminalVelFracTarget', TERMINAL_VEL_FRAC, ...
    'showTerminalVelPlane', SHOW_TERMINAL_VEL_PLANE, ...
    'showInterfacePlane', SHOW_INTERFACE_PLANE, 'interfaceHeightMm', INTERFACE_HEIGHT_MM, ...
    'nSigma', nSigmaArg, ...
    'sessionIdx', sessionIdx, 'sessionOriginsMm', sessionOriginsMm, ...
    'sessionNames', sessionNames);
