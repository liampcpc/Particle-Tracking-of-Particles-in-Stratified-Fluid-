function events = detectLineCrossingEvents(sideVideoPath, targetLinePx, cfg)
% DETECTLINECROSSINGEVENTS Scan a WHOLE side-view recording for every time the ball crosses ONE target line

v = VideoReader(sideVideoPath);
fps = v.FrameRate;
duration = v.Duration;

if isfield(cfg, 'sideCrossingMinAreaPx')
    crossingMinAreaPx = cfg.sideCrossingMinAreaPx;
else
    crossingMinAreaPx = cfg.sideMinAreaPx;
end

if isfield(cfg, 'sideCrossingMaxGapFrames')
    maxGapFrames = cfg.sideCrossingMaxGapFrames;
else
    maxGapFrames = 0;
end

useRoi = isfield(cfg, 'sideRoiFile') && exist(cfg.sideRoiFile, 'file') == 2;
if useRoi
    R = load(cfg.sideRoiFile, 'roi');
    roi = R.roi;  % [x y w h]
    colLo = max(1, roi(1));
    colHi = roi(1) + roi(3) - 1;
    bandLo = max(1, roi(2));
    bandHi = roi(2) + roi(4) - 1;
    if targetLinePx < bandLo || targetLinePx > bandHi
        warning('detectLineCrossingEvents:roiExcludesLine', ...
            ['cfg.sideRoiFile''s box (rows %d-%d) does not contain targetLinePx ' ...
             '(%.0f) -- a crossing of that line can never be detected inside this ' ...
             'ROI. Re-run pickSideViewROI.m with a taller box.'], bandLo, bandHi, targetLinePx);
    end
else
    colLo = 1;  % no ROI: full width, same as before
    colHi = [];  % resolved to frame width once the first frame is read
    bandLo = max(1, round(targetLinePx - cfg.sideBandHalfHeightPx));
    bandHi = round(targetLinePx + cfg.sideBandHalfHeightPx);
end

%% Background band-strip from the first sideBackgroundFrames of the recording
v.CurrentTime = 0;
bgFrames = cell(1, cfg.sideBackgroundFrames);
nBg = 0;
while nBg < cfg.sideBackgroundFrames && hasFrame(v)
    nBg = nBg + 1;
    F = im2double(rgb2gray(readFrame(v)));
    if isempty(colHi), colHi = size(F,2); end
    bgFrames{nBg} = F(bandLo:min(bandHi,size(F,1)), colLo:min(colHi,size(F,2)));
end
if nBg < 3
    error('detectLineCrossingEvents:noBackground', ...
        'Could not read enough frames to build a background band -- is the recording too short?');
end
bandHiClamped = bandLo + size(bgFrames{1},1) - 1;
colHiClamped  = colLo + size(bgFrames{1},2) - 1;
bg = median(cat(3, bgFrames{1:nBg}), 3);

%% Scan the WHOLE recording, band/ROI only
v.CurrentTime = 0;
se = strel('disk', cfg.sideMorphRadius);

tS  = [];
yPx = [];  % full-frame y coordinate (bandLo added back), NaN if no blob

while hasFrame(v)
    tNow = v.CurrentTime;
    F = im2double(rgb2gray(readFrame(v)));
    band = F(bandLo:bandHiClamped, colLo:colHiClamped);

    d = abs(band - bg);
    mask = d > cfg.sideBlobThreshold;
    mask = imopen(mask, se);
    mask = imclose(mask, se);

    stats = regionprops(mask, 'Area', 'Centroid');
    stats = stats([stats.Area] >= crossingMinAreaPx);

    tS(end+1) = tNow;  %#ok<AGROW>
    if isempty(stats)
        yPx(end+1) = NaN;  %#ok<AGROW>
    else
        [~, biggest] = max([stats.Area]);
        yPx(end+1) = bandLo - 1 + stats(biggest).Centroid(2);  %#ok<AGROW>
    end
end

%% Turn the (mostly-NaN) per-frame series into discrete events
present = isfinite(yPx);
events = struct('tS', {}, 'runFrames', {});

i = 1;
n = numel(present);
while i <= n
    if ~present(i)
        i = i + 1;
        continue
    end
    j = i;
    gapRun = 0;
    while j < n
        if present(j+1)
            j = j + 1;
            gapRun = 0;
        elseif gapRun < maxGapFrames
            j = j + 1;
            gapRun = gapRun + 1;
        else
            break
        end
    end
    while j > i && ~present(j)
        j = j - 1;
    end
    runLen = sum(present(i:j));

    if runLen >= cfg.sideMinRunFrames
        runMask = present(i:j);
        runYall = yPx(i:j); runTall = tS(i:j);
        runY = runYall(runMask); runT = runTall(runMask);
        signDiff = sign(runY - targetLinePx);
        crossIdx = find(signDiff(1:end-1) .* signDiff(2:end) <= 0, 1, 'first');
        if isempty(crossIdx)
            if isfield(cfg, 'sideRequireActualCrossing') && ~cfg.sideRequireActualCrossing
                tCross = runT(ceil(numel(runT)/2));
            else
                i = j + 1;
                continue
            end
        else
            y0 = runY(crossIdx); t0 = runT(crossIdx);
            y1 = runY(crossIdx+1); t1 = runT(crossIdx+1);
            if y1 == y0
                tCross = t0;
            else
                f = (targetLinePx - y0) / (y1 - y0);
                f = min(max(f, 0), 1);
                tCross = t0 + f * (t1 - t0);
            end
        end

        events(end+1).tS = tCross;  %#ok<AGROW>
        events(end).runFrames = runLen;
    end

    i = j + 1;
end

if useRoi
    fprintf(['detectLineCrossingEvents: %d candidate drop(s) found in %.1fs at line row ' ...
        '%.0fpx (ROI rows %.0f-%.0fpx, cols %.0f-%.0fpx).\n'], ...
        numel(events), duration, targetLinePx, bandLo, bandHiClamped, colLo, colHiClamped);
else
    fprintf('detectLineCrossingEvents: %d candidate drop(s) found in %.1fs at line row %.0fpx (band %.0f-%.0fpx).\n', ...
        numel(events), duration, targetLinePx, bandLo, bandHiClamped);
end

end
