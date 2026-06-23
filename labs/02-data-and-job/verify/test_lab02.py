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
    return MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group_name=f"rg-churn-{env}",
        workspace_name=f"mlw-churn-{env}",
    )


@pytest.mark.parametrize(
    "name,expected_type",
    [
        ("telco-churn-file", "uri_file"),
        ("telco-churn-folder", "uri_folder"),
        ("telco-churn-mltable", "mltable"),
    ],
)
def test_data_asset(ml_client, name, expected_type):
    asset = ml_client.data.get(name=name, version="1")
    assert asset.type == expected_type, f"{name} expected {expected_type}, got {asset.type}"


def test_storage_is_adls_gen2(ml_client, env):
    """§5.2: workspace storage should have HNS enabled → abfss:// works."""
    from azure.mgmt.storage import StorageManagementClient
    ws = ml_client.workspaces.get(f"mlw-churn-{env}")
    storage_id = ws.storage_account
    sub_id, rg, _, _, _, _, _, _, name = storage_id.split("/")[2:11]
    sm = StorageManagementClient(DefaultAzureCredential(), sub_id)
    sa = sm.storage_accounts.get_properties(rg, name)
    assert sa.is_hns_enabled is True, "Storage must be ADLS Gen2 (HNS enabled)"


def test_recent_lab02_job_completed(ml_client):
    """At least one job from lab02-data-and-job experiment should have completed."""
    jobs = list(ml_client.jobs.list(parent_job_name=None))
    lab02_jobs = [j for j in jobs if getattr(j, "experiment_name", "") == "lab02-data-and-job"]
    assert lab02_jobs, "No lab02 jobs found"
    completed = [j for j in lab02_jobs if j.status == "Completed"]
    assert completed, f"No completed lab02 jobs; statuses: {[j.status for j in lab02_jobs]}"
