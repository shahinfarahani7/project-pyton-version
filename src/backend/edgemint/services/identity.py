from edgemint.building_blocks.app import create_service_app
from edgemint.security.api_keys import generate_api_key

app = create_service_app("identity")


@app.get("/identity/health", include_in_schema=False)
async def identity_health() -> dict[str, str]:
    return {"status": "ready", "service": "identity"}


@app.post("/identity/dev/api-keys/preview", include_in_schema=False)
async def preview_api_key_format() -> dict[str, str]:
    raw, digest = generate_api_key()
    return {"sampleKeyPrefix": raw[:8], "hashPreview": digest.hex()[:16]}
