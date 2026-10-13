# Install TypeSwitch

TypeSwitch requires macOS 15 or newer. Release DMGs contain a universal app for Apple silicon and Intel Macs; Xcode and Python are not needed to run it.

**Release status:** no notarized binary release has been published yet. Until a signed release is available, use the local source build described in the repository README. Files marked `preview` are ad-hoc signed packaging checks, not public installation releases.

When a signed release is available, download the `.dmg` from [GitHub Releases](https://github.com/ywdagency/typeswitch/releases). Open the disk image and drag **TypeSwitch.app** onto **Applications**. Eject the image, then open TypeSwitch from Applications. The app runs in the menu bar.

In TypeSwitch Settings → General, use **Enable…** for **Input Monitoring** and **Accessibility**, then grant the requested access in System Settings → Privacy & Security. Return to TypeSwitch so it can refresh permission status. If macOS does not list the app, use **Show TypeSwitch in Finder** and add that installed copy with `+` in the matching permission pane. A restart may be required if macOS requests one. These permissions must be granted by the user.

Enable the English, Russian, and/or Ukrainian input sources you intend to use in macOS Keyboard settings, then select the corresponding layouts in TypeSwitch. Test with disposable text first: this is experimental software with an incomplete cross-app compatibility matrix. `Control+Option+Space` pauses or resumes correction. Immediate Esc restores the most recent eligible correction and saves a permanent exception for its original spelling and layout.

For an update, quit TypeSwitch from its menu, replace the installed app with the new copy, and reopen it. Avoid running copies from both `~/Applications` and `/Applications`; keep the copy to which you granted permissions. Settings, learned words, and exceptions remain local. If macOS requests access again, review the installed app in both permission panes.

To uninstall, quit TypeSwitch, remove its permissions in System Settings, and move TypeSwitch.app to the Trash. Removing the app does not erase local preferences or optional diagnostics.

The app has no network client, account, telemetry, clipboard collection, or runtime dictionary download. License notices are included inside TypeSwitch.app → Contents → Resources → Legal. Source and verification limits are documented at [the repository](https://github.com/ywdagency/typeswitch).
