from app.services.ai.ai_model_seed_service import normalize_model_code


def test_normalize_model_code():
    assert normalize_model_code("gpt-4o") == "gpt-4o"
    assert normalize_model_code("GPT 4o/mini") == "gpt-4o-mini"
    assert normalize_model_code("???") == "default-model"
