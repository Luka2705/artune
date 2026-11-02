import base64
from io import BytesIO
import os
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from PIL import Image
import api_server


class PredictTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.spotify_env = patch.dict(os.environ, {'SPOTIFY_CLIENT_ID': 'test', 'SPOTIFY_CLIENT_SECRET': 'test'})
        self.spotify_env.start()
        async def identity(songs): return [song.model_dump() for song in songs]
        self.spotify_mock = patch.object(api_server, 'resolve_songs', side_effect=identity)
        self.spotify_mock.start()
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=api_server.app), base_url='http://test')
        output = BytesIO()
        Image.new('RGB', (2000, 1000), 'blue').save(output, format='PNG')
        self.image = output.getvalue()

    async def asyncTearDown(self):
        await self.client.aclose()
        self.spotify_mock.stop()
        self.spotify_env.stop()

    async def post(self, image=None, popularity=50, provider='claude'):
        return await self.client.post('/predict/', files={'image': ('image.png', self.image if image is None else image, 'image/png')}, data={'target_popularity': str(popularity), 'provider': provider})

    async def test_claude_request_and_app_response(self):
        song = {'song_name': 'Teardrop', 'artist': 'Massive Attack', 'reason': 'Passt zur ruhigen Stimmung.'}
        client = AsyncMock()
        client.__aenter__.return_value = client
        client.messages.create.return_value = SimpleNamespace(stop_reason='end_turn', content=[SimpleNamespace(type='text', text=__import__('json').dumps({'recommendations': [song]}))])
        with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test-key'}), patch.object(api_server.anthropic, 'AsyncAnthropic', return_value=client):
            response = await self.post()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['message'], 'Success')
        self.assertIsNone(response.json()['recommendations'][0]['preview_url'])
        request = client.messages.create.call_args.kwargs
        image = request['messages'][0]['content'][0]['source']
        self.assertEqual(image['media_type'], 'image/jpeg')
        with Image.open(BytesIO(base64.b64decode(image['data']))) as resized:
            self.assertEqual(resized.size, (1568, 784))
        self.assertNotIn('tool_choice', request)
        self.assertNotIn('tools', request)
        self.assertEqual(request['output_config']['format']['type'], 'json_schema')

    async def test_validation_does_not_call_claude(self):
        with patch.object(api_server.anthropic, 'AsyncAnthropic') as factory:
            for kwargs in [{'image': b'not an image'}, {'image': b''}, {'popularity': 101}, {'image': b'x' * (api_server.MAX_UPLOAD_BYTES + 1)}]:
                response = await self.post(**kwargs)
                self.assertNotEqual(response.json()['message'], 'Success')
            factory.assert_not_called()

    async def test_health_identifies_artune(self):
        response = await self.client.get('/health')
        self.assertEqual(response.json()['service'], 'artune')
        self.assertIn('x-request-id', response.headers)

    async def test_unknown_provider(self):
        response = await self.post(provider='unknown')
        self.assertIn('Claude oder Ollama', response.json()['message'])

    async def test_ollama_request(self):
        song = {'song_name': 'Teardrop', 'artist': 'Massive Attack', 'reason': 'Ruhige Stimmung.'}
        client = AsyncMock()
        client.__aenter__.return_value = client
        from unittest.mock import Mock
        client.post.return_value = httpx.Response(200, json={'message': {'content': __import__('json').dumps({'recommendations': [song]})}}, request=httpx.Request('POST', 'http://ollama/api/chat'))
        with patch.object(api_server.httpx, 'AsyncClient', return_value=client):
            response = await self.post(provider='ollama')
        self.assertEqual(response.json()['message'], 'Success')
        payload = client.post.call_args.kwargs['json']
        self.assertFalse(payload['stream'])
        self.assertTrue(payload['messages'][1]['images'])

    async def test_ollama_unreachable(self):
        client = AsyncMock()
        client.__aenter__.return_value = client
        client.post.side_effect = httpx.ConnectError('connection refused')
        with patch.object(api_server.httpx, 'AsyncClient', return_value=client):
            response = await self.post(provider='ollama')
        self.assertIn('Ollama ist nicht erreichbar', response.json()['message'])

    async def test_claude_api_error_is_visible_and_redacted(self):
        import httpx2
        client = AsyncMock()
        client.__aenter__.return_value = client
        response = httpx2.Response(400, request=httpx2.Request('POST', 'https://api.anthropic.com/v1/messages'))
        client.messages.create.side_effect = api_server.anthropic.BadRequestError(
            'bad request', response=response,
            body={'error': {'type': 'invalid_request_error', 'message': 'Unsupported option for model. secret-test-key'}},
        )
        with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'secret-test-key'}), patch.object(api_server.anthropic, 'AsyncAnthropic', return_value=client), self.assertLogs('uvicorn.error', level='WARNING') as logs:
            result = await self.post()
        self.assertIn('Unsupported option for model.', result.json()['message'])
        self.assertNotIn('secret-test-key', result.text)
        self.assertNotIn('secret-test-key', str(logs.output))

    async def test_missing_key(self):
        with patch.dict(os.environ, {'ANTHROPIC_API_KEY': ''}):
            response = await self.post()
        self.assertIn('ANTHROPIC_API_KEY fehlt', response.json()['message'])

    async def test_malformed_claude_output(self):
        client = AsyncMock()
        client.__aenter__.return_value = client
        client.messages.create.return_value = SimpleNamespace(stop_reason='end_turn', content=[SimpleNamespace(type='text', text='{"recommendations": []}')])
        with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'test-key'}), patch.object(api_server.anthropic, 'AsyncAnthropic', return_value=client):
            response = await self.post()
        self.assertIn('ungültige Songdaten', response.json()['message'])


if __name__ == '__main__':
    unittest.main()
