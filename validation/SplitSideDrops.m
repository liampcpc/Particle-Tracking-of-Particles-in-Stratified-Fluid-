%% SplitSideDrops
% Splits ONE long SIDE-camera recording (e.g. dropside4.MOV) into one clip per drop
clear; clc; close all;

here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
cd(here);

addpath(here);

%% CONFIGURATION
SIDE_VIDEO_FILE = 'dropside4.MOV';  % the long SIDE-camera recording
OUTPUT_DIR      = 'drop_clips';  % where DropTracking.m looks
OUTPUT_PREFIX   = 'drop';
FPS             = 60;  % expected frame rate

% Which lines mark a drop
START_LINE_INDEX = 1;  % crossing this line = "a drop has begun"
END_LINE_INDEX   = 4;  % crossing this line = fall essentially over

% Clip window (seconds)
PRE_START_S            = 1.00;  % clean lead-in BEFORE the start-line crossing
POST_END_S             = 0.80;  % tail AFTER the end-line crossing
FALLBACK_AFTER_START_S = 1.50;  % used instead of the end line if it is not found (or END_LINE_INDEX = [])
MAX_FALL_S             = 3.00;  % how long after the start crossing to look for the end-line crossing
MIN_SEPARATION_S       = 2.00;  % two start crossings closer than this are treated as ONE drop
MIN_CLIP_S             = 0.50;  % discard a clip shorter than this (event too close to the end of the recording)

% Side-view calibration (sideLineCalib.mat and sideViewROI.mat must sit beside this script)
LINE_CALIB_FILE  = 'sideLineCalib.mat';
SIDE_ROI_FILE    = 'sideViewROI.mat';
RECALIBRATE_LINES = false;  % true = click the line rows on THIS video
CALIB_FRAME_T     = 0.5;
REDEFINE_SIDE_ROI = false;  % true = drag a new ROI on THIS video

% Detector cache
USE_TRACK_CACHE = true;  % false = always rescan

% Output
KEEP_AUDIO         = true;
CRF                = 18;  % x264 quality (lower = better)
ASK_BEFORE_CUTTING = true;  % show the check figures and ask y/N first
OVERWRITE_EXISTING = false;  % false = ask before replacing existing clips

%% SETUP
if exist(SIDE_VIDEO_FILE, 'file') ~= 2
    error('Cannot find "%s" in %s. Check the filename.', SIDE_VIDEO_FILE, here);
end

cfg = rigConfig();
ffmpegBin = locate_ffmpeg(cfg.ffmpegBin);
fprintf('ffmpeg: %s\n', ffmpegBin);

v = VideoReader(SIDE_VIDEO_FILE);
duration = v.Duration;
trueFps  = v.FrameRate;
fprintf('Side video: %s | %.2f s | %.2f fps reported | %dx%d (w x h)\n', ...
    SIDE_VIDEO_FILE, duration, trueFps, v.Width, v.Height);
if abs(trueFps - FPS) > 0.5
    warning('SplitSideDrops:fpsMismatch', ...
        'The file reports %.2f fps but FPS is set to %g.', trueFps, FPS);
end

%% Line calibration
if RECALIBRATE_LINES
    LINE_CALIB_FILE = 'sideLineCalib_dropside4.mat';
    cfg.sideLineCalibFile = LINE_CALIB_FILE;
    cfg.forceManualLineCalib = true;  % dark lines on a light backing: click them
    fprintf('\nRecalibrating the side-view lines on %s...\n', SIDE_VIDEO_FILE);
    calib = calibrateSideViewLines(SIDE_VIDEO_FILE, cfg, CALIB_FRAME_T);
else
    if exist(LINE_CALIB_FILE, 'file') ~= 2
        error(['Cannot find the line calibration "%s". Set RECALIBRATE_LINES = ' ...
            'true to click the lines on this video.'], LINE_CALIB_FILE);
    end
    S = load(LINE_CALIB_FILE, 'calib');
    calib = S.calib;
end
linePx = calib.linePx(:)';
if isfield(calib, 'heightsMm') && numel(calib.heightsMm) == numel(linePx)
    heightsMm = calib.heightsMm(:)';
else
    heightsMm = nan(size(linePx));
end
nLines = numel(linePx);

if START_LINE_INDEX < 1 || START_LINE_INDEX > nLines
    error('START_LINE_INDEX = %d but only %d line(s) are calibrated.', START_LINE_INDEX, nLines);
