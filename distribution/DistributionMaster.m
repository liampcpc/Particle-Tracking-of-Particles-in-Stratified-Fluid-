%% DistributionMaster
% MASTER SCRIPT for one full rig recording session, start to finish
clear; clc; close all;

addpath(fileparts(mfilename('fullpath')));

%% SESSION SETTINGS -- edit these for each new recording session
BOT_VIDEO_FILE  = 'dropbot77_100.MOV';  % underneath camera, full recording
SIDE_VIDEO_FILE = 'dropside77_100.MOV';  % side camera, full recording

NUM_LINES       = 5;  % Ruled lines on the side-view backing: how many, and the real-world height
LINE_HEIGHTS_MM = [225 175 125 75 25];
GRID_OPACITY = 0;

REDEFINE_LINE_CALIB = true;  % Set true to force re-running step 1/2 even if a previous calibration already exists...
REDEFINE_COLOR_ROIS = false;

%% BUILD CFG
cfg = rigConfig();
cfg.numLines      = NUM_LINES;
cfg.forceManualLineCalib = true;
cfg.gridOverlayOpacity = GRID_OPACITY;
cfg.lineHeightsMm = LINE_HEIGHTS_MM;

thisDir = fileparts(mfilename('fullpath'));

%% STEP 1/4 -- calibrateSideViewLines.m (MANUAL: click each ruled line)
if REDEFINE_LINE_CALIB || exist(cfg.sideLineCalibFile, 'file') ~= 2
    fprintf('\n=== STEP 1/4: calibrateSideViewLines -- click each ruled line on %s ===\n', SIDE_VIDEO_FILE);
    calibrateSideViewLines(SIDE_VIDEO_FILE, cfg);
else
    fprintf('\n=== STEP 1/4: reusing existing line calibration (%s). Set REDEFINE_LINE_CALIB = true to redo it. ===\n', ...
        cfg.sideLineCalibFile);
end

%% STEP 2/4 -- pickColorDotROIs.m (MANUAL: drag a box around each dot)
colorDotROIsFile = fullfile(thisDir, 'colorDotROIs.mat');
if REDEFINE_COLOR_ROIS || exist(colorDotROIsFile, 'file') ~= 2
    fprintf('\n=== STEP 2/4: pickColorDotROIs -- drag a box around each dot on %s ===\n', BOT_VIDEO_FILE);
    pickColorDotROIs(BOT_VIDEO_FILE);
else
    fprintf('\n=== STEP 2/4: reusing existing colour-dot ROIs (colorDotROIs.mat). Set REDEFINE_COLOR_ROIS = true to redo it. ===\n');
end

%% Hand video filenames to the two script-style steps below via a small .mat file
save('masterRunConfig.mat', 'BOT_VIDEO_FILE', 'SIDE_VIDEO_FILE', 'GRID_OPACITY');

%% STEP 3/4 -- SplitVisualDrops.m (automatic: find + cut each drop)
fprintf('\n=== STEP 3/4: SplitVisualDrops -- detecting + cutting drops ===\n');
runIsolated(fullfile(thisDir, 'SplitVisualDrops.m'));

%% STEP 4/4 -- SplitAndTrackHeights.m (MANUAL: click ball position/line)
fprintf('\n=== STEP 4/4: SplitAndTrackHeights -- click each line''s ball position ===\n');
runIsolated(fullfile(thisDir, 'SplitAndTrackHeights.m'));

if exist('masterRunConfig.mat', 'file') == 2
    delete('masterRunConfig.mat');
end

fprintf('\n=== RunFullSession complete (1-4 of 4) ===\n');
fprintf('Run RunCompileHeightHeatmaps.m separately (unchanged) once you''re ready to combine sessions.\n');

%% Local functions
function runIsolated(scriptFullPath)
% RUNISOLATED Run SCRIPTFULLPATH inside this function's own workspace
run(scriptFullPath);
end
