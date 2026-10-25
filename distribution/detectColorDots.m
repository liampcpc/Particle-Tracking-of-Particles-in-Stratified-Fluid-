function result = detectColorDots(source, varargin)
% DETECTCOLORDOTS Find the 4 printed colour-dot markers in an image and report each one's pixel position

p = inputParser;
addParameter(p, 'saveAnnotated', true, @islogical);
addParameter(p, 'frameTime', [], @(x) isempty(x) || isnumeric(x));
addParameter(p, 'outSuffix', '_colordots.png', @ischar);
parse(p, varargin{:});
opt = p.Results;

targets = struct( ...
    'name',   {'cyan',      'yellow',    'green',      'red'}, ...
    'rgb',    {[0 174 239], [255 212 0], [0 255 212],  [230 30 30]}, ...
    'minVal', {0.15,        0.15,        0.08,         0.28}, ...
    'minSat', {0.35,        0.50,        0.06,         0.50}, ...
    'roi',    {[],          [],          [0 0.30 0.12 0.45], []});

%% OPTIONAL: user-picked colour-dot ROIs (pickColorDotROIs.m)
colorDotROIsFile = fullfile(fileparts(mfilename('fullpath')), 'colorDotROIs.mat');
if exist(colorDotROIsFile, 'file') == 2
    Rdots = load(colorDotROIsFile, 'rois');
    for ti = 1:numel(targets)
        if isfield(Rdots.rois, targets(ti).name)
            targets(ti).roi = Rdots.rois.(targets(ti).name);
        end
    end
    fprintf('Using user-picked colour-dot ROIs from %s.\n', colorDotROIsFile);
end

hueTolDeg = 25;  % +/- degrees on a 360-degree hue wheel
minAreaPx = 30;  % reject speckle noise
maxAreaPx = 20000;  % reject implausibly large regions
warnHueOffsetDeg = 20;  % flag (not reject) a found dot whose hue sits this far from its target
morphRadius = 2;

%% Load the image
img = loadSourceImage(source, opt.frameTime);
hsvImg = rgb2hsv(im2double(img));
H = hsvImg(:,:,1); S = hsvImg(:,:,2); V = hsvImg(:,:,3);

[imgH, imgW, ~] = size(img);
se = strel('disk', morphRadius);

result = struct();
result.image = img;
result.dots  = struct('name', {}, 'found', {}, 'x', {}, 'y', {}, ...
    'areaPx', {}, 'targetRgb', {}, 'hueOffsetDeg', {}, 'suspicious', {});

fprintf('Scanning for %d colour dot(s)...\n', numel(targets));

for i = 1:numel(targets)
    t = targets(i);
    targetHsv = rgb2hsv(reshape(double(t.rgb)/255, 1, 1, 3));
    targetHueDeg = targetHsv(1) * 360;

    hueDeg = H * 360;
    dHue = abs(hueDeg - targetHueDeg);
    dHue = min(dHue, 360 - dHue);

    mask = (dHue <= hueTolDeg) & (S >= t.minSat) & (V >= t.minVal);

    if isfield(t, 'roi') && ~isempty(t.roi)
        xLo = max(1, round(t.roi(1) * imgW)); xHi = round(t.roi(2) * imgW);
        yLo = max(1, round(t.roi(3) * imgH)); yHi = round(t.roi(4) * imgH);
        roiMask = false(imgH, imgW);
        roiMask(yLo:min(yHi,imgH), xLo:min(xHi,imgW)) = true;
        mask = mask & roiMask;
    end

    mask = imopen(mask, se);
    mask = imclose(mask, se);

    stats = regionprops(mask, 'Area', 'Centroid', 'PixelIdxList');
    best = [];
    for k = 1:numel(stats)
        if stats(k).Area < minAreaPx || stats(k).Area > maxAreaPx, continue; end
        if isempty(best) || stats(k).Area > best.Area
            best = stats(k);
        end
    end

    d = struct();
    d.name = t.name;
    d.targetRgb = t.rgb;
    if isempty(best)
        d.found = false; d.x = NaN; d.y = NaN; d.areaPx = NaN;
        d.hueOffsetDeg = NaN; d.suspicious = false;
        fprintf('  %-8s NOT FOUND\n', t.name);
    else
        d.found = true;
        blobHue = mean(hueDeg(best.PixelIdxList));
        off = abs(blobHue - targetHueDeg);
        d.hueOffsetDeg = min(off, 360 - off);
        d.suspicious = d.hueOffsetDeg > warnHueOffsetDeg;
        d.x = best.Centroid(1); d.y = best.Centroid(2); d.areaPx = best.Area;
        flagStr = '';
        if d.suspicious
            flagStr = sprintf('   *** CHECK THIS -- hue offset %.0f deg past the %.0f deg warn line ***', ...
                d.hueOffsetDeg, warnHueOffsetDeg);
        end
        fprintf('  %-8s found at (%.0f, %.0f), %.0f px^2, hue offset %.0f deg%s\n', ...
            t.name, d.x, d.y, d.areaPx, d.hueOffsetDeg, flagStr);
    end
    result.dots(end+1) = d;  %#ok<AGROW>
