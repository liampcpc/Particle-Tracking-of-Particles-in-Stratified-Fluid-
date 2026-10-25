function lineResults = impactHeightSideView(underneathClipPath, underneathClipStartAbsS, ...
    sideVideoPath, offsetSec, dotTform, cfg)

S = load(cfg.sideLineCalibFile, 'calib');
calib = S.calib;
nLines = numel(calib.linePx);

vUnder = VideoReader(underneathClipPath);
fpsUnder = vUnder.FrameRate;
clipDurS = vUnder.Duration;

%% Figure out the matching window on the FULL side video
underneathClipEndAbsS = underneathClipStartAbsS + clipDurS;
sideStartT = underneathClipStartAbsS - offsetSec;
sideEndT   = underneathClipEndAbsS   - offsetSec;

margin = cfg.sideBandHalfHeightPx;
rowRangePx = [min(calib.linePx) - margin, max(calib.linePx) + margin];

fprintf('  Tracking side view [%.3f, %.3f]s for %d line(s)...\n', sideStartT, sideEndT, nLines);
track = trackBallVerticalPosition(sideVideoPath, sideStartT, sideEndT, cfg, rowRangePx);

crossings = findLineCrossings(track, calib.linePx);

%% Optional: quick confirmation plot, same "check before trusting it"
fig = figure('Name', 'Side-view height tracking check', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.1 0.2 0.7 0.5]);
plot(track.tS, track.yPx, 'b.-'); hold on;
for k = 1:nLines
    yline(calib.linePx(k), 'k:');
    if crossings(k).found
        plot(crossings(k).tS, calib.linePx(k), 'rx', 'MarkerSize', 12, 'LineWidth', 2);
    end
end
set(gca, 'YDir', 'reverse');
xlabel('Side video time (s)'); ylabel('Ball y (px)');
title(sprintf('%d / %d line crossing(s) found -- close to continue', nnz([crossings.found]), nLines));
drawnow;
pause(0.5);
close(fig);

%% Per line: extract the matching underneath frame, click position
lineResults = struct('heightMm', {}, 'linePx', {}, 'crossingFound', {}, ...
    'underneathTimeS', {}, 'xPx', {}, 'yPx', {}, 'xMm', {}, 'yMm', {}, ...
    'rMm', {}, 'gridCell', {}, 'gridCellInBounds', {}, 'positionSource', {});

worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
xMinW = min(worldXY(:,1)); xMaxW = max(worldXY(:,1));
yMinW = min(worldXY(:,2)); yMaxW = max(worldXY(:,2));

vSide = VideoReader(sideVideoPath);

