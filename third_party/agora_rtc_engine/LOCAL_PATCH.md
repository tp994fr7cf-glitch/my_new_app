# Local Agora 6.6.3 patch

Source: `AgoraIO-Extensions/Agora-Flutter-SDK`, tag `6.6.3`
(`729bc1afe470c239b45602dfd6f6ff6b09331d31`).

This app sets `RtcEngineContext.autoRegisterAgoraExtensions` to `false` for its
audio-only live feature. In that mode, the local patch in
`lib/src/impl/agora_rtc_engine_impl.dart` skips initialization of the Iris video
frame buffer manager.

The Android dependency in `android/build.gradle` also replaces the upstream
`agora-special-full` and `full-screen-sharing` artifacts with Agora's
`voice-rtc-basic` 4.6.2 module. The full SDK and the `voice-sdk` aggregate load
bundled optional extensions that this feature does not use. The basic voice
runtime keeps the core audio RTC and data-stream APIs used by this app without
loading the unused AI audio, spatial audio, video, and effect extensions.

Reducing the dependency did not by itself resolve an observed Android cold-start
hang in `CreateIrisApiEngine`. Agora's shared-native-handle path also remained
blocked in the same function after the native `RtcEngine` had been created
successfully. The app therefore uses the Agora Android API directly through a
Flutter `MethodChannel` for live audio on Android. This path does not initialize
Iris. Other platforms continue to use the Flutter package.

When upgrading Agora:

1. Re-test a fresh install/cold process on both a physical Android device and
   an Android emulator.
2. Keep the native Voice SDK version compatible with the Iris and Flutter
   wrapper versions selected by Agora's release.
3. Re-check whether the direct Android backend is still required.
4. Remove these patches if upstream provides an audio-only Flutter dependency
   and no longer creates video rendering resources for an audio-only engine.
5. Keep `autoRegisterAgoraExtensions: false` unless this feature starts using
   Agora video or optional extensions.
