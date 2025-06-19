from pydantic import BaseModel

class TechnicianOut(BaseModel):
	id: int
	name: str
	location: str
	skills: str

	class Config:
		from_attributes = True
