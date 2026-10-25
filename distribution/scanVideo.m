function data = scanVideo(videoPath, cfg, mode)
% SCANVIDEO Shared front end for both impact-detection approaches

if nargin < 3, mode = 'blob'; end

v = VideoReader(videoPath);
data.fps        = v.FrameRate;
data.videoPath  = videoPath;
data.mode       = mode;

%% Lens parameters
camParams = [];
if cfg.applyUndistort && isfile(cfg.cameraParamsFile)
    S = load(cfg.cameraParamsFile);
    camParams = S.params;

    if isfield(S, 'calibResolution') && ~isempty(S.calibResolution)
        vidRes = [v.Height, v.Width];
        if ~isequal(vidRes(:)', S.calibResolution(:)')
            msg = sprintf([ ...
                'CALIBRATION RESOLUTION MISMATCH.\n' ...
                '  calibration : %d x %d px  (%s)\n' ...
                '  this video  : %d x %d px  (%s)\n' ...
                'Distortion coefficients are in pixels, so this ' ...
                'calibration cannot be applied to this footage -- doing ' ...
                'so would bias every radius. Re-run calibrateRig on a ' ...
                'VIDEO shot in the same mode as your experiments.'], ...
                S.calibResolution(2), S.calibResolution(1), ...
                stringify(S, 'calibSource'), ...
                vidRes(2), vidRes(1), videoPath);
            if isfield(cfg,'enforceCalibResolution') && ~cfg.enforceCalibResolution
                warning('scanVideo:calibResolutionMismatch', '%s', msg);
                camParams = [];  % safer to skip than to misapply
            else
                error('scanVideo:calibResolutionMismatch', '%s', msg);
            end
        end
    else
        warning('scanVideo:calibNoResolution', ...
            ['%s predates the resolution check and does not record what ' ...
             'it was calibrated at. Cannot verify it matches this video. ' ...
             'Re-run calibrateRig to remove this risk.'], cfg.cameraParamsFile);
    end
elseif cfg.applyUndistort
    warning('scanVideo:noCalibration', ...
        ['No camera calibration found at %s. Running WITHOUT distortion ' ...
         'correction -- edge positions will be biased inward.'], ...
        cfg.cameraParamsFile);
end

%% Pass 1: background model (blob mode only) and fiducial transform
bg = [];
stack = [];
nBg = 0;

while hasFrame(v) && nBg < cfg.backgroundFrames
    F = readFrameCorrected(v, camParams, cfg);
    g = im2gray(F);
    if isempty(stack)
        stack = zeros([size(g), cfg.backgroundFrames], 'like', g);
    end
    nBg = nBg + 1;
    stack(:,:,nBg) = g;
end

if nBg == 0
    error('scanVideo:emptyVideo', 'Could not read any frames from %s', videoPath);
end

stack = stack(:,:,1:nBg);
bgFrame = median(stack, 3);

if strcmp(mode, 'blob')
    bg = bgFrame;
end

tform = [];
mmPerPx = cfg.mmPerPxAtBase;
if cfg.useFiducials
    [tform, mmPerPxDetected] = fiducialTransform(bgFrame, cfg);
    if ~isempty(mmPerPxDetected)
        mmPerPx = mmPerPxDetected;
    end
end
data.tform    = tform;
data.mmPerPx  = mmPerPx;

%% Pass 2: scan every frame
v.CurrentTime = 0;

nGuess = max(round(v.Duration * v.FrameRate) + 10, 100);
area      = nan(nGuess,1);
radius    = nan(nGuess,1);
intensity = nan(nGuess,1);
xs        = nan(nGuess,1);
ys        = nan(nGuess,1);

k = 0;
while hasFrame(v)
    F = readFrameCorrected(v, camParams, cfg);
    g = im2gray(F);
    k = k + 1;

    if k > numel(area)
        area(end+1000)      = NaN;  %#ok<AGROW>
        radius(end+1000)    = NaN;  %#ok<AGROW>
        intensity(end+1000) = NaN;  %#ok<AGROW>
        xs(end+1000)        = NaN;  %#ok<AGROW>
        ys(end+1000)        = NaN;  %#ok<AGROW>
    end

    if strcmp(mode, 'blob')
        hit = findBlob(g, bg, cfg);
    else
        hit = findGlint(g, cfg);
    end

    if ~isempty(hit)
        area(k)      = hit.area;
        xs(k)        = hit.cx;
        ys(k)        = hit.cy;
        if isfield(hit, 'radius'),    radius(k)    = hit.radius;    end
        if isfield(hit, 'intensity'), intensity(k) = hit.intensity; end
    end
end

data.nFrames   = k;
data.area      = area(1:k);
data.radius    = radius(1:k);
data.intensity = intensity(1:k);
data.x         = xs(1:k);
data.y         = ys(1:k);

