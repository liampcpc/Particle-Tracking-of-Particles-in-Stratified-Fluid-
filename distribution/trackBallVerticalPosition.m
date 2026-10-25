function track = trackBallVerticalPosition(videoPath, startT, endT, cfg, rowRangePx)
% TRACKBALLVERTICALPOSITION Background-subtraction blob tracking of the ball on the SIDE-view camera

v = VideoReader(videoPath);
fps = v.FrameRate;

startT = max(0, startT);
endT   = min(v.Duration, endT);
if endT <= startT
    error('trackBallVerticalPosition:badWindow', ...
        'Requested window [%.3f, %.3f]s is empty or invalid for %s.', startT, endT, videoPath);
end

if nargin < 5 || isempty(rowRangePx)
    rowLo = 1; rowHi = v.Height;
else
    rowLo = max(1, round(rowRangePx(1)));
    rowHi = min(v.Height, round(rowRangePx(2)));
end

if isfield(cfg, 'sideRoiFile') && exist(cfg.sideRoiFile, 'file') == 2
    R = load(cfg.sideRoiFile, 'roi');
    roi = R.roi;  % [x y w h]
    colLo = max(1, roi(1));
    colHi = min(v.Width, roi(1) + roi(3) - 1);
else
    colLo = 1; colHi = v.Width;
end

%% Build background from the first sideBackgroundFrames of the window
v.CurrentTime = startT;
bgFrames = cell(1, cfg.sideBackgroundFrames);
nBg = 0;
while nBg < cfg.sideBackgroundFrames && hasFrame(v) && v.CurrentTime <= endT
    nBg = nBg + 1;
    g = im2double(rgb2gray(readFrame(v)));
    bgFrames{nBg} = g(rowLo:rowHi, colLo:colHi);
end
if nBg < 3
    error('trackBallVerticalPosition:noBackground', ...
        ['Only found %d frame(s) to build a background from in [%.3f, %.3f]s -- ' ...
         'window is too short, or cfg.sideBackgroundFrames is too large for it.'], ...
         nBg, startT, endT);
end
bg = median(cat(3, bgFrames{1:nBg}), 3);

%% Track every frame across the (possibly row-restricted) window
v.CurrentTime = startT;
se = strel('disk', cfg.sideMorphRadius);

tS  = [];
xPx = [];
yPx = [];

while hasFrame(v) && v.CurrentTime <= endT
    tNow = v.CurrentTime;
    F = im2double(rgb2gray(readFrame(v)));
    F = F(rowLo:rowHi, colLo:colHi);

    d = abs(F - bg);
    mask = d > cfg.sideBlobThreshold;
    mask = imopen(mask, se);
    mask = imclose(mask, se);

    stats = regionprops(mask, 'Area', 'Centroid');
    stats = stats([stats.Area] >= cfg.sideMinAreaPx);

    tS(end+1)  = tNow;  %#ok<AGROW>
    if isempty(stats)
        xPx(end+1) = NaN;  %#ok<AGROW>
        yPx(end+1) = NaN;  %#ok<AGROW>
    else
        [~, biggest] = max([stats.Area]);
        c = stats(biggest).Centroid;
        xPx(end+1) = c(1) + colLo - 1;
        yPx(end+1) = c(2) + rowLo - 1;
    end
end

track = struct('tS', tS(:), 'xPx', xPx(:), 'yPx', yPx(:), 'fps', fps);

end
