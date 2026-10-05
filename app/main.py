import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from database import Base, engine
from routers import health, items

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    logger.info("database tables ready")
    yield


app = FastAPI(title="aws-devops-infra-pipeline", lifespan=lifespan)
app.include_router(health.router)
app.include_router(items.router)
