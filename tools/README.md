`render-launch-title.swift` creates the opening title using Patrick Hand glyphs filled with seeded PencilKit pencil strokes. The shipped PNGs keep startup free of rasterization work.

To regenerate, compile it for an iOS Simulator with `-D LAUNCH_TITLE_EXPORTER` and `TheChineseRoom/Support/Environment.swift`. Package the executable in a simulator app with PatrickHand-Regular.ttf registered in UIAppFonts, then launch it. It writes `title-ink`, `title-light`, and `title-dark` PNGs at 1x, 2x, and 3x into that app's Documents directory (locate it with `xcrun simctl get_app_container <device> <bundle-id> data`).

Copy the ink variants into PencilLaunchTitle.imageset and the light/dark variants into LaunchTitleGuide.imageset. LaunchScreen.storyboard shows the faint guide; LaunchTitleView reveals the full ink image over it. LaunchBackground.colorset is a static launch-screen copy of the adaptive background in Environment.swift and must stay in sync with it.
