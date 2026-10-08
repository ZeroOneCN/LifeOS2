# -*- coding: utf-8 -*-
"""LifeOS 网贷借还 API 客户端封装。

对接后端 REST 接口，提供登录、平台/账单/还款的 CRUD 能力。
所有写操作成功后由后端广播数据变更，前端页面会自动刷新。
"""
from typing import Any

import requests

from config import load_config, save_config

# 后端统一 API 前缀
API_PREFIX = "/api/v1"


class ApiError(Exception):
    """接口调用异常，携带后端返回的错误信息。"""

    def __init__(self, message: str, status_code: int = 0):
        super().__init__(message)
        self.status_code = status_code


class LifeOSApi:
    """LifeOS API 客户端，维护 base_url 与 token。"""

    def __init__(self):
        cfg = load_config()
        self.base_url: str = cfg.get("server", "http://localhost:8000").rstrip("/")
        self.token: str = cfg.get("token", "")
        self.account: str = cfg.get("account", "")

    # ---------- 基础请求 ----------
    def _headers(self) -> dict:
        """构造请求头，包含鉴权 token。"""
        h = {"Content-Type": "application/json"}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        return h

    def _request(self, method: str, path: str, **kwargs) -> Any:
        """统一请求方法，处理 401 与错误响应。

        参数：
            method: HTTP 方法（GET/POST/PUT/DELETE）。
            path: 以 / 开头的 API 路径（不含 /api/v1 前缀）。
            **kwargs: 传递给 requests 的额外参数（json/params 等）。
        返回值：
            解析后的 JSON 响应；204 无内容返回 None。
        异常：
            ApiError: 非 2xx 响应时抛出。
        """
        url = f"{self.base_url}{API_PREFIX}{path}"
        kwargs.setdefault("headers", self._headers())
        try:
            resp = requests.request(method, url, timeout=15, **kwargs)
        except requests.RequestException as e:
            raise ApiError(f"网络请求失败：{e}")

        if resp.status_code == 401:
            # 登录接口的 401 表示账号密码错误，显示后端原始提示，不清空 token
            if path != "/auth/login":
                self.token = ""
                cfg = load_config()
                cfg["token"] = ""
                save_config(cfg)
                raise ApiError("登录已失效，请重新登录", 401)
        if not resp.ok:
            try:
                detail = resp.json().get("detail", resp.text)
            except ValueError:
                detail = resp.text
            if isinstance(detail, list):
                detail = "；".join(
                    f"{'.'.join(str(x) for x in d.get('loc', [])[1:])}: {d.get('msg', '')}"
                    if isinstance(d, dict) else str(d)
                    for d in detail
                )
            raise ApiError(str(detail), resp.status_code)
        if resp.status_code == 204:
            return None
        return resp.json()

    # ---------- 认证 ----------
    def login(self, account: str, password: str, server: str | None = None) -> dict:
        """账号密码登录，成功后保存 token 与 server。

        参数：
            account: 登录账号。
            password: 登录密码。
            server: 可选，服务器地址；为空时使用当前配置。
        返回值：
            登录响应（含 access_token、user 等）。
        """
        if server:
            self.base_url = server.rstrip("/")
        self.account = account
        data = self._request("POST", "/auth/login", json={"account": account, "password": password})
        self.token = data.get("access_token", "")
        cfg = load_config()
        cfg["server"] = self.base_url
        cfg["account"] = account
        cfg["token"] = self.token
        save_config(cfg)
        return data

    # ---------- 平台 ----------
    def list_platforms(self) -> list[dict]:
        """获取全部借款平台（不分页，page_size=100）。"""
        res = self._request("GET", "/finance/loan-platforms", params={"page_size": 100})
        return res.get("items", [])

    def create_platform(self, payload: dict) -> dict:
        """新增借款平台。"""
        return self._request("POST", "/finance/loan-platforms", json=payload)

    def update_platform(self, item_id: int, payload: dict) -> dict:
        """更新借款平台。"""
        return self._request("PUT", f"/finance/loan-platforms/{item_id}", json=payload)

    def delete_platform(self, item_id: int) -> None:
        """删除借款平台。"""
        self._request("DELETE", f"/finance/loan-platforms/{item_id}")

    # ---------- 账单 ----------
    def list_bills(self, start: str | None = None, end: str | None = None) -> list[dict]:
        """获取全部账单（翻页拉取全量，避免按月翻页的痛点）。

        参数：
            start: 可选，起始账单月（YYYY-MM-DD）。
            end: 可选，结束账单月（YYYY-MM-DD）。
        返回值：
            账单列表，已按平台 ID + 账单月排序。
        """
        all_items: list[dict] = []
        page = 1
        total = 0
        while True:
            params = {"page": page, "page_size": 100}
            if start:
                params["start"] = start
            if end:
                params["end"] = end
            res = self._request("GET", "/finance/loan-bills", params=params)
            items = res.get("items", [])
            all_items.extend(items)
            total = res.get("total", 0)
            if len(all_items) >= total or not items:
                break
            page += 1
        # 按平台 ID + 账单月固定排序
        all_items.sort(key=lambda b: (b.get("platform_id") or 0, b.get("bill_month") or ""))
        return all_items

    def create_bill(self, payload: dict) -> dict:
        """新增账单。"""
        return self._request("POST", "/finance/loan-bills", json=payload)

    def update_bill(self, item_id: int, payload: dict) -> dict:
        """更新账单。"""
        return self._request("PUT", f"/finance/loan-bills/{item_id}", json=payload)

    def delete_bill(self, item_id: int) -> None:
        """删除账单。"""
        self._request("DELETE", f"/finance/loan-bills/{item_id}")

    # ---------- 还款 ----------
    def list_repayments(self, bill_id: int) -> list[dict]:
        """获取指定账单的全部还款记录。"""
        return self._request("GET", "/finance/repayments", params={"bill_id": bill_id})

    def create_repayment(self, payload: dict) -> dict:
        """新增还款记录（后端自动同步账单已还金额与状态）。"""
        return self._request("POST", "/finance/repayments", json=payload)

    def update_repayment(self, item_id: int, payload: dict) -> dict:
        """更新还款记录。"""
        return self._request("PUT", f"/finance/repayments/{item_id}", json=payload)

    def delete_repayment(self, item_id: int) -> None:
        """删除还款记录。"""
        self._request("DELETE", f"/finance/repayments/{item_id}")
