# PocketAR backend architecture test

This project separates the AR application from the platform-specific implementation that supplies tracking and surface queries.

## Architecture

- `scripts/ar_backend.gd` — common backend contract.
- `scripts/plane_data.gd` — common, typed plane description.
- `scripts/ar_hit.gd` — common, typed screen-raycast result.
- `scripts/desktop_ar_backend.gd` — desktop implementation using physics rays against the simulated room.
- `scripts/mobile_ar_backend.gd` — adapter around PocketAR's `ARView` facade for ARCore/ARKit.
- `scripts/placement_manager.gd` — shared object placement.
- `scripts/simulator.gd` — desktop room and interaction layer; it depends on `ARBackend`, not the concrete backend type.
- `main.gd` — mobile UI, delegating AR work to `MobileARBackend`.
- `scripts/platform_bootstrap.gd` — selects the desktop or mobile scene.

Both implementations expose `PlaneData` and `ARHit`. The application should use the interface methods and signals rather than reaching into backend-specific nodes.

## Desktop testing

1. Extract the ZIP.
2. Open the `pocket-ar-testing` folder in Godot 4.7 (the folder containing `project.godot`).
3. Wait for the editor import/class scan to finish.
4. Run the project (F6/F5).
5. Controls:
   - WASD: move
   - Mouse: look (left-click once to capture)
   - Left-click after capture: place a cube at the view center
   - P: toggle plane visualization
   - R: clear placed cubes
   - Esc: release mouse

The desktop detector samples a 13×9 grid of camera rays every 0.18 seconds. It groups physics hits by collider and approximate surface normal, estimates plane extents from accumulated points, and publishes plane lifecycle events. A surface becomes paused after 2.5 seconds without a hit and is removed after 12 seconds without a hit. These are simulation heuristics, not ARCore/ARKit tracking semantics.

**Important:** Desktop detection uses known room colliders. It does not perform computer vision on a camera image.

## Mobile testing

The mobile adapter creates PocketAR's `ARView`, selects ARCore on Android or ARKit on iOS, enables horizontal and vertical plane finding, and converts PocketAR plane/raycast results into the shared data types. PocketAR continues to own the native session lifecycle.

Build and test on a supported physical device. An Android emulator may not provide the camera/ARCore capabilities needed for a valid AR session. The mobile adapter is based on the PocketAR API bundled in this project; native device behavior still needs verification on hardware.

## Contract design notes

- `ARBackend` defines session start/stop, plane enumeration, screen raycasting, visualization control, and lifecycle signals.
- Backends translate their native or simulated result into `PlaneData` and `ARHit`.
- `PlacementManager` consumes a `Transform3D`; it does not need to know which backend produced it.
- `MobileARBackend` is an adapter, not a reimplementation of ARCore/ARKit.
- `ARView.applied_packet` is read only to translate PocketAR's current plane snapshot. Do not mutate PocketAR's internal packet or backend state.

## Known limitations / next engineering steps

- The desktop backend's plane grouping is intentionally simple. It groups by collider and quantized normal, not by a robust geometric plane-fitting algorithm.
- Desktop plane timeout values are test heuristics. Real providers decide tracking quality and removal.
- `ARHit` currently returns the nearest detected plane hit from PocketAR on mobile; desktop raycasts can also hit a not-yet-published surface, indicated by an empty `plane_id`.
- Object placement is shared, but persistent anchors are not yet abstracted. For long-lived placement on mobile, add a common anchor interface backed by PocketAR's anchor API.
- Test Android and iOS on physical devices before relying on the adapter in production.
