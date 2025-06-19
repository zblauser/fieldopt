from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship
from app.database import Base

class Technician(Base):
	__tablename__ = "technicians"

	id = Column(Integer, primary_key=True, index=True)
	name = Column(String, index=True)
	location = Column(String)
	skills = Column(String)  # comma-separated for now

	jobs = relationship("Job", back_populates="assigned_technician")
