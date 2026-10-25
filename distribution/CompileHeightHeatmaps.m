function results = CompileHeightHeatmaps(sessionFiles, varargin)
% COMPILEHEIGHTHEATMAPS Aggregate SplitAndTrackHeights.m's saved heightResults.mat files into one heatmap

p = inputParser;
addParameter(p, 'saveFigures', true, @islogical);
addParameter(p, 'outDir', '', @ischar);
addParameter(p, 'startCell', 'Q19', @(x) ischar(x) || isstring(x));
addParameter(p, 'startMm', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
addParameter(p, 'sessionIdx', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
addParameter(p, 'sessionOriginsMm', [], @(x) isempty(x) || (isnumeric(x) && ismatrix(x) && size(x, 2) == 2));
addParameter(p, 'sessionNames', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
addParameter(p, 'startHeightMm', [], @(x) isempty(x) || isnumeric(x));
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

SO = normaliseSessionOrigins('CompileHeightHeatmaps', numel(sessionFiles), ...
    opt.sessionIdx, opt.sessionOriginsMm, opt.sessionNames);
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
MIN_HALF_CELLS = 3;  % smallest half-width of the nSigma window, in cells

cfg = rigConfig();
worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
xMin = min(worldXY(:,1)); xMax = max(worldXY(:,1));
yMin = min(worldXY(:,2)); yMax = max(worldXY(:,2));
nCols = max(1, round(cfg.gridCols));
nRows = max(1, round(cfg.gridRows));

%% Load every session, recompute each row's cell against CURRENT calibration
allBallMm = []; allHeightMm = []; allCol = []; allRow = []; allInBounds = []; allSession = {};
nMismatch = 0;

for s = 1:numel(sessionFiles)
    f = sessionFiles{s};
    if exist(f, 'file') ~= 2
        warning('CompileHeightHeatmaps:missingFile', 'Skipping missing file: %s', f);
        continue
    end
    S = load(f, 'heightResults');
    hr = S.heightResults;

    n = numel(hr.xMm);
    oShift = SO.fileOriginMm(s, :);
    for i = 1:n
        [recomputedLabel, col, row, inBounds] = mmToGridCell( ...
            hr.xMm(i), hr.yMm(i), xMin, yMin, xMax, yMax, nCols, nRows);
        if SO.used
            [~, col, row, inBoundsShift] = mmToGridCell( ...
                hr.xMm(i) - oShift(1), hr.yMm(i) - oShift(2), xMin, yMin, xMax, yMax, nCols, nRows);
            inBounds = inBounds && inBoundsShift;
        end

        savedLabel = char(hr.gridCell(i));
        if ~strcmp(recomputedLabel, savedLabel)
            nMismatch = nMismatch + 1;
            warning('CompileHeightHeatmaps:cellMismatch', ...
                ['%s, row %d: saved cell %s does not match recomputed cell %s ' ...
                 'from the CURRENT calibration -- using the recomputed cell.'], ...
                 f, i, savedLabel, recomputedLabel);
        end

        allBallMm(end+1)   = hr.ballDiameterMm;  %#ok<AGROW>
        allHeightMm(end+1) = hr.heightMm(i);  %#ok<AGROW>
        allCol(end+1)      = col;  %#ok<AGROW>
        allRow(end+1)      = row;  %#ok<AGROW>
        allInBounds(end+1) = inBounds;  %#ok<AGROW>
        allSession{end+1}  = f;  %#ok<AGROW>
    end
end

if isempty(allBallMm)
    error('CompileHeightHeatmaps:noData', 'No usable rows found across %d session file(s).', numel(sessionFiles));
end
if nMismatch > 0
    fprintf('%d cell label(s) disagreed with the current calibration -- see warnings above.\n', nMismatch);
end

outDir = opt.outDir;
if isempty(outDir), outDir = pwd; end
if opt.saveFigures && ~exist(outDir, 'dir'), mkdir(outDir); end

%% One heatmap per (ball size, height)
sizes   = unique(allBallMm);
results = struct('ballDiameterMm', {}, 'heightMm', {}, 'counts', {}, 'nDrops', {}, ...
    'nOutOfBounds', {}, 'meanRMm', {}, 'stdRMm', {});

colLabels = arrayfun(@localColLetter, 1:nCols, 'UniformOutput', false);
rowLabels = arrayfun(@(r) sprintf('%d', r), 1:nRows, 'UniformOutput', false);

cellWMm = (xMax - xMin) / nCols;
cellHMm = (yMax - yMin) / nRows;
cellCenterX = xMin + (allCol - 0.5) * cellWMm;
cellCenterY = yMin + (allRow - 0.5) * cellHMm;
allRMm = hypot(cellCenterX, cellCenterY);

if ~isempty(opt.startMm)
    xStart = opt.startMm(1);
    yStart = opt.startMm(2);
    startLabel = sprintf('(%.4g, %.4g)', xStart, yStart);
else
    [startCol, startRow] = parseGridCellLabel(char(opt.startCell));
    if startCol < 1 || startCol > nCols || startRow < 1 || startRow > nRows
        warning('CompileHeightHeatmaps:startCellOutside', ...
            ['startCell "%s" falls outside the current %d x %d grid -- the ' ...
             'synthetic start point will still be plotted at its computed ' ...
             'position, just outside the calibrated square.'], ...
            char(opt.startCell), nCols, nRows);
    end
    xStart = xMin + (startCol - 0.5) * cellWMm;
    yStart = yMin + (startRow - 0.5) * cellHMm;
    startLabel = char(opt.startCell);
end

for k = 1:numel(sizes)
    sz = sizes(k);
    heights = unique(allHeightMm(allBallMm == sz));
    heights = sort(heights, 'descend');

    % Optional nSigma window, COMMON to every height of this ball size
    colRange = 1:nCols;  rowRange = 1:nRows;  windowed = false;
    if ~isempty(opt.nSigma)
        wLoC = inf; wHiC = -inf; wLoR = inf; wHiR = -inf;
        for hw = heights(:)'
            mw = (allBallMm == sz) & (allHeightMm == hw) & allInBounds;
            if nnz(mw) < 1, continue, end
            mc = mean(allCol(mw));  hc = max(opt.nSigma * std(allCol(mw)), MIN_HALF_CELLS);
            mr = mean(allRow(mw));  hr_ = max(opt.nSigma * std(allRow(mw)), MIN_HALF_CELLS);
            wLoC = min(wLoC, mc - hc);  wHiC = max(wHiC, mc + hc);
            wLoR = min(wLoR, mr - hr_); wHiR = max(wHiR, mr + hr_);
        end
        if isfinite(wLoC)
            colRange = max(1, floor(wLoC)):min(nCols, ceil(wHiC));
            rowRange = max(1, floor(wLoR)):min(nRows, ceil(wHiR));
            windowed = numel(colRange) >= 2 && numel(rowRange) >= 2;
            if ~windowed
                colRange = 1:nCols;  rowRange = 1:nRows;
            else
                fprintf('  %g mm ball: +/-%g sigma window = columns %d-%d, rows %d-%d (%d x %d cells)\n', ...
                    sz, opt.nSigma, colRange(1), colRange(end), rowRange(1), rowRange(end), ...
                    numel(colRange), numel(rowRange));
            end
        end
    end

    summaryHeights = []; summaryMeanR = []; summaryStdR = []; summaryN = [];

    for h = heights(:)'
        mask = (allBallMm == sz) & (allHeightMm == h) & allInBounds;

        counts = zeros(nRows, nCols);
        for i = find(mask)
            counts(allRow(i), allCol(i)) = counts(allRow(i), allCol(i)) + 1;
        end

        nInGroup  = nnz((allBallMm == sz) & (allHeightMm == h));
        nOobGroup = nnz((allBallMm == sz) & (allHeightMm == h) & ~allInBounds);
        nSessions = numel(unique(allSession((allBallMm == sz) & (allHeightMm == h))));

        fig = figure('Name', sprintf('Height heatmap - %g mm ball @ %g mm', sz, h));
        hm = heatmap(colLabels(colRange), rowLabels(rowRange), counts(rowRange, colRange));
        hm.Title = sprintf('%g mm ball @ %g mm height -- %d drop(s) across %d session(s)%s', ...
            sz, h, nnz(mask), nSessions, ...
            ternary(nOobGroup > 0, sprintf(' (%d excluded, out of bounds)', nOobGroup), ''));
        if SO.used
            hm.XLabel = 'column (grid centred on the dropper)'; hm.YLabel = 'row';
        else
            hm.XLabel = 'column'; hm.YLabel = 'row';
        end
        hm.ColorbarVisible = 'on';
        hm.Colormap = mutedHeatColormap(256);
        hm.FontSize = 7;
        if windowed
            hm.FontSize = 11;  % far fewer cells, so there is room for larger numbers
            hm.XLabel = [hm.XLabel sprintf('   (zoomed to +/-%g sigma window)', opt.nSigma)];
        end

        res = struct();
        res.ballDiameterMm = sz;
        res.heightMm       = h;
        res.counts         = counts;
        res.nDrops         = nInGroup;
        res.nOutOfBounds   = nOobGroup;
        res.meanRMm        = mean(allRMm(mask));
        res.stdRMm         = std(allRMm(mask));
        results(end+1) = res;  %#ok<AGROW>

        summaryHeights(end+1) = h;  %#ok<AGROW>
        summaryMeanR(end+1)   = res.meanRMm;  %#ok<AGROW>
        summaryStdR(end+1)    = res.stdRMm;  %#ok<AGROW>
        summaryN(end+1)       = nnz(mask);  %#ok<AGROW>

        if opt.saveFigures
            outPath = fullfile(outDir, sprintf('heightmap_%gmm_h%gmm%s%s.png', sz, h, fileSuffix, winSuffix));
            drawnow;
            safeExportGraphics(fig, outPath);
            fprintf('  %g mm @ %g mm: %d in-grid drop(s) (%d excluded) -> %s\n', ...
                sz, h, nnz(mask), nOobGroup, outPath);
        end
    end

    figS = figure('Name', sprintf('Spread vs height - %g mm ball', sz));
    errorbar(summaryHeights, summaryMeanR, summaryStdR, '-o', 'LineWidth', 1.5);
    set(gca, 'XDir', 'reverse');
    xlabel('Height above base (mm)');
    if SO.used
        ylabel('Radial distance from dropper (mm)');
    else
        ylabel('Radial distance from centre (mm)');
    end
    title(sprintf('%g mm ball: mean radial position \\pm std vs height (n per point shown below)', sz));
    grid on;
    for i = 1:numel(summaryHeights)
        text(summaryHeights(i), summaryMeanR(i), sprintf('  n=%d', summaryN(i)), ...
            'FontSize', 8, 'VerticalAlignment', 'bottom');
    end

    if opt.saveFigures
        outPath = fullfile(outDir, sprintf('spread_vs_height_%gmm%s.png', sz, fileSuffix));
        drawnow;
        safeExportGraphics(figS, outPath);
        fprintf('  %g mm: spread-vs-height summary -> %s\n', sz, outPath);
    end

    szMask     = [results.ballDiameterMm] == sz;
    szHeights  = [results(szMask).heightMm];
    szCountsC  = {results(szMask).counts};
    [~, hOrd]  = sort(szHeights, 'descend');

    if isempty(opt.startHeightMm)
        uniqueHeights = sort(unique(szHeights), 'descend');
        if numel(uniqueHeights) >= 2
            spacingMm = median(diff(sort(uniqueHeights)));
        else
            spacingMm = 0.2 * max(uniqueHeights, 1);
        end
        thisStartHeightMm = max(szHeights) + spacingMm;
    else
        thisStartHeightMm = opt.startHeightMm;
    end

    fig3D = figure('Name', sprintf('3D stacked height heatmaps - %g mm ball', sz), 'Color', 'w');
    ax3D = axes(fig3D);
    hold(ax3D, 'on');

    xCentersMm = xMin + ((1:nCols) - 0.5) * cellWMm;
    yCentersMm = yMin + ((1:nRows) - 0.5) * cellHMm;
    [Xg, Yg] = meshgrid(xCentersMm(colRange), yCentersMm(rowRange));
    maxCount = max(1, max(cellfun(@(c) max(max(c(rowRange, colRange))), szCountsC)));

    xEdgeLo = xMin + (colRange(1) - 1) * cellWMm;   xEdgeHi = xMin + colRange(end) * cellWMm;
    yEdgeLo = yMin + (rowRange(1) - 1) * cellHMm;   yEdgeHi = yMin + rowRange(end) * cellHMm;
    layerBorderX = [xEdgeLo xEdgeHi xEdgeHi xEdgeLo xEdgeLo];
    layerBorderY = [yEdgeLo yEdgeLo yEdgeHi yEdgeHi yEdgeLo];

    for hOrdIdx = hOrd
        h = szHeights(hOrdIdx);
        counts = szCountsC{hOrdIdx}(rowRange, colRange);
        Zg = h * ones(size(counts));
        surf(ax3D, Xg, Yg, Zg, counts, 'FaceColor', 'flat', ...
            'FaceAlpha', 1, 'EdgeColor', 'none', 'LineWidth', 0.25);
        plot3(ax3D, layerBorderX, layerBorderY, h * ones(1, 5), ...
            'Color', 'k', 'LineWidth', 1.25);
    end

    plot3(ax3D, xStart, yStart, thisStartHeightMm, 'kd', ...
        'MarkerSize', 10, 'MarkerFaceColor', 'k');
    text(ax3D, xStart, yStart, thisStartHeightMm, sprintf('  %s (synthetic start)', startLabel), ...
        'FontSize', 9, 'VerticalAlignment', 'bottom');

    %% Hexagonal tank wireframe, for physical context around the layers
    TANK_FIT_SCALE = 0.45;  % Purely illustrative
    gridDiagMm     = hypot(nCols * cellWMm, nRows * cellHMm);
    TANK_SIDE_MM   = 200;  % TANK_FIT_SCALE * gridDiagMm / 2
    TANK_HEIGHT_MM = max(400, thisStartHeightMm + 20);

    tankCenterX = (xMin + xMax) / 2 - SO.meanOriginMm(1);
    tankCenterY = (yMin + yMax) / 2 - SO.meanOriginMm(2);
    hexAngles   = deg2rad(30 + (0:6)*60);
    hexX = tankCenterX + TANK_SIDE_MM * cos(hexAngles);
    hexY = tankCenterY + TANK_SIDE_MM * sin(hexAngles);

    tankColor = [0.53 0.81 0.92];  % light blue

    glassFaceAlpha = 0.12;
    for vI = 1:6
        vJ = vI + 1;  % hexX/hexY already include the closing 7th point == 1st
        faceX = [hexX(vI) hexX(vJ) hexX(vJ) hexX(vI)];
        faceY = [hexY(vI) hexY(vJ) hexY(vJ) hexY(vI)];
        faceZ = [0 0 TANK_HEIGHT_MM TANK_HEIGHT_MM];
        fill3(ax3D, faceX, faceY, faceZ, tankColor, ...
            'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);
    end
    fill3(ax3D, hexX, hexY, zeros(size(hexX)), tankColor, ...
        'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);
    fill3(ax3D, hexX, hexY, TANK_HEIGHT_MM * ones(size(hexX)), tankColor, ...
        'FaceAlpha', glassFaceAlpha, 'EdgeColor', tankColor, 'LineWidth', 1.5);

    %% Red translucent "terminal velocity reached" plane
    if showTerminalVelPlane
        try
            vTermFallMm = glycerineMixtureTerminalVelocity(sz, opt.glycerinePercent, ...
                opt.temperatureC, 'fracTarget', opt.terminalVelFracTarget);
            vTermPlaneZMm = thisStartHeightMm - vTermFallMm;
            if vTermPlaneZMm < 0
                warning('CompileHeightHeatmaps:terminalVelBelowBase', ...
                    ['%g mm ball reaches %g%% of terminal velocity %.1f mm below ' ...
                     'the %s drop location (%.1f mm) -- that falls %.1f mm below ' ...
                     'this plot''s tank base, so the red plane is clamped to the ' ...
                     'base (z=0) rather than drawn off the bottom of the tank.'], ...
                     sz, opt.terminalVelFracTarget*100, vTermFallMm, ...
                     startLabel, thisStartHeightMm, -vTermPlaneZMm);
                vTermPlaneZMm = 0;
            end
            planeColor = [0.85 0.1 0.1];
            fill3(ax3D, hexX, hexY, vTermPlaneZMm * ones(size(hexX)), planeColor, ...
                'FaceAlpha', 0.55, 'EdgeColor', planeColor, 'LineWidth', 1);
            text(ax3D, hexX(1), hexY(1), vTermPlaneZMm, ...
                sprintf('  terminal velocity reached (%.1f mm below %s)', vTermFallMm, startLabel), ...
                'FontSize', 9, 'FontWeight', 'bold', 'Color', planeColor, ...
                'VerticalAlignment', 'bottom');
        catch termErr
            warning('CompileHeightHeatmaps:terminalVelFailed', ...
                ['Could not compute terminal-velocity height for the %g mm ball ' ...
                 '(%g%% glycerine, %g degC): %s -- skipping the red plane for ' ...
                 'this ball size.'], sz, opt.glycerinePercent, opt.temperatureC, ...
                 termErr.message);
        end
    end

    %% Stratified-interface plane (optional)
    if opt.showInterfacePlane
        if opt.interfaceHeightMm > TANK_HEIGHT_MM
            warning('Stratified-interface plane at %g mm is above the drawn tank (%g mm) -- skipped.', ...
                opt.interfaceHeightMm, TANK_HEIGHT_MM);
        else
            ifaceColor = [0.95 0.55 0.05];
            fill3(ax3D, hexX, hexY, opt.interfaceHeightMm * ones(size(hexX)), ifaceColor, ...
                'FaceAlpha', 0.35, 'EdgeColor', ifaceColor, 'LineWidth', 1);
            text(ax3D, hexX(4), hexY(4), opt.interfaceHeightMm, ...
                sprintf('  stratified interface (%g mm above base)', opt.interfaceHeightMm), ...
                'FontSize', 9, 'FontWeight', 'bold', 'Color', ifaceColor, ...
                'VerticalAlignment', 'bottom');
        end
    end

    colormap(ax3D, mutedHeatColormap(256));
    cb = colorbar(ax3D);
    cb.Label.String = 'drop count';
    caxis(ax3D, [0 maxCount]);  %#ok<CAXIS>
    xlabel(ax3D, ['x (mm)' axisSuffix]); ylabel(ax3D, ['y (mm)' axisSuffix]); zlabel(ax3D, 'height above base (mm)');
    if windowed
        title(ax3D, sprintf('%g mm ball: landing distribution layered by drop height (zoomed to +/-%g sigma)', sz, opt.nSigma));
    else
        title(ax3D, sprintf('%g mm ball: landing distribution layered by drop height', sz));
    end
    view(ax3D, -35, 25);
    grid(ax3D, 'on');
    box(ax3D, 'on');
    if windowed
        axis(ax3D, 'normal');
        xlim(ax3D, [xEdgeLo xEdgeHi]);
        ylim(ax3D, [yEdgeLo yEdgeHi]);
        zlim(ax3D, [0 TANK_HEIGHT_MM]);
        pbaspect(ax3D, [1 1 1.2]);
        txH = findobj(ax3D, 'Type', 'text');
        for ti = 1:numel(txH)
            tpos = get(txH(ti), 'Position');
            tstr = char(get(txH(ti), 'String'));
            if (tpos(1) < xEdgeLo || tpos(1) > xEdgeHi || tpos(2) < yEdgeLo || tpos(2) > yEdgeHi) ...
                    && ~contains(tstr, 'synthetic')
                set(txH(ti), 'Position', [xEdgeLo yEdgeLo tpos(3)]);
            end
        end
    else
        axis(ax3D, 'equal');
        pad = 0.1 * TANK_SIDE_MM;
        xlim(ax3D, [min(hexX) max(hexX)] + [-pad pad]);
        ylim(ax3D, [min(hexY) max(hexY)] + [-pad pad]);
        zlim(ax3D, [0 TANK_HEIGHT_MM]);
    end

    if opt.saveFigures
        outPath = fullfile(outDir, sprintf('heightmap_3d_stacked_%gmm%s%s.png', sz, fileSuffix, winSuffix));
        drawnow;
        safeExportGraphics(fig3D, outPath);
        fprintf('  %g mm: 3D stacked height heatmap -> %s\n', sz, outPath);
    end
end

end

%% Local functions (duplicated from CompileHeatmap.m
function [col, row] = parseGridCellLabel(label)
% PARSEGRIDCELLLABEL Inverse of mmToGridCell.m's own colLetter()
tok = regexp(label, '^([A-Za-z]+)(\d+)$', 'tokens', 'once');
if isempty(tok)
    error('CompileHeightHeatmaps:badCellLabel', ...
        '"%s" is not a valid grid cell label (expected e.g. "Q19").', label);
end
letters = upper(tok{1});
row = str2double(tok{2});
col = 0;
for i = 1:length(letters)
    col = col * 26 + (double(letters(i)) - double('A') + 1);
end
end

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
warning('CompileHeightHeatmaps:exportFailed', ...
    ['Could not save "%s" after %d attempt(s): %s -- skipping this figure ' ...
     'and continuing with the rest of the run.'], outPath, MAX_ATTEMPTS, lastErr.message);
end

function cmap = mutedHeatColormap(n)
% "Traffic-light" heatmap colour scheme
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

function s = localColLetter(col)
s = '';
n = col;
while n > 0
    r = mod(n-1, 26);
    s = [char('A'+r) s];  %#ok<AGROW>
    n = floor((n-1)/26);
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
