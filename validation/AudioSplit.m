%% AudioSplit
% Splits ONE long single-camera recording into per-drop clips
clear; clc; close all;

%% CONFIGURATION
VIDEO_FILE = 'dropside0_24.mov';  % the long recording containing all drops
OUTPUT_DIR = 'drop_clips';
OUTPUT_PREFIX = 'drop';

FPS = 60;  % expected frame rate

DETECT_MODE = 'manual';  % 'auto' - detect the piezo buzzer automatically

% Clip window

BUZZER_LAG_S = 1.75;  % Delay from the electromagnet demagnetising

MANUAL_MARKER_MODE = 'buzzer';  % 'buzzer' - click the buzzer beep

PRE_PAD_S = 0.40;  % PRE_PAD_S matters more than it looks

CLIP_DURATION_S = 1.50;  % Fall time varies enormously with the fluid

% Used only when MANUAL_MARKER_MODE = 'impact'
EXPECTED_FALL_TIME_S = 1.0;  % Generous UPPER estimate of release-to-impact time for THIS fluid/object

BACKGROUND_LEAD_S = 0.30;  % extra reach-back beyond EXPECTED_FALL_TIME_S

POST_IMPACT_S = 0.30;  % short tail after impact

% 'auto' mode settings (ignored in manual mode)
EXPECTED_DROPS = [];  % how many drops you performed

BUZZER_FREQ_HZ = 3000;  % centre frequency of your buzzer
BUZZER_BAND_HZ = 1200;  % half-width of that band

DETECT_THRESHOLD = [];  % [] = automatic (robust baseline + spread)

BUZZER_TONALITY_MIN = 0.6;  % Rejects loud noises that are not the buzzer

MIN_SEPARATION_S = 3;  % minimum gap between two drops

% Encoding
KEEP_AUDIO = false;  % clips do not need audio downstream
CRF = 18;  % x264 quality

FFMPEG_BIN = 'C:\Users\omear\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe';  % leave '' to auto-locate

%% LOCATE FFMPEG
ffmpeg = locate_ffmpeg(FFMPEG_BIN);
fprintf('ffmpeg: %s\n', ffmpeg);

%% READ VIDEO INFO + AUDIO
if exist(VIDEO_FILE, 'file') ~= 2
    error(['Cannot find "%s".\nRun  pwd  and  dir  to check you are in the ' ...
        'right folder and the name/extension match exactly.'], VIDEO_FILE);
end

vid = VideoReader(VIDEO_FILE);
duration = vid.Duration;
trueFps  = vid.FrameRate;
fprintf('Video: %.2f s | %.2f fps reported | %dx%d\n', ...
    duration, trueFps, vid.Width, vid.Height);

if abs(trueFps - FPS) > 0.5
    warning('AudioSplit:fpsMismatch', ...
        ['The file reports %.2f fps but FPS is set to %g.\n' ...
         'If this is slo-mo footage, make sure you exported the ' ...
         'UNMODIFIED original - a retimed export makes every velocity ' ...
         'wrong by the ratio of the two rates, and nothing downstream ' ...
         'can detect it.'], trueFps, FPS);
end

fprintf('Reading audio...\n');
[audio, fs] = read_mono_audio(VIDEO_FILE);
tAudio = (0:numel(audio)-1)' / fs;

%% AUDIO ENVELOPE Impulsive events are far easier to see
markerIsImpact = strcmpi(DETECT_MODE, 'manual') && strcmpi(MANUAL_MARKER_MODE, 'impact');
markerIsBuzzer = strcmpi(DETECT_MODE, 'auto') || ...
                 (strcmpi(DETECT_MODE, 'manual') && strcmpi(MANUAL_MARKER_MODE, 'buzzer'));

sig = audio;
bandUsed = false;
if markerIsBuzzer && ~isempty(BUZZER_FREQ_HZ)
    lo = max(50, BUZZER_FREQ_HZ - BUZZER_BAND_HZ);
    hi = min(fs/2 - 100, BUZZER_FREQ_HZ + BUZZER_BAND_HZ);
    try
        sig = bandpass(audio, [lo hi], fs);
        bandUsed = true;
        fprintf('Band-passed %.0f-%.0f Hz around the buzzer.\n', lo, hi);
    catch
        fprintf(['Band-pass unavailable (Signal Processing Toolbox), ' ...
                 'using broadband envelope instead.\n']);
    end
end

envWin   = max(1, round(0.010 * fs));
envRaw   = movmean(abs(sig),   envWin);
envBroad = movmean(abs(audio), envWin);
env      = envRaw / max(envRaw + eps);

