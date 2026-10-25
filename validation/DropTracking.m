%% DropTracking
% Tracks a falling object through fluid in a single-camera recording
clear; clc; close all;

%% CONFIGURATION
CALIB_FILE = 'calibration.mat';
CLIPS_DIR  = 'drop_clips';
CLIPS_META = fullfile(CLIPS_DIR, 'clips.mat');

MEDIUM = 'water';  % Must match calib.medium in calibration.mat

FPS = 60;  % verified against each clip

% Which clips
BATCH_MODE  = true;  % true = every clip listed in clips.mat false = SINGLE_CLIP only
SINGLE_CLIP = '';  % e.g. 'drop_clips/drop01.mp4' (BATCH_MODE=false)

% Region of interest
ROI_FILE     = fullfile(CLIPS_DIR, 'roi.mat');
REDEFINE_ROI = false;  % true = redraw even if roi.mat exists

% Object
OBJECT_TYPE = 'sphere';  % 'sphere' | 'disk' | 'rod' | 'any' Sets sensible area/circularity bounds

OBJECT_DIAMETER_MM = 8.0;  % sphere diameter, disk diameter, or rod diameter
OBJECT_MASS_G      = [];  % preferred - weigh it
OBJECT_DENSITY_KGM3 = 7800;  % steel ~7800
OBJECT_LENGTH_MM   = [];  % rods only, for volume/frontal area

% Fluid (for drag coefficient and Reynolds number)
FLUID_DENSITY_KGM3  = 998;  % water ~998
FLUID_VISCOSITY_PAS = 1.002e-3;  % water ~1.002e-3 Pa.s at 20 C. Pure glycerin ~1.41

% Detection tuning
DIFF_THRESHOLD   = 15;  % gray-level change vs background
MERGE_RADIUS_PX  = 7;  % closing disk that fuses a glint-split object
N_BG_FRAMES      = 5;  % frames averaged for the background model
BG_START_FRAME   = 1;  % move later if the clip opens mid-motion

% Blob area window
AREA_LIMITS_PX  = [];  % [] = derive automatically from OBJECT_DIAMETER_MM and the calibration scale
AREA_FLOOR_FRAC = 0.10;  % floor as a fraction of geometric area
AREA_CEIL_FRAC  = 8.0;  % ceiling as a multiple of geometric area

MAX_JUMP_PX      = 250;  % continuity gate per frame step

MOTION_THRESHOLD_PX = 5;  % px/frame below which the object counts as "landed", used to trim the settled tail

FLICKER_CORRECTION   = true;  % mains-LED banding
TRIM_STATIONARY_TAIL = true;

% Analysis
IMPACT_WINDOW_S   = 0.10;  % final window used for the impact-velocity fit
TERMINAL_TOL_PCT  = 5.0;  % speed change over the last third below which the fall counts as having reached...

% Output
SAVE_PLOTS    = true;
SHOW_PLOTS    = true;
WRITE_PREVIEW = true;  % master on/off switch for annotated videos
WRITE_PREVIEW_CLIPS = [1 2];  % which clip indices
RESULTS_MAT   = fullfile(CLIPS_DIR, 'tracking_results.mat');

%% LOAD CALIBRATION + CLIP LIST
if exist(CALIB_FILE, 'file') ~= 2
    error('Cannot find %s - run CalibrateCamera.m first.', CALIB_FILE);
end
S = load(CALIB_FILE, 'calib');
calib = S.calib;

if ~strcmpi(calib.medium, MEDIUM)
    error(['MEDIUM MISMATCH: this script is set to "%s" but %s was made ' ...
        'for "%s".\nRefractive index differs between fluids (water 1.333 ' ...
        'vs glycerin 1.473), so using the wrong calibration would put ' ...
        'roughly 10%% on every velocity with no visible symptom. Either ' ...
        'change MEDIUM or calibrate for this fluid.'], ...
        MEDIUM, CALIB_FILE, calib.medium);
end

fprintf('Calibration: %s | %.4f px/mm | RMSE %.2f px | drift %+.2f%%\n', ...
    calib.medium, calib.pre.scale_px_per_mm, calib.pre.rmse_px, calib.drift.scale_pct);
if calib.drift.flagged
    fprintf('  NOTE: drift was flagged. Both pre-only and adjusted results are reported.\n');
