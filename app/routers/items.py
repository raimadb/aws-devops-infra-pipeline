from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import get_db
from models import Item
from schemas import ItemCreate, ItemOut

router = APIRouter(prefix="/items", tags=["items"])

DbSession = Annotated[Session, Depends(get_db)]


@router.get("", response_model=list[ItemOut])
def list_items(db: DbSession):
    return db.scalars(select(Item).order_by(Item.id)).all()


@router.post("", response_model=ItemOut, status_code=201)
def create_item(payload: ItemCreate, db: DbSession):
    item = Item(title=payload.title)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item
