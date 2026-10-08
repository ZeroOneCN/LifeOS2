# -*- coding: utf-8 -*-
"""LifeOS 网贷借还管理桌面工具。

功能：
- 登录 LifeOS 后端（本地/局域网）
- 借款平台 CRUD
- 网贷账单 CRUD（全量列表 + 平台/状态/月份筛选，无需按月翻页）
- 账单还款记录 CRUD（选中账单后联动展示）

所有网络请求均在子线程执行，避免阻塞 GUI 主线程导致界面卡死。
"""
import threading
import tkinter as tk
from tkinter import messagebox, ttk
from datetime import date

from api_client import ApiError, LifeOSApi
from config import DEFAULT_SERVER, load_config, save_config

# 状态样式映射
STATUS_LABEL = {"pending": "待还", "partial": "部分已还", "cleared": "已结清"}


def fmt(n) -> str:
    """金额格式化，保留两位小数并加千分位。"""
    try:
        return f"{float(n):,.2f}"
    except (TypeError, ValueError):
        return "0.00"


class LoginDialog(tk.Toplevel):
    """登录弹窗，输入账号密码与服务器地址。登录请求在子线程执行，避免卡死。"""

    def __init__(self, master, on_success):
        super().__init__(master)
        self.title("登录 LifeOS")
        self.resizable(False, False)
        self.on_success = on_success
        self._logging_in = False

        cfg = load_config()
        self.server_var = tk.StringVar(value=cfg.get("server", DEFAULT_SERVER))
        self.account_var = tk.StringVar(value=cfg.get("account", ""))

        pad = {"padx": 10, "pady": 6}
        frm = ttk.Frame(self, padding=16)
        frm.grid(row=0, column=0, sticky="nsew")

        ttk.Label(frm, text="服务器地址").grid(row=0, column=0, sticky="w", **pad)
        ttk.Entry(frm, textvariable=self.server_var, width=36).grid(row=0, column=1, **pad)

        ttk.Label(frm, text="账号").grid(row=1, column=0, sticky="w", **pad)
        self.account_entry = ttk.Entry(frm, textvariable=self.account_var, width=36)
        self.account_entry.grid(row=1, column=1, **pad)

        ttk.Label(frm, text="密码").grid(row=2, column=0, sticky="w", **pad)
        self.password_entry = ttk.Entry(frm, show="*", width=36)
        self.password_entry.grid(row=2, column=1, **pad)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, pady=(12, 0))
        self.login_btn = ttk.Button(btns, text="登录", command=self._do_login)
        self.login_btn.pack(side="left", padx=4)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side="left", padx=4)

        self.transient(master)
        self.grab_set()
        self.password_entry.focus_set()
        self.bind("<Return>", lambda e: self._do_login())

    def _do_login(self):
        """在子线程执行登录，避免网络请求阻塞 GUI。"""
        if self._logging_in:
            return
        account = self.account_var.get().strip()
        password = self.password_entry.get()
        if not account or not password:
            messagebox.showwarning("提示", "请输入账号和密码", parent=self)
            return
        self._logging_in = True
        self.login_btn.config(state="disabled", text="登录中...")

        def worker():
            api = LifeOSApi()
            try:
                api.login(account, password, server=self.server_var.get().strip())
                self.after(0, lambda: self._on_success(api))
            except ApiError as e:
                self.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _on_success(self, api: LifeOSApi):
        """登录成功回调。"""
        self.on_success(api)
        self.destroy()

    def _on_error(self, msg: str):
        """登录失败回调，恢复按钮状态。"""
        self._logging_in = False
        self.login_btn.config(state="normal", text="登录")
        messagebox.showerror("登录失败", msg, parent=self)


