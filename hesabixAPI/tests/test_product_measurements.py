import os
from decimal import Decimal

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from pydantic import ValidationError

from adapters.api.v1.helpers.product_request_helper import process_product_request
from adapters.api.v1.schema_models.product import ProductUpdateRequest
from app.core.product_measurements import MEASUREMENT_FIELDS
from app.core.response_cache import ResponseCacheMiddleware
from app.core.smart_normalizer import smart_normalize_json


@pytest.mark.parametrize("value", ["-1", "-0", "NaN", "1e2", "abc", True, "0.0000000000000001", "1000000000000"])
def test_invalid_canonical_measurements(value):
    with pytest.raises(ValidationError):
        ProductUpdateRequest(length_mm=value)


def test_product_measurement_request_parses_json_and_multipart_exactly():
    app = FastAPI()

    @app.post("/")
    async def echo_measurements(request: Request):
        payload, _, _ = await process_product_request(request, 1, None, None, is_update=True)
        return payload.model_dump(mode="json", exclude_unset=True)

    @app.middleware("http")
    async def normalize_json(request, call_next):
        if request.headers.get("content-type") == "application/json":
            raw = await request.body()
            request.state.original_product_json = raw
            request._body = smart_normalize_json(raw)
        return await call_next(request)

    with TestClient(app) as client:
        response = client.post(
            "/",
            content='{"length_mm":999999999999.999999999999999,"width_mm":0,"height_mm":null}',
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 200, response.text
        assert response.json() == {
            "length_mm": "999999999999.999999999999999",
            "width_mm": "0",
            "height_mm": None,
        }
        response = client.post(
            "/",
            files={"weight_g": (None, "999999999999.999999999999999"), "length_mm": (None, "")},
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"weight_g": "999999999999.999999999999999", "length_mm": None}


def test_product_detail_reads_current_values_with_response_cache_middleware(monkeypatch):
    from app.core import response_cache

    def unexpected_cache_access():
        pytest.fail("the product detail read must reach the route even if the cache is enabled")

    monkeypatch.setattr(response_cache, "get_cache", unexpected_cache_access)
    app = FastAPI()
    app.add_middleware(ResponseCacheMiddleware)
    current = {"weight_g": "1250.500000"}

    @app.get("/api/v1/products/business/1/2")
    def detail():
        return {"success": True, "data": current}

    with TestClient(app) as client:
        assert client.get("/api/v1/products/business/1/2").json()["data"] == current
        current["weight_g"] = "1250.625000"
        assert client.get("/api/v1/products/business/1/2").json()["data"] == current


@pytest.mark.skipif(
    os.getenv("HESABIX_TEST_PRODUCT_MEASUREMENTS") != "1",
    reason="requires the isolated PostgreSQL product measurement fixture",
)
def test_product_measurement_routes_and_postcommit_state():
    from sqlalchemy import select, text

    from adapters.api.v1.businesses import router as businesses_router
    from adapters.api.v1.products import router as products_router
    from adapters.db.models.business import Business
    from adapters.db.models.product import Product
    from adapters.db.session import SessionLocal
    from app.core.error_handlers import register_error_handlers

    app = FastAPI()
    register_error_handlers(app)
    app.include_router(businesses_router, prefix="/api/v1")
    app.include_router(products_router, prefix="/api/v1")
    owner = {"Authorization": "ApiKey measurement-fixture-1"}
    outsider = {"Authorization": "ApiKey measurement-fixture-2"}
    businesses_path = "/api/v1/businesses"
    products_path = "/api/v1/products/business/1"

    def data(response):
        assert response.status_code == 200, response.text
        return response.json()["data"]

    def committed_product(product_id):
        with SessionLocal() as session:
            product = session.get(Product, product_id)
            return tuple(getattr(product, key) for key in MEASUREMENT_FIELDS)

    with SessionLocal() as session:
        print(session.execute(text("SHOW server_version")).scalar_one())
        legacy_id = session.scalar(select(Product.id).filter_by(business_id=1, code="LEGACY"))
        assert legacy_id is not None

    with TestClient(app, headers=owner) as client:
        def settings(dimension=None, weight=None):
            update = {}
            if dimension is not None:
                update["product_dimension_unit"] = dimension
            if weight is not None:
                update["product_weight_unit"] = weight
            return data(client.put(f"{businesses_path}/1", json=update))

        def product_values(product_id):
            item = data(client.get(f"{products_path}/{product_id}"))["item"]
            return tuple(item[key] for key in MEASUREMENT_FIELDS)

        initial = data(client.get(f"{businesses_path}/1"))
        assert (initial["product_dimension_unit"], initial["product_weight_unit"]) == ("mm", "g")
        assert product_values(legacy_id) == (None,) * 4
        data(client.put(f"{products_path}/{legacy_id}", json={"description": "legacy edit"}))
        assert committed_product(legacy_id) == (None,) * 4

        entered = ("125.5", "22.375", "3.0625", "1250.5")
        product = data(client.post(products_path, json={
            "name": "Decimal measurements",
            **dict(zip(MEASUREMENT_FIELDS, entered, strict=True)),
        }))
        product_id = product["id"]
        expected = tuple(Decimal(value) for value in entered)
        assert tuple(map(Decimal, product_values(product_id))) == expected
        assert committed_product(product_id) == expected
        print("created", committed_product(product_id))

        data(client.put(f"{products_path}/{product_id}", json={"width_mm": "22.8125"}))
        expected = (expected[0], Decimal("22.8125"), *expected[2:])
        assert committed_product(product_id) == expected

        dimension_only = settings(dimension="cm")
        assert dimension_only["product_weight_unit"] == "g"
        settings(weight="kg")
        assert committed_product(product_id) == expected
        settings(dimension="m", weight="t")
        data(client.put(f"{products_path}/{product_id}", json={"description": "other field"}))
        assert committed_product(product_id) == expected
        settings(dimension="mm", weight="g")
        assert tuple(map(Decimal, product_values(product_id))) == expected
        print("edited and switched back", committed_product(product_id))

        after_switch = settings(dimension="m", weight="t")
        assert (after_switch["product_dimension_unit"], after_switch["product_weight_unit"]) == ("m", "t")
        data(client.put(f"{products_path}/{product_id}", json={"height_mm": "3.125"}))
        assert committed_product(product_id) == (*expected[:2], Decimal("3.125"), expected[3])
        print("submitted with the previous form's unit", committed_product(product_id))

        peer = data(client.get(f"{businesses_path}/2"))
        assert (peer["product_dimension_unit"], peer["product_weight_unit"]) == ("mm", "g")
        assert client.put(f"{businesses_path}/1", json={"product_dimension_unit": "kg"}).status_code == 422
        assert client.put(f"{businesses_path}/1", json={"product_weight_unit": None}).status_code == 422
        assert client.put(f"{businesses_path}/1", headers=outsider, json={"product_weight_unit": "g"}).status_code == 403
        assert client.put(f"{products_path}/{product_id}", json={"weight_g": "-5"}).status_code == 400
        assert client.put(f"/api/v1/products/business/2/{product_id}", json={"weight_g": "5"}).status_code in (403, 404)
        with SessionLocal() as session:
            assert session.get(Business, 1).product_weight_unit == "t"
            assert session.get(Business, 2).product_weight_unit == "g"

        data(client.put(f"{products_path}/{product_id}", files={"height_mm": (None, "")}))
        assert committed_product(product_id) == (*expected[:2], None, expected[3])
        empty = data(client.post(products_path, json={"name": "No measurements"}))
        assert committed_product(empty["id"]) == (None,) * 4

        for dimension in ("um", "dm", "km", "in", "ft", "yd", "mi"):
            assert settings(dimension=dimension)["product_dimension_unit"] == dimension
        for weight in ("ug", "mg", "oz", "lb"):
            assert settings(weight=weight)["product_weight_unit"] == weight
        settings(dimension="in", weight="oz")
        data(client.put(f"{products_path}/{product_id}", json={
            "height_mm": "31.3580018",
            "weight_g": "34.999385715861875",
        }))
        imperial = (*expected[:2], Decimal("31.3580018"), Decimal("34.999385715861875"))
        assert committed_product(product_id) == imperial
        settings(dimension="km", weight="mg")
        data(client.put(f"{products_path}/{product_id}", json={"description": "imperial precision retained"}))
        assert committed_product(product_id) == imperial
        print("imperial input, fixed-point storage", committed_product(product_id))
        settings(dimension="mm", weight="g")
