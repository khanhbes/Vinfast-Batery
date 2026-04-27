#!/bin/bash
# ══════════════════════════════════════════════════════════════
# deploy.sh — Deploy VinFast Battery lên Linux VPS
# Chạy trên VPS: bash scripts/deploy.sh
# ══════════════════════════════════════════════════════════════
set -euo pipefail

DEPLOY_DIR="/opt/vinfast-battery"
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO.git"   # ← đổi lại
BRANCH="main"

echo "🚀 VinFast Battery — Deploy"
echo "================================"

# ── 1. Cài Docker nếu chưa có ─────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "📦 Cài Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "✅ Docker đã cài. Cần logout/login lại để áp dụng group."
fi

if ! command -v docker &>/dev/null; then
    echo "❌ Docker chưa sẵn sàng. Vui lòng chạy lại sau khi logout/login."
    exit 1
fi

# ── 2. Clone hoặc pull code ───────────────────────────────────
if [ -d "$DEPLOY_DIR/.git" ]; then
    echo "📥 Pulling latest code..."
    cd "$DEPLOY_DIR"
    git pull origin "$BRANCH"
else
    echo "📥 Cloning repo..."
    sudo mkdir -p "$DEPLOY_DIR"
    sudo chown "$USER:$USER" "$DEPLOY_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"
fi

cd "$DEPLOY_DIR/web"

# ── 3. Kiểm tra file .env ────────────────────────────────────
if [ ! -f ".env" ]; then
    echo ""
    echo "⚠  File .env chưa tồn tại!"
    echo "   Chạy lệnh sau để tạo:"
    echo "   cp .env.docker.example .env && nano .env"
    echo ""
    exit 1
fi

echo "✅ File .env tìm thấy."

# ── 4. Tạo thư mục models (nếu chưa có) ──────────────────────
mkdir -p models

# ── 5. Build và start containers ─────────────────────────────
echo ""
echo "🔨 Building Docker images..."
docker compose --env-file .env build --no-cache api dashboard

echo ""
echo "🚀 Starting services..."
docker compose --env-file .env up -d

# ── 6. Kiểm tra trạng thái ───────────────────────────────────
echo ""
echo "⏳ Chờ services khởi động (60s)..."
sleep 60

echo ""
echo "📊 Trạng thái containers:"
docker compose ps

echo ""
echo "🔍 Health check:"
curl -sf http://localhost/api/health && echo "  ✅ API OK" || echo "  ⚠ API chưa sẵn sàng"

echo ""
echo "✅ Deploy hoàn tất!"
echo "   Dashboard: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
