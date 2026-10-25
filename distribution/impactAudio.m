function result = impactAudio(videoPath, cfg, varargin)
% IMPACTAUDIO APPROACH 3

addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));

p = inputParser;
addParameter(p, 'diagnose', false, @islogical);
parse(p, varargin{:});
opt = p.Results;

[audio, fs] = read_mono_audio(videoPath);
winSamples = max(1, round(cfg.audioEnvelopeWinMs/1000 * fs));
env = movmean(abs(audio), winSamples);

if opt.diagnose
    spike = findSpike(env, fs, cfg);
    result = runAudioDiagnostic(videoPath, env, fs, spike);
    return
end

detectMode = 'auto';
if isfield(cfg, 'audioDetectMode') && ~isempty(cfg.audioDetectMode)
    detectMode = cfg.audioDetectMode;
end

switch lower(detectMode)
    case 'manual'
        spike = clickSpike(videoPath, env, fs, cfg);
    case 'auto'
        spike = findSpike(env, fs, cfg);
    otherwise
        error('impactAudio:badMode', ...
            'cfg.audioDetectMode must be ''auto'' or ''manual'' (got ''%s'').', detectMode);
end

v   = VideoReader(videoPath);
fps = v.FrameRate;

frameIndex = spike.timeS * fps + 1;

data = scanVideo(videoPath, cfg, 'blob');

result = struct();
result.method       = 'audio spike';
result.video        = videoPath;
result.fps          = fps;
result.nFrames      = data.nFrames;
result.impactFrame  = frameIndex;
result.impactTimeS  = frameIndex / fps;
result.spikeRatio   = spike.ratio;
result.audioVerdict = spike.verdict;

if spike.secondaryFrac > cfg.audioSecondaryWarnFrac
    result.warning = sprintf(['A second sound at t=%.3fs reached %.0f%% ' ...
        'of the primary spike''s amplitude (outside the primary''s own ' ...
        'ringing tail). Could be a bounce, could be a louder unrelated ' ...
        'noise that argmax picked over the real impact -- WATCH THE ' ...
        'VERIFICATION VIDEO before trusting this result.'], ...
        spike.secondaryTimeS, 100*spike.secondaryFrac);
end

result.xPx = interpAt(data.x, frameIndex);
result.yPx = interpAt(data.y, frameIndex);
result.ballPositionSource = 'automatic';  % may become 'manual' below

if ~isempty(data.tform)
    [xm, ym] = transformPointsForward(data.tform, result.xPx, result.yPx);
    result.xMm = xm;
    result.yMm = ym;
    result.rMm = hypot(xm, ym);
elseif ~isempty(data.mmPerPx)
    result.xMm = result.xPx * data.mmPerPx;
    result.yMm = result.yPx * data.mmPerPx;
end

dotTform = [];  % stays empty unless colour-dot calibration is on AND succeeds below
if isfield(cfg, 'useColorDotCalibration') && cfg.useColorDotCalibration
    try
        [dotTform, matchedDots] = fitDotHomography(videoPath, cfg.dotWorldPositionsMm);
        [xm, ym, rMm, cellLabel, inBounds] = pxToGridMm( ...
            dotTform, result.xPx, result.yPx, cfg.dotWorldPositionsMm, cfg.gridCols, cfg.gridRows);
        result.xMm = xm;
        result.yMm = ym;
        result.rMm = rMm;
        result.calibrationMethod = 'colorDots';
        result.calibDotsMatched  = matchedDots;
        result.gridCell          = cellLabel;
        result.gridCellInBounds  = inBounds;

        fprintf('  Grid cell: %s (calibrated from %d dots: %s)\n', ...
            cellLabel, numel(matchedDots), strjoin(matchedDots, ', '));
        if ~inBounds
            fprintf(['  NOTE: (%.0f, %.0f) mm is OUTSIDE the calibrated grid ' ...
                     '-- cell %s is extrapolated, not a real calibrated cell.\n'], ...
                     xm, ym, cellLabel);
        end
    catch ME
        warning('impactAudio:colorDotCalibrationFailed', ...
            ['Colour-dot calibration failed for this clip: %s\n' ...
             'xPx/yPx are still set; no xMm/yMm/gridCell for this drop.'], ...
             ME.message);
    end
end