end

haveMeta = exist(CLIPS_META, 'file') == 2;
if haveMeta
    M = load(CLIPS_META, 'clips');
    clips = M.clips;
else
    clips = struct();
    fprintf(['No clips.mat found - drift will be interpolated assuming ' ...
             'drops were evenly spaced through the session.\n']);
end

if BATCH_MODE
    if ~haveMeta
        error('BATCH_MODE needs %s. Run AudioSplit.m, or set BATCH_MODE=false.', CLIPS_META);
    end
    clipFiles = clips.files;
else
    if isempty(SINGLE_CLIP), error('BATCH_MODE is false but SINGLE_CLIP is empty.'); end
    clipFiles = {SINGLE_CLIP};
end
nClips = numel(clipFiles);
fprintf('Processing %d clip(s).\n', nClips);

fracs = drift_fractions(clips, haveMeta, nClips, BATCH_MODE);

%% REGION OF INTEREST (drawn once, reused)
if ~REDEFINE_ROI && exist(ROI_FILE, 'file') == 2
    R = load(ROI_FILE, 'roi');
    roi = R.roi;
    fprintf('ROI (reused): [%d %d %d %d]\n', roi);
else
    roi = pick_roi(clipFiles{1});
    if ~exist(CLIPS_DIR, 'dir'), mkdir(CLIPS_DIR); end
    save(ROI_FILE, 'roi');
    fprintf('ROI saved to %s\n', ROI_FILE);
end

%% BLOB AREA WINDOW Derived from the object's REAL size via the calibration scale
scalePxPerMm  = calib.pre.scale_px_per_mm;
expectedPx    = OBJECT_DIAMETER_MM * scalePxPerMm;
geomAreaPx    = (pi/4) * expectedPx^2;

if isempty(AREA_LIMITS_PX)
    areaLimits = [AREA_FLOOR_FRAC * geomAreaPx, AREA_CEIL_FRAC * geomAreaPx];
    areaSource = 'auto';
else
    areaLimits = AREA_LIMITS_PX(:)';
    areaSource = 'manual override';
end

fprintf(['Object: %.1f mm at %.3f px/mm -> %.1f px across, %.0f px^2 geometric\n' ...
         'Blob area window (%s): [%.0f  %.0f] px^2\n'], ...
    OBJECT_DIAMETER_MM, scalePxPerMm, expectedPx, geomAreaPx, ...
    areaSource, areaLimits(1), areaLimits(2));

if expectedPx < 8
    warning('DropTracking:tinyObject', ...
        ['The object is only %.1f px across at this calibration. Centroids ' ...
         'will be dominated by pixel noise. Move the camera closer, or ' ...
         'accept that velocities from this drop are low-confidence.'], expectedPx);
end

%% PROCESS EVERY CLIP
opts = struct( ...
    'object_type',           OBJECT_TYPE, ...
    'diff_threshold',        DIFF_THRESHOLD, ...
    'merge_radius_px',       MERGE_RADIUS_PX, ...
    'n_bg_frames',           N_BG_FRAMES, ...
    'bg_start_frame',        BG_START_FRAME, ...
    'roi',                   roi, ...
    'max_jump_px',           MAX_JUMP_PX, ...
    'flicker_correction',    FLICKER_CORRECTION, ...
    'trim_stationary_tail',  TRIM_STATIONARY_TAIL, ...
    'motion_threshold_px',   MOTION_THRESHOLD_PX, ...
    'area_limits_px',        areaLimits, ...
    'stationary_min_frames', 10);

allResults = cell(1, nClips);
Drop        = (1:nClips)';
status      = strings(nClips,1);
v_term_pre  = nan(nClips,1);
v_term_adj  = nan(nClips,1);
v_impact    = nan(nClips,1);
Cd_meas     = nan(nClips,1);
Re_meas     = nan(nClips,1);
nFrames     = nan(nClips,1);

