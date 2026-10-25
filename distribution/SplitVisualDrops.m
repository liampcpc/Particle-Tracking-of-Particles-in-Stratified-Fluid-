%% SplitVisualDrops
% VISUAL counterpart to SplitAudioImpacts.m: detects when each drop COMMENCES using the SIDE camera
clear; clc; close all;

addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));

%% CONFIGURATION
VIDEO_FILE      = 'drop0_5bot.MOV';  % underneath camera, full recording
SIDE_VIDEO_FILE = 'drop0_5side.MOV';  % side camera, full recording

if exist('masterRunConfig.mat', 'file') == 2
    M = load('masterRunConfig.mat');
    if isfield(M, 'BOT_VIDEO_FILE'),  VIDEO_FILE      = M.BOT_VIDEO_FILE;  end
    if isfield(M, 'SIDE_VIDEO_FILE'), SIDE_VIDEO_FILE = M.SIDE_VIDEO_FILE; end
end

OUTPUT_DIR      = 'drop_clips';
OUTPUT_PREFIX   = 'drop';

FPS = 60;

% Clip window, built FORWARD from each detected line-1 crossing
BACKGROUND_LEAD_S    = 0.30;  % Same meaning as SplitAudioImpacts.m's own settings
EXPECTED_FALL_TIME_S = 1.0;
POST_IMPACT_S        = 0.30;

MIN_SEPARATION_S = [];  % [] = use (BACKGROUND_LEAD_S + EXPECTED_FALL_TIME_S + POST_IMPACT_S)

% Side-view search ROI (pickSideViewROI.m)
REDEFINE_SIDE_ROI = false;  % true = redraw even if cfg.sideRoiFile exists

% Which ball this WHOLE recording used
BALL_DIAMETER_MM = 4;

% Grid-cell calibration (bottom position, unchanged from before)
USE_COLOR_DOT_CALIBRATION = true;

% Output per clip (unchanged from SplitAudioImpacts.m)
SAVE_SLOWMO_FOR_FIRST_ONLY = true;
KEEP_AUDIO = true;
CRF = 18;

% Per-clip impactAudio() analysis + gridResults.mat
RUN_IMPACT_AUDIO_ANALYSIS = false;  % Set false to skip running impactAudio() on every clip entirely

%% BUILD CFG
cfg = rigConfig();
cfg.useFiducials   = false;
cfg.applyUndistort = false;
cfg.savePreview    = true;
cfg.saveVerificationVideo = false;
cfg.saveSlowMoVideo       = false;
cfg.useColorDotCalibration = USE_COLOR_DOT_CALIBRATION;

if exist('masterRunConfig.mat', 'file') == 2
    M = load('masterRunConfig.mat');
    if isfield(M, 'GRID_OPACITY'), cfg.gridOverlayOpacity = M.GRID_OPACITY; end
end

ffmpegBin = locate_ffmpeg(cfg.ffmpegBin);

if exist(cfg.sideLineCalibFile, 'file') ~= 2
    error(['Cannot find line calibration "%s".\nRun calibrateSideViewLines.m ' ...
        'once for this rig setup first.'], cfg.sideLineCalibFile);
end
S = load(cfg.sideLineCalibFile, 'calib');
calib = S.calib;
targetLinePx = calib.linePx(1);
fprintf('Watching for drop starts at line 1 (row %.0fpx, %.0fmm).\n', ...
    targetLinePx, calib.heightsMm(1));

%% SYNC + DETECT
if exist(VIDEO_FILE, 'file') ~= 2
    error('Cannot find "%s". Check pwd/dir and the filename.', VIDEO_FILE);
end
if exist(SIDE_VIDEO_FILE, 'file') ~= 2
    error('Cannot find "%s". Check pwd/dir and the filename.', SIDE_VIDEO_FILE);
end

vUnder = VideoReader(VIDEO_FILE);
duration = vUnder.Duration;
trueFps  = vUnder.FrameRate;
fprintf('Underneath video: %.2f s | %.2f fps reported | %dx%d\n', ...
    duration, trueFps, vUnder.Width, vUnder.Height);
if abs(trueFps - FPS) > 0.5
    warning('SplitVisualDrops:fpsMismatch', ...
        'The file reports %.2f fps but FPS is set to %g.', trueFps, FPS);
end

fprintf('\nSyncing underneath recording against side recording...\n');
offsetSec = estimateAudioOffset(VIDEO_FILE, SIDE_VIDEO_FILE);

if REDEFINE_SIDE_ROI || exist(cfg.sideRoiFile, 'file') ~= 2
    fprintf(['\nPick the side-view search ROI -- drag the TOP edge below the water ' ...
        'surface and the LEFT/RIGHT edges inside the tank glass...\n']);
    pickSideViewROI(SIDE_VIDEO_FILE, cfg);
else
    fprintf('\nReusing existing side-view ROI (%s). Set REDEFINE_SIDE_ROI = true to redraw it.\n', ...
        cfg.sideRoiFile);
end

