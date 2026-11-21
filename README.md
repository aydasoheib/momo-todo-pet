# Momo the Monkey

A tiny pixel monkey pet that stays alive when you get your tasks done. Momo reads your Google Calendar and Google Tasks, sends a "Feed me!" reminder before things are due, gets hungry (and eventually fades away) if you ignore them, and does a happy spin when you finish everything.

- Adopt and name your monkey (with a pretend adoption certificate)
- Dress them up: fur colours, hats, flower, headphones, fur coat, sunglasses
- Health bar with sad, sick and ghost stages
- Tabs for calendar events, to-dos and starred emails

Everything is stored on your own device. There is no server and no account.

## Try it in a browser

```bash
python3 -m http.server 5173
```

Open http://localhost:5173 and use **Demo mode**. To connect Google in the browser you need your own Google Web client ID (paste it into the Google setup box).

## Build the iPhone app

You need a Mac with Xcode and a free Apple ID.

1. In Google Cloud, create an **iOS** OAuth client ID whose Bundle ID matches the app (default `com.momothemonkey.app`, change it to your own). Enable the Calendar API and the Tasks API.
2. Copy `config.example.js` to `config.js` and paste your iOS client ID into it. `config.js` is private and is never committed.
3. Open `ios/Momo.xcodeproj` in Xcode.
4. Select the **Momo** target, then **Signing & Capabilities**, pick your **Team**, and change the **Bundle Identifier** to one that is yours.
5. Plug in your iPhone (turn on Developer Mode), choose it as the run destination, and press play.

## Privacy

Momo only asks to read your calendar and to view or tick off your Google Tasks. Sign-in uses Google's standard OAuth with PKCE, and the refresh token is kept in the iPhone Keychain.