if bandUsed
    tonality = envRaw ./ (envBroad + eps);
else
    tonality = ones(size(envRaw));
end

%% FIND DROP MARKERS
switch lower(DETECT_MODE)

    case 'auto'
        minSep = MIN_SEPARATION_S;
        if isempty(minSep), minSep = CLIP_DURATION_S; end

        thr = DETECT_THRESHOLD;
        if isempty(thr)
            base = median(env);
            thr  = base + 0.35 * (prctile(env, 99.5) - base);
        end

        tonGate = BUZZER_TONALITY_MIN;
        if ~bandUsed && tonGate > 0
            fprintf(['Tonality check skipped (needs the band-pass). Loud ' ...
                     'non-buzzer noises may appear as false drops - check ' ...
                     'the confirmation plot carefully.\n']);
            tonGate = 0;
        end

        [markers, nRejected] = detect_onsets(env, tAudio, thr, minSep, ...
                                             tonality, tonGate, fs);
        fprintf('\nAuto-detected %d buzzer event(s) (threshold %.3f).\n', ...
            numel(markers), thr);
        if nRejected > 0
            fprintf('  (%d loud event(s) rejected as non-tonal - splashes, bangs etc.)\n', ...
                nRejected);
        end

        if isempty(markers)
            error(['No buzzer events found. Check BUZZER_FREQ_HZ matches ' ...
                'your buzzer, lower DETECT_THRESHOLD, lower ' ...
                'BUZZER_TONALITY_MIN, or run once in ''manual'' mode to ' ...
                'see what the audio actually looks like.']);
        end

        if numel(markers) > 2
            gaps = diff(markers);
            medGap = median(gaps);
            suspicious = find(gaps > 1.6 * medGap);
            for k = suspicious(:)'
                warning(['Large gap (%.2f s vs typical %.2f s) between ' ...
                    'detections %d and %d - a drop may have been MISSED ' ...
                    'there. It will simply be absent from the results.'], ...
                    gaps(k), medGap, k, k+1);
            end
        end

        if ~isempty(EXPECTED_DROPS) && numel(markers) ~= EXPECTED_DROPS
            warning(['Detected %d drops but you expected %d. Undetected ' ...
                'drops are OMITTED, so output numbering will not match ' ...
                'your session notes - check the confirmation plot.'], ...
                numel(markers), EXPECTED_DROPS);
        end

    case 'manual'
        markers = click_markers(tAudio, env, duration, MANUAL_MARKER_MODE);

    otherwise
        error('DETECT_MODE must be ''manual'' or ''auto'' (got ''%s'').', DETECT_MODE);
end

%% BUILD CLIP WINDOWS + CONFIRM
if markerIsImpact
    releaseTimes = nan(numel(markers), 1);
    leadS = EXPECTED_FALL_TIME_S + BACKGROUND_LEAD_S;
    startTimes = max(0, markers(:) - leadS);
    endTimes   = min(duration, markers(:) + POST_IMPACT_S);
elseif markerIsBuzzer
    releaseTimes = markers(:) - BUZZER_LAG_S;
    startTimes = max(0, releaseTimes - PRE_PAD_S);
    endTimes   = min(duration, releaseTimes + CLIP_DURATION_S);
else
    releaseTimes = markers(:);
    startTimes = max(0, releaseTimes - PRE_PAD_S);
    endTimes   = min(duration, releaseTimes + CLIP_DURATION_S);
end

keep = (endTimes - startTimes) > 0.1;
if any(~keep)
    warning('Dropping %d marker(s) too close to the ends of the recording.', sum(~keep));
end
markers = markers(keep); startTimes = startTimes(keep); endTimes = endTimes(keep);
releaseTimes = releaseTimes(keep);
nClips = numel(markers);

if markerIsBuzzer && nClips > 0
    truncated = (releaseTimes - PRE_PAD_S) < 0;
    if any(truncated)
        warning(['%d clip(s) start before the recording does: the beep ' ...
            'landed within %.2f s of t=0, so release - PRE_PAD_S is ' ...
            'negative and the start of those falls is not in the file. ' ...
            'Check them before trusting the results.'], ...
            sum(truncated), BUZZER_LAG_S + PRE_PAD_S);
    end
end

markerLabel = 'buzzer';
if strcmpi(DETECT_MODE, 'manual'), markerLabel = MANUAL_MARKER_MODE; end