end

nFound = sum([result.dots.found]);
nSuspicious = sum([result.dots.suspicious]);
fprintf('%d / %d dots found', nFound, numel(targets));
if nSuspicious > 0
    fprintf(' (%d flagged as suspicious -- verify these by eye)', nSuspicious);
end
fprintf('.\n');
if nFound < numel(targets)
    fprintf(['Some dots were not found. This can genuinely mean the dot is ' ...
        'not in frame (out of view, not yet mounted) -- no amount of ' ...
        'threshold tuning fixes that. If you can see it in the image and ' ...
        'it still was not found, check lighting/glare and whether ' ...
        'hueTolDeg/minSat/minVal need adjusting -- see the annotated image.\n']);
end

%% Annotated verification image
if opt.saveAnnotated
    vis = img;
    for i = 1:numel(result.dots)
        d = result.dots(i);
        if ~d.found, continue; end
        ringColor = 'white';
        label = d.name;
        if d.suspicious
            ringColor = 'red';  % suspicious match: red outline regardless of the dot's own colour
            label = [d.name ' ?'];
        end
        vis = insertShape(vis, 'Circle', [d.x d.y 25], ...
            'Color', ringColor, 'LineWidth', 4);
        vis = insertShape(vis, 'Circle', [d.x d.y 25], ...
            'Color', uint8(d.targetRgb), 'LineWidth', 2);
        vis = insertMarker(vis, [d.x d.y], '+', 'Color', ringColor, 'Size', 12);
        vis = insertText(vis, [d.x+30 d.y-10], label, 'FontSize', 16, ...
            'BoxColor', ringColor, 'TextColor', 'black');
    end
    vis = insertText(vis, [10 10], sprintf('%d / %d dots found', nFound, numel(targets)), ...
        'FontSize', 18, 'BoxColor', 'black', 'TextColor', 'white');

    if ischar(source) || isstring(source)
        [pth, nm] = fileparts(source);
        outPath = fullfile(pth, [nm opt.outSuffix]);
    else
        outPath = fullfile(pwd, ['detectColorDots' opt.outSuffix]);
    end
    imwrite(vis, outPath);
    result.annotatedImage = outPath;
    fprintf('Annotated image: %s\n', outPath);
end

end

%% Local functions
function img = loadSourceImage(source, frameTime)
% LOADSOURCEIMAGE Accept an already-loaded image, an image file, or a video (in which case one frame is read)
if ~(ischar(source) || isstring(source))
    img = source;  % already an image matrix
    return
end

source = char(source);
[~, ~, ext] = fileparts(source);
if any(strcmpi(ext, {'.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff'}))
    img = imread(source);
    return
end

if exist(source, 'file') ~= 2
    error('detectColorDots:notFound', 'Cannot find "%s".', source);
end
v = VideoReader(source);
if ~isempty(frameTime)
    v.CurrentTime = max(0, min(frameTime, max(0, v.Duration - 1/v.FrameRate)));
else
    v.CurrentTime = v.Duration / 2;
end
img = readFrame(v);
end
