from sqlalchemy import Column, Integer, String
from app.database.config import Base

class Technician(Base):
	__tablename__ = "technicians"
	id = Column(Integer, primary_key=True, index=True)
	name = Column(String, index=True)
	skills = Column(String)
	location = Column(String)
