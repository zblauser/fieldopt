from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.models.technician import Technician
from app.database.dependency import get_db

router = APIRouter()

@router.post("/")
def create_technician(name: str, skills: str, db: Session = Depends(get_db)):
	tech = Technician(name=name, skills=skills)
	db.add(tech)
	db.commit()
	db.refresh(tech)
	return tech

@router.get("/")
def get_technicians(db: Session = Depends(get_db)):
	return db.query(Technician).all()
