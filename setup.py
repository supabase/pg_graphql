#!/usr/bin/env python

"""Setup script for the package."""

import sys

import setuptools

PACKAGE_NAME = "pg_graphql"
MINIMUM_PYTHON_VERSION = "3.6"


def check_python_version():
    """Exit when the Python version is too low."""
    if sys.version < MINIMUM_PYTHON_VERSION:
        sys.exit("Python {0}+ is required.".format(MINIMUM_PYTHON_VERSION))


check_python_version()


DEV_REQUIRES = [
    "pytest",
    "pytest-benchmark",
    "pre-commit",
    "pylint",
    "black",
    "psycopg2",
    "sqlalchemy",
    "pre-commit",
]


setuptools.setup(
    name="pg_graphql",
    version="0.0.1",
    #packages=setuptools.find_packages("src/python", exclude=("tests",)),
    #package_dir={"": "src/python"},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Natural Language :: English",
        "Operating System :: OS Independent",
        "Programming Language :: Python",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
    ],
    install_requires=DEV_REQUIRES,
)
