function [offsetSec, audio1ds, audio2ds] = estimateAudioOffset(videoFile1, videoFile2, opts)
% ESTIMATEAUDIOOFFSET Cross-correlate two recordings' audio to find the constant timing offset between them

if nargin < 3, opts = struct(); end
opts = set_default(opts, 'syncSearchRangeSec', 60);
opts = set_default(opts, 'syncFs', 4000);
opts = set_default(opts, 'showCheckPlot', true);

fprintf('Reading audio tracks for sync...\n');
[audio1, fs1] = readMonoAudio(videoFile1);
[audio2, fs2] = readMonoAudio(videoFile2);

fprintf('Estimating audio offset...\n');
audio1ds = simpleResample(audio1, fs1, opts.syncFs);
audio2ds = simpleResample(audio2, fs2, opts.syncFs);

maxlagSamples = round(opts.syncSearchRangeSec * opts.syncFs);
maxlagSamples = min(maxlagSamples, min(numel(audio1ds), numel(audio2ds)) - 1);

[c, lags] = xcorr(audio1ds, audio2ds, maxlagSamples);
[~, idx] = max(abs(c));
lagSamples = lags(idx);
offsetSec = lagSamples / opts.syncFs;

fprintf('Estimated offset: %.3f s (cam2Time = cam1Time - %.3f)\n', offsetSec, offsetSec);

if opts.showCheckPlot
    t1 = (0:numel(audio1ds)-1) / opts.syncFs;
    t2shifted = (0:numel(audio2ds)-1) / opts.syncFs + offsetSec;

    fig = figure('Name', 'Sync check - close/press Enter to continue', ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.6]);
    plot(t1, audio1ds ./ max(abs(audio1ds)+eps), 'b'); hold on;
    plot(t2shifted, audio2ds ./ max(abs(audio2ds)+eps) - 2.2, 'r'); hold off;
    grid on; xlabel('Camera 1 time (s)');
    title(sprintf(['Alignment check: blue = cam1, red = cam2 shifted by %.3f s.\n' ...
        'Spikes should line up vertically. Close (or press Enter) to continue.'], offsetSec));
    legend({'Camera 1', 'Camera 2 (shifted)'}, 'Location', 'northoutside', 'Orientation', 'horizontal');

    input('Check the alignment plot, then press Enter here to continue...', 's');
    if isvalid(fig), close(fig); end
end

end

function s = set_default(s, field, val)
if ~isfield(s, field) || isempty(s.(field))
    s.(field) = val;
end
end

function [audioMono, fs] = readMonoAudio(videoFile)
try
    [audioData, fs] = audioread(videoFile);
catch ME
    error(['Could not read audio from "%s". Make sure it contains an ' ...
        'audio track that MATLAB''s audioread supports.\nUnderlying error: %s'], ...
        videoFile, ME.message);
end
if size(audioData,2) > 1
    audioMono = mean(audioData, 2);
else
    audioMono = audioData;
end
end

function y = simpleResample(x, origFs, targetFs)
x = x(:);
tOrig = (0:numel(x)-1)' / origFs;
tNew = (0:1/targetFs:tOrig(end))';
y = interp1(tOrig, x, tNew, 'linear', 0);
end
