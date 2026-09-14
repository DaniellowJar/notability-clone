from io import BytesIO

import httpx
import uvicorn
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse

import base64

app = FastAPI(title="rembg OpenAI-compatible shim")

API_KEY = __import__("os").environ.get("SHIM_API_KEY", "")


def check_auth(authorization: str | None) -> str | None:
    if not API_KEY:
        return None
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Bearer token")
    scheme, _, token = authorization.partition(" ")
    if token != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return None


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/v1/images/edits")
async def remove_background(
    image: UploadFile = File(...),
    model: str | None = Form("u2net"),
    prompt: str | None = Form(None),
    authorization: str | None = Header(None),
) -> JSONResponse:
    check_auth(authorization)
    data = await image.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")

    async with httpx.AsyncClient() as client:
        upstream = await client.post(
            f"{__import__('os').environ.get('REMBG_URL', 'http://rembg:7000')}/api/remove",
            data={"model": model},
            files={"file": (image.filename or "input.png", data, image.content_type)},
            timeout=120,
        )
    if upstream.status_code != 200:
        raise HTTPException(status_code=502, detail=f"rembg error {upstream.status_code}: {upstream.text[:500]}")

    b64 = base64.b64encode(upstream.content).decode("ascii")
    return JSONResponse(content={"created": 0, "data": [{"b64_json": b64}]})


@app.post("/v1/images/edits/remove-background")
async def remove_background_alt(
    image: UploadFile = File(...),
    authorization: str | None = Header(None),
) -> JSONResponse:
    return await remove_background(image, "u2net", None, authorization)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)