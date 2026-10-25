function calib = calibrateSideViewLines(sideVideoPath, cfg, calibFrameT)

if nargin < 3 || isempty(calibFrameT), calibFrameT = 0.5; end

v = VideoReader(sideVideoPath);
v.CurrentTime = min(max(calibFrameT, 0), max(0, v.Duration - 1/v.FrameRate));
F = readFrame(v);
gray = im2double(rgb2gray(F));

rowProfile = mean(gray, 2);

forceManual = isfield(cfg, 'forceManualLineCalib') && cfg.forceManualLineCalib;

if forceManual
    locs = zeros(0,1);
else
    minPeakDistPx = round(0.4 * size(gray,1) / cfg.numLines);
    [pk, locs] = findpeaks(rowProfile, 'MinPeakDistance', minPeakDistPx, ...
        'SortStr', 'descend', 'NPeaks', cfg.numLines * 2);

    if numel(locs) >= cfg.numLines
        locs = sort(locs(1:cfg.numLines));
    else
        locs = sort(locs);
    end
end

fig = figure('Name', 'Confirm detected line positions', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.1 0.1 0.5 0.8]);
subplot(1,2,1);
imshow(F); hold on;
for i = 1:numel(locs)
    yline(locs(i), 'g-', sprintf('%d', i), 'LineWidth', 1.2);
end
if forceManual
    title('Click each line below (auto-detection skipped)');
else
    title(sprintf('%d line(s) detected automatically', numel(locs)));
end

subplot(1,2,2);
plot(rowProfile, 1:size(gray,1)); set(gca, 'YDir', 'reverse'); hold on;
for i = 1:numel(locs)
    yline(locs(i), 'g-');
end
xlabel('Mean row intensity'); ylabel('Pixel row');
title('Intensity profile (peaks = lines)');

if numel(locs) ~= cfg.numLines
    if forceManual
        fprintf(['\nManual line calibration -- click each line''s row on ' ...
            'the LEFT image, top to bottom, up to %d clicks (press Enter ' ...
            'once you''ve clicked all the lines you have to accept fewer).\n'], ...
            cfg.numLines);
    else
        fprintf(['\nDetected %d line(s), expected cfg.numLines = %d.\n' ...
            'Click each line''s row on the LEFT image, top to bottom, ' ...
            '%d clicks total (or press Enter after enough clicks to accept ' ...
            'what you have).\n'], numel(locs), cfg.numLines, cfg.numLines);
    end
    subplot(1,2,1);
    manualLocs = zeros(0,1);
    for i = 1:cfg.numLines
        [~, y, btn] = ginput(1);
        if isempty(y), break; end
        manualLocs(end+1) = y;  %#ok<AGROW>
        yline(y, 'r--', sprintf('%d', numel(manualLocs)));
    end
    locs = sort(manualLocs(:));
else
    resp = input(sprintf('\n%d line(s) detected -- looks right? [Y/n]: ', numel(locs)), 's');
    if ~isempty(resp) && ~strcmpi(strtrim(resp), 'y')
        fprintf('Re-run with a different calibFrameT, or click manually -- see this function''s help.\n');
        close(fig);
        error('calibrateSideViewLines:rejected', 'Calibration rejected by user.');
    end
end
close(fig);

nFound = numel(locs);
if nFound == 0
    error('calibrateSideViewLines:noLines', 'No lines found or clicked -- nothing to save.');
end

heightsMm = cfg.lineHeightsMm;
if isempty(heightsMm)
    heightsMm = (nFound:-1:1) * cfg.lineSpacingMm;
elseif numel(heightsMm) ~= nFound
    error('calibrateSideViewLines:heightMismatch', ...
        'cfg.lineHeightsMm has %d entries but %d lines were found/clicked.', ...
        numel(heightsMm), nFound);
end

calib = struct();
calib.sourceVideo = sideVideoPath;
calib.linePx      = locs(:)';
calib.heightsMm   = heightsMm(:)';
calib.frameSize   = size(gray);
calib.createdAt   = datestr(now);  %#ok<TNOW1,DATST>

save(cfg.sideLineCalibFile, 'calib');
fprintf('\nSaved %d line(s) to %s:\n', nFound, cfg.sideLineCalibFile);
for i = 1:nFound
    fprintf('  line %d: row %.1fpx -> %.0fmm\n', i, calib.linePx(i), calib.heightsMm(i));
end

end
