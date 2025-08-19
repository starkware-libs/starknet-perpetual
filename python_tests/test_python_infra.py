def test_simple(simple_test_context):
    assert simple_test_context["version"] == "0.1.0"
    assert simple_test_context["contract_name"] == "simple_contract"