if isfield(cfg, 'manualBallSelect') && cfg.manualBallSelect
    try
        currentTime = max(0, (round(frameIndex)-1) / fps);

        vClick = VideoReader(videoPath);
        vClick.CurrentTime = currentTime;
        Fcurrent = readFrame(vClick);
        if ~isempty(dotTform)
            worldXYclick = cat(1, cfg.dotWorldPositionsMm.xy_mm);
            gridShowLabelsClick = true;
            if isfield(cfg, 'gridShowLabels'), gridShowLabelsClick = cfg.gridShowLabels; end
            Fcurrent = drawGridOverlay(Fcurrent, dotTform, worldXYclick, cfg.gridCols, cfg.gridRows, ...
                cfg.gridOverlayOpacity, gridShowLabelsClick);
        end
        if isfinite(result.xPx) && isfinite(result.yPx)
            Fcurrent = insertShape(Fcurrent, 'Circle', [result.xPx result.yPx 14], ...
                'Color', [128 128 128], 'LineWidth', 2);
            Fcurrent = insertText(Fcurrent, [result.xPx+18 result.yPx-10], 'auto (unreliable)', ...
                'FontSize', 12, 'BoxColor', [128 128 128], 'TextColor', 'white');
        end

        beforeLeadS = 2;
        beforeTime = max(0, currentTime - beforeLeadS);
        vBefore = VideoReader(videoPath);
        vBefore.CurrentTime = beforeTime;
        Fbefore = readFrame(vBefore);
        if ~isequal(size(Fbefore), size(Fcurrent))
            Fbefore = imresize(Fbefore, [size(Fcurrent,1) size(Fcurrent,2)]);
        end

        dividerPx = 6;
        divider = zeros(size(Fcurrent,1), dividerPx, 3, 'uint8');
        divider(:,:,1) = 255;
        combined = [Fbefore, divider, Fcurrent];
        beforeWidthPx = size(Fbefore, 2);
        currentOffsetPx = beforeWidthPx + dividerPx;

        combined = insertText(combined, [10 10], ...
            sprintf('BEFORE (%.1fs earlier)', currentTime - beforeTime), ...
            'FontSize', 18, 'BoxColor', 'black', 'TextColor', 'white');
        combined = insertText(combined, [currentOffsetPx+10 10], ...
            'CURRENT -- click the ball HERE', ...
            'FontSize', 18, 'BoxColor', 'black', 'TextColor', 'yellow');

        fig = figure('Name', 'Click the ball on the RIGHT image, S to skip, ENTER to keep automatic', ...
            'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.02 0.1 0.96 0.8]);
        imshow(combined);
        title({'LEFT = a couple seconds before this drop -- spot residual balls already there.', ...
               'RIGHT = now -- click the ball actually here (not on the left image).', ...
               'Press S if not visible in this frame. Press ENTER to keep the automatic position.'});

        while true
            [xRaw, yRaw, btnRaw] = ginput(1);
            if isempty(xRaw)
                btn = btnRaw;  % ENTER pressed
                break
            end
            if isnumeric(btnRaw) && ismember(btnRaw, double('sS'))
                btn = btnRaw;  % S pressed
                break
            end
            if xRaw < beforeWidthPx
                fprintf(['  That click landed on the BEFORE image (left) -- click the ' ...
                    'CURRENT image (right) instead, or press ENTER/S.\n']);
                continue
            end
            xClick = xRaw - currentOffsetPx;
            yClick = yRaw;
            btn = btnRaw;
            break
        end
        close(fig);

        isSkip = ~isempty(btn) && isnumeric(btn) && ismember(btn, double('sS'));

        if isSkip
            result.ballPositionSource = 'skipped';
            result.xPx = NaN; result.yPx = NaN;
            result.xMm = NaN; result.yMm = NaN; result.rMm = NaN;
            result.gridCell = '';
            result.gridCellInBounds = false;
            fprintf('  SKIPPED -- ball not visible in this frame. Excluded from grid results.\n');
        elseif ~isempty(xClick)
            result.xPx = xClick;
            result.yPx = yClick;
            result.ballPositionSource = 'manual';
            if ~isempty(dotTform)
                [xm, ym, rMm, cellLabel, inBounds] = pxToGridMm( ...
                    dotTform, xClick, yClick, cfg.dotWorldPositionsMm, cfg.gridCols, cfg.gridRows);
                result.xMm = xm; result.yMm = ym; result.rMm = rMm;
                result.gridCell = cellLabel; result.gridCellInBounds = inBounds;
                oobNote = '';
                if ~inBounds, oobNote = ' (OUTSIDE calibrated grid)'; end
                fprintf('  Manual position -> grid cell: %s%s\n', cellLabel, oobNote);
            end
        else
            fprintf('  Kept automatic position (no manual click).\n');
        end
    catch ME
        warning('impactAudio:manualBallSelectFailed', ...
            'Manual ball selection failed: %s\nKeeping the automatic position.', ME.message);
    end
end

frameTimes   = ((1:data.nFrames) - 1) / fps;
audioIdx     = min(max(round(frameTimes * fs) + 1, 1), numel(env));
envPerFrame  = env(audioIdx);

[pth, nm] = fileparts(videoPath);
csvPath = fullfile(pth, [nm '_audiotrace.csv']);
T = table((1:data.nFrames)', envPerFrame(:), data.x, data.y, ...
    'VariableNames', {'frame','envelope','x_px','y_px'});
writetable(T, csvPath);
result.audioTraceCsv = csvPath;

if cfg.savePreview
    gridShowLabelsPreview = true;
    if isfield(cfg, 'gridShowLabels'), gridShowLabelsPreview = cfg.gridShowLabels; end
    result.previewFile = savePreviewAudio(videoPath, round(frameIndex), ...
        result.xPx, result.yPx, dotTform, cfg.dotWorldPositionsMm, cfg.gridCols, cfg.gridRows, ...
        result.ballPositionSource, cfg.gridOverlayOpacity, gridShowLabelsPreview);
end

if isfield(cfg, 'saveVerificationVideo') && cfg.saveVerificationVideo
    vOpts = struct( ...
        'label',        'IMPACT (audio)', ...
        'markColor',    'magenta', ...
        'metricName',   'audio envelope', ...
        'metricValues', envPerFrame, ...
        'outSuffix',    '_impact_audio_verify.mp4');
    if isfield(cfg, 'verificationWindowMs')
        vOpts.windowMs = cfg.verificationWindowMs;
    end
    result.verificationVideo = renderEventVideo(videoPath, data, frameIndex, vOpts);

    ffmpegBin = '';
    if isfield(cfg, 'ffmpegBin'), ffmpegBin = cfg.ffmpegBin; end
    result.verificationVideo = muxAudioIntoVideo( ...
        result.verificationVideo, videoPath, ffmpegBin);
end

if isfield(cfg, 'saveSlowMoVideo') && cfg.saveSlowMoVideo
    smOpts = struct( ...
        'approachFrames', cfg.slowMoApproachFrames, ...
        'slowFactor',     cfg.slowMoFactor, ...
        'freezeS',        cfg.slowMoFreezeS, ...
        'markColor',      'magenta');
    result.slowMoVideo = renderSlowMoImpactVideo(videoPath, data, frameIndex, smOpts);
end

end

%% Local functions
function spike = findSpike(env, fs, cfg)
% FINDSPIKE Automatic: global peak (argmax) of the envelope
[~, peakI] = max(env);
spike = buildSpikeReport(env, fs, cfg, peakI);
end

function spike = clickSpike(videoPath, env, fs, cfg)
% CLICKSPIKE Manual: you click the impact spike yourself, mirroring AudioSplit.m's click-based marking

t = (0:numel(env)-1)' / fs;
[~, nm] = fileparts(videoPath);

fig = figure('Name', 'Click the impact spike', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.1 0.25 0.8 0.5]);
plot(t, env, '-', 'Color', [0.3 0.4 0.7]); grid on;
xlabel('Time (s)'); ylabel('Envelope');
title(sprintf('%s -- click ONCE on the impact spike', nm), 'Interpreter', 'none');