fprintf('\nScanning side recording for drop starts (line 1 crossings)...\n');
sideEvents = detectLineCrossingEvents(SIDE_VIDEO_FILE, targetLinePx, cfg);
if isempty(sideEvents)
    error(['No drop starts detected. Check targetLinePx / cfg.sideBlobThreshold, ' ...
        'or verify the ball is actually visible crossing line 1 in this recording.']);
end

%% BUILD CLIP WINDOWS (on the UNDERNEATH timeline) + DECLUTTER
minSep = MIN_SEPARATION_S;
if isempty(minSep)
    minSep = BACKGROUND_LEAD_S + EXPECTED_FALL_TIME_S + POST_IMPACT_S;
end

dropStartTimesUnder = [sideEvents.tS]' + offsetSec;  % side -> underneath
runFrames           = [sideEvents.runFrames]';

[dropStartTimesUnder, ord] = sort(dropStartTimesUnder);
runFrames = runFrames(ord);

keepIdx = false(size(dropStartTimesUnder));
nEvt = numel(dropStartTimesUnder);
i = 1;
while i <= nEvt
    j = i;
    while j < nEvt && dropStartTimesUnder(j+1) - dropStartTimesUnder(j) < minSep
        j = j + 1;
    end
    [~, best] = max(runFrames(i:j));
    keepIdx(i + best - 1) = true;
    i = j + 1;
end
nDropped = nEvt - nnz(keepIdx);
if nDropped > 0
    fprintf('%d candidate(s) within %.2fs of a stronger nearby detection were dropped.\n', nDropped, minSep);
end
dropStartTimesUnder = dropStartTimesUnder(keepIdx);

startTimes = max(0, dropStartTimesUnder - BACKGROUND_LEAD_S);
endTimes   = min(duration, dropStartTimesUnder + EXPECTED_FALL_TIME_S + POST_IMPACT_S);

keep = (endTimes - startTimes) > 0.1;
if any(~keep)
    warning('Dropping %d event(s) too close to the ends of the recording.', sum(~keep));
end
dropStartTimesUnder = dropStartTimesUnder(keep);
startTimes = startTimes(keep); endTimes = endTimes(keep);
nClips = numel(dropStartTimesUnder);

fprintf('\n--- Proposed clips (marker = line 1 crossing, mapped to underneath time) ---\n');
for i = 1:nClips
    fprintf('  %s%02d : %7.3f s -> %7.3f s  (drop start %7.3f s)\n', ...
        OUTPUT_PREFIX, i, startTimes(i), endTimes(i), dropStartTimesUnder(i));
end

%% SHOW SIDE + UNDERNEATH FRAMES AT EACH DETECTED START -- VERIFY BEFORE CUTTING
vSide = VideoReader(SIDE_VIDEO_FILE);

