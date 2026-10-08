@echo off
chcp 65001 >nul
echo ========================================
echo  LifeOS 网贷借还管理工具 - 打包脚本
echo ========================================
echo.

REM 安装依赖
echo [1/3] 检查依赖...
pip install -r requirements.txt -q
if errorlevel 1 (
    echo 依赖安装失败，请检查网络或 pip 配置
    pause
    exit /b 1
)

REM 清理旧的构建产物
echo [2/3] 清理旧产物...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist LoanBillsTool.spec del /q LoanBillsTool.spec

REM 打包
echo [3/3] 开始打包...
pyinstaller ^
    --onefile ^
    --noconsole ^
    --name LoanBillsTool ^
    --add-data "config.py;." ^
    --hidden-import config ^
    main.py

if errorlevel 1 (
    echo.
    echo 打包失败！
    pause
    exit /b 1
)

echo.
echo ========================================
echo  打包成功！
echo  可执行文件: dist\LoanBillsTool.exe
echo ========================================
pause
