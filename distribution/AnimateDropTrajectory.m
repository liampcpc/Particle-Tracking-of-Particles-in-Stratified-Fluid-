function results = AnimateDropTrajectory(sessionFiles, varargin)
% ANIMATEDROPTRAJECTORY Animate a SINGLE representative trajectory

p = inputParser;
addParameter(p, 'startCell', 'Q19', @(x) ischar(x) || isstring(x));
addParameter(p, 'startMm', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
addParameter(p, 'sessionIdx', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
addParameter(p, 'sessionOriginsMm', [], @(x) isempty(x) || (isnumeric(x) && ismatrix(x) && size(x, 2) == 2));
addParameter(p, 'sessionNames', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
addParameter(p, 'startHeightMm', [], @(x) isempty(x) || isnumeric(x));
addParameter(p, 'requireInBounds', true, @islogical);
addParameter(p, 'centralTendency', 'median', @(x) any(strcmpi(x, {'median', 'mean'})));
addParameter(p, 'glycerinePercent', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'temperatureC', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'terminalVelFracTarget', 0.99, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
addParameter(p, 'showTerminalVelPlane', true, @islogical);
addParameter(p, 'showInterfacePlane', false, @islogical);
addParameter(p, 'interfaceHeightMm', 200, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
addParameter(p, 'nFrames', 200, @(x) isnumeric(x) && isscalar(x) && x >= 10);
addParameter(p, 'frameDelaySec', 0.02, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'pauseBetweenSizesSec', 1.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parse(p, varargin{:});
opt = p.Results;
opt.centralTendency = lower(char(opt.centralTendency));
showTerminalVelPlane = opt.showTerminalVelPlane && ...
    ~isempty(opt.glycerinePercent) && ~isempty(opt.temperatureC);

switch opt.centralTendency
    case 'median', avgFn = @median;
    case 'mean',   avgFn = @mean;
end

if ischar(sessionFiles) || isstring(sessionFiles)
    sessionFiles = {char(sessionFiles)};
end

SO = normaliseSessionOrigins('AnimateDropTrajectory', numel(sessionFiles), ...
    opt.sessionIdx, opt.sessionOriginsMm, opt.sessionNames);

%% Grid calibration -- same convention as CompileHeightHeatmaps.m / CompileTrajectories.m
cfg = rigConfig();
worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
xMin = min(worldXY(:,1)); xMax = max(worldXY(:,1));
yMin = min(worldXY(:,2)); yMax = max(worldXY(:,2));
nCols = max(1, round(cfg.gridCols));
nRows = max(1, round(cfg.gridRows));
cellWMm = (xMax - xMin) / nCols;
cellHMm = (yMax - yMin) / nRows;

if ~isempty(opt.startMm)
    xStart = opt.startMm(1);
    yStart = opt.startMm(2);
    startLabel = sprintf('(%.4g, %.4g)', xStart, yStart);
else
    [startCol, startRow] = parseGridCellLabel(char(opt.startCell));
    if startCol < 1 || startCol > nCols || startRow < 1 || startRow > nRows
        warning('AnimateDropTrajectory:startCellOutside', ...
            ['startCell "%s" falls outside the current %d x %d grid -- the ' ...
             'synthetic start point will still be plotted at its computed ' ...
             'position, just outside the calibrated square.'], ...
            char(opt.startCell), nCols, nRows);
    end
    xStart = xMin + (startCol - 0.5) * cellWMm;
    yStart = yMin + (startRow - 0.5) * cellHMm;
    startLabel = char(opt.startCell);
end

if SO.used
    axisSuffix = ' from dropper';
else
    axisSuffix = '';
end

%% Load every session
allBallMm = []; allHeightMm = []; allXMm = []; allYMm = [];
allCol = []; allRow = []; allInBounds = []; allDropKey = strings(0,1);

for s = 1:numel(sessionFiles)
    f = sessionFiles{s};
    if exist(f, 'file') ~= 2
        warning('AnimateDropTrajectory:missingFile', 'Skipping missing file: %s', f);
        continue
    end
    S = load(f, 'heightResults');
    hr = S.heightResults;

    n = numel(hr.xMm);
    oShift = SO.fileOriginMm(s, :);
    for i = 1:n
        [~, ~, ~, inBoundsRaw] = mmToGridCell( ...
            hr.xMm(i), hr.yMm(i), xMin, yMin, xMax, yMax, nCols, nRows);
        [~, col, row, inBoundsShift] = mmToGridCell( ...
            hr.xMm(i) - oShift(1), hr.yMm(i) - oShift(2), xMin, yMin, xMax, yMax, nCols, nRows);
        inBounds = inBoundsRaw && inBoundsShift;

        allBallMm(end+1)   = hr.ballDiameterMm;  %#ok<AGROW>
        allHeightMm(end+1) = hr.heightMm(i);  %#ok<AGROW>
        allXMm(end+1)      = hr.xMm(i) - oShift(1);  %#ok<AGROW>
        allYMm(end+1)      = hr.yMm(i) - oShift(2);  %#ok<AGROW>
        allCol(end+1)      = col;  %#ok<AGROW>
        allRow(end+1)      = row;  %#ok<AGROW>
        allInBounds(end+1) = inBounds;  %#ok<AGROW>
        allDropKey(end+1)  = string(sprintf('%s::%d', f, hr.dropIndex(i)));  %#ok<AGROW>
    end
end

if isempty(allBallMm)
    error('AnimateDropTrajectory:noData', 'No usable rows found across %d session file(s).', numel(sessionFiles));
end

%% One animated figure per ball size
sizes = unique(allBallMm);
results = struct('ballDiameterMm', {}, 'nDropsTotal', {}, 'nDropsComplete', {}, ...
    'centralTendency', {}, 'startCell', {}, 'startXMm', {}, 'startYMm', {}, ...
    'startHeightMm', {}, 'requiredHeightsMm', {}, 'repXMm', {}, 'repYMm', {}, ...
    'terminalVelFallMm', {}, 'terminalVelPlaneHeightMm', {});

for k = 1:numel(sizes)
    sz = sizes(k);
    szMaskAll = (allBallMm == sz);
    requiredHeights = sort(unique(allHeightMm(szMaskAll)), 'descend');
    nH = numel(requiredHeights);
    if nH == 0
        continue
    end

    % heatmap counts per height, same convention as CompileHeightHeatmaps.m
    countsC = cell(1, nH);
    for hi = 1:nH
        h = requiredHeights(hi);
        mask = szMaskAll & (allHeightMm == h) & allInBounds;
        counts = zeros(nRows, nCols);
        for i = find(mask)
            counts(allRow(i), allCol(i)) = counts(allRow(i), allCol(i)) + 1;
        end
        countsC{hi} = counts;
    end
    maxCount = max(1, max(cellfun(@(c) max(c(:)), countsC)));

    % which drops are COMPLETE (all height levels present)
    dropKeysThisSize = unique(allDropKey(szMaskAll));
    nDropsTotal = numel(dropKeysThisSize);
    completeMask = false(1, nDropsTotal);
    for d = 1:nDropsTotal
        rows = szMaskAll & (allDropKey == dropKeysThisSize(d));
        heightsHere = sort(allHeightMm(rows), 'descend');
        isComplete = isequal(heightsHere, requiredHeights);
        if isComplete && opt.requireInBounds
            isComplete = all(allInBounds(rows));
        end
        completeMask(d) = isComplete;
    end
    completeDropKeys = dropKeysThisSize(completeMask);
    nDropsComplete = numel(completeDropKeys);

    if nDropsComplete == 0
        warning('AnimateDropTrajectory:noCompleteDrops', ...
            'No complete drops for the %g mm ball -- skipping its animation.', sz);
        continue
    end

    % representative (median/mean) position at each height
    repXMm = nan(1, nH); repYMm = nan(1, nH);
    for hi = 1:nH
        h = requiredHeights(hi);
        xs = nan(1, nDropsComplete); ys = nan(1, nDropsComplete);
        for d = 1:nDropsComplete
            rows = szMaskAll & (allDropKey == completeDropKeys(d)) & (allHeightMm == h);
            idx = find(rows, 1);
            xs(d) = allXMm(idx);
            ys(d) = allYMm(idx);
        end
        repXMm(hi) = avgFn(xs);
        repYMm(hi) = avgFn(ys);
    end

    % synthetic start height for THIS ball size
    if isempty(opt.startHeightMm)
        if nH >= 2
            spacingMm = median(diff(sort(requiredHeights)));
        else
            spacingMm = 0.2 * max(requiredHeights, 1);
        end
        thisStartHeightMm = max(requiredHeights) + spacingMm;
    else
        thisStartHeightMm = opt.startHeightMm;
    end

    % terminal-velocity plane height, measured down from the synthetic start marker
    vTermFallMm = NaN;
    vTermPlaneZMm = NaN;
    if showTerminalVelPlane
        try
            vTermFallMm = glycerineMixtureTerminalVelocity(sz, opt.glycerinePercent, ...
                opt.temperatureC, 'fracTarget', opt.terminalVelFracTarget);
            vTermPlaneZMm = thisStartHeightMm - vTermFallMm;
            if vTermPlaneZMm < 0
                warning('AnimateDropTrajectory:terminalVelBelowBase', ...
                    ['%g mm ball reaches %g%% of terminal velocity %.1f mm below ' ...
                     'the %s drop location (%.1f mm) -- clamping the plane to the ' ...
                     'tank base (z=0).'], sz, opt.terminalVelFracTarget*100, ...
                     vTermFallMm, startLabel, thisStartHeightMm);
                vTermPlaneZMm = 0;
            end
        catch termErr
            warning('AnimateDropTrajectory:terminalVelFailed', ...
                ['Could not compute terminal-velocity height for the %g mm ball ' ...
                 '(%g%% glycerine, %g degC): %s -- skipping the red plane for ' ...
                 'this ball size.'], sz, opt.glycerinePercent, opt.temperatureC, ...
                 termErr.message);
            vTermFallMm = NaN;
            vTermPlaneZMm = NaN;
        end
    end

    % representative curve, fit the same way as CompileTrajectories.m
    trajX = [xStart, repXMm];
    trajY = [yStart, repYMm];
    trajH = [thisStartHeightMm, requiredHeights];
    t = 1:numel(trajX);
    tFine = linspace(1, numel(trajX), opt.nFrames);
    xFine = interp1(t, trajX, tFine, 'pchip');
    yFine = interp1(t, trajY, tFine, 'pchip');
    hFine = interp1(t, trajH, tFine, 'pchip');

    fprintf(['%g mm ball: animating the %s trajectory across %d complete drop(s) ' ...
        '(of %d total) through %d height level(s)...\n'], ...
        sz, opt.centralTendency, nDropsComplete, nDropsTotal, nH);

    %% Figure setup
    fig = figure('Name', sprintf('Animated %s trajectory - %g mm ball', opt.centralTendency, sz), 'Color', 'w');
    ax = axes(fig);
    hold(ax, 'on');

    TANK_SIDE_MM   = 200;
    TANK_HEIGHT_MM = max(400, thisStartHeightMm + 20);
    tankCenterX = (xMin + xMax) / 2 - SO.meanOriginMm(1);
    tankCenterY = (yMin + yMax) / 2 - SO.meanOriginMm(2);
    hexAngles   = deg2rad(30 + (0:6)*60);
    hexX = tankCenterX + TANK_SIDE_MM * cos(hexAngles);
    hexY = tankCenterY + TANK_SIDE_MM * sin(hexAngles);
    tankColor = [0.53 0.81 0.92];
    glassFaceAlpha = 0.12;
    for vI = 1:6
        vJ = vI + 1;
        faceX = [hexX(vI) hexX(vJ) hexX(vJ) hexX(vI)];
        faceY = [hexY(vI) hexY(vJ) hexY(vJ) hexY(vI)];
        faceZ = [0 0 TANK_HEIGHT_MM TANK_HEIGHT_MM];
        fill3(ax, faceX, faceY, faceZ, tankColor, ...
            'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);
    end
    fill3(ax, hexX, hexY, zeros(size(hexX)), tankColor, ...
        'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);
    fill3(ax, hexX, hexY, TANK_HEIGHT_MM * ones(size(hexX)), tankColor, ...
        'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);

    plot3(ax, xStart, yStart, thisStartHeightMm, 'kd', ...
        'MarkerSize', 10, 'MarkerFaceColor', 'k');
    text(ax, xStart, yStart, thisStartHeightMm, sprintf('  %s (synthetic start)', startLabel), ...
        'FontSize', 9, 'VerticalAlignment', 'bottom');

    xCentersMm = xMin + ((1:nCols) - 0.5) * cellWMm;
    yCentersMm = yMin + ((1:nRows) - 0.5) * cellHMm;
    [Xg, Yg] = meshgrid(xCentersMm, yCentersMm);
    layerBorderX = [xMin xMax xMax xMin xMin];
    layerBorderY = [yMin yMin yMax yMax yMin];

    layerSurfH   = gobjects(1, nH);
    layerBorderH = gobjects(1, nH);
    anchorPtH    = gobjects(1, nH);
    layerRevealed = false(1, nH);

    for hi = 1:nH
        h = requiredHeights(hi);
        Zg = h * ones(size(countsC{hi}));
        layerSurfH(hi) = surf(ax, Xg, Yg, Zg, countsC{hi}, 'FaceColor', 'flat', ...
            'FaceAlpha', 1, 'EdgeColor', 'none', 'LineWidth', 0.25, 'Visible', 'off');
        layerBorderH(hi) = plot3(ax, layerBorderX, layerBorderY, h * ones(1, 5), ...
            'Color', 'k', 'LineWidth', 1.25, 'Visible', 'off');
        anchorPtH(hi) = plot3(ax, repXMm(hi), repYMm(hi), h, 'o', ...
            'MarkerSize', 7, 'MarkerFaceColor', [1 1 1], ...
            'MarkerEdgeColor', [0.05 0.05 0.05], 'LineWidth', 1.2, 'Visible', 'off');
    end

    planeRevealed = false;
    if showTerminalVelPlane && ~isnan(vTermPlaneZMm)
        planeColor = [0.85 0.1 0.1];
        planeSurfH = fill3(ax, hexX, hexY, vTermPlaneZMm * ones(size(hexX)), planeColor, ...
            'FaceAlpha', 0.55, 'EdgeColor', planeColor, 'LineWidth', 1, 'Visible', 'off');
        planeTextH = text(ax, hexX(1), hexY(1), vTermPlaneZMm, ...
            sprintf('  terminal velocity reached (%.1f mm below %s)', vTermFallMm, startLabel), ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', planeColor, ...
            'VerticalAlignment', 'bottom', 'Visible', 'off');
    end

    %% Stratified-interface plane (optional)
    ifaceDrawn = false;
    ifaceRevealed = false;
    if opt.showInterfacePlane
        if opt.interfaceHeightMm > TANK_HEIGHT_MM
            warning('Stratified-interface plane at %g mm is above the drawn tank (%g mm) -- skipped.', ...
                opt.interfaceHeightMm, TANK_HEIGHT_MM);
        else
            ifaceColor = [0.95 0.55 0.05];
            ifaceSurfH = fill3(ax, hexX, hexY, opt.interfaceHeightMm * ones(size(hexX)), ifaceColor, ...
                'FaceAlpha', 0.35, 'EdgeColor', ifaceColor, 'LineWidth', 1, 'Visible', 'off');
            ifaceTextH = text(ax, hexX(4), hexY(4), opt.interfaceHeightMm, ...
                sprintf('  stratified interface (%g mm above base)', opt.interfaceHeightMm), ...
                'FontSize', 9, 'FontWeight', 'bold', 'Color', ifaceColor, ...
                'VerticalAlignment', 'bottom', 'Visible', 'off');
            ifaceDrawn = true;
        end
    end

    trailH = plot3(ax, nan, nan, nan, '-', 'Color', [0.05 0.05 0.05], 'LineWidth', 2.5);
    headH  = plot3(ax, nan, nan, nan, 'o', 'MarkerSize', 12, ...
        'MarkerFaceColor', [1 1 1], 'MarkerEdgeColor', [0.05 0.05 0.05], 'LineWidth', 1.5);

    colormap(ax, mutedHeatColormap(256));
    cb = colorbar(ax);
    cb.Label.String = 'drop count';
    caxis(ax, [0 maxCount]);  %#ok<CAXIS>
    xlabel(ax, ['x (mm)' axisSuffix]); ylabel(ax, ['y (mm)' axisSuffix]); zlabel(ax, 'height above base (mm)');
    title(ax, sprintf('%g mm ball: %s trajectory descending through the landing distribution', ...
        sz, opt.centralTendency));
    view(ax, -35, 25);
    grid(ax, 'on');
    box(ax, 'on');
    axis(ax, 'equal');
    pad = 0.1 * TANK_SIDE_MM;
    xlim(ax, [min(hexX) max(hexX)] + [-pad pad]);
    ylim(ax, [min(hexY) max(hexY)] + [-pad pad]);
    zlim(ax, [0 TANK_HEIGHT_MM]);

    %% Animation loop
    for frame = 1:opt.nFrames
        set(trailH, 'XData', xFine(1:frame), 'YData', yFine(1:frame), 'ZData', hFine(1:frame));
        set(headH, 'XData', xFine(frame), 'YData', yFine(frame), 'ZData', hFine(frame));

        for hi = 1:nH
            if ~layerRevealed(hi) && hFine(frame) <= requiredHeights(hi)
                set(layerSurfH(hi), 'Visible', 'on');
                set(layerBorderH(hi), 'Visible', 'on');
                set(anchorPtH(hi), 'Visible', 'on');
                layerRevealed(hi) = true;
            end
        end
        if ifaceDrawn && ~ifaceRevealed && hFine(frame) <= opt.interfaceHeightMm
            set(ifaceSurfH, 'Visible', 'on');
            set(ifaceTextH, 'Visible', 'on');
            ifaceRevealed = true;
        end
        if showTerminalVelPlane && ~planeRevealed && ~isnan(vTermPlaneZMm) && hFine(frame) <= vTermPlaneZMm
            set(planeSurfH, 'Visible', 'on');
            set(planeTextH, 'Visible', 'on');
            planeRevealed = true;
        end

        drawnow;
        if opt.frameDelaySec > 0
            pause(opt.frameDelaySec);
        end
    end

    res = struct();
    res.ballDiameterMm = sz;
    res.nDropsTotal     = nDropsTotal;
    res.nDropsComplete  = nDropsComplete;
    res.centralTendency = opt.centralTendency;
    res.startCell        = startLabel;
    res.startXMm         = xStart;
    res.startYMm         = yStart;
    res.startHeightMm    = thisStartHeightMm;
    res.requiredHeightsMm = requiredHeights;
    res.repXMm           = repXMm;
    res.repYMm           = repYMm;
    res.terminalVelFallMm = vTermFallMm;
    res.terminalVelPlaneHeightMm = vTermPlaneZMm;
    results(end+1) = res;  %#ok<AGROW>

    if k < numel(sizes) && opt.pauseBetweenSizesSec > 0
        pause(opt.pauseBetweenSizesSec);
    end
end

end

%% Local functions
function [col, row] = parseGridCellLabel(label)
% PARSEGRIDCELLLABEL Inverse of mmToGridCell.m's own colLetter()
tok = regexp(label, '^([A-Za-z]+)(\d+)$', 'tokens', 'once');
if isempty(tok)
    error('AnimateDropTrajectory:badCellLabel', ...
        '"%s" is not a valid grid cell label (expected e.g. "Q19").', label);
end
letters = upper(tok{1});
row = str2double(tok{2});
col = 0;
for i = 1:length(letters)
    col = col * 26 + (double(letters(i)) - double('A') + 1);
end
end

function cmap = mutedHeatColormap(n)
% "Traffic-light" heatmap colour scheme (green -> yellow -> orange -> red)
if nargin < 1, n = 256; end
stops = [0.00  0.69 0.85 0.44  % green
         0.25  0.85 0.80 0.30
         0.50  0.95 0.75 0.20
         0.70  0.90 0.45 0.15
         1.00  0.75 0.12 0.12];
x = linspace(0, 1, n)';
cmap = [interp1(stops(:,1), stops(:,2), x, 'pchip'), ...
        interp1(stops(:,1), stops(:,3), x, 'pchip'), ...
        interp1(stops(:,1), stops(:,4), x, 'pchip')];
cmap = min(max(cmap, 0), 1);
end