end
useEndLine = ~isempty(END_LINE_INDEX);
if useEndLine
    if END_LINE_INDEX < 1 || END_LINE_INDEX > nLines || END_LINE_INDEX <= START_LINE_INDEX
        error(['END_LINE_INDEX must be a calibrated line BELOW the start line ' ...
            '(START_LINE_INDEX = %d, %d line(s) calibrated).'], START_LINE_INDEX, nLines);
    end
end
startPx = linePx(START_LINE_INDEX);
if useEndLine, endPx = linePx(END_LINE_INDEX); else, endPx = NaN; end

fprintf('\nCalibrated lines (from %s):\n', LINE_CALIB_FILE);
for i = 1:nLines
    tag = '';
    if i == START_LINE_INDEX, tag = '   <- START (drop begins)'; end
    if useEndLine && i == END_LINE_INDEX, tag = '   <- END (fall over)'; end
    fprintf('  line %d: row %7.1f px  (%g mm)%s\n', i, linePx(i), heightsMm(i), tag);
end
if isfield(calib, 'frameSize') && numel(calib.frameSize) >= 2
    if abs(calib.frameSize(1) - v.Height) > 16
        warning('SplitSideDrops:frameSizeMismatch', ...
            ['The line calibration was made on frames %d px tall but this video ' ...
             'is %d px tall. The saved rows may not fit -- check the figures below, ' ...
             'or set RECALIBRATE_LINES = true.'], calib.frameSize(1), v.Height);
    end
end

%% Side-view ROI
if REDEFINE_SIDE_ROI
    SIDE_ROI_FILE = 'sideViewROI_dropside4.mat';
    cfg.sideRoiFile = SIDE_ROI_FILE;
    fprintf(['\nDrag the side-view search ROI -- TOP edge below the water surface, ' ...
        'LEFT/RIGHT edges inside the tank glass, and tall enough to contain the ' ...
        'start AND end lines...\n']);
    roi = pickSideViewROI(SIDE_VIDEO_FILE, cfg);
else
    if exist(SIDE_ROI_FILE, 'file') ~= 2
        error(['Cannot find the side-view ROI "%s". Set REDEFINE_SIDE_ROI = true ' ...
            'to draw one on this video.'], SIDE_ROI_FILE);
    end
    R = load(SIDE_ROI_FILE, 'roi');
    roi = R.roi;
end
fprintf('Side-view ROI [x y w h]: [%d %d %d %d]  (%s)\n', roi, SIDE_ROI_FILE);
roiRows = [roi(2), roi(2) + roi(4) - 1];
if startPx < roiRows(1) || startPx > roiRows(2)
    error(['The start line (row %.0f) is outside the ROI rows %d-%d, so its ' ...
        'crossing can never be detected. Redraw the ROI (REDEFINE_SIDE_ROI = true).'], ...
        startPx, roiRows(1), roiRows(2));
end
if useEndLine && (endPx < roiRows(1) || endPx > roiRows(2))
    warning('SplitSideDrops:endLineOutsideRoi', ...
        'The end line (row %.0f) is outside the ROI rows %d-%d: it will never be found.', ...
        endPx, roiRows(1), roiRows(2));
end

%% TRACK THE BALL THROUGH THE WHOLE RECORDING (cached)
[~, vidName] = fileparts(SIDE_VIDEO_FILE);
cacheFile = [vidName '_sideTrack.mat'];
vidInfo = dir(SIDE_VIDEO_FILE);
sig = struct('videoBytes', vidInfo.bytes, 'roi', roi, ...
    'blobThreshold', cfg.sideBlobThreshold, 'morphRadius', cfg.sideMorphRadius, ...
    'bgFrames', cfg.sideBackgroundFrames, 'minAreaPx', crossing_min_area(cfg));

trk = [];
if USE_TRACK_CACHE && exist(cacheFile, 'file') == 2
    C = load(cacheFile, 'trk', 'sig');
    if isequal(C.sig, sig)
        trk = C.trk;
        fprintf('\nReusing the cached ball track (%s). Set USE_TRACK_CACHE = false to rescan.\n', cacheFile);
    else
        fprintf('\nCached track %s is for different settings/video -- rescanning.\n', cacheFile);
    end
end
if isempty(trk)
    fprintf('\nScanning %s for the ball (takes a few minutes)...\n', SIDE_VIDEO_FILE);
    trk = scan_side_track(SIDE_VIDEO_FILE, roi, cfg);
    if USE_TRACK_CACHE
        save(cacheFile, 'trk', 'sig');
        fprintf('Cached the track in %s.\n', cacheFile);
    end
