%% CalibrateCamera
% Checkerboard calibration for the single-camera drop rig
clear; clc; close all;

%% CONFIGURATION
SQUARE_SIZE_MM = 14.8;  % Measured across ~10 squares with calipers, then divided

MEDIUM = 'water';  % Free-text label for the fluid in the tank for this session, e.g. 'water'

PLANE_PRE  = 'BoardPre.MOV';  % filmed BEFORE the drops
PLANE_POST = 'BoardPost.MOV';  % filmed AFTER the drops
FRAMES_TO_AVG = 5;

EXPECTED_BOARD_SQUARES = [];  % Optional sanity check on detection: number of SQUARES on the printed board, e.g

DRIFT_WARN_SCALE_PCT = 1.0;  % warn if pre/post scale differs by more
DRIFT_WARN_SHIFT_PX  = 5.0;  % warn if board corners moved more

OUTPUT_MAT = 'calibration.mat';

%% FIT BOTH CALIBRATIONS
fprintf('=== Fall-plane calibration | medium: %s | square: %.3f mm ===\n', ...
    MEDIUM, SQUARE_SIZE_MM);

pre  = plane_calibration(PLANE_PRE,  SQUARE_SIZE_MM, FRAMES_TO_AVG, ...
                         EXPECTED_BOARD_SQUARES, 'PRE');
post = plane_calibration(PLANE_POST, SQUARE_SIZE_MM, FRAMES_TO_AVG, ...
                         EXPECTED_BOARD_SQUARES, 'POST');

%% DRIFT REPORT
fprintf('\n=== DRIFT: pre vs post ===\n');

if ~isequal(sort(pre.boardSize), sort(post.boardSize))
    error(['Pre and post detected DIFFERENT board sizes ([%d %d] vs ' ...
        '[%d %d]). One of them is a partial detection - most likely ' ...
        'glare or an occluded edge. Re-shoot that board image; the ' ...
        'drift comparison is meaningless until both match.'], ...
        pre.boardSize(1), pre.boardSize(2), post.boardSize(1), post.boardSize(2));
end

postPoints = post.imagePoints;
flipped = dot(pre.down_dir, post.down_dir) < 0;
if flipped
    warning(['Post board was detected 180 deg rotated relative to pre. ' ...
        'Reversing its corner order before comparing. If your board is ' ...
        'symmetric (even x even squares) this WILL happen unpredictably ' ...
        '- reprint with an even x odd square count.']);
    postPoints = flipud(postPoints);
end

scale_pct = 100 * (post.scale_px_per_mm - pre.scale_px_per_mm) / pre.scale_px_per_mm;

cornerShift = hypot(postPoints(:,1) - pre.imagePoints(:,1), ...
                    postPoints(:,2) - pre.imagePoints(:,2));
medShift = median(cornerShift);
maxShift = max(cornerShift);

fprintf('  Scale   pre %.4f px/mm | post %.4f px/mm | change %+.3f %%\n', ...
    pre.scale_px_per_mm, post.scale_px_per_mm, scale_pct);
fprintf('  Corner shift (same physical corners): median %.2f px, max %.2f px\n', ...
    medShift, maxShift);
fprintf('  Homography RMSE: pre %.3f px (%.3f mm) | post %.3f px (%.3f mm)\n', ...
    pre.rmse_px, pre.rmse_mm, post.rmse_px, post.rmse_mm);

driftFlag = false;
if abs(scale_pct) > DRIFT_WARN_SCALE_PCT
    warning('Scale drifted %+.2f%% (threshold %.2f%%).', scale_pct, DRIFT_WARN_SCALE_PCT);
    driftFlag = true;
end
if medShift > DRIFT_WARN_SHIFT_PX
    warning(['Board corners moved %.1f px median (threshold %.1f px) - ' ...
        'the camera was probably bumped during the session.'], medShift, DRIFT_WARN_SHIFT_PX);
    driftFlag = true;
end
if driftFlag
    fprintf(['  -> Drift exceeded a threshold. DropTracking will report BOTH\n' ...
             '     pre-only and drift-adjusted results so you can see its size.\n']);
