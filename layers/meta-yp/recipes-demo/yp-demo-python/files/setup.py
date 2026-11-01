#!/usr/bin/env python3
# 3.1（dunfell）的 setuptools3.bbclass 只认 setup.py，读不到 pyproject.toml；
# 4.0+ 走 PEP 517 读 pyproject.toml，本文件在那里不参与构建。
# 两处元数据必须保持一致，否则同一份源在不同 release 上装出的包名会不同。
from setuptools import setup

setup(
    name="yp-demo-python",
    version="0.1.0",
    description="Minimal YP Python demo service",
    py_modules=["yp_demo_py"],
)
