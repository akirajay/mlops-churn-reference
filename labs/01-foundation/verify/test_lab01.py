import os
import pytest
from azure.identity import DefaultAzureCredential
from azure.ai.ml import MLClient


def pytest_addoption(parser):
    parser.addoption("--env", action="store", default="dev")


@pytest.fixture(scope="session")
def env(request):
    return request.config.getoption("--env")


@pytest.fixture(scope="session")
def ml_client(env):
    sub = os.environ["AZURE_SUBSCRIPTION_ID"]
    return MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=sub,
        resource_group_name=f"rg-churn-{env}",
        workspace_name=f"mlw-churn-{env}",
    )


def test_workspace_exists(ml_client, env):
    ws = ml_client.workspaces.get(f"mlw-churn-{env}")
    assert ws.name == f"mlw-churn-{env}"
    assert ws.identity.type.lower() in ("systemassigned", "system_assigned")


def test_cpu_cluster_exists(ml_client, env):
    c = ml_client.compute.get("cpu-cluster")
    assert c.type == "amlcompute"
    assert c.min_instances == 0
    expected_priority = "lowpriority" if env == "dev" else "dedicated"
    assert c.tier.lower() == expected_priority


def test_compute_instance_exists(ml_client):
    ci = ml_client.compute.get("ci-akira")
    assert ci.type == "computeinstance"


def test_shared_registry_reachable():
    sub = os.environ["AZURE_SUBSCRIPTION_ID"]
    reg_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=sub,
        registry_name="mlr-churn-shared-jpe",
    )
    # listing models on a fresh registry should return empty list, not throw
    list(reg_client.models.list())
