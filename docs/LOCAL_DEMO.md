# Drishti: the localhost demo

The demo is the real app with one switch, `DEMO=true`. Complaints, tracking, the department console and the impact page run on sample data kept in the browser. That means no database, no keys and no internet for the complaint flow; the map tab still reads the live Supabase project. A "DEMO DATA" ribbon shows on every screen. Nothing is saved, and reloading the page resets it.

## Start it

**With Flutter installed** (from the repo root):

```bash
cd app
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=DEMO=true
```

Demo mode signs you in as a sample resident, so no email is needed.

To run against the real database instead (with real sign-in), leave out `--dart-define=DEMO=true` but keep `--web-port 5173`. Sign-in links only return to addresses on Supabase's allow-list, and port 5173 is on it.

**Without Flutter**: download the built demo instead.
1. Open the latest **app-web** run under the repo's Actions tab.
2. Download the `drishti-demo-web` artifact and unzip it.
3. In that folder, run `python3 -m http.server 8080`, or on Windows `py -m http.server 8080`.
4. Open http://localhost:8080 in Chrome.

## A five-minute walkthrough

1. **Home.** Read the headline, then drag the before/after picture; the outlined heap disappears on the later pass. Type `Shivajinagar` or `411005` and press **Look**, then **Follow Shivajinagar**. Switch to **हिं** and back.
2. **Raise a complaint.** Pick **Construction debris**. Tap the map on the horizontal road through the middle of Pune: the "Goes to" panel switches to **PWD road division**. Tap off the road and it switches to the **Municipal C&D waste cell**. Pick **Waste burning** and the target drops to 2 hours. Add a note and press **Raise complaint**; you get a ticket code such as `DRI-Q-0411`.
3. **Track it.** Press **Follow it live**. The timeline shows *Received*, with the reply clock counting down.
4. **Be the department.** Open the app's menu (**Officials** on the home page) and go to **Console**. Late complaints are at the top (the overflowing bin and the burning). Open your new complaint:
   - choose **Assigned** and post a message;
   - try **Resolved** without a photo, and it refuses;
   - attach any image and resolve;
   - press **Demo: run the next satellite passes**. The complaint becomes **Proven clean from space**.
5. **Back as the resident.** Open **Track**: every update is there, live. Press **Not fixed? Reopen** to show the resident's side of accountability.
6. **Impact.** Show the counts from found to proven, the reply times, complaints by type, and India's legacy-dumpsite goal with its source.

The sample complaints, areas and site counts are made up for the demo. The routing rules and reply targets are the same ones the database uses (targets are placeholders until a ward office confirms them).