fprintf('Click once on the impact spike for %s...\n', nm);
[x, ~] = ginput(1);
close(fig);

if isempty(x)
    error('impactAudio:noClick', 'No click registered -- nothing to use as the impact time.');
end
x = min(max(x, 0), t(end));

clickI = min(max(round(x*fs) + 1, 1), numel(env));
windowSamples = round(cfg.audioClickWindowMs/1000 * fs);
lo = max(1, clickI - windowSamples);
hi = min(numel(env), clickI + windowSamples);
[~, rel] = max(env(lo:hi));
peakI = lo + rel - 1;

spike = buildSpikeReport(env, fs, cfg, peakI);
fprintf('  Clicked t=%.3fs -> refined to t=%.3fs (searched +/-%.0f ms)\n', ...
    x, spike.timeS, cfg.audioClickWindowMs);

end

function spike = buildSpikeReport(env, fs, cfg, peakI)
% BUILDSPIKEREPORT Verdict + secondary-event check for a chosen peak sample

peakVal = env(peakI);
med = median(env);

spike.timeS = (peakI - 1) / fs;
spike.value = peakVal;
spike.ratio = peakVal / max(med, eps);

if spike.ratio < 2
    spike.verdict = ['POOR: the impact barely stands out from background ' ...
        'noise. No detection strategy fixes this -- reduce ambient/room ' ...
        'noise, or check the clip actually contains an audible knock.'];
