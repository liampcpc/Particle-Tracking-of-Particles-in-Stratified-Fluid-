function results = CompileTrajectories(sessionFiles, varargin)
% COMPILETRAJECTORIES Aggregate SplitAndTrackHeights.m's saved heightResults.mat files into one 3D...

p = inputParser;
addParameter(p, 'saveFigures', true, @islogical);
addParameter(p, 'outDir', '', @ischar);
addParameter(p, 'startCell', 'Q19', @(x) ischar(x) || isstring(x));
addParameter(p, 'startMm', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
addParameter(p, 'sessionIdx', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
addParameter(p, 'sessionOriginsMm', [], @(x) isempty(x) || (isnumeric(x) && ismatrix(x) && size(x, 2) == 2));
addParameter(p, 'sessionNames', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
addParameter(p, 'startHeightMm', [], @(x) isempty(x) || isnumeric(x));
addParameter(p, 'requireInBounds', true, @islogical);
addParameter(p, 'glycerinePercent', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'temperatureC', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'terminalVelFracTarget', 0.99, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
addParameter(p, 'showTerminalVelPlane', true, @islogical);
addParameter(p, 'showInterfacePlane', false, @islogical);
addParameter(p, 'interfaceHeightMm', 200, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
addParameter(p, 'nSigma', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
parse(p, varargin{:});
opt = p.Results;
showTerminalVelPlane = opt.showTerminalVelPlane && ...
    ~isempty(opt.glycerinePercent) && ~isempty(opt.temperatureC);

if ischar(sessionFiles) || isstring(sessionFiles)
    sessionFiles = {char(sessionFiles)};
end

SO = normaliseSessionOrigins('CompileTrajectories', numel(sessionFiles), ...
    opt.sessionIdx, opt.sessionOriginsMm, opt.sessionNames);

%% Grid calibration
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
        warning('CompileTrajectories:startCellOutside', ...
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
    fileSuffix = '_combined';
else
    axisSuffix = '';
    fileSuffix = '';
end
if isempty(opt.nSigma)
    winSuffix = '';
else
    winSuffix = sprintf('_%gsigma', opt.nSigma);
end
MIN_HALF_MM = 2;  % smallest half-width of the nSigma window, in mm

%% Load every session, recompute EACH ROW's in-bounds flag against the CURRENT calibration
allBallMm = []; allDropIdx = []; allHeightMm = []; allXMm = []; allYMm = [];
allInBounds = []; allDropKey = strings(0,1);

for s = 1:numel(sessionFiles)
    f = sessionFiles{s};
    if exist(f, 'file') ~= 2
        warning('CompileTrajectories:missingFile', 'Skipping missing file: %s', f);
        continue
    end
    S = load(f, 'heightResults');
    hr = S.heightResults;

    n = numel(hr.xMm);
    oShift = SO.fileOriginMm(s, :);
    for i = 1:n
        [~, ~, ~, inBounds] = mmToGridCell( ...
            hr.xMm(i), hr.yMm(i), xMin, yMin, xMax, yMax, nCols, nRows);

        allBallMm(end+1)   = hr.ballDiameterMm;  %#ok<AGROW>
        allDropIdx(end+1)  = hr.dropIndex(i);  %#ok<AGROW>
        allHeightMm(end+1) = hr.heightMm(i);  %#ok<AGROW>
        allXMm(end+1)      = hr.xMm(i) - oShift(1);  %#ok<AGROW>
        allYMm(end+1)      = hr.yMm(i) - oShift(2);  %#ok<AGROW>
        allInBounds(end+1) = inBounds;  %#ok<AGROW>
        allDropKey(end+1)  = string(sprintf('%s::%d', f, hr.dropIndex(i)));  %#ok<AGROW>
    end
end

if isempty(allBallMm)
    error('CompileTrajectories:noData', 'No usable rows found across %d session file(s).', numel(sessionFiles));
end

outDir = opt.outDir;
if isempty(outDir), outDir = pwd; end
if opt.saveFigures && ~exist(outDir, 'dir'), mkdir(outDir); end

%% One trajectory-bundle figure per ball size
sizes = unique(allBallMm);
results = struct('ballDiameterMm', {}, 'nDropsTotal', {}, 'nDropsComplete', {}, ...
    'startCell', {}, 'startXMm', {}, 'startYMm', {}, 'startHeightMm', {}, ...
    'terminalVelFallMm', {}, 'terminalVelPlaneHeightMm', {});

for k = 1:numel(sizes)
    sz = sizes(k);
    szMask = (allBallMm == sz);
    requiredHeights = sort(unique(allHeightMm(szMask)), 'descend');

    if isempty(opt.startHeightMm)
        if numel(requiredHeights) >= 2
            spacingMm = median(diff(sort(requiredHeights)));
        else
            spacingMm = 0.2 * max(requiredHeights, 1);
        end
        thisStartHeightMm = max(requiredHeights) + spacingMm;
    else
        thisStartHeightMm = opt.startHeightMm;
    end

    dropKeysThisSize = unique(allDropKey(szMask));
    nDropsTotal = numel(dropKeysThisSize);

    trajX = {}; trajY = {}; trajH = {};
    for d = 1:nDropsTotal
        rows = szMask & (allDropKey == dropKeysThisSize(d));
        heightsHere = sort(allHeightMm(rows), 'descend');

        isComplete = isequal(heightsHere, requiredHeights);
        if isComplete && opt.requireInBounds
            isComplete = all(allInBounds(rows));
        end
        if ~isComplete, continue; end

        [hSorted, ord] = sort(allHeightMm(rows), 'descend');
        xRows = allXMm(rows); yRows = allYMm(rows);
        xSorted = xRows(ord); ySorted = yRows(ord);

        trajX{end+1} = [xStart, xSorted];  %#ok<AGROW>
        trajY{end+1} = [yStart, ySorted];  %#ok<AGROW>
        trajH{end+1} = [thisStartHeightMm, hSorted];  %#ok<AGROW>
    end
    nDropsComplete = numel(trajX);

    % Optional nSigma window (x/y), from the complete drops' positions
    windowed = false;
    if ~isempty(opt.nSigma) && nDropsComplete >= 2
        XM = vertcat(trajX{:});  YM = vertcat(trajY{:});
        muXw = mean(XM(:, 2:end), 1);  sdXw = std(XM(:, 2:end), 0, 1);
        muYw = mean(YM(:, 2:end), 1);  sdYw = std(YM(:, 2:end), 0, 1);
        xWinLo = min([muXw - opt.nSigma * sdXw, xStart]);  xWinHi = max([muXw + opt.nSigma * sdXw, xStart]);
        yWinLo = min([muYw - opt.nSigma * sdYw, yStart]);  yWinHi = max([muYw + opt.nSigma * sdYw, yStart]);
        halfWin = max([(xWinHi - xWinLo) / 2, (yWinHi - yWinLo) / 2, MIN_HALF_MM]);
        cxWin = (xWinLo + xWinHi) / 2;  cyWin = (yWinLo + yWinHi) / 2;
        xWinLo = cxWin - halfWin;  xWinHi = cxWin + halfWin;
        yWinLo = cyWin - halfWin;  yWinHi = cyWin + halfWin;
        windowed = true;
        fprintf('  %g mm ball: +/-%g sigma window = x %.1f to %.1f mm, y %.1f to %.1f mm\n', ...
            sz, opt.nSigma, xWinLo, xWinHi, yWinLo, yWinHi);
    end

    fprintf('%g mm ball: %d / %d drop(s) had all %d height level(s) -- plotting those.\n', ...
        sz, nDropsComplete, nDropsTotal, numel(requiredHeights));

    fig = figure('Name', sprintf('Trajectories - %g mm ball', sz), 'Color', 'w');
    ax = axes(fig);
    hold(ax, 'on');

    colors = hsv(max(nDropsComplete, 1));
    for d = 1:nDropsComplete
        t = 1:numel(trajX{d});
        tFine = linspace(1, numel(trajX{d}), 200);
        xFine = interp1(t, trajX{d}, tFine, 'pchip');
        yFine = interp1(t, trajY{d}, tFine, 'pchip');
        hFine = interp1(t, trajH{d}, tFine, 'pchip');

        plot3(ax, xFine, yFine, hFine, '-', 'Color', colors(d,:), 'LineWidth', 1.2);
        plot3(ax, trajX{d}(2:end), trajY{d}(2:end), trajH{d}(2:end), '.', ...
            'Color', colors(d,:), 'MarkerSize', 10);
    end

    if nDropsComplete > 0
        plot3(ax, xStart, yStart, thisStartHeightMm, 'kd', ...
            'MarkerSize', 10, 'MarkerFaceColor', 'k');
        text(ax, xStart, yStart, thisStartHeightMm, sprintf('  %s (drop start)', startLabel), ...
            'FontSize', 9, 'VerticalAlignment', 'bottom');
    end

    %% Terminal-velocity height for THIS ball size (own diameter)
    vTermFallMm = NaN;
    vTermPlaneZMm = NaN;
    if showTerminalVelPlane
        try
            vTermFallMm = glycerineMixtureTerminalVelocity(sz, opt.glycerinePercent, ...
                opt.temperatureC, 'fracTarget', opt.terminalVelFracTarget);
            vTermPlaneZMm = thisStartHeightMm - vTermFallMm;
            if vTermPlaneZMm < 0
                warning('CompileTrajectories:terminalVelBelowBase', ...
                    ['%g mm ball reaches %g%% of terminal velocity %.1f mm below ' ...
                     'the %s drop location (%.1f mm) -- that falls %.1f mm below ' ...
                     'this plot''s tank base, so the red plane is clamped to the ' ...
                     'base (z=0) rather than drawn off the bottom of the tank.'], ...
                     sz, opt.terminalVelFracTarget*100, vTermFallMm, ...
                     startLabel, thisStartHeightMm, -vTermPlaneZMm);
                vTermPlaneZMm = 0;
            end
        catch termErr
            warning('CompileTrajectories:terminalVelFailed', ...
                ['Could not compute terminal-velocity height for the %g mm ball ' ...
                 '(%g%% glycerine, %g degC): %s -- skipping the red plane for ' ...
                 'this ball size.'], sz, opt.glycerinePercent, opt.temperatureC, ...
                 termErr.message);
            vTermFallMm = NaN;
            vTermPlaneZMm = NaN;
        end
    end

    %% Hexagonal glass tank, same as CompileHeightHeatmaps.m's 3D plot
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

    %% Red translucent "terminal velocity reached" plane
    if showTerminalVelPlane && ~isnan(vTermPlaneZMm)
        planeColor = [0.85 0.1 0.1];
        fill3(ax, hexX, hexY, vTermPlaneZMm * ones(size(hexX)), planeColor, ...
            'FaceAlpha', 0.55, 'EdgeColor', planeColor, 'LineWidth', 1);
        text(ax, hexX(1), hexY(1), vTermPlaneZMm, sprintf('  terminal velocity reached (%.1f mm below %s)', vTermFallMm, startLabel), ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', planeColor, ...
            'VerticalAlignment', 'bottom');
    end

    %% Stratified-interface plane (optional)
    if opt.showInterfacePlane
        if opt.interfaceHeightMm > TANK_HEIGHT_MM
            warning('Stratified-interface plane at %g mm is above the drawn tank (%g mm) -- skipped.', ...
                opt.interfaceHeightMm, TANK_HEIGHT_MM);
        else
            ifaceColor = [0.95 0.55 0.05];
            fill3(ax, hexX, hexY, opt.interfaceHeightMm * ones(size(hexX)), ifaceColor, ...
                'FaceAlpha', 0.35, 'EdgeColor', ifaceColor, 'LineWidth', 1);
            text(ax, hexX(4), hexY(4), opt.interfaceHeightMm, ...
                sprintf('  stratified interface (%g mm above base)', opt.interfaceHeightMm), ...
                'FontSize', 9, 'FontWeight', 'bold', 'Color', ifaceColor, ...
                'VerticalAlignment', 'bottom');
        end
    end

    xlabel(ax, ['x (mm)' axisSuffix]); ylabel(ax, ['y (mm)' axisSuffix]); zlabel(ax, 'height above base (mm)');
    title(ax, sprintf('%g mm ball: %d / %d drop(s) with all %d height levels, from %s', ...
        sz, nDropsComplete, nDropsTotal, numel(requiredHeights), startLabel));
    view(ax, -35, 25);
    grid(ax, 'on');
    box(ax, 'on');
    if windowed
        axis(ax, 'normal');
        xlim(ax, [xWinLo xWinHi]);
        ylim(ax, [yWinLo yWinHi]);
        zlim(ax, [0 TANK_HEIGHT_MM]);
        pbaspect(ax, [1 1 1.2]);
        txH = findobj(ax, 'Type', 'text');
        for ti = 1:numel(txH)
            tpos = get(txH(ti), 'Position');
            tstr = char(get(txH(ti), 'String'));
            if (tpos(1) < xWinLo || tpos(1) > xWinHi || tpos(2) < yWinLo || tpos(2) > yWinHi) ...
                    && ~contains(tstr, 'synthetic')
                set(txH(ti), 'Position', [xWinLo yWinLo tpos(3)]);
            end
        end
        tHandle = get(ax, 'Title');
        tHandle.String = [tHandle.String sprintf('  (zoomed to +/-%g sigma)', opt.nSigma)];
    else
        axis(ax, 'equal');
        pad = 0.1 * TANK_SIDE_MM;
        xlim(ax, [min(hexX) max(hexX)] + [-pad pad]);
        ylim(ax, [min(hexY) max(hexY)] + [-pad pad]);
        zlim(ax, [0 TANK_HEIGHT_MM]);
    end

    res = struct();
    res.ballDiameterMm = sz;
    res.nDropsTotal     = nDropsTotal;
    res.nDropsComplete  = nDropsComplete;
    res.startCell       = startLabel;
    res.startXMm        = xStart;
    res.startYMm        = yStart;
    res.startHeightMm   = thisStartHeightMm;
    res.terminalVelFallMm = vTermFallMm;
    res.terminalVelPlaneHeightMm = vTermPlaneZMm;
    results(end+1) = res;  %#ok<AGROW>

    if opt.saveFigures
        outPath = fullfile(outDir, sprintf('trajectories_%gmm%s%s.png', sz, fileSuffix, winSuffix));
        drawnow;
        safeExportGraphics(fig, outPath);
        fprintf('  %g mm: trajectory bundle -> %s\n', sz, outPath);
    end
end

end

%% Local functions
function safeExportGraphics(fig, outPath)
% SAFEEXPORTGRAPHICS exportgraphics with a few retries
MAX_ATTEMPTS = 5;  % SAFEEXPORTGRAPHICS exportgraphics with a few retries
RETRY_DELAY_S = 1.5;
lastErr = [];
for attempt = 1:MAX_ATTEMPTS
    try
        exportgraphics(fig, outPath);
        return
    catch lastErr
        if attempt < MAX_ATTEMPTS
            pause(RETRY_DELAY_S);
        end
    end
end
warning('CompileTrajectories:exportFailed', ...
    ['Could not save "%s" after %d attempt(s): %s -- skipping this figure ' ...
     'and continuing with the rest of the run.'], outPath, MAX_ATTEMPTS, lastErr.message);
end

function [col, row] = parseGridCellLabel(label)
% PARSEGRIDCELLLABEL Inverse of mmToGridCell.m's own colLetter()
tok = regexp(label, '^([A-Za-z]+)(\d+)$', 'tokens', 'once');
if isempty(tok)
    error('CompileTrajectories:badCellLabel', ...
        '"%s" is not a valid grid cell label (expected e.g. "Q19").', label);
end
letters = upper(tok{1});
row = str2double(tok{2});
col = 0;
for i = 1:length(letters)
    col = col * 26 + (double(letters(i)) - double('A') + 1);
end
end
