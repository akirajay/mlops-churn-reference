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
