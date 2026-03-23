from fastapi import Request
from fastapi.responses import JSONResponse


async def security_layer(request: Request, call_next):
    if "authorization" not in request.headers:
        return JSONResponse(status_code=401, content={"error": "unauthorized"})

    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response
