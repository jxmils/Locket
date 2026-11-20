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
import base64, datetime as dt, json, pathlib, sys
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
(folder/"books.json").write_text(json.dumps(dict(books=[book("Jason", True, [0,1,2,3]),book("Alex", False, [2,3]), book("Maya", False, [1]), book("Noah", False, [3])])))
PY
for tab in today postbox books; do
  SIMCTL_CHILD_LOCKET_CAPTURE_TAB="$tab" xcrun simctl launch --terminate-running-process "$device" com.jasonmiller.Locket
  sleep 4
  xcrun simctl io "$device" screenshot "$out/$tab.png"
done
