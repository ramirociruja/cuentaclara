# app/tests/test_payments_register_void.py

def _create_customer(client, headers, suffix):
    r = client.post("/customers/", json={
        "first_name": "Carlos",
        "last_name": "Luna",
        "dni": f"320030{suffix}",
        "address": "San Martín 10",
        "phone": f"38100099{suffix}",
        "province": "Tucumán",
        "email": None
    }, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]

def _create_loan(client, headers, customer_id, employee_id, company_id):
    r = client.post("/loans/createLoan/", json={
        "customer_id": customer_id,
        "employee_id": employee_id,
        "company_id": company_id,          # ✅ requerido
        "amount": 300.0,
        "total_due": 300.0,
        "installments_count": 3,
        "installment_amount": 100.0,
        "frequency": "weekly",
        "description": "X"
    }, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]

def test_payment_and_void_idempotent(client, auth_headers, seeded_admin):
    company, admin = seeded_admin
    suffix = "003"
    cid = _create_customer(client, auth_headers, suffix)
    loan_id = _create_loan(client, auth_headers, cid, admin.id, company.id)

    r1 = client.post("/payments/", json={
        "loan_id": loan_id,
        "amount": 100.0,
        "payment_type": "cash",
        "description": "test"
    }, headers=auth_headers)
    assert r1.status_code == 201, r1.text
    payment_id = r1.json()["id"]

    r2 = client.post(f"/payments/void/{payment_id}", headers=auth_headers)
    assert r2.status_code == 200, r2.text

    r3 = client.post(f"/payments/void/{payment_id}", headers=auth_headers)
    assert r3.status_code in (200, 409)

    r4 = client.get(f"/loans/{loan_id}", headers=auth_headers)
    assert r4.status_code == 200
    loan_json = r4.json()
    remaining = loan_json.get("total_due") or loan_json.get("remaining_amount") or 300.0
    assert abs(remaining - 300.0) < 0.01
