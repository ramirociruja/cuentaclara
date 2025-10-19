# python -m app.jobs.overdue_cli
from dotenv import load_dotenv  # opcional si usás .env
load_dotenv()

from app.jobs.overdue import mark_overdue_installments_job

if __name__ == "__main__":
    updated = mark_overdue_installments_job()
    print(f"Overdue marcadas: {updated}")