for k = 1:nLines
    res = struct();
    res.heightMm      = calib.heightsMm(k);
    res.linePx        = calib.linePx(k);
    res.crossingFound = crossings(k).found;
    res.xPx = NaN; res.yPx = NaN; res.xMm = NaN; res.yMm = NaN; res.rMm = NaN;
    res.gridCell = ''; res.gridCellInBounds = false;

    if ~crossings(k).found
        res.underneathTimeS = NaN;
        res.positionSource  = 'no_crossing';
        fprintf('  Line %d (%.0fmm): no crossing found in side view -- skipped.\n', k, res.heightMm);
        lineResults(end+1) = res;  %#ok<AGROW>
        continue
    end

    underneathAbsT  = crossings(k).tS + offsetSec;
    clipLocalT      = underneathAbsT - underneathClipStartAbsS;
    res.underneathTimeS = clipLocalT;

    if clipLocalT < 0 || clipLocalT > clipDurS
        fprintf(['  Line %d (%.0fmm): computed underneath time %.3fs falls outside ' ...
            'this clip (0-%.3fs) -- skipped. Check offsetSec / clip windowing.\n'], ...
            k, res.heightMm, clipLocalT, clipDurS);
        res.positionSource = 'no_crossing';
        lineResults(end+1) = res;  %#ok<AGROW>
        continue
    end

    vUnder.CurrentTime = clipLocalT;
    F = readFrame(vUnder);
    if ~isempty(dotTform)
        gridShowLabels = true;
        if isfield(cfg, 'gridShowLabels'), gridShowLabels = cfg.gridShowLabels; end
        F = drawGridOverlay(F, dotTform, worldXY, cfg.gridCols, cfg.gridRows, ...
            cfg.gridOverlayOpacity, gridShowLabels);
    end
    F = insertText(F, [10 10], sprintf('UNDERNEATH  t=%.3fs (HEIGHT %.0fmm, line %d/%d)', ...
        clipLocalT, res.heightMm, k, nLines), 'FontSize', 16, 'BoxColor', 'black', 'TextColor', 'cyan');

    % Automatic QA preview: side-view frame
    try
        vSide.CurrentTime = max(0, min(vSide.Duration - 1/vSide.FrameRate, crossings(k).tS));
        Fside = readFrame(vSide);
        Fside = insertShape(Fside, 'Line', [1 calib.linePx(k) size(Fside,2) calib.linePx(k)], ...
            'Color', 'green', 'LineWidth', 2);
        fLo = crossings(k).frameLo;
        if isfinite(track.xPx(fLo))
            Fside = insertMarker(Fside, [track.xPx(fLo) track.yPx(fLo)], 'o', ...
                'Color', 'red', 'Size', 10);
        end
        Fside = insertText(Fside, [10 10], sprintf('SIDE  t=%.3fs (line %d @ row %.0fpx)', ...
            crossings(k).tS, k, calib.linePx(k)), 'FontSize', 16, 'BoxColor', 'black', 'TextColor', 'green');

        if size(Fside,1) ~= size(F,1)
            Fside = imresize(Fside, [size(F,1) NaN]);
        end
        dividerPx = 6;
        divider = zeros(size(F,1), dividerPx, 3, 'uint8'); divider(:,:,1) = 255;
        combined = [Fside, divider, F];

        [pth, nm] = fileparts(underneathClipPath);
        checkPath = fullfile(pth, sprintf('%s_h%04.0fmm_check.png', nm, res.heightMm));
        imwrite(combined, checkPath);
        fprintf('  Line %d (%.0fmm): side t=%.3fs -> underneath t=%.3fs  [%s]\n', ...
            k, res.heightMm, crossings(k).tS, clipLocalT, checkPath);
    catch ME
        warning('impactHeightSideView:qaPreviewFailed', 'QA preview failed for line %d: %s', k, ME.message);
    end

    if isfield(cfg, 'heightManualBallSelect') && cfg.heightManualBallSelect
        fig = figure('Name', sprintf('Click ball at %.0fmm -- S to skip, ENTER if not visible', res.heightMm), ...
            'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.8]);
        imshow(F);
        title(sprintf('Drop: %s  |  Line %d/%d = %.0fmm.  Click the ball, S to skip, ENTER to skip.', ...
            underneathClipPath, k, nLines, res.heightMm), 'Interpreter', 'none');

        [x, y, btn] = ginput(1);
        close(fig);

        isSkip = isempty(x) || (isnumeric(btn) && ismember(btn, double('sS')));
        if isSkip
            res.positionSource = 'skipped';
            fprintf('  Line %d (%.0fmm): SKIPPED (not visible).\n', k, res.heightMm);
        else
            res.xPx = x; res.yPx = y;
            res.positionSource = 'manual';
            if ~isempty(dotTform)
                [xm, ym] = transformPointsForward(dotTform, x, y);
                res.xMm = xm; res.yMm = ym; res.rMm = hypot(xm, ym);
                [cellLabel, ~, ~, inBounds] = mmToGridCell(xm, ym, xMinW, yMinW, xMaxW, yMaxW, ...
                    cfg.gridCols, cfg.gridRows);
                res.gridCell = cellLabel; res.gridCellInBounds = inBounds;
            end
            fprintf('  Line %d (%.0fmm): (%.0f, %.0f)mm -> %s\n', k, res.heightMm, res.xMm, res.yMm, res.gridCell);
        end
    else
        res.positionSource = 'skipped';
    end

    try
        Fp = F;
        if isfinite(res.xPx)
            Fp = insertShape(Fp, 'Circle', [res.xPx res.yPx 14], 'Color', 'magenta', 'LineWidth', 2);
            Fp = insertMarker(Fp, [res.xPx res.yPx], 'x', 'Color', 'yellow', 'Size', 10);
        end
        [pth, nm] = fileparts(underneathClipPath);
        outPath = fullfile(pth, sprintf('%s_h%04.0fmm.png', nm, res.heightMm));
        imwrite(Fp, outPath);
    catch
    end

    lineResults(end+1) = res;  %#ok<AGROW>
end

end
