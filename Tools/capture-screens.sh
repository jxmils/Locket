#!/bin/bash
set -euo pipefail
app="${1:?Pass the simulator app path}"
out="${2:?Pass an output directory}"
device=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(dev["udid"] for runtime,devices in reversed(list(d.items())) if "iOS" in runtime for dev in devices if dev["name"].startswith("iPhone") and "Pro" in dev["name"]))')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$device" "$app"
container=$(xcrun simctl get_app_container "$device" com.jasonmiller.Locket data)
fixture="$container/Library/Caches/LocketCapture"
mkdir -p "$fixture" "$out"
# Sample pictures are used exclusively for simulator screenshots.
photos=(photo-1470770841072-f978cf4d019e photo-1441974231531-c6227db76b6e photo-1442512595331-e89e73853f31 photo-1476514525535-07fb3b4ae5f1)
for index in "${!photos[@]}"; do
  curl -fsSL --retry 3 "https://images.unsplash.com/${photos[$index]}?w=1000&q=85&fm=jpg" -o "$fixture/$index.jpg"
  sips -g pixelWidth "$fixture/$index.jpg"
done
curl -fsSL --retry 3 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=192&h=192&fit=crop&crop=faces&fm=jpg' -o "$fixture/portrait.jpg"
curl -fsSL --retry 3 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=192&h=192&fit=crop&crop=faces&fm=jpg' -o "$fixture/owner.jpg"
python3 - "$fixture" <<'PY'
import hashlib, base64, datetime as dt, json, pathlib, sys
folder = pathlib.Path(sys.argv[1])
now = dt.datetime.now(dt.timezone.utc)
epoch = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
def book(author, mine, pictures):
    stamps = []
    for offset, picture in enumerate(pictures):
        when = now - dt.timedelta(days=offset)
        day = when.date().isoformat()
        stamps.append(dict(id=day, day=day, posted=(when-epoch).total_seconds(), photo=f"{picture}.jpg", thumbnail=f"{picture}.jpg"))
    return dict(id=author, author=author, mine=mine, timeZone="UTC", stamps=stamps, portrait=base64.b64encode((folder/("owner.jpg" if mine else "portrait.jpg")).read_bytes()).decode() if mine or author=="Alex" else None)
books=[book("Jason", True, [0,1,2,3]),book("Alex", False, [2,3]), book("Maya", False, [1]), book("Noah", False, [3])]
# Noah still has a book but his only stamp is from yesterday.
books[3]["stamps"] = book("Noah", False, [0,3])["stamps"][1:]
for n, b in enumerate(books, start=1):
    b["mailbox"]=base64.b64encode(bytes([n])*32).decode()
    b["discussionKey"]=base64.b64encode(bytes([n+10])*32).decode()
older=book("Jason", True, [1])["stamps"][0].copy()
last_month=now.replace(day=1)-dt.timedelta(days=1)
older.update(day=last_month.date().isoformat(),id=last_month.date().isoformat(),posted=(last_month-epoch).total_seconds())
books[0]["stamps"].append(older)
target=hashlib.sha256((books[1]["mailbox"]+"/"+books[1]["stamps"][0]["id"]).encode()).hexdigest()
# Give the archive enough stamps to exercise the four-stamp page boundary.
album_owner = dict(books[0])
history = book("Jason", True, [0,1,2,3,1,2])["stamps"]
album_owner["stamps"] = list({s["day"]: s for s in books[0]["stamps"] + history}.values())
(folder/"album.json").write_text(json.dumps(dict(books=[album_owner] + books[1:])))
books[0]["activities"]=[dict(id="pin-demo",target=target,kind="pin",day=now.date().isoformat(),created=(now-epoch).total_seconds())]
(folder/"empty.json").write_text(json.dumps(dict(books=[])))
(folder/"posted.json").write_text(json.dumps(dict(books=books)))
books[0]["stamps"]=books[0]["stamps"][1:]
(folder/"unposted.json").write_text(json.dumps(dict(books=books)))
PY
# Sample comments use the same authenticated envelope the simulator reads in production.
swift - "$fixture/unposted.json" <<'SWIFT'
import Foundation
import CryptoKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
var shelf = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
var books = shelf["books"] as! [[String: Any]]
let pin = (books[0]["activities"] as! [[String: Any]])[0]
let target = pin["target"] as! String
let room = SymmetricKey(data: Data(base64Encoded: books[1]["discussionKey"] as! String)!)
for (actor, action, text) in [(2, "comment", "Is this the café by the station?"), (1, "comment", "Yes! I finally made it in before work."), (0, "like", "")] {
    let id = action + "-sample-" + String(actor)
    let data = try JSONSerialization.data(withJSONObject: ["action": action, "text": text])
    let sealed = try AES.GCM.seal(data, using: room, authenticating: Data((target + id).utf8))
    var activity = pin
    activity["id"] = id
    activity["kind"] = "note"
    activity["created"] = Date().timeIntervalSinceReferenceDate
    activity["contents"] = sealed.combined!.base64EncodedString()
    var entries = books[actor]["activities"] as? [[String: Any]] ?? []
    entries.append(activity)
    books[actor]["activities"] = entries
}
shelf["books"] = books
try JSONSerialization.data(withJSONObject: shelf).write(to: url)
SWIFT
for tab in today postbox books calendar press zoom proof comments detail pins friend welcome empty widget-small widget-medium widget-large; do
  sample=posted
  case "$tab" in
    postbox|press|zoom|proof|comments) sample=unposted ;;
    books|calendar|friend) sample=album ;;
    welcome|empty) sample=empty ;;
  esac
  cp "$fixture/$sample.json" "$fixture/books.json"
  SIMCTL_CHILD_LOCKET_CAPTURE_TAB="$tab" xcrun simctl launch --terminate-running-process "$device" com.jasonmiller.Locket
  sleep 4
  xcrun simctl io "$device" screenshot "$out/$tab.png"
done

cp "$fixture/unposted.json" "$fixture/books.json"
rm -f "$fixture/record-shutter"
for scene in press swipe; do
  SIMCTL_CHILD_LOCKET_CAPTURE_TAB="${scene}Demo" xcrun simctl launch --terminate-running-process "$device" com.jasonmiller.Locket
  xcrun simctl io "$device" recordVideo --codec=h264 "$out/$scene-demo.mp4" &
  recorder=$!
  if [[ "$scene" == press ]]; then
    sleep 5
    touch "$fixture/record-shutter"
    sleep 4
  else
    sleep 9
  fi
  kill -INT "$recorder"
  wait "$recorder"
  test -s "$out/$scene-demo.mp4"
done
