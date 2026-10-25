function [sessionFiles, sessionIdx, sessionNames, sessionOriginsMm] = gatherSessionFiles(datasetFolder, sessions, filePattern)
% GATHERSESSIONFILES Collect the heightResults*.mat files of several recording sessions that sit in sub-folders...

if exist(datasetFolder, 'dir') ~= 7
    error('gatherSessionFiles:noFolder', ...
        ['Cannot find folder "%s".\nRun  pwd  and  dir  to check you are ' ...
         'in the right place, or set DATASET_FOLDER to a full path.'], datasetFolder);
end

sessionFiles = {};
sessionIdx = [];
sessionNames = {};
sessionOriginsMm = zeros(0, 2);

for k = 1:numel(sessions)
    folder = fullfile(datasetFolder, sessions(k).folder);
    if exist(folder, 'dir') ~= 7
        error('gatherSessionFiles:noSessionFolder', 'Cannot find session folder "%s".', folder);
    end
    listing = dir(fullfile(folder, filePattern));
    if isempty(listing)
        error('gatherSessionFiles:noFiles', ...
            'No files matching "%s" found in "%s".', filePattern, folder);
    end
    files = fullfile({listing.folder}, {listing.name});
    sessionFiles = [sessionFiles, files];  %#ok<AGROW>
    sessionIdx   = [sessionIdx, repmat(k, 1, numel(files))];  %#ok<AGROW>
    sessionNames{end+1} = sessions(k).name;  %#ok<AGROW>

    o = sessions(k).originMm;
    if isempty(o), o = [NaN NaN]; end
    sessionOriginsMm(end+1, :) = o;  %#ok<AGROW>

    fprintf('Session "%s": %d file(s) in "%s"', sessions(k).name, numel(files), folder);
    if all(isfinite(o))
        fprintf(' -> dropper at (%.3f, %.3f) mm\n', o(1), o(2));
    else
        fprintf(' -> NO origin given (left unshifted)\n');
    end
    for i = 1:numel(files)
        fprintf('    %s\n', files{i});
    end
end
end
