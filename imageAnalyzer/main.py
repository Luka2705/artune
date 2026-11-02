import openai
import base64
import requests
import json
import os
from dotenv import load_dotenv

# Load environment variables from a .env file
load_dotenv()

# Fetch API keys from environment variables
openai_api_key = os.getenv("OPENAI_API_KEY")
spotify_client_id = os.getenv("SPOTIFY_CLIENT_ID")
spotify_client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")

# Azure OpenAI Client initialization with the environment variable
client = openai.AzureOpenAI(
    api_version="2024-06-01",
    azure_endpoint="https://genai-nexus.api.corpinter.net/apikey/",
    api_key=openai_api_key,
)

# Function to get Spotify access token
def get_access_token(client_id, client_secret):
    url = "https://accounts.spotify.com/api/token"
    headers = {
        "Authorization": "Basic " + base64.b64encode((client_id + ":" + client_secret).encode()).decode()
    }
    data = {
        "grant_type": "client_credentials"
    }
    response = requests.post(url, headers=headers, data=data)
    return response.json().get("access_token")

# Function to get song recommendations based on audio features
def get_recommendations_based_on_features(audio_features, access_token, target_popularity):
    url = "https://api.spotify.com/v1/recommendations"
    
    params = {
        "limit": 10,
        "seed_genres": ",".join(audio_features.get("seed_genres", ["pop"])),
        "target_acousticness": audio_features["acousticness"],
        "target_danceability": audio_features["danceability"],
        "target_energy": audio_features["energy"],
        "target_instrumentalness": audio_features["instrumentalness"],
        "target_key": audio_features["key"],
        "target_liveness": audio_features["liveness"],
        "target_loudness": audio_features["loudness"],
        "target_mode": audio_features["mode"],
        "target_speechiness": audio_features["speechiness"],
        "target_tempo": audio_features["tempo"],
        "target_valence": audio_features["valence"],
        "target_popularity": target_popularity
    }
    
    headers = {
        "Authorization": f"Bearer {access_token}"
    }
    
    response = requests.get(url, headers=headers, params=params)
    return response.json()

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

# Encode the image and define the prompt
image_path = "./img.jpeg"
base64_image = encode_image(image_path)

# Define prompt with constraints for a JSON-only response
prompt = """
Du bist ein Bildanalyse-Experte. Deine Aufgabe ist es, das Bild, das ich dir gleich zur Analyse gebe, ausschließlich in die folgenden Kategorien einzuordnen:

{ "acousticness": Range 0 - 1, "danceability": Range 0 - 1, "duration_ms": Target duration of the track (ms), "energy": Range 0 - 1, "instrumentalness": Range 0 - 1, "key": Range 0 - 11, "liveness": Range 0 - 1, "loudness": Range -60 - 0, "mode": Range 0 - 1, "popularity": Range 0 - 100, "speechiness": Range 0 - 1, "tempo": Target tempo (BPM), "valence": Range 0 - 1, "seed_genres": Array of 3 strings from the following list: ["acoustic", "afrobeat", "alt-rock", "alternative", "ambient", "anime", "black-metal", "bluegrass", "blues", "bossanova", "brazil", "breakbeat", "british", "cantopop", "chicago-house", "children", "chill", "classical", "club", "comedy", "country", "dance", "dancehall", "death-metal", "deep-house", "detroit-techno", "disco", "disney", "drum-and-bass", "dub", "dubstep", "edm", "electro", "electronic", "emo", "folk", "forro", "french", "funk", "garage", "german", "gospel", "goth", "grindcore", "groove", "grunge", "guitar", "happy", "hard-rock", "hardcore", "hardstyle", "heavy-metal", "hip-hop", "holidays", "honky-tonk", "house", "idm", "indian", "indie", "indie-pop", "industrial", "iranian", "j-dance", "j-idol", "j-pop", "j-rock", "jazz", "k-pop", "kids", "latin", "latino", "malay", "mandopop", "metal", "metal-misc", "metalcore", "minimal-techno", "movies", "mpb", "new-age", "new-release", "opera", "pagode", "party", "philippines-opm", "piano", "pop", "pop-film", "post-dubstep", "power-pop", "progressive-house", "psych-rock", "punk", "punk-rock", "r-n-b", "rainy-day", "reggae", "reggaeton", "road-trip", "rock", "rock-n-roll", "rockabilly", "romance", "sad", "salsa", "samba", "sertanejo", "show-tunes", "singer-songwriter", "ska", "sleep", "songwriter", "soul", "soundtracks", "spanish", "study", "summer", "swedish", "synth-pop", "tango", "techno", "trance", "trip-hop", "turkish", "work-out", "world-music"] }

Es ist absolut entscheidend, dass du ausschließlich das JSON-Objekt mit den geforderten Werten als Antwort zurückgibst.
"""

# Send the request to the OpenAI API
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[
        {
            "role": "system",
            "content": "You are an expert in image analysis with a focus on extracting audio-related attributes and categorizing visual content to map it to relevant music genres and characteristics. Only respond with a JSON object containing the required numerical values and genre classifications based on the visual analysis."
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"}}
            ],
        }
    ],
    max_tokens=300
)

# Parse OpenAI response and get user input for popularity
try:
    # Get the raw response text
    response_text = response.choices[0].message.content.strip()
    print("Raw Response Text:", response_text)

    # Remove markdown formatting if present
    if response_text.startswith("```") and response_text.endswith("```"):
        response_text = response_text[response_text.find("{"):response_text.rfind("}") + 1]

    # Attempt to parse the cleaned JSON response
    audio_features = json.loads(response_text)

    # Check if parsed JSON contains the required audio feature fields
    required_keys = {"acousticness", "danceability", "energy", "instrumentalness", "key", 
                     "liveness", "loudness", "mode", "speechiness", "tempo", "valence", "seed_genres"}
    if all(key in audio_features for key in required_keys):
        # Prompt the user for the target popularity value
        target_popularity = int(input("Enter the desired popularity value (0-100): "))

        # Ensure the value is within the valid range
        if 0 <= target_popularity <= 100:
            # Get Spotify access token
            access_token = get_access_token(spotify_client_id, spotify_client_secret)
            
            # Fetch recommendations from Spotify based on OpenAI-derived audio features
            recommendations = get_recommendations_based_on_features(audio_features, access_token, target_popularity)

            # Display only the song name, artist(s), and preview URL from each recommendation
            if "tracks" in recommendations:
                print("Recommendations:")
                for track in recommendations["tracks"]:
                    song_name = track["name"]
                    artist_name = ", ".join(artist["name"] for artist in track["artists"])
                    preview_url = track.get("preview_url", "No preview available")
                
                    print(f"Song: {song_name}, Artist(s): {artist_name}, Preview URL: {preview_url}")
            else:
                print("No recommendations found.")
        else:
            print("Error: Popularity value must be between 0 and 100.")
    else:
        print("OpenAI response does not contain all required audio feature fields.")
except json.JSONDecodeError:
    print("Error: OpenAI response is not valid JSON.")
except Exception as e:
    print("Unexpected error:", e)