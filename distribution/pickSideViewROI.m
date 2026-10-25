function roi = pickSideViewROI(sideVideoPath, cfg, varargin)
% PICKSIDEVIEWROI Interactively drag a box on a side-view frame to restrict where line-crossing detection...

p = inputParser;
addParameter(p, 'frameTime', [], @(x) isempty(x) || isnumeric(x));
parse(p, varargin{:});

v = VideoReader(sideVideoPath);
if ~isempty(p.Results.frameTime)
    v.CurrentTime = max(0, min(p.Results.frameTime, max(0, v.Duration - 1/v.FrameRate)));
else
    v.CurrentTime = v.Duration / 2;
end
F = readFrame(v);

fprintf('\n=== Drag a box around the fall path (TOP below water surface; LEFT/RIGHT inside tank glass) ===\n');

hf = figure('Name', 'Drag the side-view search ROI', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.1 0.1 0.6 0.8]);
imshow(F);
hold on;
text(10, 22, 'DRAG A BOX AROUND THE FALL PATH.', ...
    'Color', 'black', 'BackgroundColor', 'yellow', 'FontSize', 16, 'FontWeight', 'bold', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'Clipping', 'on');
text(10, 50, 'TOP edge BELOW the water surface; LEFT/RIGHT edges INSIDE the tank glass.', ...
    'Color', 'black', 'BackgroundColor', 'yellow', 'FontSize', 11, ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'Clipping', 'on');
hold off;
title({'Drag a box around the fall path.', ...
       'TOP edge BELOW the water surface; LEFT/RIGHT edges INSIDE the tank glass.'}, ...
       'Interpreter', 'none');

roi = round(getrect(hf));
close(hf);

if roi(3) < 20 || roi(4) < 20
    error('pickSideViewROI:tooSmall', ...
        'ROI too small (%dx%d px) -- re-run and drag a larger box.', roi(3), roi(4));
end

save(cfg.sideRoiFile, 'roi');
fprintf('Side-view ROI saved to %s: [x=%d y=%d w=%d h=%d]\n', cfg.sideRoiFile, roi(1), roi(2), roi(3), roi(4));

end
