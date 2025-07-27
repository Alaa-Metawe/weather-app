import json
import os
import requests
from datetime import datetime

# Environment variables will be set by Terraform
RAPIDAPI_KEY = os.environ.get('RAPIDAPI_KEY')
RAPIDAPI_HOST = os.environ.get('RAPIDAPI_HOST') # e.g., 'community-open-weather-map.p.rapidapi.com'
WEATHER_API_URL = os.environ.get('WEATHER_API_URL') # e.g., 'https://community-open-weather-map.p.rapidapi.com/weather'

def lambda_handler(event, context):
    """
    Handles incoming API Gateway requests, fetches weather data, and returns it.
    """
    try:
        # Log the incoming event for debugging
        print(f"Received event: {json.dumps(event)}")

        # Parse the request body (assuming JSON for POST requests)
        # For GET requests, parameters might be in event['queryStringParameters']
        if event.get('body'):
            body = json.loads(event['body'])
            city = body.get('city')
        elif event.get('queryStringParameters'):
            city = event['queryStringParameters'].get('city')
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*', # Allow CORS for frontend
                    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
                },
                'body': json.dumps({'error': 'City parameter missing in request body or query string.'})
            }

        if not city:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
                },
                'body': json.dumps({'error': 'City parameter is required.'})
            }

        print(f"Fetching weather for city: {city}")

        # RapidAPI headers
        headers = {
            "X-RapidAPI-Key": RAPIDAPI_KEY,
            "X-RapidAPI-Host": RAPIDAPI_HOST
        }

        # Parameters for the weather API call
        # CORRECTED: Use "place" instead of "q" and "units" as "standard"
        params = {
            "place": city, # Query parameter for city name, changed from "q" to "place"
            "units": "standard", # Changed from "metric" to "standard" as per your curl example
            "mode": "json", # Added as per your curl example
            "lang": "en" # Added as per your curl example
        }

        response = requests.get(WEATHER_API_URL, headers=headers, params=params, timeout=10)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)

        weather_data = response.json()
        print(f"Weather data received: {json.dumps(weather_data)}")

        # Reformat the result in a nice GUI-friendly format
        # UPDATED: Adjusted parsing based on the actual JSON response structure
        # The API returns a list of forecast data, we'll use the first item for current conditions.
        first_forecast = weather_data.get('list', [{}])[0] # Get the first item from the 'list' array

        formatted_weather = {
            'city': city, # The API doesn't return city name in the response, use the input city
            'country': None, # The API response doesn't seem to contain country code directly
            'temperature': first_forecast.get('main', {}).get('temprature'), # Temperature in Kelvin
            'feels_like': first_forecast.get('main', {}).get('temprature_feels_like'), # Feels like temperature in Kelvin
            'description': first_forecast.get('weather', [{}])[0].get('description'),
            'icon': first_forecast.get('weather', [{}])[0].get('icon'),
            'humidity': first_forecast.get('main', {}).get('humidity'),
            'wind_speed': first_forecast.get('wind', {}).get('speed'),
            'timestamp': datetime.now().isoformat()
        }

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*', # Crucial for CORS
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps(formatted_weather)
        }

    except requests.exceptions.HTTPError as e:
        status_code = e.response.status_code
        error_message = f"HTTP error occurred: {e.response.text}"
        print(error_message)
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({'error': 'Failed to fetch weather data from external API.', 'details': error_message})
        }
    except requests.exceptions.ConnectionError as e:
        error_message = f"Connection error occurred: {e}"
        print(error_message)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({'error': 'Network connection error while fetching weather data.'})
        }
    except requests.exceptions.Timeout as e:
        error_message = f"Request timed out: {e}"
        print(error_message)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({'error': 'Request to external API timed out.'})
        }
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body.'})
        }
    except Exception as e:
        error_message = f"An unexpected error occurred: {e}"
        print(error_message)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)})
        }
