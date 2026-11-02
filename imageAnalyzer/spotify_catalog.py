"""Resolve LLM suggestions against real Spotify catalogue entries."""
import asyncio
from difflib import SequenceMatcher
import logging
import os
import re
import unicodedata

import httpx

logger = logging.getLogger('uvicorn.error')


class SpotifyError(Exception):
    pass


def normalized(value):
    value = unicodedata.normalize('NFKD', value).casefold()
    return ' '.join(re.sub(r'[^a-z0-9 ]', '', value).split())


def match_score(song, track):
    title = SequenceMatcher(None, normalized(song.song_name), normalized(track.get('name', ''))).ratio()
    artist = max((SequenceMatcher(None, normalized(song.artist), normalized(a.get('name', ''))).ratio()
                  for a in track.get('artists', [])), default=0)
    # Reject unrelated results, covers by another artist and most incorrect versions.
    return title + artist if title >= .88 and artist >= .80 else 0


def spotify_status(response):
    if response.status_code == 429:
        raise SpotifyError('Spotify-Suchlimit erreicht. Bitte später erneut versuchen.')
    if response.status_code in (401, 403):
        raise SpotifyError('Spotify verweigert den Zugriff. Bitte Client-ID, Secret und den Zugriff deiner Spotify-App prüfen.')
    response.raise_for_status()


async def resolve_songs(songs, client=None):
    client_id = os.getenv('SPOTIFY_CLIENT_ID')
    secret = os.getenv('SPOTIFY_CLIENT_SECRET')
    if not client_id or not secret:
        raise SpotifyError('SPOTIFY_CLIENT_ID und SPOTIFY_CLIENT_SECRET fehlen in imageAnalyzer/.env. Backend danach neu starten.')
    if client is None:
        async with httpx.AsyncClient(timeout=12) as session:
            return await resolve_songs(songs, session)
    try:
        response = await client.post('https://accounts.spotify.com/api/token',
                                     auth=(client_id, secret), data={'grant_type': 'client_credentials'})
        spotify_status(response)
        token = response.json()['access_token']
        headers = {'Authorization': f'Bearer {token}'}
        semaphore = asyncio.Semaphore(3)

        async def lookup(song):
            async with semaphore:
                title = song.song_name.replace('"', '')
                artist = song.artist.replace('"', '')
                # A fielded query first, then plain text to tolerate punctuation differences.
                for query in [f'track:"{title}" artist:"{artist}"', f'{title} {artist}']:
                    response = await client.get('https://api.spotify.com/v1/search', headers=headers,
                                                params={'q': query, 'type': 'track', 'limit': 5,
                                                        'market': os.getenv('SPOTIFY_MARKET', 'DE')})
                    spotify_status(response)
                    items = response.json().get('tracks', {}).get('items', [])
                    candidates = [track for track in items if match_score(song, track) > 0 and track.get('id') and track.get('external_urls', {}).get('spotify')]
                    if not candidates:
                        continue
                    track = max(candidates, key=lambda t: (match_score(song, t), bool(t.get('preview_url'))))
                    images = track.get('album', {}).get('images', [])
                    return {
                        'song_name': track['name'],
                        'artist': ', '.join(a['name'] for a in track['artists']),
                        'reason': song.reason,
                        'spotify_id': track['id'],
                        'spotify_url': track['external_urls']['spotify'],
                        'album_name': track.get('album', {}).get('name'),
                        'artwork_url': images[0]['url'] if images else None,
                        'preview_url': track.get('preview_url') or None,
                    }
                logger.info('Spotify: no confident match for a suggested song')
                return None

        results = await asyncio.wait_for(asyncio.gather(*(lookup(song) for song in songs)), timeout=45)
        unique = {track['spotify_id']: track for track in results if track}
        logger.info('Spotify verified %s/%s suggestions; %s previews available', len(unique), len(songs), sum(bool(t['preview_url']) for t in unique.values()))
        return list(unique.values())
    except SpotifyError:
        raise
    except (httpx.RequestError, asyncio.TimeoutError):
        raise SpotifyError('Spotify ist gerade nicht erreichbar. Bitte erneut versuchen.') from None
    except (httpx.HTTPStatusError, KeyError, ValueError, TypeError):
        raise SpotifyError('Spotify konnte die Suche nicht abschließen. Bitte Zugangsdaten und Serverlogs prüfen.') from None
