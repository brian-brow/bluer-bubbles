from fastapi import Header, HTTPException
from dotenv import load_dotenv
import os

load_dotenv()

API_KEY = os.environ.get('BLUE_BUBBLES_API_KEY')

async def verify_api_key(x_api_key: str = Header(...)):
    if not API_KEY or x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail='Invalid or missing API key')
