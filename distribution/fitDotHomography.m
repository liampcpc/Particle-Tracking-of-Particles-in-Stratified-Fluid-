function [tform, matchedNames, imgPts, worldPts, img] = fitDotHomography(source, worldPositions)
% FITDOTHOMOGRAPHY Detect the colour dots in SOURCE and fit an image pixel -> world mm projective transform...

det = detectColorDots(source, 'saveAnnotated', false);
img = det.image;

imgPts = []; worldPts = []; matchedNames = {};
for i = 1:numel(worldPositions)
    name = worldPositions(i).name;
    idx = find(strcmpi({det.dots.name}, name), 1);
    if isempty(idx) || ~det.dots(idx).found
        warning('fitDotHomography:missingDot', ...
            '%s was not detected -- excluded from the fit.', name);
        continue
    end
    imgPts(end+1, :)    = [det.dots(idx).x, det.dots(idx).y];  %#ok<AGROW>
    worldPts(end+1, :)  = worldPositions(i).xy_mm;  %#ok<AGROW>
    matchedNames{end+1} = name;  %#ok<AGROW>
end

if size(imgPts, 1) < 4
    error('fitDotHomography:tooFewPoints', ...
        ['Only %d of %d dots were both detected AND have a world position ' ...
         '-- a projective fit needs at least 4. Check detectColorDots ' ...
         'found everything expected first.'], size(imgPts,1), numel(worldPositions));
end

try
    tform = fitgeotform2d(imgPts, worldPts, 'projective');
catch
    tform = fitgeotrans(imgPts, worldPts, 'projective');
end

end