fprintf('\n--- Proposed clips (marker = %s) ---\n', markerLabel);
if markerIsBuzzer
    fprintf('    buzzer lag %.3f s -> release = buzzer - lag\n', BUZZER_LAG_S);
    for i = 1:nClips
        fprintf('  %s%02d : %7.3f s -> %7.3f s  (buzzer %7.3f s, release %7.3f s)\n', ...
            OUTPUT_PREFIX, i, startTimes(i), endTimes(i), markers(i), releaseTimes(i));
    end
else
    for i = 1:nClips
        fprintf('  %s%02d : %7.3f s -> %7.3f s  (marker %7.3f s)\n', ...
            OUTPUT_PREFIX, i, startTimes(i), endTimes(i), markers(i));
    end
end

figure('Name', 'Drop markers - check before cutting', 'Color', 'w', ...
    'Units', 'normalized', 'Position', [0.05 0.3 0.9 0.5]);
plot(tAudio, env, 'Color', [0.3 0.4 0.7]); hold on;
for i = 1:nClips
    xline(markers(i), 'r-', sprintf('%d', i), 'LineWidth', 1.2);
    if ~isnan(releaseTimes(i))
        xline(releaseTimes(i), 'g--', 'LineWidth', 1.4);
    end
    patch([startTimes(i) endTimes(i) endTimes(i) startTimes(i)], ...
          [0 0 1 1], [1 0.6 0.2], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
end
if strcmpi(DETECT_MODE, 'auto')
    yline(thr, 'k--', 'threshold');
end
xlabel('Time (s)'); ylabel('Normalised envelope');
if markerIsBuzzer
    title(sprintf(['%d clip(s). Red = buzzer, GREEN DASHED = release ' ...
        '(buzzer - %.2f s), shaded = clip window.%s'], ...
        nClips, BUZZER_LAG_S, ternary(bandUsed, ' Band-passed.', '')));
else
    title(sprintf('%d clip(s). Red = %s marker, shaded = clip window.%s', ...
        nClips, markerLabel, ternary(bandUsed, ' Band-passed.', '')));
end
grid on; hold off; drawnow;

resp = input(sprintf('\nCut %d clip(s)? Re-encoding takes a few seconds each. [y/N]: ', nClips), 's');
if ~strcmpi(strtrim(resp), 'y')
    fprintf('Aborted - nothing was written.\n');
    return;
end

%% CUT
if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

clipFiles = cell(1, nClips);
fprintf('\nCutting...\n');
for i = 1:nClips
    out = fullfile(OUTPUT_DIR, sprintf('%s%02d.mp4', OUTPUT_PREFIX, i));
    cut_exact(ffmpeg, VIDEO_FILE, out, startTimes(i), endTimes(i), ...
              FPS, CRF, KEEP_AUDIO);
    clipFiles{i} = out;
    fprintf('  [%2d/%2d] %s\n', i, nClips, out);
end

%% SAVE METADATA DropTracking uses markerTimes to weight the pre/post calibration by when each drop
clips.sourceVideo   = VIDEO_FILE;
clips.files         = clipFiles;
clips.markerTimes   = markers(:)';
clips.releaseTimes  = releaseTimes(:)';
clips.buzzerLeadS   = BUZZER_LAG_S;  % [] would be meaningless here
clips.startTimes    = startTimes(:)';
clips.endTimes      = endTimes(:)';
clips.fps           = FPS;
clips.trueFps       = trueFps;
clips.preRollS      = PRE_PAD_S;
clips.detectMode    = DETECT_MODE;
clips.markerMeans   = markerLabel;  % what markerTimes actually marks - 'buzzer', 'release', or 'impact'
clips.sessionSpanS  = [min(markers), max(markers)];
clips.createdAt     = datestr(now);  %#ok<TNOW1,DATST>

metaFile = fullfile(OUTPUT_DIR, 'clips.mat');
save(metaFile, 'clips');

fprintf('\nWrote %d clip(s) + %s\n', nClips, metaFile);
fprintf('=== Complete ===\n');

%% LOCAL FUNCTIONS
function ff = locate_ffmpeg(explicitPath)
% MATLAB launched from the Dock/Start menu does not inherit the shell PATH
    if ~isempty(explicitPath)
        if exist(explicitPath, 'file') ~= 2
            error('FFMPEG_BIN is set to "%s" but no file exists there.', explicitPath);
        end
        ff = explicitPath; return;
    end

    if system('ffmpeg -version >/dev/null 2>&1') == 0
        ff = 'ffmpeg'; return;
    end

    candidates = {'/opt/homebrew/bin/ffmpeg', ...  % Apple Silicon Homebrew
                  '/usr/local/bin/ffmpeg',   ...
                  '/usr/bin/ffmpeg', ...
                  'C:\ffmpeg\bin\ffmpeg.exe'};
    for k = 1:numel(candidates)
        if exist(candidates{k}, 'file') == 2
            ff = candidates{k};
            fprintf('Found ffmpeg at %s (not on MATLAB''s PATH).\n', ff);
            return;
        end
    end

    error(['ffmpeg not found.\n' ...
        'In a TERMINAL run:  which ffmpeg\n' ...
        '  - if it prints a path, put that path in FFMPEG_BIN at the top ' ...
        'of this script (MATLAB does not inherit your terminal PATH).\n' ...
        '  - if it prints nothing, install it:  brew install ffmpeg  (Mac) ' ...
        'or  winget install ffmpeg  (Windows).']);
end

function [a, fs] = read_mono_audio(videoFile)
    try
        [x, fs] = audioread(videoFile);
    catch ME
        error(['Could not read audio from "%s". The splitter needs an ' ...
            'audio track to locate the drops.\nUnderlying error: %s'], ...
            videoFile, ME.message);
    end
    if size(x,2) > 1, a = mean(x,2); else, a = x; end
end

function [m, nRejected] = detect_onsets(env, t, thr, minSepS, tonality, tonMin, fs)
% Rising-edge crossings of the threshold, gated on tonality
    above = env > thr;
    rise  = find(above(2:end) & ~above(1:end-1)) + 1;

    win = max(1, round(0.040 * fs));
    m = [];
    nRejected = 0;
    lastT = -inf;
    for k = rise(:)'
        if tonMin > 0
            seg = tonality(k : min(numel(tonality), k + win));
            if median(seg) < tonMin
                nRejected = nRejected + 1;  % loud, but not the buzzer
                continue;
            end
        end
        if t(k) - lastT >= minSepS
            m(end+1) = t(k);  %#ok<AGROW>
            lastT = t(k);
        end
    end
end

function m = click_markers(t, env, duration, markerMode)
% One click per drop, on the envelope
    switch lower(markerMode)
        case 'buzzer'
            instr = 'the BUZZER BEEP (the fall already happened, 1.75 s BEFORE it)';
        case 'impact'
            instr = 'the LOUD IMPACT spike (object hitting the bottom)';
        otherwise
            instr = 'the release sound';
    end

    fig = figure('Name', 'Click ONCE per drop', 'Color', 'w', ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.05 0.25 0.9 0.55]);
    plot(t, env, 'Color', [0.3 0.4 0.7]); grid on;
    xlim([0 duration]);
    xticks(0:5:duration);
    xtickangle(90);
    grid on; grid minor;
    xlabel('Time (s)'); ylabel('Normalised envelope');
    title(sprintf('Click ONCE at each drop, on %s. Press ENTER when finished.', instr));

    fprintf('\nClick once per drop on %s, then press ENTER in the figure.\n', instr);
    hold on;
    m = [];
    while true
        [x, ~, btn] = ginput(1);
        if isempty(x) || isempty(btn), break; end
        x = min(max(x, 0), duration);
        m(end+1) = x;  %#ok<AGROW>
        xline(x, 'r-', sprintf('%d', numel(m)), 'LineWidth', 1.2);
        fprintf('  drop %2d at %.3f s\n', numel(m), x);
    end
    hold off;
    close(fig);

    if isempty(m)
        error('No drops were clicked.');
    end
    m = sort(m);
end

function cut_exact(ffmpeg, inFile, outFile, startT, endT, fps, crf, keepAudio)
% Frame-accurate cut. -ss AFTER -i forces an accurate (decode-and-discard) seek rather than a keyframe snap
    if keepAudio, aflag = ''; else, aflag = '-an'; end

    cmd = sprintf(['"%s" -y -i "%s" -ss %.4f -to %.4f %s ' ...
                   '-c:v libx264 -preset fast -crf %d -pix_fmt yuv420p ' ...
                   '-r %g "%s"'], ...
                   ffmpeg, inFile, startT, endT, aflag, crf, fps, outFile);

    [status, cmdout] = system(cmd);
    if status ~= 0
        error('ffmpeg failed writing %s:\n%s', outFile, cmdout);
    end

    info = dir(outFile);
    if isempty(info) || info.bytes < 10000
        error(['ffmpeg reported success but %s is missing or almost empty. ' ...
            'Check the requested window (%.3f-%.3f s) is inside the ' ...
            'recording.'], outFile, startT, endT);
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
