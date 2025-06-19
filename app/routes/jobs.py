from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.models.job import Job
from app.models.technician import Technician
from app.schemas.job import JobOut
from app.database import SessionLocal
from typing import List

router = APIRouter()

def get_db():
	db = SessionLocal()
	try:
		yield db
	finally:
		db.close()

@router.get("/", response_model=List[JobOut])
def get_jobs(db: Session = Depends(get_db)):
	return db.query(Job).all()

@router.post("/")
def create_job(customer_name: str, location: str, required_skill: str, db: Session = Depends(get_db)):
	job = Job(customer_name=customer_name, location=location, required_skill=required_skill)
	db.add(job)
	db.commit()
	db.refresh(job)
	return job

@router.post("/{job_id}/assign")
def assign_job(job_id: int, db: Session = Depends(get_db)):
	job = db.query(Job).filter(Job.id == job_id).first()
	if not job or job.status != "pending":
		raise HTTPException(status_code=400, detail="Job not assignable")
	for tech in db.query(Technician).all():
		if job.required_skill in tech.skills.split(","):
			job.assigned_technician_id = tech.id
			job.status = "assigned"
			db.commit()
			db.refresh(job)
			return job
	raise HTTPException(status_code=404, detail="No matching technician")
