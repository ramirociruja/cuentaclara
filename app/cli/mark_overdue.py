# app/cli/mark_overdue.py
from app.jobs.overdue import mark_overdue_installments_job

if __name__ == "__main__":
    n = mark_overdue_installments_job()
    print(f"[mark_overdue] updated={n}")
