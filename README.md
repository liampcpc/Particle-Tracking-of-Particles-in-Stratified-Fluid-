# Settling Spheres in Single-Layer and Stratified Fluids

MATLAB code for a University of Melbourne capstone project. Steel balls are dropped into a hexagonal glycerine–water tank, and two synchronised cameras measure where each ball is at five heights as it falls. The code compares how much the balls spread sideways in a single-layer fluid and in a density-stratified fluid.

## Folders

### `validation/`
Checks that the rig reproduces known terminal velocities before any distribution measurements are made.
- `CalibrateCamera.m` — checkerboard calibration of the single-camera rig.
- `AudioSplit.m`, `SplitSideDrops.m` — split one long recording into one clip per drop.
- `DropTracking.m` — tracks a falling ball through the fluid and measures its velocity.
- `ValidateGaRe_Uncertainty.m` — Galileo–Reynolds validation plot against Cabrera-Booman et al. (2024), with propagated measurement uncertainty.

### `distribution/`
The main measurement pipeline: where each ball lands at each tracked height.
- `DistributionMaster.m` — **start here.** Runs one full recording session end to end: side-view line calibration, colour-dot calibration, splitting the recording into drops, and height tracking.
- `SplitVisualDrops.m`, `SplitAndTrackHeights.m` — detect each drop from the side camera, synchronise the two cameras by audio, and record the ball's position as it crosses each line.
- `RecomputeHeightPositions.m` — recomputes positions in existing results after a calibration fix.
- `PickDropperLocation.m` — finds the dropper position used as the origin.
- `RunCompileHeightHeatmaps.m`, `RunGaussianLayers3D.m`, `RunCompileTrajectories.m`, `RunAnimateDropTrajectory.m` — combine sessions and produce the heatmaps, Gaussian fits, trajectory plots and animation.
- The remaining files are helper functions (calibration, detection, synchronisation, video export).

### `theoretical_calcs/`
Fluid properties and predicted ball behaviour.
- `density_viscosity_calc.m` — density and viscosity of glycerine–water mixtures, Reynolds number, and designing the salted lower layer.
- `glycerine_mixture_terminal_velocity.m`, `glycerine_terminal_velocity_calculator.m` — terminal velocity, and the distance a ball needs to reach it.

## Requirements
- MATLAB (developed on R2025b)
- Image Processing Toolbox, Computer Vision Toolbox, Signal Processing Toolbox
- [FFmpeg](https://ffmpeg.org/) for cutting and exporting video clips

## Notes
- Recordings and results files are not included. Each script's settings section at the top sets the file names and folders to point at your own data.
- Measured positions are relative to the dropper and are not corrected for camera parallax.