else
    fprintf('  -> Drift within thresholds; interpolation will change little.\n');
end

worstRmse = max(pre.rmse_px, post.rmse_px);
fprintf('\n  RMSE check (this is what justifies having no distortion model):\n');
if worstRmse < 0.5
    fprintf('    %.3f px - EXCELLENT. Consistent with corner-detection noise\n', worstRmse);
    fprintf('    alone. A pure perspective model fits this framing; lens\n');
    fprintf('    distortion is not measurably affecting you.\n');
elseif worstRmse < 2.0
    fprintf('    %.3f px - ACCEPTABLE, but above the pure-noise floor, so\n', worstRmse);
    fprintf('    some model error is present. Usually a slightly bowed board\n');
    fprintf('    or one not quite in the fall plane. Worth a look, not fatal.\n');
else
    fprintf('    %.3f px - HIGH. For reference, ~3 px is what mild barrel\n', worstRmse);
    fprintf('    distortion produces. Check FIRST that the board is rigid,\n');
    fprintf('    flat and fully in the fall plane - that is the usual cause.\n');
    fprintf('    If it is, tell me and we add an intrinsics stage.\n');
end

%% VERIFICATION FIGURE
fig = figure('Name', 'Calibration check', 'Color', 'w', ...
    'Units', 'normalized', 'Position', [0.05 0.1 0.9 0.75]);

show_board(subplot(1,2,1), pre,  'PRE');
show_board(subplot(1,2,2), post, 'POST');

sgtitle(sprintf(['%s | square %.3f mm | scale %.3f px/mm | drift %+.2f%% | ' ...
    'RMSE %.2f / %.2f px'], MEDIUM, SQUARE_SIZE_MM, pre.scale_px_per_mm, ...
    scale_pct, pre.rmse_px, post.rmse_px), 'FontWeight', 'bold');

saveas(fig, 'calibration_check.png');
fprintf('\nSaved verification figure: calibration_check.png\n');
fprintf('  CHECK IT: green dots should sit exactly on the internal corners\n');
fprintf('  of the board, covering the region the object falls through.\n');

%% SAVE
calib.mode           = 'single';  % two-layer mode added later
calib.medium         = MEDIUM;
calib.squareSizeMm   = SQUARE_SIZE_MM;
calib.hasIntrinsics  = false;
calib.pre            = pre;
calib.post           = post;
calib.drift.scale_pct        = scale_pct;
calib.drift.corner_shift_med = medShift;
calib.drift.corner_shift_max = maxShift;
calib.drift.flagged          = driftFlag;
calib.drift.postFlipCorrected = flipped;
calib.createdAt      = datestr(now);  %#ok<TNOW1,DATST>

save(OUTPUT_MAT, 'calib');
fprintf('\nSaved %s\n=== Complete ===\n', OUTPUT_MAT);

