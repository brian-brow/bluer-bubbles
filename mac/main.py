from fastapi import FastAPI, Depends
from routes import router
from auth import verify_api_key

app = FastAPI()
app.include_router(router, dependencies=[Depends(verify_api_key)])
