function results = GaussianLayers3D(sessionFiles, varargin)
% GAUSSIANLAYERS3D One 3D Gaussian-distribution figure PER (ball size, height) layer

p = inputParser;
addParameter(p, 'saveFigures', true, @islogical);
addParameter(p, 'outDir', '', @ischar);
addParameter(p, 'nSigma', 4, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'yWall', 'max', @(x) any(strcmpi(x, {'max', 'min'})));
addParameter(p, 'gridN', 45, @(x) isnumeric(x) && isscalar(x) && x >= 10);
addParameter(p, 'showPoints', true, @islogical);
addParameter(p, 'showEmpirical', true, @islogical);
addParameter(p, 'minDrops', 3, @(x) isnumeric(x) && isscalar(x) && x >= 3);
addParameter(p, 'dropDuplicates', false, @islogical);
addParameter(p, 'requireInBounds', true, @islogical);
addParameter(p, 'originCell', '', @(x) ischar(x) || isstring(x) || iscellstr(x));
addParameter(p, 'originMm', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
addParameter(p, 'sessionIdx', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
addParameter(p, 'sessionOriginsMm', [], @(x) isempty(x) || (isnumeric(x) && ismatrix(x) && size(x, 2) == 2));
addParameter(p, 'sessionNames', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
parse(p, varargin{:});
opt = p.Results;
originCells = cellstr(string(opt.originCell));
originCells = upper(strtrim(originCells(:)'));
originCells = originCells(~cellfun(@isempty, originCells));
opt.originCell = strjoin(originCells, '+');
if isempty(opt.originCell), opt.originCell = ''; end

useOriginMm = ~isempty(opt.originMm);
if useOriginMm
    opt.originMm = double(opt.originMm(:)');
    if ~isempty(opt.originCell)
        warning('GaussianLayers3D:originBoth', ...
            'Both originMm and originCell were given -- using originMm (%.2f, %.2f) mm.', ...
            opt.originMm(1), opt.originMm(2));
    end
    opt.originCell = sprintf('(%.2f, %.2f)', opt.originMm(1), opt.originMm(2));
end

if ischar(sessionFiles) || isstring(sessionFiles)
    sessionFiles = {char(sessionFiles)};
end

useSessions = ~isempty(opt.sessionOriginsMm);
sessOrigins = [];
sessNames = {};
if useSessions
    sessOrigins = double(opt.sessionOriginsMm);
    nSess = size(sessOrigins, 1);
    if isempty(opt.sessionIdx) || numel(opt.sessionIdx) ~= numel(sessionFiles)
        error('GaussianLayers3D:sessionIdx', ...
            ['''sessionIdx'' must have one entry per file (%d files given, %d entries): ' ...
             'e.g. [1 1 1 2 2] = the first three files are session 1, the next two session 2.'], ...
            numel(sessionFiles), numel(opt.sessionIdx));
    end
    sessIdxVec = double(opt.sessionIdx(:)');
    if any(sessIdxVec < 1) || any(sessIdxVec > nSess) || any(sessIdxVec ~= round(sessIdxVec))
        error('GaussianLayers3D:sessionIdxRange', ...
            '''sessionIdx'' entries must be whole numbers from 1 to %d (one row of sessionOriginsMm per session).', nSess);
    end
    if isempty(opt.sessionNames)
        sessNames = arrayfun(@(k) sprintf('Session %d', k), 1:nSess, 'UniformOutput', false);
    else
        sessNames = cellstr(string(opt.sessionNames));
        sessNames = sessNames(:)';
        if numel(sessNames) ~= nSess
            error('GaussianLayers3D:sessionNames', ...
                '''sessionNames'' needs %d entries (one per row of sessionOriginsMm), got %d.', nSess, numel(sessNames));
        end
    end
    if useOriginMm || ~isempty(opt.originCell)
        warning('GaussianLayers3D:originIgnored', ...
            ['originCell / originMm are ignored while sessionOriginsMm is in use -- ' ...
             'each session is shifted to its own origin instead.']);
    end
    useOriginMm = false;
    opt.originCell = 'drop point';  % label only: "x (mm) from drop point"
    for k = 1:nSess
        if any(~isfinite(sessOrigins(k, :)))
            warning('GaussianLayers3D:sessionNoOrigin', ...
                '%s has no origin (NaN) -- its positions are left UNSHIFTED (raw rig mm).', sessNames{k});
        end
    end
end

%% Load every session file (real mm positions only -- no grid involved)
allBall = []; allDrop = []; allH = []; allX = []; allY = []; allSess = [];
nOutOfBounds = 0;
nRowsPerSess = zeros(1, max(1, numel(sessNames)));
nFilesPerSess = zeros(1, max(1, numel(sessNames)));

for s = 1:numel(sessionFiles)
    f = sessionFiles{s};
    if exist(f, 'file') ~= 2
        warning('GaussianLayers3D:missingFile', 'Skipping missing file: %s', f);
        continue
    end
    S = load(f, 'heightResults');
    hr = S.heightResults;
    n = numel(hr.xMm);
    keepRow = true(1, n);
    if opt.requireInBounds && isfield(hr, 'inBounds') && numel(hr.inBounds) == n
        keepRow = logical(hr.inBounds(:))';
        for bad = find(~keepRow)
            [~, fname] = fileparts(f);
            fprintf(['  Skipping out-of-bounds detection: %s, drop %g, %g mm ' ...
                     '(x = %.1f, y = %.1f mm) -- tracker likely lost the ball.\n'], ...
                fname, hr.dropIndex(bad), hr.heightMm(bad), hr.xMm(bad), hr.yMm(bad));
        end
        nOutOfBounds = nOutOfBounds + nnz(~keepRow);
    end
    allBall = [allBall, repmat(hr.ballDiameterMm, 1, nnz(keepRow))];  %#ok<AGROW>
    dI = hr.dropIndex(:)';  hM = hr.heightMm(:)';
    xM = hr.xMm(:)';        yM = hr.yMm(:)';
    sIdx = 1;
    if useSessions
        sIdx = sessIdxVec(s);
        o = sessOrigins(sIdx, :);
        if all(isfinite(o))
            xM = xM - o(1);
            yM = yM - o(2);
        end
        nRowsPerSess(sIdx)  = nRowsPerSess(sIdx)  + nnz(keepRow);
        nFilesPerSess(sIdx) = nFilesPerSess(sIdx) + 1;
    end
    allDrop = [allDrop, dI(keepRow)];  %#ok<AGROW>
    allH    = [allH,    hM(keepRow)];  %#ok<AGROW>
    allX    = [allX,    xM(keepRow)];  %#ok<AGROW>
    allY    = [allY,    yM(keepRow)];  %#ok<AGROW>
    allSess = [allSess, repmat(sIdx, 1, nnz(keepRow))];  %#ok<AGROW>
end
if useSessions
    for k = 1:numel(sessNames)
        if all(isfinite(sessOrigins(k, :)))
            fprintf('  %s: %d file(s), %d row(s), origin (%.3f, %.3f) mm subtracted.\n', ...
                sessNames{k}, nFilesPerSess(k), nRowsPerSess(k), sessOrigins(k, 1), sessOrigins(k, 2));
        else
            fprintf('  %s: %d file(s), %d row(s), NOT shifted (no origin given).\n', ...
                sessNames{k}, nFilesPerSess(k), nRowsPerSess(k));
        end
    end
end
if nOutOfBounds > 0
    fprintf('Ignored %d out-of-bounds row(s) in total (set ''requireInBounds'', false to keep them).\n', nOutOfBounds);
end

if isempty(allBall)
    error('GaussianLayers3D:noData', 'No usable rows found across %d session file(s).', numel(sessionFiles));
end

ok = ~isnan(allX) & ~isnan(allY);
allBall = allBall(ok); allDrop = allDrop(ok); allH = allH(ok);
allX = allX(ok); allY = allY(ok); allSess = allSess(ok);

originXMm = 0; originYMm = 0;
if useOriginMm
    originXMm = opt.originMm(1);
    originYMm = opt.originMm(2);
    fprintf('Origin shifted to (%.2f, %.2f) mm in rig coordinates (given as originMm).\n', ...
        originXMm, originYMm);
    allX = allX - originXMm;
    allY = allY - originYMm;
elseif ~useSessions && ~isempty(opt.originCell)
    cfg = rigConfig();
    worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
    gxMin = min(worldXY(:,1)); gxMax = max(worldXY(:,1));
    gyMin = min(worldXY(:,2)); gyMax = max(worldXY(:,2));
    gCols = max(1, round(cfg.gridCols));
    gRows = max(1, round(cfg.gridRows));
    cellX = zeros(1, numel(originCells));
    cellY = zeros(1, numel(originCells));
    for ci = 1:numel(originCells)
        [oCol, oRow] = parseGridCellLabel(originCells{ci});
        if oCol < 1 || oCol > gCols || oRow < 1 || oRow > gRows
            error('GaussianLayers3D:originOutside', ...
                'originCell "%s" is outside the %d x %d grid (columns A..%d, rows 1..%d).', ...
                originCells{ci}, gCols, gRows, gCols, gRows);
        end
        cellX(ci) = gxMin + (oCol - 0.5) * (gxMax - gxMin) / gCols;
        cellY(ci) = gyMin + (oRow - 0.5) * (gyMax - gyMin) / gRows;
    end
    originXMm = mean(cellX);
    originYMm = mean(cellY);
    if numel(originCells) == 1
        fprintf('Origin shifted to the centre of cell %s = (%.2f, %.2f) mm in rig coordinates.\n', ...
            originCells{1}, originXMm, originYMm);
    else
        fprintf('Origin shifted to the midpoint of cells %s = (%.2f, %.2f) mm in rig coordinates.\n', ...
            strjoin(originCells, ', '), originXMm, originYMm);
    end
    allX = allX - originXMm;
    allY = allY - originYMm;
end

if opt.dropDuplicates
    M = [allBall(:), allDrop(:), allH(:), allX(:), allY(:)];
    [~, keep] = unique(M, 'rows', 'stable');
    keep = sort(keep(:))';
    nDup = size(M, 1) - numel(keep);
    if nDup > 0
        fprintf(['Removed %d exact duplicate row(s) (the same drop saved in more ' ...
                 'than one session file) so they are not counted twice.\n'], nDup);
    end
    allBall = allBall(keep); allDrop = allDrop(keep); allH = allH(keep);
    allX = allX(keep); allY = allY(keep); allSess = allSess(keep);
end

outDir = opt.outDir;
if isempty(outDir), outDir = pwd; end
if opt.saveFigures && ~exist(outDir, 'dir'), mkdir(outDir); end

%% One figure per (ball size, height)
results = struct('ballDiameterMm', {}, 'heightMm', {}, 'nDrops', {}, ...
    'muXMm', {}, 'muYMm', {}, 'sigmaXMm', {}, 'sigmaYMm', {}, 'rho', {}, ...
    'originCell', {}, 'originXMm', {}, 'originYMm', {}, 'nPerSession', {});

sizes = unique(allBall);
for k = 1:numel(sizes)
    sz = sizes(k);
    heights = sort(unique(allH(allBall == sz)), 'descend');
    nHt = numel(heights);

    % pass 1: fit every layer, so the axis window can be shared
    nD = zeros(1, nHt); muX = nan(1, nHt); muY = nan(1, nHt);
    C11 = nan(1, nHt); C12 = nan(1, nHt); C22 = nan(1, nHt);
    for hi = 1:nHt
        m = (allBall == sz) & (allH == heights(hi));
        x = allX(m); y = allY(m);
        nD(hi) = numel(x);
        if nD(hi) < opt.minDrops
            warning('GaussianLayers3D:tooFewDrops', ...
                '%g mm @ %g mm: only %d drop(s) (need %d) -- skipping this layer.', ...
                sz, heights(hi), nD(hi), opt.minDrops);
            continue
        end
        C = cov([x(:), y(:)]);
        if C(1,1) <= 0 || C(2,2) <= 0 || det(C) <= eps
            warning('GaussianLayers3D:degenerate', ...
                '%g mm @ %g mm: positions have no spread (singular covariance) -- skipping this layer.', ...
                sz, heights(hi));
            continue
        end
        muX(hi) = mean(x); muY(hi) = mean(y);
        C11(hi) = C(1,1); C12(hi) = C(1,2); C22(hi) = C(2,2);
    end

    valid = ~isnan(muX);
    if ~any(valid)
        continue
    end
    sx = sqrt(C11(valid)); sy = sqrt(C22(valid));
    xLo = min(muX(valid) - opt.nSigma * sx);  xHi = max(muX(valid) + opt.nSigma * sx);
    yLo = min(muY(valid) - opt.nSigma * sy);  yHi = max(muY(valid) + opt.nSigma * sy);
    half = max(xHi - xLo, yHi - yLo) / 2;
    cx = (xLo + xHi) / 2;  cy = (yLo + yHi) / 2;
    xLo = cx - half; xHi = cx + half;
    yLo = cy - half; yHi = cy + half;

    xv = linspace(xLo, xHi, opt.gridN);
    yv = linspace(yLo, yHi, opt.gridN);
    [Xg, Yg] = meshgrid(xv, yv);
    xf = linspace(xLo, xHi, 240);
    yf = linspace(yLo, yHi, 240);

    % pass 2: one figure per valid layer
    for hi = 1:nHt
        if isnan(muX(hi)), continue; end
        h  = heights(hi);
        m  = (allBall == sz) & (allH == h);
        x  = allX(m); y = allY(m);
        sessOfRow = allSess(m);
        mx = muX(hi); my = muY(hi);
        c11 = C11(hi); c12 = C12(hi); c22 = C22(hi);
        detC = c11 * c22 - c12^2;
        i11 = c22 / detC; i22 = c11 / detC; i12 = -c12 / detC;
        sigX = sqrt(c11); sigY = sqrt(c22);
        rho  = c12 / (sigX * sigY);

        bell = @(xx, yy) exp(-0.5 * (i11 * (xx - mx).^2 + ...
                                      2 * i12 * (xx - mx) .* (yy - my) + ...
                                      i22 * (yy - my).^2));
        Z = bell(Xg, Yg);

        fig = figure('Name', sprintf('3D Gaussian - %g mm ball @ %g mm', sz, h), 'Color', 'w');
        ax = axes(fig);
        hold(ax, 'on');

        surf(ax, Xg, Yg, Z, Z, 'FaceColor', 'interp', ...
            'EdgeColor', [0.2 0.2 0.2], 'EdgeAlpha', 0.35, 'LineWidth', 0.4);

        gx = exp(-(xf - mx).^2 / (2 * c11));
        gy = exp(-(yf - my).^2 / (2 * c22));
        colX = [0.00 0.45 0.74];
        colY = [0.10 0.55 0.25];
        hX = plot3(ax, xf, yHi * ones(size(xf)), gx, '-', 'Color', colX, 'LineWidth', 3);
        if strcmpi(opt.yWall, 'max'), xWall = xHi; else, xWall = xLo; end
        hY = plot3(ax, xWall * ones(size(yf)), yf, gy, '-', 'Color', colY, 'LineWidth', 3);
        legH = [hX, hY];
        legS = {sprintf('x distribution (\\sigma_x = %.2f mm)', sigX), ...
                sprintf('y distribution (\\sigma_y = %.2f mm)', sigY)};

        if opt.showEmpirical
            wX = 3.49 * sigX * numel(x)^(-1/3);
            wY = 3.49 * sigY * numel(y)^(-1/3);
            eX = xLo : wX : (xHi + wX);
            eY = yLo : wY : (yHi + wY);
            dX = min(histcounts(x, eX) / (numel(x) * wX) * sqrt(2 * pi * c11), 1.05);
            dY = min(histcounts(y, eY) / (numel(y) * wY) * sqrt(2 * pi * c22), 1.05);
            xs = reshape([eX(1:end-1); eX(2:end)], 1, []);  hxs = reshape([dX; dX], 1, []);
            ys = reshape([eY(1:end-1); eY(2:end)], 1, []);  hys = reshape([dY; dY], 1, []);
            hE = plot3(ax, xs, yHi * ones(size(xs)), hxs, '-', 'Color', [0.50 0.50 0.50], 'LineWidth', 1);
            plot3(ax, xWall * ones(size(ys)), ys, hys, '-', 'Color', [0.50 0.50 0.50], 'LineWidth', 1);
            legH(end+1) = hE;  %#ok<AGROW>
            legS{end+1} = 'measured (histogram)';  %#ok<AGROW>
        end

        if opt.showPoints
            if useSessions && numel(sessNames) > 1
                ptCols = [0.00 0.00 0.00; 0.55 0.10 0.70; 0.00 0.50 0.50; 0.30 0.30 0.30; 0.85 0.45 0.00];
                ptMark = {'o', 's', '^', 'd', 'v'};
                for sk = 1:numel(sessNames)
                    sm = (sessOfRow == sk);
                    if ~any(sm), continue; end
                    ci = mod(sk - 1, size(ptCols, 1)) + 1;
                    hP = plot3(ax, x(sm), y(sm), bell(x(sm), y(sm)) + 0.015, ptMark{ci}, ...
                        'MarkerSize', 5, 'LineStyle', 'none', 'Color', ptCols(ci, :), ...
                        'MarkerFaceColor', ptCols(ci, :));
                    legH(end+1) = hP;  %#ok<AGROW>
                    legS{end+1} = sprintf('%s (n = %d)', sessNames{sk}, nnz(sm));  %#ok<AGROW>
                end
            else
                plot3(ax, x, y, bell(x, y) + 0.015, 'k.', 'MarkerSize', 9);
            end
        end

        colormap(ax, redOrangeYellowWhite(256));
        cb = colorbar(ax);
        cb.Label.String = 'relative density (peak = 1)';
        caxis(ax, [0 1]);  %#ok<CAXIS>

        if isempty(opt.originCell)
            xlabel(ax, 'x (mm)'); ylabel(ax, 'y (mm)');
            centreWhere = '';
        else
            if useSessions
                originShown = 'the dropper';
            else
                originShown = upper(opt.originCell);
            end
            xlabel(ax, sprintf('x (mm) from %s', originShown));
            ylabel(ax, sprintf('y (mm) from %s', originShown));
            centreWhere = sprintf(' from %s', originShown);
        end
        zlabel(ax, 'relative density');
        title(ax, {sprintf('%g mm ball @ %g mm height -- %d drop(s)', sz, h, numel(x)), ...
                   sprintf('centre (%.2f, %.2f) mm%s,  \\sigma_x = %.2f mm,  \\sigma_y = %.2f mm,  \\rho = %.2f', ...
                           mx, my, centreWhere, sigX, sigY, rho)}, 'FontWeight', 'normal');
        legend(ax, legH, legS, 'Location', 'northeast');
        view(ax, -37.5, 30);
        grid(ax, 'on');
        box(ax, 'on');
        xlim(ax, [xLo xHi]); ylim(ax, [yLo yHi]); zlim(ax, [0 1.05]);
        pbaspect(ax, [1 1 0.65]);

        res = struct();
        res.ballDiameterMm = sz;
        res.heightMm       = h;
        res.nDrops         = numel(x);
        res.muXMm          = mx;
        res.muYMm          = my;
        res.sigmaXMm       = sigX;
        res.sigmaYMm       = sigY;
        res.rho            = rho;
        res.originCell     = upper(opt.originCell);
        res.originXMm      = originXMm;
        res.originYMm      = originYMm;
        if useSessions
            res.nPerSession = arrayfun(@(sk) nnz(sessOfRow == sk), 1:numel(sessNames));
        else
            res.nPerSession = [];
        end
        results(end+1) = res;  %#ok<AGROW>

        if useSessions && numel(sessNames) > 1
            fprintf('  %g mm @ %g mm, per-session centre after shifting:', sz, h);
            for sk = 1:numel(sessNames)
                sm = (sessOfRow == sk);
                if nnz(sm) == 0, continue; end
                fprintf('  %s (%.2f, %.2f) n=%d;', sessNames{sk}, mean(x(sm)), mean(y(sm)), nnz(sm));
            end
            fprintf('  pooled (%.2f, %.2f)\n', mx, my);
        end

        if opt.saveFigures
            if useSessions
                outName = sprintf('gaussian3d_%gmm_h%gmm_combined.png', sz, h);
            elseif isempty(opt.originCell)
                outName = sprintf('gaussian3d_%gmm_h%gmm.png', sz, h);
            else
                originTag = regexprep(upper(opt.originCell), '[(), ]+', '_');
                originTag = regexprep(originTag, '^_+|_+$', '');
                outName = sprintf('gaussian3d_%gmm_h%gmm_origin%s.png', sz, h, originTag);
            end
            outPath = fullfile(outDir, outName);
            drawnow;
            safeExportGraphics(fig, outPath);
            fprintf('  %g mm @ %g mm: n = %d, sigma = (%.2f, %.2f) mm -> %s\n', ...
                sz, h, numel(x), sigX, sigY, outPath);
        end
    end
end

end

%% Local functions
function cmap = redOrangeYellowWhite(n)
% White -> yellow -> orange -> red, low to high density (the bell's tails are white, its peak is red)
if nargin < 1, n = 256; end
stops = [0.00  1.00 1.00 1.00  % white
         0.18  1.00 0.92 0.25
         0.40  1.00 0.65 0.10
         0.65  0.95 0.35 0.05
         1.00  0.72 0.05 0.05];
x = linspace(0, 1, n)';
cmap = [interp1(stops(:,1), stops(:,2), x, 'pchip'), ...
        interp1(stops(:,1), stops(:,3), x, 'pchip'), ...
        interp1(stops(:,1), stops(:,4), x, 'pchip')];
cmap = min(max(cmap, 0), 1);
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
warning('GaussianLayers3D:exportFailed', ...
    ['Could not save "%s" after %d attempt(s): %s -- skipping this figure ' ...
     'and continuing with the rest of the run.'], outPath, MAX_ATTEMPTS, lastErr.message);
end

function [col, row] = parseGridCellLabel(label)
% PARSEGRIDCELLLABEL Inverse of mmToGridCell.m's colLetter(): 'AW50' -> col 49, row 50
tok = regexp(label, '^([A-Za-z]+)(\d+)$', 'tokens', 'once');
if isempty(tok)
    error('GaussianLayers3D:badCellLabel', ...
        '"%s" is not a valid grid cell label (expected e.g. "AW50").', label);
end
letters = upper(tok{1});
row = str2double(tok{2});
col = 0;
for i = 1:length(letters)
    col = col * 26 + (double(letters(i)) - double('A') + 1);
end
end
