"""
Setup script for DGMSTT Python shared utilities
"""

from setuptools import setup, find_packages

with open("requirements.txt") as f:
    requirements = f.read().splitlines()
    # Filter out comments and empty lines
    requirements = [r for r in requirements if r and not r.startswith("#")]

setup(
    name="dgmstt-shared",
    version="1.0.0",
    description="Shared Python utilities for DGMSTT projects",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
)