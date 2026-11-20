# Locket

An iPhone stamp book. Choose one photo for the day, keep it on a dated page, and invite friends to turn through your book.

## Using Locket

- **Today** — name your book, take a photo or choose one from Photos, preview the perforated paper frame, then save. Trying a different photo before saving is fine. Saving uses that day’s page.
- **Postbox** — tap the photo or **Next stamp** to turn through stamps from friends, newest first.
- **Stamp books** — browse your own book or choose a friend's, grouped by month. Tap a stamp to open it.
- **Invitations** — choose **Invite to my stamp book**. Apple's sharing sheet grants invited people read-only access to the entire book, including future entries. A friend sends their own invitation to share back. Use the same sheet to manage access.
- **Home Screen** — add the **Friends’ stamps** widget in small, medium or large. Tap the stamp to advance when there are multiple entries. With one entry, a tap opens the Postbox. WidgetKit schedules background updates.

The book keeps the time zone in which it was created. Each day has one CloudKit record in the owner's private book zone. A create-only write prevents two devices from filling the same date twice. Saving needs iCloud and a connection. Previously downloaded books can be read offline. Photos are re-encoded before upload so the uploaded JPEG contains the image without the source file's GPS metadata. Full-size and widget-size copies use the shared app container.

## Building on iPhone

Open **Locket.xcodeproj** and run the **Locket** scheme on iOS 17 or later. The project includes the app and the embedded FriendsStamps widget.

For a signed device build, configure both bundle IDs on the Apple Developer team:

| Target | Bundle ID |
| --- | --- |
| Locket | com.jasonmiller.Locket |
| FriendsStamps | com.jasonmiller.Locket.FriendsStamps |

Both targets use the App Group `group.com.jasonmiller.Locket` and the CloudKit container `iCloud.com.jasonmiller.Locket`. The app also declares its camera usage and accepts CloudKit share invitations. Use two different iCloud accounts to test the invite, revisit an older stamp, post a new one, page through the widget, and revoke access. Create a book and a stamp in the development environment, then deploy the CloudKit schema to production before distributing a TestFlight build.

The GitHub workflow tests daily boundaries and feed paging, builds for iOS Simulator, and checks that the widget is embedded. It does not change the Apple Developer account or submit the app.