%% LOCAL FUNCTIONS
function P = plane_calibration(fileName, squareSizeMm, nAvg, expectedSquares, label)
% Detect the board and fit an image -> millimetre homography for the plane it sits in

    fprintf('\n--- %s: %s ---\n', label, fileName);
    img = read_still(fileName, nAvg);

    [imagePoints, boardSize] = detectCheckerboardPoints(img);
    if isempty(imagePoints)
        error(['No checkerboard found in %s.\nCheck that: the whole board ' ...
            'is in frame, it is in focus, glare is not washing out the ' ...
            'squares, and the print is matte rather than glossy.'], fileName);
    end

    nCorners = size(imagePoints, 1);
    fprintf('  Detected %d x %d squares -> %d internal corners\n', ...
        boardSize(1), boardSize(2), nCorners);

    if ~isempty(expectedSquares)
        if ~isequal(sort(boardSize(:))', sort(expectedSquares(:))')
            warning(['Detected a %d x %d board but you expected %d x %d. ' ...
                'This is a PARTIAL detection - part of the board was ' ...
                'missed (usually glare or an edge cut off). The scale will ' ...
                'still be right but you lose coverage where it was missed.'], ...
                boardSize(1), boardSize(2), expectedSquares(1), expectedSquares(2));
        end
    end

    worldPoints = generateCheckerboardPoints(boardSize, squareSizeMm);

    tf = fit_homography(imagePoints, worldPoints);

    mapped   = transformPointsForward(tf, imagePoints);
    resid_mm = hypot(mapped(:,1) - worldPoints(:,1), mapped(:,2) - worldPoints(:,2));
    rmse_mm  = sqrt(mean(resid_mm.^2));

    d_img = hypot(diff(imagePoints(:,1)),  diff(imagePoints(:,2)));
    d_mm  = hypot(diff(worldPoints(:,1)),  diff(worldPoints(:,2)));
    adj   = d_mm > 0.5 * squareSizeMm & d_mm < 1.5 * squareSizeMm;
    if ~any(adj)
        error('Could not identify adjacent corner pairs in %s - is SQUARE_SIZE_MM right?', fileName);
    end
    scale_px_per_mm = median(d_img(adj) ./ d_mm(adj));

    rmse_px = rmse_mm * scale_px_per_mm;

    down_dir = world_down_dir(tf, imagePoints);

    spanX = max(worldPoints(:,1)) - min(worldPoints(:,1));
    spanY = max(worldPoints(:,2)) - min(worldPoints(:,2));

    fprintf('  Scale %.4f px/mm | RMSE %.3f px (%.3f mm) | covers %.0f x %.0f mm\n', ...
        scale_px_per_mm, rmse_px, rmse_mm, spanX, spanY);

    P.file            = fileName;
    P.tform           = tf;
    P.image           = img;
    P.imagePoints     = imagePoints;
    P.worldPoints     = worldPoints;
    P.boardSize       = boardSize;
    P.scale_px_per_mm = scale_px_per_mm;
    P.rmse_mm         = rmse_mm;
    P.rmse_px         = rmse_px;
    P.resid_mm        = resid_mm;
    P.down_dir        = down_dir;
    P.span_mm         = [spanX, spanY];
end

function d = world_down_dir(tf, imagePoints)
% Unit vector in WORLD (mm) coordinates corresponding to moving DOWN in the image
    c = mean(imagePoints, 1);
    p = transformPointsForward(tf, [c; c + [0, 100]]);
    v = p(2,:) - p(1,:);
    d = v / max(norm(v), eps);
end

function img = read_still(fileName, nAvg)
% Accept either a still image or a video
    if exist(fileName, 'file') ~= 2
        error(['Cannot find "%s".\nCheck it is in the current folder ' ...
            '(run  pwd  and  dir  to confirm) and that the name and ' ...
            'extension match exactly.'], fileName);
    end

    [~, ~, ext] = fileparts(fileName);
    if any(strcmpi(ext, {'.png','.jpg','.jpeg','.tif','.tiff','.bmp'}))
        img = imread(fileName);
        return;
    end

    vid = VideoReader(fileName);
    acc = []; n = 0;
    while hasFrame(vid) && n < nAvg
        fr = double(readFrame(vid));
        if isempty(acc), acc = zeros(size(fr)); end
        acc = acc + fr;
        n = n + 1;
    end
    if n == 0
        error('Read 0 frames from %s - the file may be empty or unreadable.', fileName);
    end
    img = uint8(acc / n);
end

function tf = fit_homography(movingPts, fixedPts)
% Projective fit, compatible across MATLAB versions (fitgeotform2d is the modern name
    try
        tf = fitgeotform2d(movingPts, fixedPts, 'projective');
    catch
        tf = fitgeotrans(movingPts, fixedPts, 'projective');
    end
end

function show_board(ax, P, label)
% Board image with detected corners
    axes(ax);  %#ok<LAXES>
    imshow(P.image); hold on;
    plot(P.imagePoints(:,1), P.imagePoints(:,2), 'g.', 'MarkerSize', 8);
    plot(P.imagePoints(1,1), P.imagePoints(1,2), 'ro', ...
        'MarkerSize', 14, 'LineWidth', 2);
    title(sprintf('%s  |  %.3f px/mm  |  RMSE %.2f px', ...
        label, P.scale_px_per_mm, P.rmse_px));
    hold off;
end
