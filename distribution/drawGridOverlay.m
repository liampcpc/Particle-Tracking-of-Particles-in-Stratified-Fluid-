function vis = drawGridOverlay(img, tform, worldPts, nCols, nRows, opacity, showLabels)
% DRAWGRIDOVERLAY Draw a world-space grid, mapped through TFORM's inverse, onto IMG

if nargin < 6 || isempty(opacity)
    opacity = 1;
end
if nargin < 7 || isempty(showLabels)
    showLabels = true;
end

xMin = min(worldPts(:,1)); xMax = max(worldPts(:,1));
yMin = min(worldPts(:,2)); yMax = max(worldPts(:,2));

nCols = max(1, round(nCols));
nRows = max(1, round(nRows));
xLines = linspace(xMin, xMax, nCols+1);
yLines = linspace(yMin, yMax, nRows+1);

vis = img;
nSamples = 20;  % points per line

for xv = xLines
    wp = [repmat(xv, nSamples, 1), linspace(yMin, yMax, nSamples)'];
    ip = transformPointsInverse(tform, wp);
    vis = drawPolyline(vis, ip, [255 255 0], opacity);
end
for yv = yLines
    wp = [linspace(xMin, xMax, nSamples)', repmat(yv, nSamples, 1)];
    ip = transformPointsInverse(tform, wp);
    vis = drawPolyline(vis, ip, [255 255 0], opacity);
end

if opacity > 0.01 && showLabels
    for ci = 1:nCols
        for ri = 1:nRows
            cx = (xLines(ci) + xLines(ci+1)) / 2;
            cy = (yLines(ri) + yLines(ri+1)) / 2;
            label = mmToGridCell(cx, cy, xMin, yMin, xMax, yMax, nCols, nRows);
            ip = transformPointsInverse(tform, [cx cy]);
            if all(isfinite(ip))
                vis = insertText(vis, ip, label, 'FontSize', 10, ...
                    'BoxOpacity', 0, 'TextColor', [255 255 0], 'AnchorPoint', 'Center');
            end
        end
    end
end

end

%% Local functions
function img = drawPolyline(img, pts, colorRgb, opacity)
% DRAWPOLYLINE Connect points with line segments, via a single insertShape 'Line' call
valid = all(isfinite(pts), 2);
pts = pts(valid, :);
if size(pts, 1) < 2 || opacity <= 0.01
    return
end
pos = reshape(pts', 1, []);

canvas = insertShape(zeros(size(img), 'like', img), 'Line', pos, ...
    'Color', colorRgb, 'LineWidth', 2);
alphaMap = (double(max(canvas, [], 3)) / double(intmax(class(canvas)))) * opacity;
colorImg = reshape(double(colorRgb), 1, 1, 3);
img = uint8(double(img) .* (1 - alphaMap) + colorImg .* alphaMap);
end
