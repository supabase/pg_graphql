from setuptools import find_packages, setup

setup(
    name="graphql_server",
    version="0.0.1",
    python_requires=">=3.7",
    packages=find_packages("."),
    package_dir={"": "."},
    install_requires=[
        "sqlalchemy",
        "asyncpg",
        "fastapi",
        "typing_extensions",
        "uvicorn",
        "databases",
    ],
    classifiers=[
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
    ],
)