for i = 1:nClips
    fprintf('\n=== Drop %d / %d: %s ===\n', i, nClips, clipFiles{i});
    try
        r = process_clip(clipFiles{i}, FPS, opts, calib, fracs(i), ...
                IMPACT_WINDOW_S, TERMINAL_TOL_PCT, ...
                OBJECT_TYPE, OBJECT_DIAMETER_MM, OBJECT_LENGTH_MM, ...
                OBJECT_MASS_G, OBJECT_DENSITY_KGM3, ...
                FLUID_DENSITY_KGM3, FLUID_VISCOSITY_PAS);

        if WRITE_PREVIEW && ismember(i, WRITE_PREVIEW_CLIPS)
            pf = fullfile(CLIPS_DIR, sprintf('drop%02d_tracked.mp4', i));
            fprintf('  Rendering verification preview -> %s\n', pf);
            render_preview(clipFiles{i}, pf, r.cx_px, r.cy_px, FPS, roi);
        end

        if SAVE_PLOTS || SHOW_PLOTS
            pp = '';
            if SAVE_PLOTS, pp = fullfile(CLIPS_DIR, sprintf('drop%02d_plot.png', i)); end
            make_plots(r, i, clipFiles{i}, pp, SHOW_PLOTS);
        end

        allResults{i} = r;
        v_term_pre(i) = r.pre.v_terminal_mm_s / 1e3;
        v_term_adj(i) = r.adj.v_terminal_mm_s / 1e3;
        v_impact(i)   = r.adj.v_impact_mm_s   / 1e3;
        Cd_meas(i)    = r.drag.Cd;
        Re_meas(i)    = r.drag.Re;
        nFrames(i)    = numel(r.t_s);
        status(i)     = "ok";
    catch ME
        warning('Drop %d failed: %s', i, ME.message);
        status(i) = "FAILED: " + string(ME.message);
    end
end

%% SUMMARY
summary = table(Drop, status, v_term_pre, v_term_adj, v_impact, ...
                Cd_meas, Re_meas, nFrames);
summary.Properties.VariableNames = {'Drop','Status','vTerm_pre_m_s', ...
    'vTerm_adj_m_s','vImpact_m_s','Cd','Re','Frames'};

fprintf('\n================ SUMMARY (%d drops) ================\n', nClips);
disp(summary);

ok = status == "ok";
if any(ok)
    fprintf('Terminal velocity (drift-adjusted): mean %.4f m/s, std %.4f m/s over %d drop(s)\n', ...
        mean(v_term_adj(ok), 'omitnan'), std(v_term_adj(ok), 'omitnan'), sum(ok));

    d = v_term_adj(ok) - v_term_pre(ok);
    rel = 100 * mean(abs(d), 'omitnan') / max(mean(v_term_pre(ok), 'omitnan'), eps);
    fprintf('Drift correction changed terminal velocity by %.3f%% on average.\n', rel);
    if rel < 0.1
        fprintf('  -> Negligible; the rig was stable across the session.\n');
    end

    fprintf('Drag: mean Cd %.3f, mean Re %.1f\n', ...
        mean(Cd_meas(ok), 'omitnan'), mean(Re_meas(ok), 'omitnan'));

    if strcmpi(OBJECT_TYPE, 'sphere')
        ReM = mean(Re_meas(ok), 'omitnan');
        CdM = mean(Cd_meas(ok), 'omitnan');
        [CdRef, refValid, tolPct] = sphere_drag_reference(ReM);
        fprintf('\nSphere drag check at Re = %.1f (Brown & Lawler correlation):\n', ReM);
        if refValid
            devPct = 100*(CdM - CdRef)/CdRef;
            fprintf('  reference Cd %.3f | measured Cd %.3f | deviation %+.1f%%\n', ...
                CdRef, CdM, devPct);
            if abs(devPct) <= tolPct
                fprintf(['  -> AGREES within the %.0f%% scatter expected for this\n' ...
                         '     correlation. This is an INDEPENDENT validation: calibration,\n' ...
                         '     tracking and velocity extraction all have to be right to\n' ...
                         '     match a published drag curve.\n'], tolPct);
            else
                fprintf(['  -> Outside the %.0f%% scatter expected for this correlation.\n' ...
                         '     Check the calibration scale, SQUARE_SIZE_MM, and the fluid\n' ...
                         '     density and viscosity you entered.\n'], tolPct);
            end
        else
            fprintf('  No reliable published correlation at this Re - comparison skipped.\n');
        end
    end
end

save(RESULTS_MAT, 'allResults', 'summary', 'calib', 'opts');
fprintf('\nSaved results: %s\n', RESULTS_MAT);
fprintf('=== Complete ===\n');

