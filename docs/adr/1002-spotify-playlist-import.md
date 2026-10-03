# ADR-1002: Import Spotify playlists from export files

## Status

Accepted

## Context

People moving from Spotify want their playlists in YouTube Music. Mozaic reads
the library and playlists live from the signed-in YouTube Music account, so a
playlist created in that account appears in Mozaic, the YouTube Music website,
and the mobile apps alike. The open question is how to get the Spotify track
list in.

- The Spotify Web API needs a registered client ID and an OAuth flow, and its
  playlist endpoints are restricted for new apps.
- Scraping a public playlist link (the embed page) works today but is fragile,
  covers only public playlists, and conflicts with Spotify's terms.
- Spotify users can already export their playlists: Exportify, TuneMyMusic, and
  Soundiiz write CSV, and Spotify's account data download contains
  `Playlist*.json` and `YourLibrary.json`.

## Decision

Import works from files. The user picks an export file in Library → Import
Playlist and Mozaic:

1. Parses it with `PlaylistImportParser`: CSV with a header row (column-name
   aliases for Exportify, TuneMyMusic, and Soundiiz), Spotify account-data
   JSON (every playlist in the file, or saved tracks as "Liked Songs"), or
   plain text with one `Artist - Title` per line.
2. Searches YouTube Music songs for each track (title without Spotify version
   suffixes, plus the primary artist), four searches at a time.
3. Scores candidates with `PlaylistTrackMatcher` on title, artist, and
   duration, penalizes covers, karaoke, and similar versions the source didn't
   ask for, and accepts the best result at or above 0.6.
4. Shows matched and unmatched counts, then creates a private playlist with the
   existing `PlayerService.saveQueueAsPlaylist(title:songs:owner:)` path, which
   already handles the account-switch guard and library refresh.

No Spotify credentials, API calls, or new dependencies are involved.

## Consequences

- The playlist lives in the YouTube Music account, so it syncs everywhere
  without Mozaic keeping its own copy.
- Users need one extra step (export first). The sheet links to Exportify.
- Matching is heuristic: unmatched tracks are listed so users can add them by
  hand, and an occasional wrong version is possible.
- Large playlists issue one search per track; four concurrent requests keep
  this reasonable without bursting the InnerTube endpoint.
- Library and playlist refresh now drop cached responses
  (`LibraryMutationActions.invalidateResponseCaches()`), so playlists created
  or edited elsewhere appear on the next refresh instead of after the 5–30
  minute cache TTL.