end
fprintf('Ball detected in %d of %d frames.\n', nnz(isfinite(trk.yPx)), numel(trk.tS));

%% FIND THE DROPS: START-LINE CROSSINGS (+ END-LINE CROSSINGS)
events = find_drop_events(trk.tS, trk.yPx, startPx, endPx, cfg, MAX_FALL_S);
if isempty(events)
    error(['No drops found: the ball never crossed line %d (row %.0f px). Check the ' ...
        'ROI / line calibration (the figure of the tracked ball will show what was ' ...
        'detected), or cfg.sideBlobThreshold in rigConfig.m.'], START_LINE_INDEX, startPx);
end
fprintf('\n%d start-line crossing(s) found.\n', numel(events));

[~, ord] = sort([events.tStart]);
events = events(ord);
keep = true(size(events));
i = 1;
while i <= numel(events)
    j = i;
    while j < numel(events) && events(j+1).tStart - events(j).tStart < MIN_SEPARATION_S
        j = j + 1;
    end
    if j > i
        [~, best] = max([events(i:j).runFrames]);
        keep(i:j) = false;
        keep(i + best - 1) = true;
    end
    i = j + 1;
end
if any(~keep)
    fprintf('%d crossing(s) within %.1f s of a stronger one were merged.\n', nnz(~keep), MIN_SEPARATION_S);
end
events = events(keep);

nEv = numel(events);
startTimes = zeros(1, nEv); endTimes = zeros(1, nEv); endFound = false(1, nEv);
for i = 1:nEv
    startTimes(i) = max(0, events(i).tStart - PRE_START_S);
    if useEndLine && isfinite(events(i).tEnd)
        endTimes(i) = events(i).tEnd + POST_END_S;
        endFound(i) = true;
    else
        endTimes(i) = events(i).tStart + FALLBACK_AFTER_START_S;
    end
    endTimes(i) = min(duration, endTimes(i));
end
okClip = (endTimes - startTimes) >= MIN_CLIP_S;
if any(~okClip)
    warning('SplitSideDrops:tooShort', 'Dropping %d event(s) whose clip would be under %.2f s.', ...
        nnz(~okClip), MIN_CLIP_S);
end
events = events(okClip); startTimes = startTimes(okClip); endTimes = endTimes(okClip);
endFound = endFound(okClip);
nClips = numel(events);
if nClips == 0
    error('No usable clips left after the filters above.');
end
for i = 1:nClips - 1
    if endTimes(i) > startTimes(i+1)
        warning('SplitSideDrops:overlap', ...
            ['Clip %d (ends %.2f s) overlaps clip %d (starts %.2f s). The earlier ball ' ...
             'may still be in view when the later clip begins -- shorten POST_END_S / ' ...
             'PRE_START_S if DropTracking mistakes it for the new drop.'], ...
            i, endTimes(i), i+1, startTimes(i+1));
    end
end

fprintf('\n--- Proposed clips ---\n');
fprintf('  clip   clip window (s)      start-line t   end-line t   mean speed between lines\n');
for i = 1:nClips
    if endFound(i)
        dtFall = events(i).tEnd - events(i).tStart;
        dh = heightsMm(START_LINE_INDEX) - heightsMm(END_LINE_INDEX);
        if isfinite(dh) && dtFall > 0
            spd = sprintf('%.2f m/s', dh / dtFall / 1000);
        else
            spd = 'n/a';
        end
        endStr = sprintf('%9.3f', events(i).tEnd);
    else
        spd = 'n/a (end line not found - fixed window)';
        endStr = '      ---';
    end
    fprintf('  %s%02d  %7.2f -> %7.2f   %9.3f     %s    %s\n', ...
        OUTPUT_PREFIX, i, startTimes(i), endTimes(i), events(i).tStart, endStr, spd);
end
if useEndLine && any(~endFound)
    fprintf('  (%d clip(s) used the fixed %.1f s window because the end line was not found.)\n', ...
        nnz(~endFound), FALLBACK_AFTER_START_S);
end

