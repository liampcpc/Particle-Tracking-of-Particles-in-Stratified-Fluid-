function cfg = rigConfig()
% RIGCONFIG Default settings for the settling-tank tracking pipeline

%% Lens calibration
cfg.cameraParamsFile = 'cameraParams.mat';  % produced by calibrateRig
cfg.applyUndistort   = true;

cfg.enforceCalibResolution = true;  % Distortion coefficients are expressed in PIXELS

%% Rig geometry
cfg.cameraToBaseMm = [];  % Perpendicular distance from the camera sensor to the OUTSIDE of the tank base, in mm

%% ArUco fiducials on the tank base
cfg.useFiducials  = true;
cfg.arucoFamily   = 'DICT_4X4_50';

R = 153;  % 173 mm circumradius - 20 mm
ang = (0:5)' * 60;
cfg.tagIds    = (0:5)';
cfg.tagWorld  = [R*cosd(ang), R*sind(ang)];

cfg.minTagsRequired = 4;  % projective transform needs 4

%% Blob detection -- APPROACH 1 (area / perspective)
cfg.backgroundFrames = 30;  % frames used to build the static background
cfg.blobThreshold    = 0.10;  % normalised 0-1 difference from background
cfg.minAreaPx        = 20;  % reject blobs smaller than this
cfg.edgeMarginPx     = 5;  % reject blobs touching the frame border
cfg.morphRadius      = 2;  % disk radius for open/close

cfg.ballDiameterMm   = [];  % e.g. 3.0
cfg.mmPerPxAtBase    = [];  % from the fiducial transform, or a ruler
cfg.fitFrames        = 200;  % frames before the peak to include in the fit

%% Glint detection -- APPROACH 2 (laser sheet)
cfg.laserThreshold   = 0.78;  % normalised 0-1 absolute brightness
cfg.laserMinAreaPx   = 4;  % glints are small
cfg.burstMaxGap      = 5;  % blank frames tolerated within one burst
cfg.sheetHeightMm    = [];  % height of the laser plane above the base
cfg.specularOffsetPx = [0 0];  % glint-to-centre offset, calibrate once

%% Impact-sound detection -- APPROACH 3 (audio spike)
cfg.audioDetectMode = 'auto';  % 'auto' - argmax of the envelope

cfg.audioEnvelopeWinMs = 10;  % envelope smoothing window

cfg.audioClickWindowMs = 150;  % Manual clicking is precise to "roughly here," not to the sample

cfg.audioRingDecayExclMs = 400;  % How far past the primary impact's own peak to look before checking for a genuinely...

cfg.audioSecondaryWarnFrac = 0.5;  % If a peak OUTSIDE that exclusion window exceeds this fraction of the primary impact's...

%% Colour-dot grid calibration -- OPTIONAL, per-clip
cfg.useColorDotCalibration = false;  % When true, impactAudio ALSO runs detectColorDots + fits its own homography...

cfg.dotWorldPositionsMm = struct( ...
    'name',  {'cyan',      'red',      'yellow',   'green'}, ...
    'xy_mm', {[-168.5/2  -224/2], [168.5/2  -224/2],  [168.5/2  224/2], [-168.5/2  224/2]});

cfg.gridCols = 100;  % Grid divisions for the "which cell did it land in" label
cfg.gridRows = 100;  % ----20 and 20 is what we are using

cfg.gridOverlayOpacity = 0.1;  % How see-through the yellow grid lines drawn by drawGridOverlay.m

cfg.gridShowLabels = false;  % Set false to draw the grid LINES only, with no per-cell text labels

cfg.manualBallSelect = true;  % When automatic ball tracking

cfg.ffmpegBin = 'C:\Users\omear\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe';;  % impactAudio muxes the clip's own audio into its verification video

cfg.saveSlowMoVideo = true;  % Slow-in / freeze-with-flash / slow-out verification video, specific to impactAudio

cfg.slowMoApproachFrames = 30;  % source frames before/after impact that get the slow treatment
cfg.slowMoFactor         = 5;  % each of those frames plays 5x longer than normal
cfg.slowMoFreezeS        = 1.5;  % EXTRA hold time, in seconds of output playback, on the exact impact frame

%% Side-view height tracking -- APPROACH 4 (horizontal camera, ruled backing)
cfg.lineSpacingMm = 50;  % physical spacing between ruled lines (mm)
cfg.numLines      = 8;  % how many lines are on the backing

cfg.lineHeightsMm = [];  % Real-world height (mm) of each line, indexed TOP-TO-BOTTOM in the image

cfg.sideLineCalibFile = 'sideLineCalib.mat';  % Written by calibrateSideViewLines.m: the pixel ROW

cfg.sideRoiFile = 'sideViewROI.mat';  % Written by pickSideViewROI.m: an OPTIONAL manually-dragged [x y w h] box

cfg.sideBackgroundFrames = 15;  % frames (from the clean pre-drop lead time) used to build the side-view background
cfg.sideBlobThreshold    = 0.15;  % normalised 0-1 difference from background
cfg.sideMinAreaPx        = 15;  % reject blobs smaller than this
cfg.sideMorphRadius      = 2;  % disk radius for open/close

cfg.heightManualBallSelect = true;  % see cfg.manualBallSelect above

cfg.sideBandHalfHeightPx = 80;  % how far above/below the target line's row to scan
cfg.sideCrossingMinAreaPx = 150;  % row to scan
cfg.sideCrossingMaxGapFrames = 1;  % cfg.sideCrossingMaxGapFrames
cfg.sideMinRunFrames     = 2;  % consecutive in-band frames required before a detection counts as a real crossing...
cfg.sideRequireActualCrossing = true;  % require the tracked blob's

%% Output
cfg.savePreview = true;  % write the chosen frame with the mark on it

cfg.saveVerificationVideo = true;  % Playable verification video: the whole clip, replayed at full length
cfg.verificationWindowMs  = 200;  % how long the highlighted window lasts, each side of the estimated frame

cfg.verbose = true;

end
