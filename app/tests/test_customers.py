# app/tests/test_customers.py
def test_create_customer_without_email(client, auth_headers, seeded_admin):
    company, admin = seeded_admin
    suffix = "001"
    payload = {
        "first_name": "Juan",
        "last_name": "Pérez",
        "dni": f"300010{suffix}",
        "address": "Calle Falsa 123",
        "phone": f"38112345{suffix}",
        "province": "Tucumán",
        "email": None
    }
    r = client.post("/customers/", json=payload, headers=auth_headers)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["email"] is None

    # ✅ Usa el endpoint real de tu backend para listar:
    r2 = client.get(f"/customers/employees/{admin.id}", headers=auth_headers)
    assert r2.status_code == 200, r2.text
    lst = r2.json()
    assert any(c["dni"] == f"300010{suffix}" for c in lst)