%% VERIFY BEFORE CUTTING
figTrack = figure('Name', 'Tracked ball height + detected drops', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.03 0.55 0.94 0.38]);
axT = axes(figTrack); hold(axT, 'on');
frameH = v.Height;
for i = 1:nClips
    patch(axT, [startTimes(i) endTimes(i) endTimes(i) startTimes(i)], [0 0 frameH frameH], ...
        [0.2 0.6 1.0], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    text(axT, startTimes(i), 30, sprintf('%s%02d', OUTPUT_PREFIX, i), 'FontSize', 8, ...
        'VerticalAlignment', 'top', 'Color', [0.1 0.3 0.7]);
end
for k = 1:nLines
    if k == START_LINE_INDEX
        lc = [0 0.6 0]; lw = 1.5;
    elseif useEndLine && k == END_LINE_INDEX
        lc = [0.85 0 0]; lw = 1.5;
    else
        lc = [0.7 0.7 0.7]; lw = 0.75;
    end
    plot(axT, [0 duration], [linePx(k) linePx(k)], '-', 'Color', lc, 'LineWidth', lw);
end
plot(axT, trk.tS, trk.yPx, 'k.', 'MarkerSize', 6);
plot(axT, [events.tStart], startPx * ones(1, nClips), 'o', 'MarkerFaceColor', [0 0.7 0], ...
    'MarkerEdgeColor', 'k', 'MarkerSize', 7);
if useEndLine
    tEndAll = [events.tEnd];
    plot(axT, tEndAll(isfinite(tEndAll)), endPx * ones(1, nnz(isfinite(tEndAll))), 's', ...
        'MarkerFaceColor', [0.9 0.1 0.1], 'MarkerEdgeColor', 'k', 'MarkerSize', 7);
end
set(axT, 'YDir', 'reverse');
xlim(axT, [0 duration]); ylim(axT, [0 frameH]);
xlabel(axT, 'time in recording (s)'); ylabel(axT, 'ball row (px, down = lower)');
title(axT, sprintf(['%d drop(s): green dot = start line crossing, red square = end line ' ...
    'crossing, blue = clip window. Black dots = tracked ball.'], nClips));
box(axT, 'on');

tileH = 420;
nC = ceil(sqrt(nClips)); nR = ceil(nClips / nC);
figFrames = figure('Name', 'Verify each drop - close to continue', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.03 0.03 0.94 0.85]);
for i = 1:nClips
    tShowS = events(i).tStart;
    if endFound(i), tShowE = events(i).tEnd; else, tShowE = events(i).tStart + 0.25; end
    FS = grab_frame(v, tShowS);
    FE = grab_frame(v, tShowE);
    sc = tileH / size(FS, 1);
    FS = imresize(FS, [tileH NaN]); FE = imresize(FE, [tileH NaN]);
    div = 8;
    divider = 255 * ones(tileH, div, 3, 'uint8'); divider(:, :, 2:3) = 0;
    tile = [FS, divider, FE];
    subplot(nR, nC, i);
    imshow(tile); hold on;
    plot([1 size(FS,2)], [startPx startPx] * sc, '-', 'Color', [0 0.9 0], 'LineWidth', 1.2);
    if useEndLine
        xo = size(FS,2) + div;
        plot(xo + [1 size(FE,2)], [endPx endPx] * sc, '--', 'Color', [1 0.2 0.2], 'LineWidth', 1.2);
    end
    if endFound(i)
        ttl = sprintf('%s%02d  start t=%.2fs | end t=%.2fs', OUTPUT_PREFIX, i, tShowS, tShowE);
    else
        ttl = sprintf('%s%02d  start t=%.2fs | (end line not found)', OUTPUT_PREFIX, i, tShowS);
    end
    title(ttl, 'FontSize', 8);
end
sgtitle(sprintf(['%d drop(s): LEFT of each pair = ball at the START line (green); RIGHT = ' ...
    'ball at the END line (red). Check the ball is really on the line.'], nClips));
drawnow;

if ASK_BEFORE_CUTTING
    resp = input(sprintf('\nDo these look like real drops? Cut %d clip(s)? [y/N]: ', nClips), 's');
    if isvalid(figFrames), close(figFrames); end
    if ~strcmpi(strtrim(resp), 'y')
        fprintf('Aborted - nothing was written. The tracked ball is cached in %s, so re-running is quick.\n', cacheFile);
        return;
    end
end

%% CUT
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end
existing = dir(fullfile(OUTPUT_DIR, [OUTPUT_PREFIX '*.mp4']));
if ~isempty(existing) && ~OVERWRITE_EXISTING
    resp = input(sprintf(['\n%s already holds %d %s*.mp4 clip(s). Overwrite / replace them? ' ...
        '[y/N]: '], OUTPUT_DIR, numel(existing), OUTPUT_PREFIX), 's');
    if ~strcmpi(strtrim(resp), 'y')
        fprintf('Aborted - nothing was written. Set OUTPUT_DIR to a new folder (and point DropTracking.m at it) to keep both.\n');
        return;
    end
