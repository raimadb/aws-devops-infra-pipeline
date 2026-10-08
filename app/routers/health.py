from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
def health():
    # Deliberately does not touch the database: the ALB polls this, and a brief
    # DB blip should not mark every task unhealthy.
    return {"status": "ok"}
