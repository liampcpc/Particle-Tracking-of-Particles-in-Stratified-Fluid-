%% RecomputeHeightPositions
% Re-derives xMm/yMm/gridCell in an EXISTING heightResults.mat from its saved raw pixel clicks
clear; clc;

addpath(fileparts(mfilename('fullpath')));

%% SETTINGS -- edit for your session(s)
HEIGHT_RESULTS_FILES = {'drop_clips/heightResults.mat'};  % one or more, one per session
OVERWRITE = true;  % true = update the file in place (keeps a backup) false

%% RECOMPUTE
cfg = rigConfig();
worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
xMinW = min(worldXY(:,1)); xMaxW = max(worldXY(:,1));
yMinW = min(worldXY(:,2)); yMaxW = max(worldXY(:,2));

for f = 1:numel(HEIGHT_RESULTS_FILES)
    file = HEIGHT_RESULTS_FILES{f};
    if exist(file, 'file') ~= 2
        warning('RecomputeHeightPositions:missingFile', 'Skipping missing file: %s', file);
        continue
    end
    S = load(file, 'heightResults');
    hr = S.heightResults;

    if ~isfield(hr, 'xPx') || ~isfield(hr, 'yPx') || ~isfield(hr, 'clipFile')
        warning('RecomputeHeightPositions:noPixelData', ...
            ['%s was written by an older SplitAndTrackHeights.m that did not save ' ...
             'raw pixel positions -- cannot be corrected this way. Re-run ' ...
             'SplitAndTrackHeights.m for this session instead (with re-clicking).'], file);
        continue
    end

    n = numel(hr.xPx);
    newXMm = nan(n, 1); newYMm = nan(n, 1);
    newGridCell = strings(n, 1); newInBounds = false(n, 1);

    useDotCalib = isfield(hr, 'dotCalibration') && isstruct(hr.dotCalibration) && ...
        isfield(hr.dotCalibration, 'dropIndex') && ~isempty(hr.dotCalibration.dropIndex);

    if useDotCalib

        %% PATH 1: refit from saved dot pixel positions -- no video needed
        dc = hr.dotCalibration;
        fprintf('%s: %d row(s) across %d drop(s) -- using saved dot-pixel calibration, no clip files needed.\n', ...
            file, n, numel(dc.dropIndex));

        for d = 1:numel(dc.dropIndex)
            rows = find(hr.dropIndex == dc.dropIndex(d));
            if isempty(rows), continue; end

            names  = dc.names{d};
            imgPts = dc.imgPts{d};
            worldPts = nan(size(imgPts));
            matchedOk = true(numel(names), 1);
            for k = 1:numel(names)
                idx = find(strcmpi({cfg.dotWorldPositionsMm.name}, names{k}), 1);
                if isempty(idx)
                    matchedOk(k) = false;
                    continue
                end
                worldPts(k, :) = cfg.dotWorldPositionsMm(idx).xy_mm;
            end

            if nnz(matchedOk) < 4
                warning('RecomputeHeightPositions:tooFewPoints', ...
                    ['Drop %d: only %d of %d saved dot(s) still have a matching name in ' ...
                     'cfg.dotWorldPositionsMm -- a projective fit needs at least 4. %d row(s) ' ...
                     'left as NaN.'], dc.dropIndex(d), nnz(matchedOk), numel(names), numel(rows));
                continue
            end

            try
                dotTform = fitgeotform2d(imgPts(matchedOk,:), worldPts(matchedOk,:), 'projective');
            catch
                dotTform = fitgeotrans(imgPts(matchedOk,:), worldPts(matchedOk,:), 'projective');
            end
            fprintf('  Drop %d (%s): refit from %d saved dot pixel(s), re-projecting %d row(s)...\n', ...
                dc.dropIndex(d), dc.clipFile(d), nnz(matchedOk), numel(rows));

            for ri = rows(:)'
                [xm, ym] = transformPointsForward(dotTform, hr.xPx(ri), hr.yPx(ri));
                [cellLabel, ~, ~, inBounds] = mmToGridCell(xm, ym, xMinW, yMinW, xMaxW, yMaxW, ...
                    cfg.gridCols, cfg.gridRows);
                newXMm(ri) = xm; newYMm(ri) = ym;
                newGridCell(ri) = cellLabel; newInBounds(ri) = inBounds;
            end
        end

    else

        %% PATH 2 (fallback): re-detect the dots from each clip file
        uniqueClips = unique(hr.clipFile);
        fprintf(['%s: %d row(s) across %d clip(s) -- no saved dot-pixel calibration found ' ...
            '(older file), falling back to re-detecting the dots from each clip file.\n'], ...
            file, n, numel(uniqueClips));

        for c = 1:numel(uniqueClips)
            clipFile = char(uniqueClips(c));
            rows = find(hr.clipFile == uniqueClips(c));

            if exist(clipFile, 'file') ~= 2
                warning('RecomputeHeightPositions:missingClip', ...
                    ['%s: clip file not found from the current folder -- %d row(s) left ' ...
                     'as NaN. Run this script from the same folder SplitAndTrackHeights.m ' ...
                     'was run from, or fix the path.'], clipFile, numel(rows));
                continue
            end

            try
                [dotTform, matchedDots] = fitDotHomography(clipFile, cfg.dotWorldPositionsMm);
                fprintf('  %s: %d dots matched, re-projecting %d row(s)...\n', ...
                    clipFile, numel(matchedDots), numel(rows));
            catch ME
                warning('RecomputeHeightPositions:calibFailed', ...
                    '%s: colour-dot calibration failed (%s) -- %d row(s) left as NaN.', ...
                    clipFile, ME.message, numel(rows));
                continue
            end

            for ri = rows(:)'
                [xm, ym] = transformPointsForward(dotTform, hr.xPx(ri), hr.yPx(ri));
                [cellLabel, ~, ~, inBounds] = mmToGridCell(xm, ym, xMinW, yMinW, xMaxW, yMaxW, ...
                    cfg.gridCols, cfg.gridRows);
                newXMm(ri) = xm; newYMm(ri) = ym;
                newGridCell(ri) = cellLabel; newInBounds(ri) = inBounds;
            end
        end
    end

    nChanged = nnz(~isnan(newXMm));
    fprintf('  %d / %d row(s) successfully recomputed.\n', nChanged, n);
    if nChanged < n
        fprintf(['  %d row(s) could not be recomputed (see warnings above) -- their ' ...
            'xMm/yMm/gridCell are now NaN/empty rather than silently keeping the OLD, ' ...
            'wrong-calibration values.\n'], n - nChanged);
    end

    hr.xMm      = newXMm;
    hr.yMm      = newYMm;
    hr.gridCell = newGridCell;
    hr.inBounds = newInBounds;
    hr.gridCols = cfg.gridCols;
    hr.gridRows = cfg.gridRows;
    hr.recomputedAt = datestr(now);  %#ok<TNOW1,DATST>
    hr.recomputedFromDotWorldPositionsMm = cfg.dotWorldPositionsMm;
    heightResults = hr;  %#ok<NASGU>

    [pth, nm, ext] = fileparts(file);
    if OVERWRITE
        bakFile = fullfile(pth, [nm '_prerecompute' ext]);
        if exist(bakFile, 'file') ~= 2
            copyfile(file, bakFile);
            fprintf('  Backed up original -> %s\n', bakFile);
        end
        save(file, 'heightResults');
        fprintf('  Overwrote %s\n', file);
    else
        outFile = fullfile(pth, [nm '_recomputed' ext]);
        save(outFile, 'heightResults');
        fprintf('  Wrote %s\n', outFile);
    end
end

fprintf('\n=== Complete ===\n');
fprintf('Run CompileHeightHeatmaps.m / RunCompileHeightHeatmaps.m next to rebuild the heatmaps from the corrected data.\n');
