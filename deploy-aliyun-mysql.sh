#!/bin/bash
# =====================================================
# MyFavor Backend 一键部署脚本(Aliyun ECS + SQLPub)
# 系统:Ubuntu 22.04 LTS
# 数据库:MySQL 8 (SQLPub)
# =====================================================
# 用法:
#   1. 在 Windows PowerShell 执行:
#        scp deploy-aliyun-mysql.sh root@你的ECS_IP:/root/
#   2. SSH 上去:
#        ssh root@你的ECS_IP
#   3. 跑:
#        bash /root/deploy-aliyun-mysql.sh
#   4. 按提示填入 SQLPub 连接串
# =====================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 MyFavor Backend 部署${NC}"
echo "================================="

# ===== 1. 系统更新 =====
echo -e "\n${YELLOW}[1/8]${NC} 更新系统..."
apt update && apt upgrade -y

# ===== 2. 装基础工具 =====
echo -e "\n${YELLOW}[2/8]${NC} 装基础工具..."
apt install -y curl wget git build-essential ufw ca-certificates

# ===== 3. 装 Node.js 20 =====
echo -e "\n${YELLOW}[3/8]${NC} 装 Node.js 20..."
if ! command -v node &> /dev/null || [ "$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" -lt 20 ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
fi
node -v
npm -v

# ===== 4. 装 PM2 =====
echo -e "\n${YELLOW}[4/8]${NC} 装 PM2..."
npm install -g pm2

# ===== 5. 防火墙 =====
echo -e "\n${YELLOW}[5/8]${NC} 配置防火墙..."
ufw allow OpenSSH 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw allow 3000/tcp 2>/dev/null || true
echo "y" | ufw enable
ufw status

# ===== 6. 拉代码 =====
echo -e "\n${YELLOW}[6/8]${NC} 拉取代码..."
mkdir -p /opt/myfavor
cd /opt/myfavor
if [ -d "MyFavor" ]; then
    echo "已存在代码,拉最新..."
    cd MyFavor && git pull
    cd ..
else
    git clone https://github.com/chenyi1320/MyFavor.git
    cd MyFavor
fi

cd backend
echo "装依赖..."
npm install --omit=dev
npx prisma generate
echo "推送 schema 到数据库(创建表)..."
npx prisma db push --skip-generate
echo "编译 TypeScript..."
npm run build


# ===== 7. 创建 .env(需要手动填 SQLPub 连接串) =====
echo -e "\n${YELLOW}[7/8]${NC} 配置 .env..."
if [ ! -f ".env" ]; then
    # 生成 JWT 强密钥
    JWT_SECRET_GEN=$(openssl rand -hex 64)
    
    cat > .env <<EOF
# === 数据库(SQLPub MySQL)===
# ⚠️ 必填!在 SQLPub 控制台拿:https://sqlpub.com
# 格式:mysql://user:pass@host:port/dbname
# 示例:mysql://myfavor:mypwd@db-myfavor.sqlpub.com:3306/myfavor
# (密码含 @ # \$ % 等特殊字符要 URL-encode,@ → %40, # → %23)
DATABASE_URL="mysql://USER:PASSWORD@HOST:3306/DBNAME"

# === Resend 邮件服务 ===
# ⚠️ 在 https://resend.com/api-keys 拿新 Key
RESEND_API_KEY="re_XXXXXX"
RESEND_FROM_EMAIL="MyFavor <onboarding@resend.dev>"

# === App 元信息 ===
APP_NAME="MyFavor"
# 部署后填入 ECS 公网 IP 或你自己的域名
APP_URL="http://YOUR_ECS_IP:3000"
APP_URL_SCHEME="myfavor"

# === JWT ===
JWT_SECRET="${JWT_SECRET_GEN}"
JWT_EXPIRES_IN="30d"

# === 服务器 ===
PORT=3000
NODE_ENV=production
EOF
    
    echo -e "${RED}⚠️  .env 已创建,但你必须手动填真实值!${NC}"
    echo ""
    echo "下一步(在这个 SSH 终端里):"
    echo -e "  ${YELLOW}nano /opt/myfavor/MyFavor/backend/.env${NC}"
    echo ""
    echo "至少要改这两个字段:"
    echo "  DATABASE_URL=你的 SQLPub MySQL 连接串"
    echo "  RESEND_API_KEY=你的新 Resend Key"
    echo "  APP_URL=http://你的 ECS 公网 IP:3000"
    echo ""
    echo "保存: Ctrl+O → Enter → Ctrl+X"
    echo ""
    echo -e "${YELLOW}填完后回我,我帮你跑迁移和启动!${NC}"
    echo ""
    
    # 自动用 nano 打开,让用户填
    if [ -n "$PS1" ]; then
        read -p "现在打开 nano 编辑? [y/N] " open
        if [ "$open" = "y" ]; then
            nano .env
        fi
    fi
else
    echo ".env 已存在,跳过"
fi

# ===== 8. 启动后端(占位启动,等填好 .env 后) =====
echo -e "\n${YELLOW}[8/8]${NC} 启动后端(填好 .env 后会自动跑)..."
pm2 delete myfavor-api 2>/dev/null || true
pm2 start dist/server.js --name myfavor-api
pm2 save

# pm2 开机自启(可能需要 sudo 重启时启用)
pm2 startup | tail -1 | bash 2>/dev/null || pm2 startup systemd -u root --hp /root 2>/dev/null || true

echo ""
echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}✅ 基础部署完成!${NC}"
echo -e "${GREEN}=================================${NC}"
echo ""
echo "检查状态:"
echo "  pm2 status"
echo "  pm2 logs myfavor-api"
echo ""
echo "本机测试:"
echo "  curl http://localhost:3000/health"
echo ""
echo "如果 curl 返回 {\"status\":\"healthy\"}= 成功!"
echo ""
echo "接下来:"
echo "  1. 在 SQLPub 控制台加 ECS 公网 IP 到白名单"
echo "  2. 在阿里云 ECS 安全组开放 22/80/443/3000 端口"
echo "  3. 在 iOS App 中改 baseURL 为 http://你的ECS_IP:3000"
echo "  4. curl http://你的ECS_IP:3000/health 测试公网连通"
