import pytest


def pytest_addoption(parser):
    parser.addoption("--env", action="store", default="dev")


@pytest.fixture(scope="session")
def env(request):
    return request.config.getoption("--env")
