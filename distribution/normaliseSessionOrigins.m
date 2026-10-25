function S = normaliseSessionOrigins(callerName, nFiles, sessionIdx, sessionOriginsMm, sessionNames)
% NORMALISESESSIONORIGINS Validate the per-session origin options shared by CompileTrajectories.m

S = struct('used', false, 'fileOriginMm', zeros(nFiles, 2), 'names', {{}}, ...
           'origins', zeros(0, 2), 'meanOriginMm', [0 0]);

if isempty(sessionOriginsMm)
    return
end

origins = double(sessionOriginsMm);
nSess = size(origins, 1);

if isempty(sessionIdx) || numel(sessionIdx) ~= nFiles
    error(sprintf('%s:sessionIdx', callerName), ...
        ['''sessionIdx'' must have one entry per file (%d files given, %d entries): ' ...
         'e.g. [1 1 1 2 2] = the first three files are session 1, the next two session 2.'], ...
        nFiles, numel(sessionIdx));
end
idx = double(sessionIdx(:)');
if any(idx < 1) || any(idx > nSess) || any(idx ~= round(idx))
    error(sprintf('%s:sessionIdxRange', callerName), ...
        '''sessionIdx'' entries must be whole numbers from 1 to %d (one row of sessionOriginsMm per session).', nSess);
end

if isempty(sessionNames)
    names = arrayfun(@(k) sprintf('Session %d', k), 1:nSess, 'UniformOutput', false);
else
    names = cellstr(string(sessionNames));
    names = names(:)';
    if numel(names) ~= nSess
        error(sprintf('%s:sessionNames', callerName), ...
            '''sessionNames'' needs %d entries (one per row of sessionOriginsMm), got %d.', nSess, numel(names));
    end
end

fileOrigin = zeros(nFiles, 2);
for f = 1:nFiles
    o = origins(idx(f), :);
    if all(isfinite(o))
        fileOrigin(f, :) = o;
    end
end

fprintf('Per-session origins (each session is shifted so its dropper is (0, 0)):\n');
for k = 1:nSess
    if all(isfinite(origins(k, :)))
        fprintf('  %s: dropper at (%.3f, %.3f) mm subtracted from %d file(s)\n', ...
            names{k}, origins(k, 1), origins(k, 2), nnz(idx == k));
    else
        warning(sprintf('%s:sessionNoOrigin', callerName), ...
            '%s has no origin (NaN) -- its positions are left UNSHIFTED (raw rig mm).', names{k});
    end
end

finiteRows = all(isfinite(origins), 2);
if any(finiteRows)
    meanOrigin = mean(origins(finiteRows, :), 1);
else
    meanOrigin = [0 0];
end

S.used = true;
S.fileOriginMm = fileOrigin;
S.names = names;
S.origins = origins;
S.meanOriginMm = meanOrigin;
end
