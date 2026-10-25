function outPath = renderEventVideo(videoPath, data, eventFrame, opts)
% RENDEREVENTVIDEO Play a drop clip back with the estimated event marked

outPath = '';
try
    windowMs = 200;
    if isfield(opts, 'windowMs') && ~isempty(opts.windowMs)
        windowMs = opts.windowMs;
    end

    drawTrail = true;
    if isfield(opts, 'drawTrail')
        drawTrail = opts.drawTrail;
    end

    v  = VideoReader(videoPath);
    fps = v.FrameRate;
    windowFrames = round(windowMs/1000 * fps);

    eventRounded = round(eventFrame);

    haveSpan = isfield(opts, 'highlightSpan') && ~isempty(opts.highlightSpan);
    if haveSpan
        spanLo = opts.highlightSpan(1);
        spanHi = opts.highlightSpan(2);
    end

    [pth, nm] = fileparts(videoPath);
    outPath = fullfile(pth, [nm opts.outSuffix]);
    wr = VideoWriter(outPath, 'MPEG-4');
    wr.FrameRate = fps;
    open(wr);

    k = 0;
    while hasFrame(v)
        k = k + 1;
        F = readFrame(v);

        haveXY = k <= numel(data.x) && isfinite(data.x(k)) && isfinite(data.y(k));
        inWindow = abs(k - eventFrame) <= windowFrames;
        isTheFrame = (k == eventRounded);

        if haveXY && drawTrail
            F = insertShape(F, 'Circle', [data.x(k) data.y(k) 8], ...
                'Color', 'green', 'LineWidth', 1, 'Opacity', 0.7);
        end

        if inWindow && haveXY
            F = insertShape(F, 'Circle', [data.x(k) data.y(k) 22], ...
                'Color', opts.markColor, 'LineWidth', 3);
        end

        if isTheFrame
            if haveXY
                F = insertShape(F, 'Circle', [data.x(k) data.y(k) 30], ...
                    'Color', 'yellow', 'LineWidth', 4);
                F = insertMarker(F, [data.x(k) data.y(k)], 'x', ...
                    'Color', 'yellow', 'Size', 16);
            end
            F = insertText(F, [10 70], sprintf('%s FRAME (est. %.2f)', ...
                opts.label, eventFrame), 'FontSize', 22, ...
                'BoxColor', 'yellow', 'TextColor', 'black');
        elseif inWindow
            F = insertText(F, [10 70], sprintf('%s WINDOW', opts.label), ...
                'FontSize', 18, 'BoxColor', opts.markColor, 'TextColor', 'black');
        end

        if haveSpan && k >= spanLo && k <= spanHi
            F = insertText(F, [10 100], 'BURST', 'FontSize', 16, ...
                'BoxColor', 'white', 'TextColor', 'black');
        end

        metricStr = 'n/a';
        if k <= numel(opts.metricValues) && isfinite(opts.metricValues(k))
            metricStr = sprintf('%.2f', opts.metricValues(k));
        end
        F = insertText(F, [10 10], sprintf('frame %d/%d   %s = %s', ...
            k, data.nFrames, opts.metricName, metricStr), ...
            'FontSize', 16, 'BoxColor', 'black', 'TextColor', 'white');

        writeVideo(wr, padFrameForEncoder(F));
    end

    close(wr);
catch ME
    warning('renderEventVideo:failed', ...
        'Could not render verification video for %s: %s', videoPath, ME.message);
    outPath = '';
end

end
