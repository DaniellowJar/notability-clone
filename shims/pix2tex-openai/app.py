from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
import httpx
import uvicorn

app = FastAPI(title="pix2tex OpenAI-compatible shim")

API_KEY = __import__("os").environ.get("SHIM_API_KEY", "")


def check_auth(authorization: str | None) -> None:
    if not API_KEY:
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or malformed Bearer token")
    if authorization.partition(" ")[2] != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/v1/math/ocr")
async def math_ocr(
    image: UploadFile = File(...),
    authorization: str | None = Header(None),
) -> JSONResponse:
    check_auth(authorization)
    data = await image.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")

    upstream_url = __import__("os").environ.get("PIX2TEX_URL", "http://pix2tex:8502")
    async with httpx.AsyncClient() as client:
        upstream = await client.post(
            f"{upstream_url}/predict",
            files={"file": (image.filename or "equation.png", data, image.content_type)},
            timeout=60,
        )
    if upstream.status_code != 200:
        raise HTTPException(status_code=502, detail=f"pix2tex error {upstream.status_code}: {upstream.text[:500]}")

    latex = upstream.text
    try:
        payload = upstream.json()
        latex = payload.get("result") or payload.get("latex") or latex
    except Exception:
        pass

    return JSONResponse(content={"latex": latex})


@app.post("/predict")
async def predict_passthrough(
    file: UploadFile = File(...),
) -> JSONResponse:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")

    upstream_url = __import__("os").environ.get("PIX2TEX_URL", "http://pix2tex:8502")
    async with httpx.AsyncClient() as client:
        upstream = await client.post(
            f"{upstream_url}/predict",
            files={"file": (file.filename or "equation.png", data, file.content_type)},
            timeout=60,
        )
    if upstream.status_code != 200:
        raise HTTPException(status_code=502, detail=upstream.text[:500])

    try:
        return JSONResponse(content=upstream.json())
    except Exception:
        return JSONResponse(content={"result": upstream.text})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)