class BillDialog(tk.Toplevel):
    """账单新增/编辑弹窗。保存请求在子线程执行。"""

    def __init__(self, master, api, platforms, bill=None, on_saved=None):
        super().__init__(master)
        self.title("编辑账单" if bill else "新增账单")
        self.resizable(False, False)
        self.api = api
        self.platforms = platforms
        self.bill = bill
        self.on_saved = on_saved
        self._saving = False

        pad = {"padx": 8, "pady": 5}
        frm = ttk.Frame(self, padding=16)
        frm.grid(row=0, column=0, sticky="nsew")

        ttk.Label(frm, text="平台").grid(row=0, column=0, sticky="w", **pad)
        self.platform_var = tk.StringVar()
        self.platform_combo = ttk.Combobox(
            frm, textvariable=self.platform_var, state="readonly", width=28,
            values=[p["name"] for p in platforms],
        )
        self.platform_combo.grid(row=0, column=1, **pad)
        if bill and bill.get("platform_id"):
            pname = next((p["name"] for p in platforms if p["id"] == bill["platform_id"]), "")
            self.platform_combo.set(pname)

        ttk.Label(frm, text="账单月").grid(row=1, column=0, sticky="w", **pad)
        self.bill_month_var = tk.StringVar(value=(bill.get("bill_month") or "")[:7] if bill else "")
        ttk.Entry(frm, textvariable=self.bill_month_var, width=28).grid(row=1, column=1, **pad)

        ttk.Label(frm, text="到期日").grid(row=2, column=0, sticky="w", **pad)
        self.due_date_var = tk.StringVar(value=bill.get("due_date") or "" if bill else "")
        ttk.Entry(frm, textvariable=self.due_date_var, width=28).grid(row=2, column=1, **pad)

        ttk.Label(frm, text="欠款金额(含息)").grid(row=3, column=0, sticky="w", **pad)
        self.amount_var = tk.StringVar(value=str(bill.get("amount") or "") if bill else "")
        ttk.Entry(frm, textvariable=self.amount_var, width=28).grid(row=3, column=1, **pad)

        ttk.Label(frm, text="利息").grid(row=4, column=0, sticky="w", **pad)
        self.interest_var = tk.StringVar(value=str(bill.get("interest") or "") if bill else "")
        ttk.Entry(frm, textvariable=self.interest_var, width=28).grid(row=4, column=1, **pad)

        ttk.Label(frm, text="状态").grid(row=5, column=0, sticky="w", **pad)
        # 修复：bill 为 None 时直接用默认值，避免 None.get() 崩溃
        status_val = bill.get("status") if bill else None
        self.status_var = tk.StringVar(value=status_val or "pending")
        ttk.Combobox(
            frm, textvariable=self.status_var, state="readonly", width=28,
            values=["pending", "partial", "cleared"],
        ).grid(row=5, column=1, **pad)

        ttk.Label(frm, text="备注").grid(row=6, column=0, sticky="w", **pad)
        self.note_var = tk.StringVar(value=bill.get("note") or "" if bill else "")
        ttk.Entry(frm, textvariable=self.note_var, width=28).grid(row=6, column=1, **pad)

        btns = ttk.Frame(frm)
        btns.grid(row=7, column=0, columnspan=2, pady=(12, 0))
        self.save_btn = ttk.Button(btns, text="保存", command=self._save)
        self.save_btn.pack(side="left", padx=4)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side="left", padx=4)

        self.transient(master)
        self.grab_set()

    def _save(self):
        """校验后在子线程保存账单。"""
        if self._saving:
            return
        pname = self.platform_var.get()
        platform = next((p for p in self.platforms if p["name"] == pname), None)
        bill_month = self.bill_month_var.get().strip()
        amount_s = self.amount_var.get().strip()
        if not platform:
            messagebox.showwarning("提示", "请选择平台", parent=self)
            return
        if not bill_month:
            messagebox.showwarning("提示", "请输入账单月（YYYY-MM）", parent=self)
            return
        if not amount_s:
            messagebox.showwarning("提示", "请输入欠款金额", parent=self)
            return
        try:
            payload = {
                "platform_id": platform["id"],
                "bill_month": f"{bill_month}-01",
                "due_date": self.due_date_var.get().strip() or None,
                "amount": float(amount_s),
                "interest": float(self.interest_var.get()) if self.interest_var.get().strip() else None,
                "status": self.status_var.get(),
                "note": self.note_var.get().strip() or None,
            }
        except ValueError:
            messagebox.showwarning("提示", "金额格式不正确", parent=self)
            return

        self._saving = True
        self.save_btn.config(state="disabled", text="保存中...")

        def worker():
            try:
                if self.bill:
                    self.api.update_bill(self.bill["id"], payload)
                else:
                    self.api.create_bill(payload)
                self.after(0, self._on_saved)
            except ApiError as e:
                self.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _on_saved(self):
        """保存成功回调。"""
        if self.on_saved:
            self.on_saved()
        self.destroy()

    def _on_error(self, msg: str):
        """保存失败回调，恢复按钮。"""
        self._saving = False
        self.save_btn.config(state="normal", text="保存")
        messagebox.showerror("保存失败", msg, parent=self)


