import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import httpx
from spotify_catalog import resolve_songs, SpotifyError


class SpotifyTests(unittest.IsolatedAsyncioTestCase):
    def song(self, title='Teardrop', artist='Massive Attack'):
        return SimpleNamespace(song_name=title, artist=artist, reason='Passt zur Stimmung.')

    def track(self, artist='Massive Attack', preview=None):
        return {'id': 'real-id', 'name': 'Teardrop', 'artists': [{'name': artist}],
                'preview_url': preview, 'external_urls': {'spotify': 'https://open.spotify.com/track/real-id'},
                'album': {'name': 'Mezzanine', 'images': [{'url': 'https://i.scdn.co/image/cover'}]}}

    async def resolve(self, items, songs=None, search_status=200):
        requests=[]
        def handler(request):
            requests.append(request)
            if '/api/token' in str(request.url):
                return httpx.Response(200, json={'access_token': 'test-token'})
            self.assertEqual(request.headers['Authorization'], 'Bearer test-token')
            return httpx.Response(search_status, json={'tracks': {'items': items}})
        with patch.dict(os.environ, {'SPOTIFY_CLIENT_ID': 'test', 'SPOTIFY_CLIENT_SECRET': 'test'}):
            async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
                result=await resolve_songs(songs or [self.song()],client)
        return result,requests

    async def test_real_catalog_metadata_and_preview_are_returned(self):
        result,requests=await self.resolve([self.track(preview='https://p.scdn.co/preview.mp3')])
        self.assertEqual(result[0]['spotify_id'],'real-id')
        self.assertEqual(result[0]['preview_url'],'https://p.scdn.co/preview.mp3')
        self.assertIn('track:',requests[1].url.params['q'])
        self.assertEqual(result[0]['reason'],'Passt zur Stimmung.')
        self.assertEqual(result[0]['album_name'],'Mezzanine')

    async def test_missing_previews_do_not_remove_real_tracks(self):
        result,_=await self.resolve([self.track()])
        self.assertEqual(len(result),1)
        self.assertIsNone(result[0]['preview_url'])

    async def test_wrong_artist_is_not_a_match(self):
        result,requests=await self.resolve([self.track(artist='Unrelated Cover Artist')])
        self.assertEqual(result,[])
        self.assertEqual(len(requests),3) # token, fielded search, plain-text fallback

    async def test_duplicates_are_removed(self):
        result,_=await self.resolve([self.track()],songs=[self.song(),self.song()])
        self.assertEqual(len(result),1)

    async def test_rate_limit_is_actionable(self):
        with self.assertRaisesRegex(SpotifyError,'Suchlimit'):
            await self.resolve([],search_status=429)

    async def test_missing_credentials(self):
        with patch.dict(os.environ, {'SPOTIFY_CLIENT_ID':'','SPOTIFY_CLIENT_SECRET':''}):
            with self.assertRaisesRegex(SpotifyError,'fehlen'):
                await resolve_songs([self.song()])
