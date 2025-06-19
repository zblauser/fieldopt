from sqlalchemy import Column, Integer, String, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class Job(Base):
	__tablename__ = "jobs"

	id = Column(Integer, primary_key=True, index=True)
	customer_name = Column(String, index=True)
	location = Column(String)
	required_skill = Column(String)
	status = Column(String, default="pending")
	assigned_technician_id = Column(Integer, ForeignKey("technicians.id"), nullable=True)

	assigned_technician = relationship("Technician", back_populates="jobs")