class RepaymentDialog(tk.Toplevel):
    """还款记录新增/编辑弹窗。"""

    def __init__(self, master, api, bill, repayment=None, on_saved=None):
        super().__init__(master)
        self.title("编辑还款" if repayment else "新增还款")
        self.resizable(False, False)
        self.api = api
        self.bill = bill
        self.repayment = repayment
        self.on_saved = on_saved
        self._saving = False

        pad = {"padx": 8, "pady": 5}
        frm = ttk.Frame(self, padding=16)
        frm.grid(row=0, column=0, sticky="nsew")

        remaining = (bill.get("amount") or 0) - (bill.get("paid_amount") or 0)
        ttk.Label(frm, text=f"账单剩余：{fmt(remaining)}").grid(
            row=0, column=0, columnspan=2, sticky="w", **pad
        )

        ttk.Label(frm, text="还款日期").grid(row=1, column=0, sticky="w", **pad)
        self.date_var = tk.StringVar(
            value=repayment.get("repay_date") if repayment else date.today().isoformat()
        )
        ttk.Entry(frm, textvariable=self.date_var, width=28).grid(row=1, column=1, **pad)

        ttk.Label(frm, text="实付金额").grid(row=2, column=0, sticky="w", **pad)
        self.amount_var = tk.StringVar(value=str(repayment.get("amount") or "") if repayment else "")
        ttk.Entry(frm, textvariable=self.amount_var, width=28).grid(row=2, column=1, **pad)

        ttk.Label(frm, text="优惠(券/抵扣)").grid(row=3, column=0, sticky="w", **pad)
        self.discount_var = tk.StringVar(value=str(repayment.get("discount") or "") if repayment else "")
        ttk.Entry(frm, textvariable=self.discount_var, width=28).grid(row=3, column=1, **pad)

        ttk.Label(frm, text="还款方式").grid(row=4, column=0, sticky="w", **pad)
        self.method_var = tk.StringVar(value=repayment.get("method") or "" if repayment else "")
        ttk.Entry(frm, textvariable=self.method_var, width=28).grid(row=4, column=1, **pad)

        ttk.Label(frm, text="备注").grid(row=5, column=0, sticky="w", **pad)
        self.note_var = tk.StringVar(value=repayment.get("note") or "" if repayment else "")
        ttk.Entry(frm, textvariable=self.note_var, width=28).grid(row=5, column=1, **pad)

        btns = ttk.Frame(frm)
        btns.grid(row=6, column=0, columnspan=2, pady=(12, 0))
        self.save_btn = ttk.Button(btns, text="保存", command=self._save)
        self.save_btn.pack(side="left", padx=4)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side="left", padx=4)

        self.transient(master)
        self.grab_set()

    def _save(self):
        """校验后在子线程保存还款记录。"""
        if self._saving:
            return
        try:
            payload = {
                "bill_id": self.bill["id"],
                "repay_date": self.date_var.get().strip(),
                "amount": float(self.amount_var.get()),
                "discount": float(self.discount_var.get()) if self.discount_var.get().strip() else None,
                "method": self.method_var.get().strip() or None,
                "note": self.note_var.get().strip() or None,
            }
        except ValueError:
            messagebox.showwarning("提示", "金额格式不正确", parent=self)
            return

        self._saving = True
        self.save_btn.config(state="disabled", text="保存中...")

        def worker():
            try:
                if self.repayment:
                    self.api.update_repayment(self.repayment["id"], payload)
                else:
                    self.api.create_repayment(payload)
                self.after(0, self._on_saved)
            except ApiError as e:
                self.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _on_saved(self):
        if self.on_saved:
            self.on_saved()
        self.destroy()

    def _on_error(self, msg: str):
        self._saving = False
        self.save_btn.config(state="normal", text="保存")
        messagebox.showerror("保存失败", msg, parent=self)


