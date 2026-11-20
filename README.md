# Stampnote

An iPhone stamp book. Choose one photo for the day, keep it on a dated page, and invite friends to turn through your book.

## Using Stampnote

- **Today** — compose through the live perforated stamp. Tap the shutter to freeze the photo and press the postmark onto it. Retake or tap Post stamp to use the day’s page. You can switch lenses or choose a picture from Photos.
- **Postbox** — the app opens here. Swipe through stamps from friends, newest first. The perforated plus labeled **Make today’s stamp** opens your daily page and disappears after you post. Mutual friends who can open a stamp can like it and leave comments. Pin a friend’s stamp to your book for the day. A visitor needs access to the original book to see a pin.
- **Stamp books** — browse your own book or choose a friend's, grouped by month. Tap a stamp to open it.
- **Invitations** — open your own book and choose **Book options (•••) → Share stamp book**. Apple's sharing sheet grants invited people read-only access to the entire book, including future entries. A friend sends their own invitation to share back. Use the same sheet to manage access.
- **Home Screen** — add the **Friends’ stamps** widget in small, medium or large. Tap the stamp to advance when there are multiple entries. With one entry, a tap opens the Postbox. WidgetKit schedules background updates.

The book keeps the time zone in which it was created. Each day has one CloudKit record in the owner's private book zone. A create-only write prevents two devices from filling the same date twice. Saving needs iCloud and a connection. Previously downloaded books can be read offline. Photos are re-encoded before upload so the uploaded JPEG contains the image without the source file's GPS metadata. Full-size and widget-size copies use the shared app container.

## Building on iPhone

Open **Locket.xcodeproj** and run the **Locket** scheme on iOS 17 or later. The project includes the app and the embedded FriendsStamps widget.

For a signed device build, configure both bundle IDs on the Apple Developer team:

| Target | Bundle ID |
| --- | --- |
| Locket | com.jasonmiller.Locket |
| FriendsStamps | com.jasonmiller.Locket.FriendsStamps |

Both targets use the App Group `group.com.jasonmiller.Locket` and the CloudKit container `iCloud.com.jasonmiller.Locket`. The app also declares its camera usage and accepts CloudKit share invitations. Use two different iCloud accounts to test the invite, revisit an older stamp, post a new one, page through the widget, and revoke access. The deployed schema is tracked in `CloudKit/StampBooks.ckdb`.

Pushes to `main` build Stampnote and its widget, sign them with the repository’s encrypted Apple credentials, upload the IPA and wait for the internal TestFlight group. The workflow also checks daily boundaries and widget paging and captures iPhone screenshots using sample books. Pull requests build and run the checks without Apple credentials.