elseif spike.ratio < 4
    spike.verdict = 'MARGINAL: workable but check the verification video carefully.';
else
    spike.verdict = 'GOOD: clear separation between the impact and background.';
end

exclSamples = round(cfg.audioRingDecayExclMs/1000 * fs);
idx = (1:numel(env))';
outside = abs(idx - peakI) > exclSamples;

if any(outside)
    envOutside = env;
    envOutside(~outside) = -Inf;
    [secVal, secI] = max(envOutside);
    spike.secondaryTimeS = (secI - 1) / fs;
    spike.secondaryValue = secVal;
    spike.secondaryFrac  = secVal / max(peakVal, eps);
else
    spike.secondaryTimeS = NaN;
    spike.secondaryValue = NaN;
    spike.secondaryFrac  = 0;
end

end

function outPath = renderSlowMoImpactVideo(videoPath, data, eventFrame, opts)
% RENDERSLOWMOIMPACTVIDEO Slow-in, freeze-with-flash, slow-out around the estimated impact frame

v   = VideoReader(videoPath);
fps = v.FrameRate;
eventRounded = round(eventFrame);
freezeExtra  = round(opts.freezeS * fps);

[pth, nm] = fileparts(videoPath);
outPath = fullfile(pth, [nm '_impact_audio_slowmo.mp4']);
wr = VideoWriter(outPath, 'MPEG-4');
wr.FrameRate = fps;
open(wr);

k = 0;
while hasFrame(v)
    k = k + 1;
    F = readFrame(v);

    inApproach = abs(k - eventRounded) <= opts.approachFrames;
    isImpact   = (k == eventRounded);
    haveXY     = k <= numel(data.x) && isfinite(data.x(k)) && isfinite(data.y(k));

    if haveXY
        F = insertShape(F, 'Circle', [data.x(k) data.y(k) 18], ...
            'Color', opts.markColor, 'LineWidth', 3);
    end

    if isImpact
        [h, w, ~] = size(F);
        F = insertShape(F, 'FilledCircle', [w-50 50 35], ...
            'Color', 'green', 'Opacity', 1);
        F = insertText(F, [10 10], 'IMPACT FRAME', 'FontSize', 26, ...
            'BoxColor', 'green', 'TextColor', 'black');
        reps = opts.slowFactor + freezeExtra;
    elseif inApproach
        F = insertText(F, [10 10], sprintf('slow-mo   frame %d', k), ...
            'FontSize', 16, 'BoxColor', 'yellow', 'TextColor', 'black');
        reps = opts.slowFactor;
    else
        reps = 1;
    end

    Fpad = padFrameForEncoder(F);
    for r = 1:reps
        writeVideo(wr, Fpad);
    end
end

close(wr);
end

function report = runAudioDiagnostic(videoPath, env, fs, spike)
% RUNAUDIODIAGNOSTIC Report + plot, no persistent output

report = struct();
report.video         = videoPath;
report.spikeTimeS    = spike.timeS;
report.spikeRatio    = spike.ratio;
report.verdict       = spike.verdict;
report.secondaryTimeS = spike.secondaryTimeS;
report.secondaryFrac  = spike.secondaryFrac;

fprintf('Peak at t=%.3fs, %.1fx the noise floor -- %s\n', ...
    spike.timeS, spike.ratio, spike.verdict);
if isfinite(spike.secondaryFrac)
    fprintf('Next-largest separate peak: t=%.3fs, %.0f%% of the primary.\n', ...
        spike.secondaryTimeS, 100*spike.secondaryFrac);
end

t = (0:numel(env)-1)' / fs;
figure('Name', 'Audio impact spike');
plot(t, env, '-'); hold on;
xline(spike.timeS, 'r--', 'primary');
if isfinite(spike.secondaryTimeS)
    xline(spike.secondaryTimeS, 'b:', 'next-largest');
end
xlabel('Time (s)'); ylabel('Envelope');
title(sprintf('Ratio %.1fx -- %s', spike.ratio, spike.verdict));
grid on;

end

function val = interpAt(series, frame)
% INTERPAT Linear interpolation of a per-frame series at a fractional frame
lo = floor(frame);
hi = lo + 1;

if lo < 1 || hi > numel(series)
    val = NaN;
    return
end

if isfinite(series(lo)) && isfinite(series(hi))
    f = frame - lo;
    val = series(lo)*(1-f) + series(hi)*f;
else
    near = min(max(round(frame), 1), numel(series));
    val = series(near);
end
end

