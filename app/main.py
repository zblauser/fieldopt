from fastapi import FastAPI
from app.database import engine, Base
from app.routes import jobs, technicians

from fastapi.middleware.cors import CORSMiddleware

Base.metadata.create_all(bind=engine)

app = FastAPI(title="FieldOpt FSM")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(jobs.router, prefix="/jobs", tags=["Jobs"])
app.include_router(technicians.router, prefix="/technicians", tags=["Technicians"])

@app.get("/")
def root():
	return {"message": "FieldOpt backend is running"}
