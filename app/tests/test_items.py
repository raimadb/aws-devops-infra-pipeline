import pytest

pytestmark = pytest.mark.integration


def test_create_and_list_item(db_client):
    created = db_client.post("/items", json={"title": "first"})
    assert created.status_code == 201
    assert created.json()["title"] == "first"

    listed = db_client.get("/items")
    assert listed.status_code == 200
    assert [i["title"] for i in listed.json()] == ["first"]


def test_rejects_empty_title(db_client):
    response = db_client.post("/items", json={"title": ""})
    assert response.status_code == 422