%% PROCESSING
function r = process_clip(videoFile, fps, opts, calib, frac, impactWinS, ...
        termTolPct, objType, diaMm, lenMm, massG, densKgm3, fluidRho, fluidMu)

    [cx, cy, t_vec, diag] = detect_object(videoFile, fps, opts);

    valid = ~isnan(cx) & ~isnan(cy);
    if sum(valid) < 5
        error(['Only %d detections.\n' ...
            '  DETECTOR DIAGNOSTICS\n' ...
            '    candidate blobs found     : %d\n' ...
            '    largest blob seen         : %.0f px^2   (area window [%.0f %.0f])\n' ...
            '    highest circularity seen  : %.2f        (minimum %.2f)\n' ...
            '    rejected on AREA          : %d\n' ...
            '    rejected on CIRCULARITY   : %d\n' ...
            '  %s'], ...
            sum(valid), diag.nBlobs, diag.maxAreaSeen, diag.areaLim(1), ...
            diag.areaLim(2), diag.maxCircSeen, diag.circMin, ...
            diag.nRejArea, diag.nRejCirc, detector_hint(diag));
    end

    t  = t_vec(valid);
    px = [cx(valid), cy(valid)];

    % pixels -> millimetres, twice
    mm_pre  = transformPointsForward(calib.pre.tform,  px);
    mm_post = transformPointsForward(calib.post.tform, px);
    mm_adj  = (1 - frac) * mm_pre + frac * mm_post;

    r.video   = videoFile;
    r.t_s     = t;
    r.cx_px   = cx;   r.cy_px = cy;
    r.frac    = frac;
    r.pre     = kinematics(t, mm_pre, impactWinS, termTolPct);
    r.adj     = kinematics(t, mm_adj, impactWinS, termTolPct);

    fprintf('  Detections %d | terminal %s | impact %.3f m/s\n', ...
        numel(t), fmt_terminal(r.adj.v_terminal_mm_s), r.adj.v_impact_mm_s/1e3);

    ang = atan2d(r.adj.down_dir(1), r.adj.down_dir(2));
    fprintf('  Fall direction is %.1f deg off the board''s vertical axis\n', abs(ang));
    if abs(ang) > 10
        fprintf(['    -> over 10 deg. Either the board mount is tilted, or the\n' ...
                 '       object is drifting sideways. Worth checking.\n']);
    end
    r.fall_angle_deg = ang;

    % drag
    r.drag = drag_metrics(r.adj.v_terminal_mm_s, objType, diaMm, lenMm, ...
                          massG, densKgm3, fluidRho, fluidMu);
    if ~isnan(r.drag.Cd)
        fprintf('  Cd = %.3f | Re = %.1f\n', r.drag.Cd, r.drag.Re);
    else
        fprintf('  Cd/Re not computed (terminal velocity was not reached).\n');
    end
end

function K = kinematics(t, mm, impactWinS, termTolPct)
% Velocity profile, terminal velocity and impact velocity from a millimetre-space trajectory

    X = mm(:,1); Y = mm(:,2);

    vX = gradient(X, t);
    vY = gradient(Y, t);

    w = min(11, numel(vX));
    if mod(w,2) == 0, w = w - 1; end
    if numel(vX) > 15 && w >= 5
        try
            vX = sgolayfilt(vX, 3, w);
            vY = sgolayfilt(vY, 3, w);
        catch
        end
    end
    speed = hypot(vX, vY);

    disp_vec = [X(end)-X(1), Y(end)-Y(1)];
    down_dir = disp_vec / max(norm(disp_vec), eps);

    tRel = t - t(1);
    i3 = tRel >= (2/3) * tRel(end);
    v_terminal = NaN;
    if sum(i3) >= 5
        p = polyfit(tRel(i3), speed(i3), 1);
        changePct = 100 * abs(p(1) * (tRel(end)/3)) / max(mean(speed(i3)), eps);
        if changePct < termTolPct
            v_terminal = mean(speed(i3));
        end
        K.terminal_change_pct = changePct;
    else
        K.terminal_change_pct = NaN;
    end

    dt = median(diff(t));
    n = max(5, round(impactWinS / max(dt, eps)));
    n = min(n, numel(t));
    ii = numel(t)-n+1 : numel(t);
    A = [ones(n,1), t(ii)-t(ii(1))];
    cxw = A \ X(ii);  cyw = A \ Y(ii);
    v_impact = hypot(cxw(2), cyw(2));

    K.t_to_terminal_s = NaN; K.dist_to_terminal_mm = NaN;
    if ~isnan(v_terminal)
        near = abs(speed - v_terminal) <= 0.05 * v_terminal;
        k = find(near, 1, 'first');
        if ~isempty(k) && all(near(k:end))
            K.t_to_terminal_s   = tRel(k);
            K.dist_to_terminal_mm = hypot(X(k)-X(1), Y(k)-Y(1));
        end
    end

    Aq = [ones(size(tRel)), tRel, 0.5*tRel.^2];
    cX = Aq \ X;  cY = Aq \ Y;
    resid = hypot(X - Aq*cX, Y - Aq*cY);

    K.X_mm = X;  K.Y_mm = Y;
    K.vX_mm_s = vX;  K.vY_mm_s = vY;
    K.speed_mm_s = speed;
    K.down_dir = down_dir;
    K.v_terminal_mm_s = v_terminal;
    K.v_impact_mm_s   = v_impact;
    K.impact_idx      = ii;
    K.quadfit_rmse_mm = sqrt(mean(resid.^2));
