def test_login_success(client, seeded_admin):
    r = client.post("/login", json={
        "username": "admin@test.local",  # tu backend espera 'username'
        "password": "123456"
    })
    assert r.status_code == 200, r.text
    data = r.json()
    assert "access_token" in data and "refresh_token" in data
    assert data.get("token_type") == "bearer"