end

clipFiles = cell(1, nClips);
fprintf('\nCutting...\n');
for i = 1:nClips
    out = fullfile(OUTPUT_DIR, sprintf('%s%02d.mp4', OUTPUT_PREFIX, i));
    cut_exact(ffmpegBin, SIDE_VIDEO_FILE, out, startTimes(i), endTimes(i), FPS, CRF, KEEP_AUDIO);
    clipFiles{i} = out;
    fprintf('  [%2d/%2d] %s  (%.2f s)\n', i, nClips, out, endTimes(i) - startTimes(i));
end

%% SAVE METADATA (same fields as AudioSplit.m, so DropTracking.m just works)
markers = [events.tStart];  % start-line crossing, on the source recording's timeline

clips = struct();
clips.sourceVideo   = SIDE_VIDEO_FILE;
clips.files         = clipFiles;
clips.markerTimes   = markers(:)';
clips.releaseTimes  = nan(1, nClips);
clips.buzzerLeadS   = [];
clips.startTimes    = startTimes(:)';
clips.endTimes      = endTimes(:)';
clips.fps           = FPS;
clips.trueFps       = trueFps;
clips.preRollS      = PRE_START_S;
clips.detectMode    = 'side_line_crossing';
clips.markerMeans   = sprintf('crossing of side-view line %d (%g mm)', START_LINE_INDEX, heightsMm(START_LINE_INDEX));
clips.sessionSpanS  = [min(markers), max(markers)];
clips.createdAt     = datestr(now);  %#ok<TNOW1,DATST>
clips.lineCalibFile = LINE_CALIB_FILE;
clips.linePx        = linePx;
clips.lineHeightsMm = heightsMm;
clips.startLineIndex = START_LINE_INDEX;
clips.endLineIndex   = END_LINE_INDEX;
clips.startLineCrossingS = [events.tStart];
clips.endLineCrossingS   = [events.tEnd];  % NaN where the end line was not found

metaFile = fullfile(OUTPUT_DIR, 'clips.mat');
save(metaFile, 'clips');
fprintf('\nWrote %d clip(s) + %s\n', nClips, metaFile);
fprintf(['\nNext: run DropTracking.m (BATCH_MODE = true). Make sure its MEDIUM, ' ...
    'OBJECT_DIAMETER_MM and ROI settings are right for this session.\n']);
fprintf('\n=== Complete ===\n');

%% LOCAL FUNCTIONS
function a = crossing_min_area(cfg)
% Same rule as detectLineCrossingEvents.m
if isfield(cfg, 'sideCrossingMinAreaPx')
    a = cfg.sideCrossingMinAreaPx;
else
    a = cfg.sideMinAreaPx;
end
end

function trk = scan_side_track(videoFile, roi, cfg)
% SCAN_SIDE_TRACK Background-subtraction track of the ball's row
minAreaPx = crossing_min_area(cfg);

v = VideoReader(videoFile);
nEst = max(1, floor(v.Duration * v.FrameRate));

colLo = max(1, roi(1));  colHi = min(v.Width,  roi(1) + roi(3) - 1);
rowLo = max(1, roi(2));  rowHi = min(v.Height, roi(2) + roi(4) - 1);

% background from the first (ball-free) frames
v.CurrentTime = 0;
bgFrames = cell(1, cfg.sideBackgroundFrames);
nBg = 0;
while nBg < cfg.sideBackgroundFrames && hasFrame(v)
    nBg = nBg + 1;
    F = readFrame(v);
    F = F(rowLo:min(rowHi, size(F,1)), colLo:min(colHi, size(F,2)), :);
    bgFrames{nBg} = im2double(rgb2gray(F));
end
if nBg < 3
    error('SplitSideDrops:noBackground', 'Could not read enough frames to build a background -- is the recording too short?');
end
bg = median(cat(3, bgFrames{1:nBg}), 3);
se = strel('disk', cfg.sideMorphRadius);