if cfg.verbose
    fprintf('%s: %d frames, %d detections (%s mode)\n', ...
        videoPath, k, nnz(isfinite(data.x)), mode);
end

end

%% Local functions
function s = stringify(S, fieldName)
% STRINGIFY Best-effort description of a saved field, for error messages
if isfield(S, fieldName) && (ischar(S.(fieldName)) || isstring(S.(fieldName)))
    s = char(S.(fieldName));
else
    s = 'source not recorded';
end
end

function F = readFrameCorrected(v, camParams, cfg)
% READFRAMECORRECTED Read one frame and undistort it if we can
F = readFrame(v);
if cfg.applyUndistort && ~isempty(camParams)
    F = undistortImage(F, camParams);
end
end

function [tform, mmPerPx] = fiducialTransform(gray, cfg)
% FIDUCIALTRANSFORM Map image pixels to tank coordinates using ArUco tags

tform   = [];
mmPerPx = [];

try
    [ids, locs] = readArucoMarker(gray, cfg.arucoFamily);
catch ME
    warning('scanVideo:arucoUnavailable', ...
        ['readArucoMarker failed (%s). Continuing without fiducial ' ...
         'registration -- positions stay in raw pixels.'], ME.identifier);
    return
end

if isempty(ids)
    warning('scanVideo:noTags', 'No ArUco tags detected.');
    return
end

imgPts   = [];
worldPts = [];
for i = 1:numel(ids)
    row = find(cfg.tagIds == ids(i), 1);
    if isempty(row), continue; end
    corners = locs(:,:,i);
    imgPts(end+1,:)   = mean(corners, 1);  %#ok<AGROW> tag centre
    worldPts(end+1,:) = cfg.tagWorld(row,:);  %#ok<AGROW>
end

nMatched = size(imgPts,1);
if nMatched < cfg.minTagsRequired
    warning('scanVideo:tooFewTags', ...
        'Only %d tags matched (need %d). No transform applied.', ...
        nMatched, cfg.minTagsRequired);
    return
end

if nMatched < numel(cfg.tagIds)
    warning('scanVideo:partialTags', ...
        '%d of %d tags found -- transform is fitted but less constrained.', ...
        nMatched, numel(cfg.tagIds));
end

tform = fitgeotform2d(imgPts, worldPts, 'projective');

dW = pdist(worldPts);
dI = pdist(imgPts);
good = dI > 0;
if any(good)
    mmPerPx = mean(dW(good) ./ dI(good));
end

end

function hit = findBlob(gray, bg, cfg)
% FINDBLOB Isolate the moving particle by background subtraction

hit = [];

d = imabsdiff(im2double(gray), im2double(bg));
mask = d > cfg.blobThreshold;

se = strel('disk', cfg.morphRadius);
mask = imclose(mask, se);
mask = imopen(mask, se);

stats = regionprops(mask, 'Area', 'Centroid', 'BoundingBox');
if isempty(stats), return; end

[h, w] = size(gray);
m = cfg.edgeMarginPx;

best = [];
for i = 1:numel(stats)
    if stats(i).Area < cfg.minAreaPx, continue; end

    bb = stats(i).BoundingBox;
    if bb(1) <= m || bb(2) <= m || ...
       bb(1)+bb(3) >= w-m || bb(2)+bb(4) >= h-m
        continue
    end

    if isempty(best) || stats(i).Area > best.Area
        best = stats(i);
    end
end

if isempty(best), return; end

hit.area   = best.Area;
hit.cx     = best.Centroid(1);
hit.cy     = best.Centroid(2);
hit.radius = sqrt(best.Area / pi);

end

function hit = findGlint(gray, cfg)
% FINDGLINT Find the specular highlight from the laser sheet

hit = [];

g = im2double(gray);
mask = g > cfg.laserThreshold;
if ~any(mask(:)), return; end

stats = regionprops(mask, g, 'Area', 'Centroid', 'BoundingBox', ...
                    'MeanIntensity');
if isempty(stats), return; end

[h, w] = size(gray);
m = cfg.edgeMarginPx;

best = [];
bestI = -inf;
for i = 1:numel(stats)
    if stats(i).Area < cfg.laserMinAreaPx, continue; end

    bb = stats(i).BoundingBox;
    if bb(1) <= m || bb(2) <= m || ...
       bb(1)+bb(3) >= w-m || bb(2)+bb(4) >= h-m
        continue
    end

    totalI = stats(i).Area * stats(i).MeanIntensity;
    if totalI > bestI
        bestI = totalI;
        best = stats(i);
    end
end

if isempty(best), return; end

hit.area      = best.Area;
hit.cx        = best.Centroid(1);
hit.cy        = best.Centroid(2);
hit.intensity = bestI;

end
