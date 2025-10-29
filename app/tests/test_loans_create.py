# app/tests/test_loans_create.py
from datetime import datetime, timezone

def test_create_loan_and_installments(client, auth_headers, seeded_admin):
    company, admin = seeded_admin

    suffix = "002"
    rc = client.post("/customers/", json={
        "first_name": "Ana",
        "last_name": "García",
        "dni": f"310020{suffix}",
        "address": "Belgrano 100",
        "phone": f"38176543{suffix}",
        "province": "Tucumán",
        "email": None
    }, headers=auth_headers)
    assert rc.status_code == 201, rc.text
    customer_id = rc.json()["id"]

    payload = {
        "customer_id": customer_id,
        "employee_id": admin.id,
        "company_id": company.id,              # ✅ requerido por tu esquema
        "amount": 300.0,
        "total_due": 300.0,
        "installments_count": 3,
        "installment_amount": 100.0,
        "frequency": "weekly",
        "start_date": datetime.now(timezone.utc).isoformat(),
        "description": "Prueba",
        "collection_day": None
    }
    r = client.post("/loans/createLoan/", json=payload, headers=auth_headers)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["employee_id"] == admin.id
    assert data["installments_count"] == 3

    r2 = client.get(f"/loans/{data['id']}/installments", headers=auth_headers)
    assert r2.status_code == 200
    insts = r2.json()
    assert len(insts) == 3
    assert abs(sum(i["amount"] for i in insts) - 300.0) < 0.01
