# Local Agora 6.6.3 patch

Source: `AgoraIO-Extensions/Agora-Flutter-SDK`, tag `6.6.3`
(`729bc1afe470c239b45602dfd6f6ff6b09331d31`).

This app sets `RtcEngineContext.autoRegisterAgoraExtensions` to `false` for its
audio-only live feature. In that mode, the local patch in
`lib/src/impl/agora_rtc_engine_impl.dart` skips initialization of the Iris video
frame buffer manager.

The Android dependency in `android/build.gradle` also replaces the upstream
`agora-special-full` and `full-screen-sharing` artifacts with Agora's official
`voice-sdk` 4.6.2. The full SDK loads every bundled video and optional extension
while `CreateIrisApiEngine` is starting, before
`autoRegisterAgoraExtensions=false` reaches `RtcEngine.initialize`. On the
tested Android device and emulator, that first-process bootstrap can remain
pending. The Voice SDK keeps the core audio RTC and data-stream APIs used by
this app without loading the unused video extensions.

When upgrading Agora:

1. Re-test a fresh install/cold process on both a physical Android device and
   an Android emulator.
2. Keep the native Voice SDK version compatible with the Iris and Flutter
   wrapper versions selected by Agora's release.
3. Remove these patches if upstream provides an audio-only Flutter dependency
   and no longer creates video rendering resources for an audio-only engine.
4. Keep `autoRegisterAgoraExtensions: false` unless this feature starts using
   Agora video or optional extensions.