end

function D = drag_metrics(vTermMmS, objType, diaMm, lenMm, massG, densKgm3, rhoF, muF)
% Drag coefficient and Reynolds number from terminal velocity
    D = struct('Cd', NaN, 'Re', NaN, 'volume_m3', NaN, 'area_m2', NaN, 'mass_kg', NaN);
    if isnan(vTermMmS) || vTermMmS <= 0, return; end

    v = vTermMmS / 1e3;  % m/s
    d = diaMm / 1e3;
    g = 9.81;

    switch lower(objType)
        case 'sphere'
            V = (pi/6) * d^3;
            A = (pi/4) * d^2;
        case 'disk'
            if isempty(lenMm)
                warning('OBJECT_LENGTH_MM (disk thickness) not set - Cd not computed.');
                return;
            end
            V = (pi/4) * d^2 * (lenMm/1e3);
            A = (pi/4) * d^2;
        case 'rod'
            if isempty(lenMm)
                warning('OBJECT_LENGTH_MM not set - Cd not computed.');
                return;
            end
            L = lenMm/1e3;
            V = (pi/4) * d^2 * L;
            A = d * L;  % assumes broadside-on
        otherwise
            return;
    end

    if ~isempty(massG)
        m = massG / 1e3;
    else
        m = densKgm3 * V;
    end

    net = m - rhoF * V;  % effective mass after buoyancy
    if net <= 0
        warning('Object is buoyant in this fluid (it would float) - Cd not computed.');
        return;
    end

    D.Cd        = 2 * net * g / (rhoF * A * v^2);
    D.Re        = rhoF * v * d / muF;
    D.volume_m3 = V;
    D.area_m2   = A;
    D.mass_kg   = m;
end

function [Cd, valid, tolPct] = sphere_drag_reference(Re)
% Published sphere-drag reference via Brown & Lawler (2003)
    if Re <= 0
        Cd = NaN; valid = false; tolPct = NaN;
    elseif Re <= 2e5
        Cd = (24/Re) * (1 + 0.150*Re^0.681) + 0.407/(1 + 8710/Re);
        valid = true; tolPct = 15;  % literature scatter across the fitted range
    else
        Cd = NaN; valid = false; tolPct = NaN;  % beyond the fitted range (post drag-crisis)
    end
end

function f = drift_fractions(clips, haveMeta, n, batchMode)
% Where each drop sits between the pre and post calibrations, on [0,1]
    if haveMeta && batchMode && isfield(clips, 'markerTimes') && numel(clips.markerTimes) >= n
        m = clips.markerTimes(1:n);
        if max(m) > min(m)
            f = (m - min(m)) / (max(m) - min(m));
        else
            f = zeros(1, n);
        end
    else
        if n > 1, f = linspace(0, 1, n); else, f = 0; end
    end
    f = f(:)';
end

function s = fmt_terminal(v)
    if isnan(v), s = 'not reached'; else, s = sprintf('%.3f m/s', v/1e3); end
end

