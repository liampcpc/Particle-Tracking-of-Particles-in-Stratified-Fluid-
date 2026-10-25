function rois = pickColorDotROIs(videoPath, varargin)
% PICKCOLORDOTROIS Interactively drag one box per colour dot

p = inputParser;
addParameter(p, 'frameTime', [], @(x) isempty(x) || isnumeric(x));
addParameter(p, 'outFile', 'colorDotROIs.mat', @ischar);
parse(p, varargin{:});
opt = p.Results;

v = VideoReader(videoPath);
if ~isempty(opt.frameTime)
    v.CurrentTime = max(0, min(opt.frameTime, max(0, v.Duration - 1/v.FrameRate)));
else
    v.CurrentTime = v.Duration / 2;
end
F = readFrame(v);
[imgH, imgW, ~] = size(F);

names = {'cyan', 'yellow', 'green', 'red'};
rois = struct();

for i = 1:numel(names)
    fprintf('\n=== Step %d/%d: drag a box around the %s DOT ===\n', i, numel(names), upper(names{i}));

    hf = figure('Name', sprintf('Step %d/%d: drag a box around the %s dot', i, numel(names), names{i}), ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.1 0.1 0.6 0.8]);
    imshow(F);
    hold on;
    text(10, 22, sprintf('STEP %d/%d: DRAG A BOX AROUND THE %s DOT ONLY.', i, numel(names), upper(names{i})), ...
        'Color', 'black', 'BackgroundColor', 'yellow', 'FontSize', 16, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'top', 'Interpreter', 'none', 'Clipping', 'on');
    text(10, 50, 'Generous margin is fine -- keep the OTHER dots and glass edges out of the box.', ...
        'Color', 'black', 'BackgroundColor', 'yellow', 'FontSize', 11, ...
        'VerticalAlignment', 'top', 'Interpreter', 'none', 'Clipping', 'on');
    hold off;
    title({sprintf('Drag a box around the %s DOT ONLY.', upper(names{i})), ...
           'Generous margin is fine -- keep the OTHER dots and glass edges out of the box.'}, ...
           'Interpreter', 'none');

    r = round(getrect(hf));
    close(hf);

    if r(3) < 5 || r(4) < 5
        error('pickColorDotROIs:tooSmall', ...
            '%s ROI too small (%dx%d px) -- re-run and drag a larger box.', names{i}, r(3), r(4));
    end

    xMinFrac = max(0, r(1) / imgW);
    xMaxFrac = min(1, (r(1) + r(3)) / imgW);
    yMinFrac = max(0, r(2) / imgH);
    yMaxFrac = min(1, (r(2) + r(4)) / imgH);
    rois.(names{i}) = [xMinFrac xMaxFrac yMinFrac yMaxFrac];

    fprintf('%-8s ROI: [x %.3f-%.3f, y %.3f-%.3f] (fraction of frame)\n', ...
        names{i}, xMinFrac, xMaxFrac, yMinFrac, yMaxFrac);
end

save(opt.outFile, 'rois');
fprintf('\nSaved all 4 dot ROIs to %s\n', opt.outFile);

end
