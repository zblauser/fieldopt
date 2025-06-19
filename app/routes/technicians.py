from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.models.technician import Technician
from app.schemas.technician import TechnicianOut
from app.database import SessionLocal
from typing import List

router = APIRouter()

def get_db():
	db = SessionLocal()
	try:
		yield db
	finally:
		db.close()

@router.get("/", response_model=List[TechnicianOut])
def get_technicians(db: Session = Depends(get_db)):
	return db.query(Technician).all()

@router.post("/")
def create_technician(name: str, location: str, skills: str, db: Session = Depends(get_db)):
	tech = Technician(name=name, location=location, skills=skills)
	db.add(tech)
	db.commit()
	db.refresh(tech)
	return tech