function h = detector_hint(d)
% Turn the rejection tallies into the ONE thing most likely to fix it
    if d.nBlobs == 0
        h = ['LIKELY CAUSE: nothing crossed DIFF_THRESHOLD at all - the ' ...
             'object never appeared in the ROI, or contrast is too low. ' ...
             'Check the ROI covers the fall path, then lower ' ...
             'DIFF_THRESHOLD.'];
    elseif d.maxAreaSeen < d.areaLim(1)
        h = sprintf(['LIKELY CAUSE: every blob was SMALLER than the area ' ...
             'floor (biggest %.0f vs floor %.0f px^2). Check ' ...
             'OBJECT_DIAMETER_MM matches the object you actually dropped ' ...
             '- note it is a DIAMETER, not a radius. Failing that, lower ' ...
             'AREA_FLOOR_FRAC or set AREA_LIMITS_PX manually.'], ...
             d.maxAreaSeen, d.areaLim(1));
    elseif d.nRejArea > 0 && d.maxAreaSeen > d.areaLim(2)
        h = sprintf(['LIKELY CAUSE: blobs exceeded the area ceiling ' ...
             '(biggest %.0f vs ceiling %.0f px^2) - usually merged ' ...
             'reflections or a ripple. Tighten the ROI, or raise ' ...
             'AREA_CEIL_FRAC if the object really is that large.'], ...
             d.maxAreaSeen, d.areaLim(2));
    elseif d.nRejCirc > 0
        h = sprintf(['LIKELY CAUSE: blobs were the right SIZE but too ' ...
             'irregular (best circularity %.2f vs minimum %.2f). Motion ' ...
             'blur stretches a fast object into a streak - use a looser ' ...
             'OBJECT_TYPE (''any'' disables the shape test entirely).'], ...
             d.maxCircSeen, d.circMin);
    else
        h = ['Blobs passed size and shape but did not form a continuous ' ...
             'track - MAX_JUMP_PX may be too small for how fast this ' ...
             'object moves.'];
    end
end