nCols = ceil(sqrt(nClips));
nRows = ceil(nClips / nCols);
figCheck = figure('Name', 'Verify each detected drop start - close to continue', ...
    'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.9]);
for i = 1:nClips
    dropStartTimeSide = dropStartTimesUnder(i) - offsetSec;

    vSide.CurrentTime = max(0, min(vSide.Duration - 1/vSide.FrameRate, dropStartTimeSide));
    Fside = readFrame(vSide);
    Fside = insertShape(Fside, 'Line', [1 targetLinePx size(Fside,2) targetLinePx], ...
        'Color', 'green', 'LineWidth', 2);
    Fside = insertText(Fside, [10 10], sprintf('SIDE  t=%.3fs (line 1 @ row %.0fpx)', ...
        dropStartTimeSide, targetLinePx), 'FontSize', 12, 'BoxColor', 'black', 'TextColor', 'green');

    vUnder.CurrentTime = max(0, dropStartTimesUnder(i));
    F = readFrame(vUnder);
    F = insertText(F, [10 10], sprintf('UNDERNEATH  t=%.3fs', dropStartTimesUnder(i)), ...
        'FontSize', 12, 'BoxColor', 'black', 'TextColor', 'cyan');

    if size(Fside,1) ~= size(F,1)
        Fside = imresize(Fside, [size(F,1) NaN]);
    end
    dividerPx = 6;
    divider = zeros(size(F,1), dividerPx, 3, 'uint8'); divider(:,:,1) = 255;
    combined = [Fside, divider, F];

    subplot(nRows, nCols, i);
    imshow(combined);
    title(sprintf('%s%02d  side t=%.3fs / under t=%.3fs', ...
        OUTPUT_PREFIX, i, dropStartTimeSide, dropStartTimesUnder(i)), 'FontSize', 9);
end
sgtitle(sprintf('%d detected drop start(s) -- check the ball is crossing line 1 (left, green) and entering the tank (right)', nClips));
drawnow;

resp = input(sprintf('\nDo these look like real drop starts? Cut %d clip(s)? [y/N]: ', nClips), 's');
if isvalid(figCheck), close(figCheck); end
if ~strcmpi(strtrim(resp), 'y')
    fprintf('Aborted - nothing was written.\n');
    return;
end

%% CUT
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
fprintf('ffmpeg: %s\n', ffmpegBin);

clipFiles = cell(1, nClips);
fprintf('\nCutting...\n');
for i = 1:nClips
    out = fullfile(OUTPUT_DIR, sprintf('%s%02d.mp4', OUTPUT_PREFIX, i));
    cut_exact(ffmpegBin, VIDEO_FILE, out, startTimes(i), endTimes(i), FPS, CRF, KEEP_AUDIO);
    clipFiles{i} = out;
    fprintf('  [%2d/%2d] %s\n', i, nClips, out);
end

%% SAVE METADATA
clips = struct();
clips.sourceVideo     = VIDEO_FILE;
clips.sourceVideoSide = SIDE_VIDEO_FILE;
clips.offsetSec       = offsetSec;
clips.detectionMethod = 'visual_line1';
clips.files           = clipFiles;
clips.dropStartTimes  = dropStartTimesUnder(:)';
clips.startTimes      = startTimes(:)';
clips.endTimes        = endTimes(:)';
clips.fps             = FPS;
clips.trueFps         = trueFps;
clips.createdAt       = datestr(now);  %#ok<TNOW1,DATST>

metaFile = fullfile(OUTPUT_DIR, 'clips.mat');
save(metaFile, 'clips');
fprintf('\nWrote %d clip(s) + %s\n', nClips, metaFile);

%% RUN impactAudio ON EVERY CLIP
if RUN_IMPACT_AUDIO_ANALYSIS

fprintf('\n--- Running impactAudio on each clip ---\n');

gridCells   = strings(nClips, 1);
gridXMm     = nan(nClips, 1);
gridYMm     = nan(nClips, 1);
gridInBounds = false(nClips, 1);
gridOk      = false(nClips, 1);
gridPositionSource = strings(nClips, 1);

for i = 1:nClips
    [~, nm] = fileparts(clipFiles{i});
    fprintf('\n[%d/%d] %s\n', i, nClips, nm);

    cfg.saveSlowMoVideo = SAVE_SLOWMO_FOR_FIRST_ONLY && (i == 1);

    try
        r = impactAudio(clipFiles{i}, cfg);
        if isfield(r, 'previewFile') && ~isempty(r.previewFile)
            fprintf('  PNG: %s\n', r.previewFile);
        end
        if isfield(r, 'warning')
            fprintf('  WARNING: %s\n', r.warning);
        end
        if isfield(r, 'gridCell') && ~isempty(r.gridCell)
            gridCells(i)    = string(r.gridCell);
            gridXMm(i)      = r.xMm;
            gridYMm(i)      = r.yMm;
            gridInBounds(i) = r.gridCellInBounds;
            gridOk(i)       = true;
            if isfield(r, 'ballPositionSource')
                gridPositionSource(i) = string(r.ballPositionSource);
            end
        end
    catch ME
        warning('Clip %d (%s) failed: %s', i, nm, ME.message);
    end
end

if any(gridOk)
    gridResults.sourceVideo   = VIDEO_FILE;
    gridResults.ballDiameterMm = BALL_DIAMETER_MM;
    gridResults.files         = clipFiles(gridOk);
    gridResults.gridCell      = gridCells(gridOk);
    gridResults.xMm           = gridXMm(gridOk);
    gridResults.yMm           = gridYMm(gridOk);
    gridResults.inBounds      = gridInBounds(gridOk);
    gridResults.positionSource = gridPositionSource(gridOk);
    gridResults.gridCols      = cfg.gridCols;
    gridResults.gridRows      = cfg.gridRows;
    gridResults.createdAt     = datestr(now);  %#ok<TNOW1,DATST>

    gridFile = fullfile(OUTPUT_DIR, 'gridResults.mat');
    save(gridFile, 'gridResults');
    fprintf('\nWrote %d grid result(s) + %s\n', nnz(gridOk), gridFile);
end

else
    fprintf(['\n--- Skipping impactAudio / gridResults.mat ' ...
        '(RUN_IMPACT_AUDIO_ANALYSIS = false) ---\n']);
end

fprintf('\n=== Complete ===\n');

%% LOCAL FUNCTIONS
function cut_exact(ffmpeg, inFile, outFile, startT, endT, fps, crf, keepAudio)
% CUT_EXACT Same as SplitAudioImpacts.m's function of the same name
if keepAudio, aflag = ''; else, aflag = '-an'; end
cmd = sprintf(['"%s" -y -i "%s" -ss %.4f -to %.4f %s ' ...
               '-c:v libx264 -preset fast -crf %d -pix_fmt yuv420p ' ...
               '-r %g "%s"'], ...
               ffmpeg, inFile, startT, endT, aflag, crf, fps, outFile);
[status, cmdout] = system(cmd);
if status ~= 0
    error('ffmpeg failed writing %s:\n%s', outFile, cmdout);
end
info = dir(outFile);
if isempty(info) || info.bytes < 10000
    error(['ffmpeg reported success but %s is missing or almost empty. ' ...
        'Check the requested window (%.3f-%.3f s) is inside the recording.'], ...
        outFile, startT, endT);
end
end
