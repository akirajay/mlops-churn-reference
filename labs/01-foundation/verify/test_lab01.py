import os
import pytest
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient


def test_workspace_exists(ml_client, env):
    ws = ml_client.workspaces.get(f"mlw-churn-{env}")
    assert ws.name == f"mlw-churn-{env}"
    assert ws.identity.type.lower() in ("systemassigned", "system_assigned")


def test_cpu_cluster_exists(ml_client, env):
    c = ml_client.compute.get("cpu-cluster")
    assert c.type == "amlcompute"
    assert c.min_instances == 0
    expected_priority = "low_priority" if env == "dev" else "dedicated"
    assert c.tier.lower() == expected_priority


def test_compute_instance_exists(ml_client, env):
    candidates = [f"ci-akira-{env}", "ci-akira"]
    for ci_name in candidates:
        try:
            ci = ml_client.compute.get(ci_name)
            assert ci.type == "computeinstance"
            return
        except Exception:
            continue

    pytest.fail(f"No compute instance found in candidates: {candidates}")


def test_shared_registry_reachable():
    sub = os.environ["AZURE_SUBSCRIPTION_ID"]
    reg_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=sub,
        registry_name="mlr-churn-shared-jpe",
    )
    # listing models on a fresh registry should return empty list, not throw
    list(reg_client.models.list())
