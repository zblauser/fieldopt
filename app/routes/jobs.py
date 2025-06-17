from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.models.job import Job
from app.models.technician import Technician
from app.database.dependency import get_db

router = APIRouter()

@router.post("/")
def create_job(customer_name: str, location: str, required_skill: str, db: Session = Depends(get_db)):
	job = Job(customer_name=customer_name, location=location, required_skill=required_skill)
	db.add(job)
	db.commit()
	db.refresh(job)
	return job

@router.get("/")
def get_jobs(db: Session = Depends(get_db)):
	return db.query(Job).all()

@router.post("/{job_id}/assign")
def assign_job(job_id: int, db: Session = Depends(get_db)):
	job = db.query(Job).filter(Job.id == job_id).first()
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	if job.status != "pending":
		raise HTTPException(status_code=400, detail="Job already assigned or in progress")
	techs = db.query(Technician).all()
	for tech in techs:
		tech_skills = [s.strip() for s in tech.skills.split(",")]
		if job.required_skill in tech_skills:
			job.assigned_technician_id = tech.id
			job.status = "assigned"
			db.commit()
			db.refresh(job)
			return {"job_id": job.id, "assigned_to": tech.name, "status": job.status}
	raise HTTPException(status_code=404, detail="No matching technician available")

@router.patch("/{job_id}/start")
def start_job(job_id: int, db: Session = Depends(get_db)):
	job = db.query(Job).filter(Job.id == job_id).first()
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	if job.status != "assigned":
		raise HTTPException(status_code=400, detail="Job must be assigned before starting")
	job.status = "in_progress"
	db.commit()
	db.refresh(job)
	return {"job_id": job.id, "status": job.status}

@router.patch("/{job_id}/complete")
def complete_job(job_id: int, db: Session = Depends(get_db)):
	job = db.query(Job).filter(Job.id == job_id).first()
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	if job.status != "in_progress":
		raise HTTPException(status_code=400, detail="Job must be in progress to complete")
	job.status = "completed"
	db.commit()
	db.refresh(job)
	return {"job_id": job.id, "status": job.status}
