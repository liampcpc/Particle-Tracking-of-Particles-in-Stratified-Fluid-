function ff = locate_ffmpeg(explicitPath)
% LOCATE_FFMPEG Find an ffmpeg binary to shell out to

if ~isempty(explicitPath)
    if exist(explicitPath, 'file') ~= 2
        error('locate_ffmpeg:badPath', ...
            'cfg.ffmpegBin (or FFMPEG_BIN) is set to "%s" but no file exists there.', ...
            explicitPath);
    end
    ff = explicitPath; return;
end

if system('ffmpeg -version >/dev/null 2>&1') == 0
    ff = 'ffmpeg'; return;
end

candidates = {'/opt/homebrew/bin/ffmpeg', ...  % Apple Silicon Homebrew
              '/usr/local/bin/ffmpeg',   ...
              '/usr/bin/ffmpeg', ...
              'C:\ffmpeg\bin\ffmpeg.exe'};
for k = 1:numel(candidates)
    if exist(candidates{k}, 'file') == 2
        ff = candidates{k};
        return;
    end
end

error('locate_ffmpeg:notFound', ...
    ['ffmpeg not found.\nIn a TERMINAL run:  which ffmpeg\n' ...
     '  - if it prints a path, set cfg.ffmpegBin (or FFMPEG_BIN) to that path.\n' ...
     '  - if it prints nothing, install it:  brew install ffmpeg  (Mac).']);

end