class PlatformDialog(tk.Toplevel):
    """借款平台新增/编辑弹窗。"""

    def __init__(self, master, api, platform=None, on_saved=None):
        super().__init__(master)
        self.title("编辑平台" if platform else "新增平台")
        self.resizable(False, False)
        self.api = api
        self.platform = platform
        self.on_saved = on_saved
        self._saving = False

        pad = {"padx": 8, "pady": 5}
        frm = ttk.Frame(self, padding=16)
        frm.grid(row=0, column=0, sticky="nsew")

        ttk.Label(frm, text="平台名称").grid(row=0, column=0, sticky="w", **pad)
        self.name_var = tk.StringVar(value=platform.get("name") if platform else "")
        ttk.Entry(frm, textvariable=self.name_var, width=28).grid(row=0, column=1, **pad)

        ttk.Label(frm, text="账单日").grid(row=1, column=0, sticky="w", **pad)
        self.bill_day_var = tk.StringVar(value=str(platform.get("bill_day") or "") if platform else "")
        ttk.Entry(frm, textvariable=self.bill_day_var, width=28).grid(row=1, column=1, **pad)

        ttk.Label(frm, text="还款日").grid(row=2, column=0, sticky="w", **pad)
        self.due_day_var = tk.StringVar(value=str(platform.get("due_day") or "") if platform else "")
        ttk.Entry(frm, textvariable=self.due_day_var, width=28).grid(row=2, column=1, **pad)

        ttk.Label(frm, text="额度").grid(row=3, column=0, sticky="w", **pad)
        self.limit_var = tk.StringVar(value=str(platform.get("credit_limit") or "") if platform else "")
        ttk.Entry(frm, textvariable=self.limit_var, width=28).grid(row=3, column=1, **pad)

        btns = ttk.Frame(frm)
        btns.grid(row=4, column=0, columnspan=2, pady=(12, 0))
        self.save_btn = ttk.Button(btns, text="保存", command=self._save)
        self.save_btn.pack(side="left", padx=4)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side="left", padx=4)

        self.transient(master)
        self.grab_set()

    def _save(self):
        if self._saving:
            return
        name = self.name_var.get().strip()
        if not name:
            messagebox.showwarning("提示", "请输入平台名称", parent=self)
            return
        try:
            payload = {
                "name": name,
                "bill_day": int(self.bill_day_var.get()) if self.bill_day_var.get().strip() else None,
                "due_day": int(self.due_day_var.get()) if self.due_day_var.get().strip() else None,
                "credit_limit": float(self.limit_var.get()) if self.limit_var.get().strip() else None,
            }
        except ValueError:
            messagebox.showwarning("提示", "数字格式不正确", parent=self)
            return

        self._saving = True
        self.save_btn.config(state="disabled", text="保存中...")

        def worker():
            try:
                if self.platform:
                    self.api.update_platform(self.platform["id"], payload)
                else:
                    self.api.create_platform(payload)
                self.after(0, self._on_saved)
            except ApiError as e:
                self.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _on_saved(self):
        if self.on_saved:
            self.on_saved()
        self.destroy()

    def _on_error(self, msg: str):
        self._saving = False
        self.save_btn.config(state="normal", text="保存")
        messagebox.showerror("保存失败", msg, parent=self)


