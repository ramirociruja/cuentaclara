from app.database.db import engine, Base
from app.models.models import *

print("Creating tables...")
Base.metadata.create_all(bind=engine)
print("Tables created successfully!")