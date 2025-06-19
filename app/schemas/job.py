from pydantic import BaseModel

class JobOut(BaseModel):
	id: int
	customer_name: str
	location: str
	required_skill: str
	status: str
	assigned_technician_id: int | None

	class Config:
		from_attributes = True
