# GM Assistant

Customer companion app for Green Motion car rental customers (Zurich, Switzerland). Built with SwiftUI and Firebase.

Customers enter their reservation code and license plate to view their rental, upload check-out/return/damage photos, request a shuttle and track it live on a map, and reach roadside assistance or the branch office directly. Submissions appear in real time on the staff side.

## Stack

- SwiftUI (iOS 17+), Swift 5, the `Observation` framework (`@Observable`)
- Firebase: Auth (anonymous), Firestore, Cloud Functions, Storage

## Features

- Reservation lookup by RES code + plate suffix (two-factor, rate-limited server-side)
- Check-out / return / damage photo capture and upload
- Free-text notes to staff
- Shuttle request with live driver tracking and ETA
- Roadside assistance and office calling
- English / German / Turkish localization

## Project structure

```
GM Assistant/
  GM_AssistantApp.swift, ContentView.swift
  Models/      CustomerRecord, CustomerReservation, ShuttleDriverLocation
  Services/    AppState, CustomerRecordService, PhotoUploadService,
               ReservationService, ShuttleTrackingService
  Theme/       GMTheme
  Utilities/   Haptics
  Views/       WelcomeView, ReservationHomeView, PhotoCaptureView,
               RemotePhotoGalleryView, ShuttleFullScreenMapView
```

The backend (Cloud Functions and Firestore/Storage security rules) is not part of this repo.
