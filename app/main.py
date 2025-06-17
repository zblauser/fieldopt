from fastapi import FastAPI
from app.routes import jobs, technicians

app = FastAPI(title="FieldOpt")

app.include_router(technicians.router, prefix="/technicians", tags=["Technicians"])
app.include_router(jobs.router, prefix="/jobs", tags=["Jobs"])

@app.get("/")
def root():
	return {"message": "Welcome to FieldOpt"}