% scan everything
v.CurrentTime = 0;
cap = nEst + 200;
tS = nan(1, cap); yPx = nan(1, cap); areaPx = zeros(1, cap);
n = 0; nextReport = 0.1; t0 = tic;
while hasFrame(v)
    tNow = v.CurrentTime;
    F = readFrame(v);
    F = F(rowLo:min(rowHi, size(F,1)), colLo:min(colHi, size(F,2)), :);
    G = im2double(rgb2gray(F));

    mask = abs(G - bg) > cfg.sideBlobThreshold;
    mask = imopen(mask, se);
    mask = imclose(mask, se);
    stats = regionprops(mask, 'Area', 'Centroid');
    if ~isempty(stats)
        stats = stats([stats.Area] >= minAreaPx);
    end

    n = n + 1;
    if n > numel(tS)
        tS(end+200) = NaN; yPx(end+200) = NaN; areaPx(end+200) = 0;  %#ok<AGROW>
    end
    tS(n) = tNow;
    if ~isempty(stats)
        [~, big] = max([stats.Area]);
        yPx(n) = rowLo - 1 + stats(big).Centroid(2);
        areaPx(n) = stats(big).Area;
    end

    if n / nEst >= nextReport
        fprintf('  %3.0f%%  (%d frames, %.0f s elapsed)\n', 100 * min(1, n / nEst), n, toc(t0));
        nextReport = nextReport + 0.1;
    end
end
trk = struct('tS', tS(1:n), 'yPx', yPx(1:n), 'areaPx', areaPx(1:n));
fprintf('  scan finished: %d frames in %.0f s.\n', n, toc(t0));
end

function events = find_drop_events(tS, yPx, startPx, endPx, cfg, maxFallS)
% FIND_DROP_EVENTS Turn the per-frame ball track into discrete drops: groups of consecutive detections
if isfield(cfg, 'sideCrossingMaxGapFrames'), maxGap = cfg.sideCrossingMaxGapFrames; else, maxGap = 0; end
minRun = cfg.sideMinRunFrames;
requireCross = ~(isfield(cfg, 'sideRequireActualCrossing') && ~cfg.sideRequireActualCrossing);

present = isfinite(yPx);
events = struct('tStart', {}, 'tEnd', {}, 'runFrames', {});
n = numel(present);
i = 1;
while i <= n
    if ~present(i), i = i + 1; continue; end
    j = i; gapRun = 0;
    while j < n
        if present(j+1)
            j = j + 1; gapRun = 0;
        elseif gapRun < maxGap
            j = j + 1; gapRun = gapRun + 1;
        else
            break
        end
    end
    while j > i && ~present(j), j = j - 1; end
    runLen = sum(present(i:j));

    if runLen >= minRun
        m = present(i:j);
        runT = tS(i:j); runY = yPx(i:j);
        runT = runT(m); runY = runY(m);
        tStart = first_crossing(runT, runY, startPx);
        if isnan(tStart) && ~requireCross
            tStart = runT(ceil(numel(runT) / 2));
        end
        if ~isnan(tStart)
            tEnd = NaN;
            if isfinite(endPx)
                w = isfinite(yPx) & tS >= tStart & tS <= tStart + maxFallS;
                tEnd = first_crossing(tS(w), yPx(w), endPx);
            end
            events(end+1).tStart = tStart;  %#ok<AGROW>
            events(end).tEnd = tEnd;
            events(end).runFrames = runLen;
        end
    end
    i = j + 1;
end
end

function tc = first_crossing(t, y, linePx)
% FIRST_CROSSING Interpolated time at which y first crosses linePx
tc = NaN;
if numel(y) < 2, return; end
s = sign(y - linePx);
k = find(s(1:end-1) .* s(2:end) <= 0, 1, 'first');
if isempty(k), return; end
y0 = y(k); y1 = y(k+1); t0 = t(k); t1 = t(k+1);
if y1 == y0
    tc = t0;
else
    f = min(max((linePx - y0) / (y1 - y0), 0), 1);
    tc = t0 + f * (t1 - t0);
end
end

function F = grab_frame(v, t)
% GRAB_FRAME The frame at time t (clamped inside the recording)
v.CurrentTime = max(0, min(v.Duration - 1 / v.FrameRate, t));
F = readFrame(v);
end

function cut_exact(ffmpeg, inFile, outFile, startT, endT, fps, crf, keepAudio)
% CUT_EXACT Frame-accurate cut, re-encoded to constant-frame-rate H.264/MP4. -ss BEFORE -i seeks fast
if keepAudio, aflag = '-c:a aac'; else, aflag = '-an'; end
cmd = sprintf(['"%s" -y -ss %.4f -i "%s" -t %.4f %s ' ...
               '-c:v libx264 -preset fast -crf %d -pix_fmt yuv420p ' ...
               '-r %g "%s"'], ...
               ffmpeg, startT, inFile, endT - startT, aflag, crf, fps, outFile);
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