class App(tk.Tk):
    """主应用窗口。"""

    def __init__(self):
        super().__init__()
        self.title("LifeOS 网贷借还管理")
        self.geometry("1180x720")
        self.minsize(960, 600)

        self.api: LifeOSApi | None = None
        self.platforms: list[dict] = []
        self.bills: list[dict] = []
        self.repayments: list[dict] = []
        self._loading = False

        # 筛选变量
        self.filter_platform = tk.StringVar(value="全部")
        self.filter_status = tk.StringVar(value="全部")
        self.filter_month = tk.StringVar()

        self._build_ui()
        self.after(100, self._check_login)

    # ---------- 通用异步执行 ----------
    def _run_async(self, func, on_success=None, on_error=None):
        """在子线程执行 func，完成后在主线程回调 on_success(result) 或 on_error(exc)。

        参数：
            func: 无参可调用对象，在子线程执行。
            on_success: 成功回调，接收 func 返回值。
            on_error: 失败回调，接收异常对象；为 None 时弹错误框。
        """
        def worker():
            try:
                result = func()
                if on_success:
                    self.after(0, lambda: on_success(result))
            except Exception as e:
                if on_error:
                    self.after(0, lambda: on_error(e))
                else:
                    self.after(0, lambda: messagebox.showerror("错误", str(e)))
        threading.Thread(target=worker, daemon=True).start()

    # ---------- UI 构建 ----------
    def _build_ui(self):
        """构建主界面：顶部状态栏 + Notebook 三标签页。"""
        style = ttk.Style(self)
        try:
            style.theme_use("vista")
        except tk.TclError:
            pass

        top = ttk.Frame(self, padding=(12, 8))
        top.pack(side="top", fill="x")
        self.status_label = ttk.Label(top, text="未登录", foreground="gray")
        self.status_label.pack(side="left")
        self.refresh_btn = ttk.Button(top, text="刷新", command=self._refresh_all)
        self.refresh_btn.pack(side="right", padx=4)
        ttk.Button(top, text="重新登录", command=self._relogin).pack(side="right", padx=4)

        self.nb = ttk.Notebook(self)
        self.nb.pack(fill="both", expand=True, padx=12, pady=(0, 12))

        self._build_bills_tab()
        self._build_platforms_tab()

    def _build_bills_tab(self):
        """构建账单管理标签页。"""
        tab = ttk.Frame(self.nb)
        self.nb.add(tab, text="账单与还款")

        filt = ttk.Frame(tab, padding=(0, 0, 0, 8))
        filt.pack(fill="x")
        ttk.Label(filt, text="平台:").pack(side="left", padx=(0, 4))
        self.platform_combo = ttk.Combobox(
            filt, textvariable=self.filter_platform, state="readonly", width=14,
            values=["全部"],
        )
        self.platform_combo.pack(side="left", padx=(0, 12))
        ttk.Label(filt, text="状态:").pack(side="left", padx=(0, 4))
        ttk.Combobox(
            filt, textvariable=self.filter_status, state="readonly", width=12,
            values=["全部", "pending", "partial", "cleared"],
        ).pack(side="left", padx=(0, 12))
        ttk.Label(filt, text="账单月:").pack(side="left", padx=(0, 4))
        ttk.Entry(filt, textvariable=self.filter_month, width=10).pack(side="left", padx=(0, 12))
        ttk.Button(filt, text="筛选", command=self._apply_filter).pack(side="left", padx=4)
        ttk.Button(filt, text="清除", command=self._clear_filter).pack(side="left", padx=4)

        btns = ttk.Frame(filt)
        btns.pack(side="right")
        ttk.Button(btns, text="新增账单", command=self._add_bill).pack(side="left", padx=2)
        ttk.Button(btns, text="编辑账单", command=self._edit_bill).pack(side="left", padx=2)
        ttk.Button(btns, text="删除账单", command=self._delete_bill).pack(side="left", padx=2)

        paned = ttk.PanedWindow(tab, orient="vertical")
        paned.pack(fill="both", expand=True)

        bills_frame = ttk.LabelFrame(paned, text="账单列表（点击行查看下方还款记录）", padding=6)
        paned.add(bills_frame, weight=3)

        cols = ("platform", "bill_month", "due_date", "amount", "interest", "paid", "remaining", "status")
        headers = ("平台", "账单月", "到期日", "欠款(含息)", "利息", "已还", "剩余", "状态")
        widths = (100, 90, 90, 110, 90, 100, 100, 90)
        self.bills_tree = ttk.Treeview(bills_frame, columns=cols, show="headings", height=12)
        for c, h, w in zip(cols, headers, widths):
            self.bills_tree.heading(c, text=h)
            self.bills_tree.column(c, width=w, anchor="center" if c != "platform" else "w")
        self.bills_tree.pack(side="left", fill="both", expand=True)
        sb1 = ttk.Scrollbar(bills_frame, orient="vertical", command=self.bills_tree.yview)
        sb1.pack(side="right", fill="y")
        self.bills_tree.configure(yscrollcommand=sb1.set)
        self.bills_tree.bind("<<TreeviewSelect>>", self._on_bill_select)
        self.bills_tree.bind("<Double-1>", lambda e: self._edit_bill())

        rep_frame = ttk.LabelFrame(paned, text="还款记录", padding=6)
        paned.add(rep_frame, weight=2)

        rep_btns = ttk.Frame(rep_frame)
        rep_btns.pack(fill="x", pady=(0, 4))
        ttk.Button(rep_btns, text="新增还款", command=self._add_repayment).pack(side="left", padx=2)
        ttk.Button(rep_btns, text="编辑还款", command=self._edit_repayment).pack(side="left", padx=2)
        ttk.Button(rep_btns, text="删除还款", command=self._delete_repayment).pack(side="left", padx=2)

        rcols = ("repay_date", "amount", "discount", "method", "note")
        rheaders = ("还款日期", "实付", "优惠", "方式", "备注")
        rwidths = (110, 100, 90, 120, 300)
        self.rep_tree = ttk.Treeview(rep_frame, columns=rcols, show="headings", height=8)
        for c, h, w in zip(rcols, rheaders, rwidths):
            self.rep_tree.heading(c, text=h)
            self.rep_tree.column(c, width=w, anchor="w")
        self.rep_tree.pack(side="left", fill="both", expand=True)
        sb2 = ttk.Scrollbar(rep_frame, orient="vertical", command=self.rep_tree.yview)
        sb2.pack(side="right", fill="y")
        self.rep_tree.configure(yscrollcommand=sb2.set)
        self.rep_tree.bind("<Double-1>", lambda e: self._edit_repayment())

    def _build_platforms_tab(self):
        """构建平台管理标签页。"""
        tab = ttk.Frame(self.nb)
        self.nb.add(tab, text="平台管理")

        btns = ttk.Frame(tab, padding=(0, 0, 0, 8))
        btns.pack(fill="x")
        ttk.Button(btns, text="新增平台", command=self._add_platform).pack(side="left", padx=2)
        ttk.Button(btns, text="编辑平台", command=self._edit_platform).pack(side="left", padx=2)
        ttk.Button(btns, text="删除平台", command=self._delete_platform).pack(side="left", padx=2)

        cols = ("name", "bill_day", "due_day", "credit_limit")
        headers = ("平台名称", "账单日", "还款日", "额度")
        widths = (200, 100, 100, 150)
        self.plat_tree = ttk.Treeview(tab, columns=cols, show="headings")
        for c, h, w in zip(cols, headers, widths):
            self.plat_tree.heading(c, text=h)
            self.plat_tree.column(c, width=w, anchor="center")
        self.plat_tree.pack(side="left", fill="both", expand=True, padx=(0, 0), pady=4)
        sb = ttk.Scrollbar(tab, orient="vertical", command=self.plat_tree.yview)
        sb.pack(side="right", fill="y")
        self.plat_tree.configure(yscrollcommand=sb.set)
        self.plat_tree.bind("<Double-1>", lambda e: self._edit_platform())

    # ---------- 登录 ----------
    def _check_login(self):
        """启动时检查是否已有有效 token，无则弹出登录框。"""
        cfg = load_config()
        if cfg.get("token"):
            self.api = LifeOSApi()
            # 在子线程验证 token 有效性
            def verify():
                try:
                    self.api.list_platforms()
                    return True
                except ApiError:
                    return False
            def on_done(ok):
                if ok:
                    self._on_login_success(self.api)
                else:
                    self._show_login()
            self._run_async(verify, on_success=on_done)
        else:
            self._show_login()

    def _show_login(self):
        """显示登录弹窗。"""
        LoginDialog(self, self._on_login_success)

    def _on_login_success(self, api: LifeOSApi):
        """登录成功回调，更新状态栏并加载数据。"""
        self.api = api
        self.status_label.config(text=f"已登录：{api.account} @ {api.base_url}", foreground="green")
        self._refresh_all()

    def _relogin(self):
        """清除 token 并重新登录。"""
        cfg = load_config()
        cfg["token"] = ""
        save_config(cfg)
        if self.api:
            self.api.token = ""
        self._show_login()

    # ---------- 数据加载 ----------
    def _refresh_all(self):
        """异步刷新平台、账单数据。"""
        if not self.api or self._loading:
            return
        self._loading = True
        self.refresh_btn.config(state="disabled", text="加载中...")
        self.status_label.config(text=f"已登录：{self.api.account} @ {self.api.base_url}（加载中...）", foreground="blue")

        def load():
            platforms = self.api.list_platforms()
            bills = self.api.list_bills()
            return platforms, bills

        def on_done(result):
            self.platforms, self.bills = result
            self._refresh_platforms_tree()
            self._refresh_bills_tree()
            self.repayments = []
            self._refresh_rep_tree()
            names = ["全部"] + [p["name"] for p in self.platforms]
            self.platform_combo["values"] = names
            self._loading = False
            self.refresh_btn.config(state="normal", text="刷新")
            self.status_label.config(text=f"已登录：{self.api.account} @ {self.api.base_url}", foreground="green")

        def on_error(e):
            self._loading = False
            self.refresh_btn.config(state="normal", text="刷新")
            self.status_label.config(text=f"已登录：{self.api.account} @ {self.api.base_url}", foreground="green")
            if isinstance(e, ApiError) and e.status_code == 401:
                messagebox.showinfo("提示", "登录已失效，请重新登录")
                self._show_login()
            else:
                messagebox.showerror("加载失败", str(e))

        self._run_async(load, on_success=on_done, on_error=on_error)

    def _refresh_platforms_tree(self):
        """刷新平台表格。"""
        for i in self.plat_tree.get_children():
            self.plat_tree.delete(i)
        for p in self.platforms:
            self.plat_tree.insert("", "end", iid=str(p["id"]), values=(
                p.get("name", ""),
                p.get("bill_day") or "",
                p.get("due_day") or "",
                fmt(p.get("credit_limit") or 0),
            ))

    def _refresh_bills_tree(self):
        """根据筛选条件刷新账单表格。"""
        for i in self.bills_tree.get_children():
            self.bills_tree.delete(i)
        fp = self.filter_platform.get()
        fs = self.filter_status.get()
        fm = self.filter_month.get().strip()
        platform_ids = set()
        if fp and fp != "全部":
            platform_ids = {p["id"] for p in self.platforms if p["name"] == fp}
        for b in self.bills:
            if platform_ids and b.get("platform_id") not in platform_ids:
                continue
            if fs and fs != "全部" and b.get("status") != fs:
                continue
            if fm and not (b.get("bill_month") or "").startswith(fm):
                continue
            amount = b.get("amount") or 0
            paid = b.get("paid_amount") or 0
            interest = b.get("interest") or 0
            self.bills_tree.insert("", "end", iid=str(b["id"]), values=(
                self._platform_name(b.get("platform_id")),
                (b.get("bill_month") or "")[:7],
                b.get("due_date") or "",
                fmt(amount),
                fmt(interest),
                fmt(paid),
                fmt(amount - paid),
                STATUS_LABEL.get(b.get("status"), b.get("status", "")),
            ))

    def _refresh_rep_tree(self):
        """刷新还款记录表格。"""
        for i in self.rep_tree.get_children():
            self.rep_tree.delete(i)
        for r in self.repayments:
            self.rep_tree.insert("", "end", iid=str(r["id"]), values=(
                r.get("repay_date", ""),
                fmt(r.get("amount") or 0),
                fmt(r.get("discount") or 0),
                r.get("method") or "",
                r.get("note") or "",
            ))

    def _platform_name(self, pid) -> str:
        """根据平台 id 查找名称。"""
        return next((p["name"] for p in self.platforms if p["id"] == pid), "")

    # ---------- 筛选 ----------
    def _apply_filter(self):
        self._refresh_bills_tree()

    def _clear_filter(self):
        self.filter_platform.set("全部")
        self.filter_status.set("全部")
        self.filter_month.set("")
        self._refresh_bills_tree()

    # ---------- 账单 CRUD ----------
    def _selected_bill(self) -> dict | None:
        sel = self.bills_tree.selection()
        if not sel:
            return None
        bid = int(sel[0])
        return next((b for b in self.bills if b["id"] == bid), None)

    def _add_bill(self):
        BillDialog(self, self.api, self.platforms, on_saved=self._refresh_all)

    def _edit_bill(self):
        bill = self._selected_bill()
        if not bill:
            messagebox.showinfo("提示", "请先选择一条账单")
            return
        BillDialog(self, self.api, self.platforms, bill=bill, on_saved=self._refresh_all)

    def _delete_bill(self):
        bill = self._selected_bill()
        if not bill:
            messagebox.showinfo("提示", "请先选择一条账单")
            return
        if not messagebox.askyesno("确认", f"确定删除账单「{self._platform_name(bill.get('platform_id'))} {bill.get('bill_month', '')[:7]}」吗？"):
            return
        def do_delete():
            self.api.delete_bill(bill["id"])
        def on_done(_):
            self._refresh_all()
        self._run_async(do_delete, on_success=on_done, on_error=lambda e: messagebox.showerror("删除失败", str(e)))

    def _on_bill_select(self, _event):
        """账单行选中时异步加载其还款记录。"""
        bill = self._selected_bill()
        if not bill:
            return
        def load():
            return self.api.list_repayments(bill["id"])
        def on_done(reps):
            self.repayments = reps
            self._refresh_rep_tree()
        self._run_async(load, on_success=on_done, on_error=lambda e: messagebox.showerror("加载还款失败", str(e)))

    # ---------- 还款 CRUD ----------
    def _selected_repayment(self) -> dict | None:
        sel = self.rep_tree.selection()
        if not sel:
            return None
        rid = int(sel[0])
        return next((r for r in self.repayments if r["id"] == rid), None)

    def _add_repayment(self):
        bill = self._selected_bill()
        if not bill:
            messagebox.showinfo("提示", "请先在上方选择一条账单")
            return
        RepaymentDialog(self, self.api, bill, on_saved=self._refresh_all)

    def _edit_repayment(self):
        bill = self._selected_bill()
        rep = self._selected_repayment()
        if not bill or not rep:
            messagebox.showinfo("提示", "请先选择一条还款记录")
            return
        RepaymentDialog(self, self.api, bill, repayment=rep, on_saved=self._refresh_all)

    def _delete_repayment(self):
        rep = self._selected_repayment()
        if not rep:
            messagebox.showinfo("提示", "请先选择一条还款记录")
            return
        if not messagebox.askyesno("确认", "确定删除这条还款记录吗？"):
            return
        def do_delete():
            self.api.delete_repayment(rep["id"])
        def on_done(_):
            self._refresh_all()
        self._run_async(do_delete, on_success=on_done, on_error=lambda e: messagebox.showerror("删除失败", str(e)))

    # ---------- 平台 CRUD ----------
    def _selected_platform(self) -> dict | None:
        sel = self.plat_tree.selection()
        if not sel:
            return None
        pid = int(sel[0])
        return next((p for p in self.platforms if p["id"] == pid), None)

    def _add_platform(self):
        PlatformDialog(self, self.api, on_saved=self._refresh_all)

    def _edit_platform(self):
        p = self._selected_platform()
        if not p:
            messagebox.showinfo("提示", "请先选择一个平台")
            return
        PlatformDialog(self, self.api, platform=p, on_saved=self._refresh_all)

    def _delete_platform(self):
        p = self._selected_platform()
        if not p:
            messagebox.showinfo("提示", "请先选择一个平台")
            return
        if not messagebox.askyesno("确认", f"确定删除平台「{p.get('name')}」吗？"):
            return
        def do_delete():
            self.api.delete_platform(p["id"])
        def on_done(_):
            self._refresh_all()
        self._run_async(do_delete, on_success=on_done, on_error=lambda e: messagebox.showerror("删除失败", str(e)))


def main():
    """程序入口。"""
    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()