function [xMm, yMm, rMm, cellLabel, inBounds] = pxToGridMm( ...
    dotTform, xPx, yPx, dotWorldPositionsMm, nCols, nRows)
[xMm, yMm] = transformPointsForward(dotTform, xPx, yPx);
rMm = hypot(xMm, yMm);
[cellLabel, inBounds] = worldMmToGridResult(xMm, yMm, dotWorldPositionsMm, nCols, nRows);
end

function [cellLabel, inBounds] = worldMmToGridResult(xMm, yMm, dotWorldPositionsMm, nCols, nRows)
% WORLDMMTOGRIDRESULT World mm -> grid cell, given a position ALREADY in world mm (no pixel/homography step)
worldXY = cat(1, dotWorldPositionsMm.xy_mm);
xMin = min(worldXY(:,1)); xMax = max(worldXY(:,1));
yMin = min(worldXY(:,2)); yMax = max(worldXY(:,2));
[cellLabel, ~, ~, inBounds] = mmToGridCell(xMm, yMm, xMin, yMin, xMax, yMax, nCols, nRows);
end

function [a, fs] = read_mono_audio(videoFile)
% READ_MONO_AUDIO Same approach as AudioSplit.m's helper of the same purpose
try
    [x, fs] = audioread(videoFile);
catch ME
    error(['Could not read audio from "%s". impactAudio needs an audio ' ...
        'track to find the impact.\nUnderlying error: %s'], videoFile, ME.message);
end
if size(x,2) > 1, a = mean(x,2); else, a = x; end
end

function outPath = savePreviewAudio(videoPath, frameIdx, x, y, dotTform, dotWorldPositionsMm, nCols, nRows, positionSource, gridOverlayOpacity, gridShowLabels)
% SAVEPREVIEWAUDIO Single still at the chosen frame
if nargin < 10 || isempty(gridOverlayOpacity)
    gridOverlayOpacity = 1;
end
if nargin < 11 || isempty(gridShowLabels)
    gridShowLabels = true;
end
outPath = '';
try
    v = VideoReader(videoPath);
    v.CurrentTime = max(0, (frameIdx-1) / v.FrameRate);
    F = readFrame(v);

    if nargin >= 5 && ~isempty(dotTform)
        worldXY = cat(1, dotWorldPositionsMm.xy_mm);
        F = drawGridOverlay(F, dotTform, worldXY, nCols, nRows, gridOverlayOpacity, gridShowLabels);
    end

    if isfinite(x) && isfinite(y)
        F = insertShape(F, 'Circle', [x y 14], 'Color', 'magenta', ...
                        'LineWidth', 2);
        F = insertMarker(F, [x y], 'x', 'Color', 'yellow', 'Size', 10);
    end
    label = 'AUDIO';
    if nargin >= 9 && ~isempty(positionSource)
        label = sprintf('AUDIO (%s)', positionSource);
    end
    F = insertText(F, [10 10], label, 'FontSize', 20, ...
                   'BoxColor', 'black', 'TextColor', 'magenta');

    [pth, nm] = fileparts(videoPath);
    outPath = fullfile(pth, [nm '_impact_audio.png']);
    imwrite(F, outPath);
catch
end
end

function finalPath = muxAudioIntoVideo(silentVideoPath, sourceVideoPath, ffmpegBinCfg)
% MUXAUDIOINTOVIDEO Add the clip's own audio track to the (silent) rendered verification video, in place
finalPath = silentVideoPath;
if isempty(silentVideoPath), return; end

try
    ff = locate_ffmpeg(ffmpegBinCfg);
    [pth, nm, ext] = fileparts(silentVideoPath);
    tmpPath = fullfile(pth, [nm '_withaudio' ext]);

    cmd = sprintf(['"%s" -y -i "%s" -i "%s" -map 0:v:0 -map 1:a:0 ' ...
                   '-c:v copy -c:a aac -shortest "%s"'], ...
                   ff, silentVideoPath, sourceVideoPath, tmpPath);
    [status, cmdout] = system(cmd);

    if status ~= 0 || exist(tmpPath, 'file') ~= 2
        warning('impactAudio:muxFailed', ...
            ['Could not add audio to the verification video:\n%s\n' ...
             'The video is still valid but SILENT -- you will not be ' ...
             'able to hear the impact while watching it.'], strtrim(cmdout));
        return
    end

    movefile(tmpPath, silentVideoPath, 'f');
    finalPath = silentVideoPath;
catch ME
    warning('impactAudio:muxFailed', ...
        ['Could not add audio to the verification video: %s\n' ...
         'The video is still valid but SILENT.'], ME.message);
end
end