%% DETECTION
function [cx_px, cy_px, t_vec, diag] = detect_object(video_file, fps, opts)
% Frame-difference detector with specular-split merging, shape filtering and anchor-and-walk continuity tracking

    switch lower(opts.object_type)
        case 'sphere', circMin = 0.30;
        case 'disk',   circMin = 0.10;
        case 'rod',    circMin = 0.03;
        case 'any',    circMin = 0.00;
        otherwise, error('Unknown OBJECT_TYPE: %s', opts.object_type);
    end
    areaLim = opts.area_limits_px;

    diag = struct('nBlobs', 0, 'maxAreaSeen', 0, 'maxCircSeen', 0, ...
                  'nRejArea', 0, 'nRejCirc', 0, 'areaLim', areaLim, ...
                  'circMin', circMin);

    vid = VideoReader(video_file);
    if abs(vid.FrameRate - fps) > 0.5
        warning('DropTracking:fps', ...
            ['%s reports %.2f fps but FPS is %g. Every velocity scales by ' ...
             'the ratio of those numbers. If this is slo-mo footage, check ' ...
             'you exported the UNMODIFIED original.'], video_file, vid.FrameRate, fps);
    end

    nFrames = floor(vid.Duration * fps);
    W = vid.Width; H = vid.Height;

    roi = opts.roi;
    if ~isempty(roi)
        roi = round(roi);
        roi(1) = max(1, min(roi(1), W-1));
        roi(2) = max(1, min(roi(2), H-1));
        roi(3) = max(1, min(roi(3), W-roi(1)));
        roi(4) = max(1, min(roi(4), H-roi(2)));
    end

    % background model
    vid.CurrentTime = max(0, (opts.bg_start_frame - 1) / fps);
    acc = []; nbg = 0;
    for k = 1:opts.n_bg_frames
        if ~hasFrame(vid), break; end
        fr = readFrame(vid);
        if ~isempty(roi), fr = imcrop(fr, roi); end
        g = double(rgb2gray(fr));
        if isempty(acc), acc = zeros(size(g)); end
        acc = acc + g; nbg = nbg + 1;
    end
    if nbg == 0
        error('BG_START_FRAME is past the end of %s.', video_file);
    end
    background = acc / nbg;

    seOpen  = strel('disk', 2);
    seClose = strel('disk', max(1, round(opts.merge_radius_px)));

    % pass 1: candidates in every frame
    cand = cell(nFrames,1);
    vid.CurrentTime = 0;
    f = 0;
    while hasFrame(vid)
        f = f + 1;
        if f > nFrames, break; end
        fr = readFrame(vid);
        if ~isempty(roi), fr = imcrop(fr, roi); end
        gray = double(rgb2gray(fr));

        d = gray - background;
        if opts.flicker_correction
            d = d - movmean(median(d, 2), 31);
        end

        mask = abs(d) > opts.diff_threshold;
        mask = imopen(mask, seOpen);
        mask = imclose(mask, seClose);
        mask = imfill(mask, 'holes');

        st = regionprops(mask, 'Centroid', 'Area', 'Perimeter');
        if isempty(st), continue; end
        A = [st.Area]';
        P = max([st.Perimeter]', eps);
        C = reshape([st.Centroid], 2, [])';
        circ = 4*pi*A ./ P.^2;

        okArea = A >= areaLim(1) & A <= areaLim(2);
        okCirc = circ >= circMin;
        diag.nBlobs      = diag.nBlobs + numel(A);
        diag.maxAreaSeen = max(diag.maxAreaSeen, max(A));
        diag.maxCircSeen = max(diag.maxCircSeen, max(circ));
        diag.nRejArea    = diag.nRejArea + sum(~okArea);
        diag.nRejCirc    = diag.nRejCirc + sum(okArea & ~okCirc);

        keep = okArea & okCirc;
        if any(keep)
            cand{f} = [C(keep,1), C(keep,2), A(keep)];
        end
    end
    nFrames = f;

    % pass 2: anchor, then walk outwards with continuity gating
    cx_px = nan(nFrames,1); cy_px = nan(nFrames,1);
    t_vec = (0:nFrames-1)' / fps;

    anchor = 0; aj = 0; best = 0;
    for k = 1:nFrames
        if isempty(cand{k}), continue; end
        [a, j] = max(cand{k}(:,3));
        if a > best, best = a; anchor = k; aj = j; end
    end

    if anchor > 0
        cx_px(anchor) = cand{anchor}(aj,1);
        cy_px(anchor) = cand{anchor}(aj,2);
        for dir = [1 -1]
            last = [cx_px(anchor), cy_px(anchor)];
            lastF = anchor;
            k = anchor + dir;
            while k >= 1 && k <= nFrames
                if ~isempty(cand{k})
                    allowed = opts.max_jump_px * abs(k - lastF);
                    dist = hypot(cand{k}(:,1)-last(1), cand{k}(:,2)-last(2));
                    in = find(dist <= allowed);
                    if ~isempty(in)
                        [~, b] = max(cand{k}(in,3));
                        j = in(b);
                        cx_px(k) = cand{k}(j,1);
                        cy_px(k) = cand{k}(j,2);
                        last = cand{k}(j,1:2); lastF = k;
                    end
                end
                k = k + dir;
            end
        end
    end

    if ~isempty(roi)
        cx_px = cx_px + roi(1) - 1;
        cy_px = cy_px + roi(2) - 1;
    end

    % trim the settled object
    if opts.trim_stationary_tail
        v = find(~isnan(cx_px));
        if numel(v) > opts.stationary_min_frames
            steps = hypot(diff(cx_px(v)), diff(cy_px(v)));
            lastMoving = find(steps > opts.motion_threshold_px, 1, 'last');
            if ~isempty(lastMoving) && (numel(v)-lastMoving) >= opts.stationary_min_frames
                kill = v(lastMoving+1:end);
                cx_px(kill) = NaN; cy_px(kill) = NaN;
                fprintf('    trimmed %d settled frames\n', numel(kill));
            end
        end
    end

    fprintf('    detected %d / %d frames\n', sum(~isnan(cx_px)), nFrames);
end

%% ROI / PREVIEW / PLOTS
function roi = pick_roi(videoFile)
% Drag a box around the fall path
    vid = VideoReader(videoFile);
    vid.CurrentTime = min(vid.Duration/2, max(0, vid.Duration - 1/vid.FrameRate));
    fr = readFrame(vid);

    hf = figure('Name', 'Drag the ROI', 'NumberTitle', 'off', ...
        'Units', 'normalized', 'Position', [0.15 0.08 0.7 0.84]);
    imshow(fr);
    title({'Drag a box around the object''s fall path.', ...
           'TOP edge BELOW the waterline; sides INSIDE the tank walls.'}, ...
           'FontWeight', 'bold');
    roi = round(getrect(hf));
    close(hf);

    if roi(3) < 20 || roi(4) < 20
        error('ROI too small (%dx%d px) - re-run and drag a larger box.', roi(3), roi(4));
    end
    fprintf('ROI: [%d %d %d %d]\n', roi);
end

function render_preview(inFile, outFile, cx, cy, fps, roi)
    rd = VideoReader(inFile);
    wr = VideoWriter(outFile, 'MPEG-4');
    wr.FrameRate = fps;
    open(wr);
    i = 0;
    while hasFrame(rd)
        i = i + 1;
        fr = readFrame(rd);
        if ~isempty(roi)
            fr = insertShape(fr, 'rectangle', roi, 'Color', 'yellow', 'LineWidth', 2);
        end
        if i <= numel(cx) && ~isnan(cx(i))
            fr = insertShape(fr, 'circle', [cx(i) cy(i) 25], ...
                'Color', 'red', 'LineWidth', 3, 'Opacity', 0.9);
            fr = insertMarker(fr, [cx(i) cy(i)], '+', 'Color', 'red', 'Size', 14);
        end
        writeVideo(wr, fr);
    end
    close(wr);
end

function make_plots(r, idx, videoFile, savePath, showIt)
    vis = 'off'; if showIt, vis = 'on'; end
    [~, lbl] = fileparts(videoFile);
    K = r.adj;
    tRel = r.t_s - r.t_s(1);

    fig = figure('Name', sprintf('Drop %d', idx), 'Color', 'w', 'Visible', vis, ...
        'Units', 'normalized', 'Position', [0.05 0.08 0.88 0.8]);

    subplot(2,2,1); hold on; grid on; box on;
    scatter(K.Y_mm, K.X_mm, 22, tRel, 'filled');
    c = colorbar; c.Label.String = 'Time (s)';
    xlabel('Y (mm) - across tank'); ylabel('X (mm) - down tank');
    title('Trajectory in the fall plane');
    axis equal; set(gca,'YDir','reverse');

    subplot(2,2,2); hold on; grid on; box on;
    plot(tRel, K.speed_mm_s/1e3, '-', 'LineWidth', 2, 'Color', [.85 .33 .2]);
    if ~isnan(K.v_terminal_mm_s)
        yline(K.v_terminal_mm_s/1e3, 'b--', ...
            sprintf('terminal %.3f m/s', K.v_terminal_mm_s/1e3), 'LineWidth', 1.5);
    end
    yline(K.v_impact_mm_s/1e3, 'k:', sprintf('impact %.3f m/s', K.v_impact_mm_s/1e3));
    xlabel('Time (s)'); ylabel('Speed (m/s)');
    title('Speed profile'); axis tight;

    subplot(2,2,3); hold on; grid on; box on;
    plot(tRel, K.vX_mm_s/1e3, '-', 'DisplayName', 'v_x (down tank)');
    plot(tRel, K.vY_mm_s/1e3, '-', 'DisplayName', 'v_y (across tank)');
    xlabel('Time (s)'); ylabel('Velocity (m/s)');
    legend('Location','best'); title('Velocity components');

    subplot(2,2,4); hold on; grid on; box on;
    plot(tRel, r.pre.speed_mm_s/1e3, '-',  'LineWidth', 1.5, 'DisplayName', 'pre-only');
    plot(tRel, K.speed_mm_s/1e3,     '--', 'LineWidth', 1.5, 'DisplayName', 'drift-adjusted');
    xlabel('Time (s)'); ylabel('Speed (m/s)');
    legend('Location','best');
    title('Effect of the calibration drift correction');

    ttl = sprintf('%s | terminal %s | Cd %.3f | Re %.1f', strrep(lbl,'_','\_'), ...
        fmt_terminal(K.v_terminal_mm_s), r.drag.Cd, r.drag.Re);
    sgtitle(ttl, 'FontWeight', 'bold');

    if ~isempty(savePath), saveas(fig, savePath); end
    if ~showIt, close(fig); end
end
