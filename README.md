# Simple Card Game (Flutter Deck Draw Demo)

A minimal single-player deck drawing demo implemented per `flutter_deck_draw_plan.md`. The app shuffles a small money deck, lets you draw cards, shows the last drawn card, and reports how many cards remain.

## What’s included
- Deck logic and UI in `lib/main.dart`
- Simple card model with money values (1–4)
- Draw button, deck counter, snackbar when empty, and a reset/shuffle button

## Run it locally
Flutter CLI is not available in this workspace, so the project wasn’t scaffolded or run here. Once you have Flutter installed:
1) From the repo root, generate missing platform scaffolding (if needed): `flutter create .`
2) Fetch dependencies: `flutter pub get`
3) Start an emulator or connect a device
4) Run the app: `flutter run`

You can evolve the structure later by moving the model into `lib/models/` and adding a deck service, as outlined in the plan.
