%% SplitAndTrackHeights
% Adds SIDE-VIEW height tracking to a session already split by SplitAudioImpacts.m
clear; clc; close all;

addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));

%% CONFIGURATION
UNDERNEATH_SESSION_DIR = 'drop_clips';  % OUTPUT_DIR from SplitAudioImpacts.m
SIDE_VIDEO_FILE        = 'dropside0_24.MOV';  % full-length side-view recording

if exist('masterRunConfig.mat', 'file') == 2
    M = load('masterRunConfig.mat');
    if isfield(M, 'SIDE_VIDEO_FILE'), SIDE_VIDEO_FILE = M.SIDE_VIDEO_FILE; end
end

BALL_DIAMETER_MM = 4;  % must match what SplitAudioImpacts.m used for this session

%% LOAD THE UNDERNEATH SESSION
clipsMatFile = fullfile(UNDERNEATH_SESSION_DIR, 'clips.mat');
if exist(clipsMatFile, 'file') ~= 2
    error(['Cannot find "%s".\nRun SplitAudioImpacts.m for this session first.'], clipsMatFile);
end
L = load(clipsMatFile, 'clips');
clips = L.clips;
nDrops = numel(clips.files);
fprintf('Loaded %d drop(s) from %s.\n', nDrops, clipsMatFile);

if isfield(clips, 'sourceVideoSide') && ~isempty(clips.sourceVideoSide) && ...
        ~strcmp(clips.sourceVideoSide, SIDE_VIDEO_FILE)
    error(['SIDE_VIDEO_FILE (''%s'') does not match the side video this session''s ' ...
        'clips were actually cut against (clips.sourceVideoSide = ''%s''). Update ' ...
        'SIDE_VIDEO_FILE above to match, or you will get a spurious sync offset.'], ...
        SIDE_VIDEO_FILE, clips.sourceVideoSide);
end

cfg = rigConfig();
cfg.useColorDotCalibration = true;  % height tracking needs the grid to mean anything

if exist('masterRunConfig.mat', 'file') == 2
    M = load('masterRunConfig.mat');
    if isfield(M, 'GRID_OPACITY'), cfg.gridOverlayOpacity = M.GRID_OPACITY; end
end

if exist(cfg.sideLineCalibFile, 'file') ~= 2
    error(['Cannot find line calibration "%s".\nRun calibrateSideViewLines.m ' ...
        'once for this rig setup first.'], cfg.sideLineCalibFile);
end

%% SYNC: underneath (cam1) vs side (cam2)
fprintf('\nSyncing underneath recording against side recording...\n');
offsetSec = estimateAudioOffset(clips.sourceVideo, SIDE_VIDEO_FILE);

%% PER-DROP HEIGHT TRACKING
allDropIdx    = [];
allHeightMm   = [];
allXMm        = [];
allYMm        = [];
allXPx        = [];
allYPx        = [];
allClipFile   = strings(0,1);
allGridCell   = strings(0,1);
allInBounds   = [];
allSource     = strings(0,1);

dotCalibDropIdx  = [];
dotCalibClipFile = strings(0,1);
dotCalibNames    = {};  % one cell array of matched dot names per drop
dotCalibImgPts   = {};  % one Nx2 pixel-position matrix per drop, same order as names

for i = 1:nDrops
    fprintf('\n[%d/%d] %s\n', i, nDrops, clips.files{i});

    try
        [dotTform, matchedDots, imgPts] = fitDotHomography(clips.files{i}, cfg.dotWorldPositionsMm);
        fprintf('  Colour-dot calibration: %d dots matched.\n', numel(matchedDots));
        dotCalibDropIdx(end+1)   = i;  %#ok<AGROW>
        dotCalibClipFile(end+1)  = string(clips.files{i});  %#ok<AGROW>
        dotCalibNames{end+1}     = matchedDots;  %#ok<AGROW>
        dotCalibImgPts{end+1}    = imgPts;  %#ok<AGROW>
    catch ME
        warning('SplitAndTrackHeights:calibFailed', ...
            'Drop %d: colour-dot calibration failed (%s) -- skipping height tracking for this drop.', ...
            i, ME.message);
        continue
    end

    try
        lineResults = impactHeightSideView(clips.files{i}, clips.startTimes(i), ...
            SIDE_VIDEO_FILE, offsetSec, dotTform, cfg);
    catch ME
        warning('SplitAndTrackHeights:dropFailed', 'Drop %d failed: %s', i, ME.message);
        continue
    end

    for k = 1:numel(lineResults)
        r = lineResults(k);
        if ~strcmp(r.positionSource, 'manual')
            continue
        end
        allDropIdx(end+1)  = i;  %#ok<AGROW>
        allHeightMm(end+1) = r.heightMm;  %#ok<AGROW>
        allXMm(end+1)      = r.xMm;  %#ok<AGROW>
        allYMm(end+1)      = r.yMm;  %#ok<AGROW>
        allXPx(end+1)      = r.xPx;  %#ok<AGROW>
        allYPx(end+1)      = r.yPx;  %#ok<AGROW>
        allClipFile(end+1) = string(clips.files{i});  %#ok<AGROW>
        allGridCell(end+1) = string(r.gridCell);  %#ok<AGROW>
        allInBounds(end+1) = r.gridCellInBounds;  %#ok<AGROW>
        allSource(end+1)   = string(r.positionSource);  %#ok<AGROW>
    end
end

%% SAVE -- what CompileHeightHeatmaps.m reads
if isempty(allDropIdx)
    fprintf('\nNo usable (drop, line) positions were recorded -- nothing saved.\n');
else
    heightResults = struct();
    heightResults.sourceVideoUnderneath = clips.sourceVideo;
    heightResults.sourceVideoSide       = SIDE_VIDEO_FILE;
    heightResults.offsetSec             = offsetSec;
    heightResults.ballDiameterMm        = BALL_DIAMETER_MM;
    heightResults.dropIndex             = allDropIdx(:);
    heightResults.heightMm              = allHeightMm(:);
    heightResults.xMm                   = allXMm(:);
    heightResults.yMm                   = allYMm(:);
    heightResults.xPx                   = allXPx(:);
    heightResults.yPx                   = allYPx(:);
    heightResults.clipFile              = allClipFile(:);
    dotCalibration = struct();
    dotCalibration.dropIndex = dotCalibDropIdx(:);
    dotCalibration.clipFile  = dotCalibClipFile(:);
    dotCalibration.names     = dotCalibNames(:);
    dotCalibration.imgPts    = dotCalibImgPts(:);
    heightResults.dotCalibration        = dotCalibration;
    heightResults.gridCell              = allGridCell(:);
    heightResults.inBounds              = allInBounds(:);
    heightResults.positionSource        = allSource(:);
    heightResults.gridCols              = cfg.gridCols;
    heightResults.gridRows              = cfg.gridRows;
    heightResults.createdAt             = datestr(now);  %#ok<TNOW1,DATST>

    outFile = fullfile(UNDERNEATH_SESSION_DIR, 'heightResults.mat');
    save(outFile, 'heightResults');
    fprintf('\nWrote %d (drop, line) position(s) -> %s\n', numel(allDropIdx), outFile);
end

fprintf('\n=== Complete ===\n');
