function crossings = findLineCrossings(track, linePx)
% FINDLINECROSSINGS Find when a falling ball's y-centroid crosses each of a set of target pixel rows

nLines = numel(linePx);
crossings = struct('linePx', num2cell(linePx(:)'), 'found', false, 'tS', NaN, 'frameLo', NaN);

valid = isfinite(track.yPx);
if nnz(valid) < 2
    warning('findLineCrossings:noTrack', 'Fewer than 2 valid tracked frames -- cannot find any crossings.');
    return
end

vIdx = find(valid);
vY   = track.yPx(vIdx);
vT   = track.tS(vIdx);

for k = 1:nLines
    Ly = linePx(k);
    signDiff = sign(vY - Ly);
    crossIdx = find(signDiff(1:end-1) .* signDiff(2:end) <= 0, 1, 'first');

    if isempty(crossIdx)
        continue
    end

    y0 = vY(crossIdx);   t0 = vT(crossIdx);
    y1 = vY(crossIdx+1); t1 = vT(crossIdx+1);

    if y1 == y0
        tCross = t0;
    else
        f = (Ly - y0) / (y1 - y0);
        f = min(max(f, 0), 1);
        tCross = t0 + f * (t1 - t0);
    end

    crossings(k).found   = true;
    crossings(k).tS      = tCross;
    crossings(k).frameLo = vIdx(crossIdx);
end

end
