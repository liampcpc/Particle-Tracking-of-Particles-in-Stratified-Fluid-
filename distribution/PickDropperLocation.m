%% PickDropperLocation
% Shows the LAST frame of a clip you choose, with the same colour-dot grid overlay SplitAndTrackHeights.m draws
clear; clc; close all;

addpath(fileparts(mfilename('fullpath')));

%% CONFIGURATION -- EDIT THESE
CLIP_FILE    = '';  % path to the clip, e.g. '14_10_26/dropbot0_24.MOV'. ''
START_FOLDER = '';  % folder the picker opens in ('' = current folder)

FRAME_TO_USE = 0.1;  % 'last' = final frame of the clip, or a number = that many seconds into the clip

GRID_OPACITY = [];  % 0-1
SHOW_LABELS  = [];  % true / false (cell-name text
SHOW_DOTS    = true;  % ring the 4 detected colour dots so you can see the calibration found the right things

ZOOM_HALF_WIDTH_PX = 150;  % half-size of the zoomed window around your first click
ZOOM_GRID_OPACITY  = 0.5;  % stronger grid in the zoomed view (the rig default is faint)
ZOOM_SHOW_LABELS   = false;

SAVE_ANNOTATED_PNG = true;  % <clip name>_dropper.png beside the clip
SAVE_MAT           = true;  % dropperLocation.mat beside the clip

%% CHOOSE THE CLIP
if isempty(CLIP_FILE)
    startDir = START_FOLDER;
    if isempty(startDir), startDir = pwd; end
    [fn, fp] = uigetfile({'*.mov;*.MOV;*.mp4;*.MP4;*.avi;*.AVI;*.m4v;*.M4V', 'Video files'; ...
                          '*.*', 'All files'}, ...
                         'Choose the clip whose last frame shows the dropper', startDir);
    if isequal(fn, 0)
        error('PickDropperLocation:cancelled', 'No clip chosen.');
    end
    CLIP_FILE = fullfile(fp, fn);
end
if exist(CLIP_FILE, 'file') ~= 2
    error('PickDropperLocation:notFound', ...
        'Cannot find "%s". Run  pwd  to check where MATLAB is looking.', CLIP_FILE);
end
fprintf('Clip: %s\n', CLIP_FILE);

%% READ THE FRAME
if ischar(FRAME_TO_USE) || isstring(FRAME_TO_USE)
    if ~strcmpi(char(FRAME_TO_USE), 'last')
        error('PickDropperLocation:badFrame', 'FRAME_TO_USE must be ''last'' or a time in seconds.');
    end
    F = readLastFrame(CLIP_FILE);
    frameDesc = 'last frame';
else
    F = readFrameAtTime(CLIP_FILE, FRAME_TO_USE);
    frameDesc = sprintf('frame at %.2f s', FRAME_TO_USE);
end
[imgH, imgW, ~] = size(F);
fprintf('Using the %s (%d x %d px).\n', frameDesc, imgW, imgH);

%% CALIBRATE FROM THE COLOUR DOTS
cfg = rigConfig();
worldXY = cat(1, cfg.dotWorldPositionsMm.xy_mm);
xMinW = min(worldXY(:,1)); xMaxW = max(worldXY(:,1));
yMinW = min(worldXY(:,2)); yMaxW = max(worldXY(:,2));

try
    [dotTform, matchedDots, imgPts] = fitDotHomography(F, cfg.dotWorldPositionsMm);
    calibFrom = frameDesc;
catch ME
    warning('PickDropperLocation:calibOnFrame', ...
        ['Colour-dot calibration failed on the %s (%s) -- trying the middle of ' ...
         'the clip instead.'], frameDesc, ME.message);
    [dotTform, matchedDots, imgPts] = fitDotHomography(CLIP_FILE, cfg.dotWorldPositionsMm);
    calibFrom = 'middle of the clip';
end
fprintf('Colour-dot calibration: %d dots matched (%s), from the %s.\n', ...
    numel(matchedDots), strjoin(matchedDots, ', '), calibFrom);

%% DRAW THE GRID
opac = cfg.gridOverlayOpacity;
if ~isempty(GRID_OPACITY), opac = GRID_OPACITY; end
lbl = true;
if isfield(cfg, 'gridShowLabels'), lbl = cfg.gridShowLabels; end
if ~isempty(SHOW_LABELS), lbl = SHOW_LABELS; end

Fgrid = drawGridOverlay(F, dotTform, worldXY, cfg.gridCols, cfg.gridRows, opac, lbl);
Fzoom = drawGridOverlay(F, dotTform, worldXY, cfg.gridCols, cfg.gridRows, ...
    ZOOM_GRID_OPACITY, ZOOM_SHOW_LABELS);
if SHOW_DOTS
    for k = 1:size(imgPts, 1)
        Fgrid = insertShape(Fgrid, 'Circle', [imgPts(k,1) imgPts(k,2) 22], 'Color', 'white', 'LineWidth', 2);
        Fzoom = insertShape(Fzoom, 'Circle', [imgPts(k,1) imgPts(k,2) 22], 'Color', 'white', 'LineWidth', 2);
    end
end

%% STEP 1 -- ROUGH CLICK ON THE FULL FRAME
fig = figure('Name', 'Pick the dropper location', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
ax = axes('Parent', fig);
hImg = imshow(Fgrid, 'Parent', ax);
title(ax, sprintf(['STEP 1/2 -- click roughly on the DROPPER  (%s of %s).  ' ...
    'Q = cancel'], frameDesc, shortName(CLIP_FILE)), 'Interpreter', 'none');

xRough = NaN; yRough = NaN;
while isnan(xRough)
    [x, y, btn] = ginput(1);
    if isempty(x), continue; end
    if isnumeric(btn) && ismember(btn, double('qQ'))
        close(fig);
        error('PickDropperLocation:cancelled', 'Cancelled.');
    end
    if isnumeric(btn) && btn == 1
        xRough = x; yRough = y;
    end
end

%% STEP 2 -- ZOOM IN AND FINE-TUNE
set(hImg, 'CData', Fzoom);
xl = [max(0.5, xRough - ZOOM_HALF_WIDTH_PX), min(imgW + 0.5, xRough + ZOOM_HALF_WIDTH_PX)];
yl = [max(0.5, yRough - ZOOM_HALF_WIDTH_PX), min(imgH + 0.5, yRough + ZOOM_HALF_WIDTH_PX)];
set(ax, 'XLim', xl, 'YLim', yl);
hold(ax, 'on');

xSel = xRough; ySel = yRough;
hMark = plot(ax, xSel, ySel, 'r+', 'MarkerSize', 22, 'LineWidth', 2);
[xm, ym] = transformPointsForward(dotTform, xSel, ySel);
title(ax, zoomTitle(xm, ym, xMinW, yMinW, xMaxW, yMaxW, cfg), 'Interpreter', 'none');

done = false;
while ~done
    [x, y, btn] = ginput(1);
    if isempty(x)
        done = true;
    elseif isnumeric(btn) && ismember(btn, double('qQ'))
        close(fig);
        error('PickDropperLocation:cancelled', 'Cancelled.');
    elseif isnumeric(btn) && btn == 1
        xSel = x; ySel = y;
        delete(hMark);
        hMark = plot(ax, xSel, ySel, 'r+', 'MarkerSize', 22, 'LineWidth', 2);
        [xm, ym] = transformPointsForward(dotTform, xSel, ySel);
        title(ax, zoomTitle(xm, ym, xMinW, yMinW, xMaxW, yMaxW, cfg), 'Interpreter', 'none');
    end
end
close(fig);

%% RESULT
[xMm, yMm] = transformPointsForward(dotTform, xSel, ySel);
[cellLabel, cellCol, cellRow, inBounds] = mmToGridCell(xMm, yMm, xMinW, yMinW, xMaxW, yMaxW, ...
    cfg.gridCols, cfg.gridRows);

fprintf('\n================ DROPPER LOCATION ================\n');
fprintf('  x = %.3f mm\n', xMm);
fprintf('  y = %.3f mm\n', yMm);
fprintf('  grid cell: %s (col %d, row %d)%s\n', cellLabel, cellCol, cellRow, ...
    ternary(inBounds, '', '  -- OUTSIDE the calibrated grid'));
fprintf('  pixel position: (%.1f, %.1f)\n', xSel, ySel);
fprintf('\nPaste into RunGaussianLayers3D.m:\n');
fprintf('  ORIGIN_MM = [%.3f %.3f];\n', xMm, yMm);
fprintf('==================================================\n\n');

try
    clipboard('copy', sprintf('%.3f, %.3f', xMm, yMm));
    fprintf('(Copied "%.3f, %.3f" to the clipboard.)\n', xMm, yMm);
catch
end

[clipDir, clipName] = fileparts(CLIP_FILE);
if isempty(clipDir), clipDir = pwd; end

if SAVE_ANNOTATED_PNG
    try
        Fout = Fgrid;
        Fout = insertShape(Fout, 'Circle', [xSel ySel 14], 'Color', 'magenta', 'LineWidth', 2);
        Fout = insertMarker(Fout, [xSel ySel], 'x', 'Color', 'yellow', 'Size', 12);
        Fout = insertText(Fout, [10 10], sprintf('Dropper: x = %.2f mm, y = %.2f mm  (%s)', ...
            xMm, yMm, cellLabel), 'FontSize', 20, 'BoxColor', 'black', 'TextColor', 'yellow');
        pngPath = fullfile(clipDir, [clipName '_dropper.png']);
        imwrite(Fout, pngPath);
        fprintf('Annotated image saved: %s\n', pngPath);
    catch ME
        warning('PickDropperLocation:pngFailed', 'Could not save the annotated PNG: %s', ME.message);
    end
end

dropperLocation = struct( ...
    'xMm', xMm, 'yMm', yMm, 'gridCell', cellLabel, 'inBounds', inBounds, ...
    'xPx', xSel, 'yPx', ySel, 'clipFile', CLIP_FILE, 'frame', frameDesc, ...
    'dotsMatched', {matchedDots}, 'createdAt', datestr(now));  %#ok<TNOW1,DATST>
if SAVE_MAT
    try
        matPath = fullfile(clipDir, 'dropperLocation.mat');
        save(matPath, 'dropperLocation');
        fprintf('Saved: %s\n', matPath);
    catch ME
        warning('PickDropperLocation:matFailed', 'Could not save dropperLocation.mat: %s', ME.message);
    end
end

%% Local functions
function F = readLastFrame(videoPath)
% READLASTFRAME Final frame of a video
v = VideoReader(videoPath);
v.CurrentTime = max(0, v.Duration - 0.5);
F = [];
while hasFrame(v)
    F = readFrame(v);
end
if isempty(F)
    v = VideoReader(videoPath);
    while hasFrame(v)
        F = readFrame(v);
    end
end
if isempty(F)
    error('PickDropperLocation:noFrames', 'Could not read any frames from "%s".', videoPath);
end
end

function F = readFrameAtTime(videoPath, tSec)
v = VideoReader(videoPath);
v.CurrentTime = max(0, min(tSec, max(0, v.Duration - 1 / v.FrameRate)));
F = readFrame(v);
end

function s = zoomTitle(xm, ym, xMin, yMin, xMax, yMax, cfg)
[lab, ~, ~, inB] = mmToGridCell(xm, ym, xMin, yMin, xMax, yMax, cfg.gridCols, cfg.gridRows);
note = '';
if ~inB, note = '  (outside grid)'; end
s = {'STEP 2/2 -- left-click to place / move the marker, ENTER to accept, Q = cancel', ...
     sprintf('marker: x = %.2f mm, y = %.2f mm   (cell %s)%s', xm, ym, lab, note)};
end

function s = shortName(p)
[~, n, e] = fileparts(p);
s = [n e];
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
