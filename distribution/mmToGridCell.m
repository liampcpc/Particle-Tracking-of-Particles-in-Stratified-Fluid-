function [label, col, row, inBounds] = mmToGridCell(xMm, yMm, xMin, yMin, xMax, yMax, nCols, nRows)
% MMTOGRIDCELL Convert a world (x,y) position in mm to a spreadsheet-style grid cell label ("C4")

nCols = max(1, round(nCols));
nRows = max(1, round(nRows));
xSpacing = (xMax - xMin) / nCols;
ySpacing = (yMax - yMin) / nRows;

col = floor((xMm - xMin) / xSpacing) + 1;
row = floor((yMm - yMin) / ySpacing) + 1;

xEdgeTolMm = 0.01 * xSpacing;
yEdgeTolMm = 0.01 * ySpacing;
if xMm >= xMin && xMm <= xMax + xEdgeTolMm, col = min(col, nCols); end
if yMm >= yMin && yMm <= yMax + yEdgeTolMm, row = min(row, nRows); end

inBounds = col >= 1 && col <= nCols && row >= 1 && row <= nRows;

label = sprintf('%s%d', colLetter(col), row);

end

function s = colLetter(col)
% COLLETTER 1 -> 'A', 2 -> 'B', ..., 26 -> 'Z', 27 -> 'AA', ... Out-of-range
if col < 1
    s = sprintf('(%d)', col);
    return
end
s = '';
n = col;
while n > 0
    r = mod(n-1, 26);
    s = [char('A'+r) s];  %#ok<AGROW>
    n = floor((n-1)/26);
end
end
