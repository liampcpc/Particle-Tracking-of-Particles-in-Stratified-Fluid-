%% RunGaussianLayers3D
% Gathers the heightResults*.mat files of one or more recording SESSIONS and builds one 3D Gaussian figure
close all; clear; clc

%% WHAT TO COMBINE -- EDIT THESE
DATASET_FOLDER = 'SingleLayerResults';  % 'StratifiedResults' or 'SingleLayerResults'
FILE_PATTERN   = 'heightResults*.mat';

USE_SESSION_ORIGINS = true;  % true = shift each session to its own dropper location

% Dropper locations (mm): Stratified S1 [-1.988 -0.093], S2 [-1.588 -1.533]; SingleLayer S1 [-2.624 -0.472], S2 [-2.588 -3.533]
SESSIONS = struct( ...
    'name',     {'Matt',                'Charlie'}, ...
    'folder',   {'Session1',            'Session2'}, ...
     'originMm', {[-2.624 -0.472],       [-2.588 -3.533]});

%% PLOT OPTIONS -- EDIT THESE
N_SIGMA         = 4;  % plotted window = mean +/- N_SIGMA std (common to a ball size's layers)
SHOW_POINTS     = false;  % individual drops as dots on the bell (coloured per session)
SHOW_EMPIRICAL  = true;  % measured x / y histograms as gray steps on the walls
DROP_DUPLICATES = false;  % false = count every row, even exact copies
REQUIRE_IN_BOUNDS = true;  % true = skip rows the tracker flagged inBounds = false (it lost the ball)

% Only used when USE_SESSION_ORIGINS = false
ORIGIN_CELL     = '';  % grid cell whose CENTRE becomes (0, 0), e.g. 'AW50', or several in braces
ORIGIN_MM       = [];  % OR an exact origin in mm, [x y], e.g

SAVE_FIGURES = true;
OUT_DIR = fullfile(DATASET_FOLDER, 'combined_gaussians');

%% FIND THE FILES OF EVERY SESSION
if exist(DATASET_FOLDER, 'dir') ~= 7
    error(['Cannot find folder "%s".\nRun  pwd  and  dir  to check you are ' ...
        'in the right place, or set DATASET_FOLDER to a full path.'], DATASET_FOLDER);
end

sessionFiles = {};
sessionIdx   = [];
sessionNames = {};
sessionOriginsMm = zeros(0, 2);

for k = 1:numel(SESSIONS)
    folder = fullfile(DATASET_FOLDER, SESSIONS(k).folder);
    if exist(folder, 'dir') ~= 7
        error('Cannot find session folder "%s".', folder);
    end
    listing = dir(fullfile(folder, FILE_PATTERN));
    if isempty(listing)
        error('GaussianLayers3D:noFiles', ...
            'No files matching "%s" found in "%s".', FILE_PATTERN, folder);
    end
    files = fullfile({listing.folder}, {listing.name});
    sessionFiles = [sessionFiles, files];  %#ok<AGROW>
    sessionIdx   = [sessionIdx, repmat(k, 1, numel(files))];  %#ok<AGROW>
    sessionNames{end+1} = SESSIONS(k).name;  %#ok<SAGROW>

    o = SESSIONS(k).originMm;
    if isempty(o), o = [NaN NaN]; end
    sessionOriginsMm(end+1, :) = o;  %#ok<SAGROW>

    fprintf('Session "%s": %d file(s) in "%s"', SESSIONS(k).name, numel(files), folder);
    if all(isfinite(o))
        fprintf(' -> dropper at (%.3f, %.3f) mm\n', o(1), o(2));
    else
        fprintf(' -> NO origin given (left unshifted)\n');
    end
    for i = 1:numel(files)
        fprintf('    %s\n', files{i});
    end
end

%% BUILD THE FIGURES
args = {'saveFigures', SAVE_FIGURES, 'outDir', OUT_DIR, ...
    'nSigma', N_SIGMA, 'showPoints', SHOW_POINTS, 'showEmpirical', SHOW_EMPIRICAL, ...
    'dropDuplicates', DROP_DUPLICATES, 'requireInBounds', REQUIRE_IN_BOUNDS};

if USE_SESSION_ORIGINS
    args = [args, {'sessionIdx', sessionIdx, 'sessionOriginsMm', sessionOriginsMm, ...
                   'sessionNames', sessionNames}];
else
    args = [args, {'originCell', ORIGIN_CELL, 'originMm', ORIGIN_MM}];
end

results = GaussianLayers3D(sessionFiles, args{:});
