#!/bin/bash

# Turkmen VPN Panel - SQLite bilen
# Tamamly işleýän sistem

# Renk kodlary
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Root barlag
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Ýalňyş: Bu script root ulanyjy hökmünde işlemeli.${NC}"
    exit 1
fi

# Funksiýalar
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

# Giriş maglumatlaryny soramak
get_credentials() {
    echo
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           TURKMEN VPN PANEL GURNALAMA${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════${NC}"
    echo
    
    read -p "Admin username giriziň: " ADMIN_USERNAME
    while [ -z "$ADMIN_USERNAME" ]; do
        print_error "Username boş bolmaly däl!"
        read -p "Admin username giriziň: " ADMIN_USERNAME
    done
    
    read -s -p "Admin paroly giriziň: " ADMIN_PASSWORD
    echo
    while [ -z "$ADMIN_PASSWORD" ]; do
        print_error "Parol boş bolmaly däl!"
        read -s -p "Admin paroly giriziň: " ADMIN_PASSWORD
        echo
    done
    
    read -p "Web panel porty (default: 7000): " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-7000}
    
    # Server IP-ni al
    SERVER_IP=$(curl -s icanhazip.com || hostname -I | awk '{print $1}')
}

# Sistem tälimleri
system_setup() {
    print_status "Sistem tälenir..."
    apt-get update && apt-get upgrade -y
}

# Gerekli programmalar
install_dependencies() {
    print_status "Programmalar ýüklenir..."
    apt-get install -y wget curl git python3 python3-pip nginx \
        sqlite3 shadowsocks-libev
}

# SQLite düzümleri
setup_database() {
    print_status "SQLite database düzülýär..."
    
    # Projekt papkasyny döret
    mkdir -p /opt/turkmen-vpn-panel/{web,api,data,configs}
    cd /opt/turkmen-vpn-panel
    
    # Database döret
    sqlite3 data/vpn_panel.db <<EOF
    CREATE TABLE IF NOT EXISTS admin_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        email TEXT,
        subscription_type TEXT DEFAULT 'free',
        data_limit INTEGER DEFAULT 1073741824,
        used_data INTEGER DEFAULT 0,
        expiration_date TEXT,
        is_active BOOLEAN DEFAULT 1,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        config TEXT,
        is_active BOOLEAN DEFAULT 1
    );
    
    CREATE TABLE IF NOT EXISTS subscriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        server_id INTEGER,
        config_data TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users (id),
        FOREIGN KEY (server_id) REFERENCES servers (id)
    );
    
    -- Admin ulanyjysyny döret
    INSERT OR IGNORE INTO admin_users (username, password) 
    VALUES ('${ADMIN_USERNAME}', '${ADMIN_PASSWORD}');
    
    -- Serverleri döret
    INSERT OR IGNORE INTO servers (name, type, host, port, config) VALUES
    ('Shadowsocks Server', 'shadowsocks', '${SERVER_IP}', 8388, '{"method": "aes-256-gcm", "password": "turkmenvpn2024"}'),
    ('VLESS Server', 'vless', '${SERVER_IP}', 443, '{"flow": "", "encryption": "none"}'),
    ('VMESS Server', 'vmess', '${SERVER_IP}', 8443, '{"alterId": 0}');
EOF

    # Database hukuklary
    chmod 755 data/vpn_panel.db
}

# Web panel düzümleri
setup_web_panel() {
    print_status "Web panel düzülýär..."
    
    cd /opt/turkmen-vpn-panel/web
    
    # Giriş sahypasy
    cat > login.html <<'EOF'
<!DOCTYPE html>
<html lang="tk">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Turkmen VPN - Giriş</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary: #6366f1;
            --primary-dark: #4338ca;
            --secondary: #64748b;
            --dark: #1e293b;
            --darker: #0f172a;
            --light: #f8fafc;
            --danger: #ef4444;
            --success: #10b981;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', system-ui, sans-serif; 
            background: linear-gradient(135deg, var(--darker), var(--dark));
            color: var(--light);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .login-container {
            background: rgba(30, 41, 59, 0.95);
            backdrop-filter: blur(10px);
            padding: 2.5rem;
            border-radius: 1rem;
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        
        .logo {
            text-align: center;
            margin-bottom: 2rem;
        }
        
        .logo h1 {
            color: var(--primary);
            font-size: 1.8rem;
            margin-bottom: 0.5rem;
        }
        
        .logo p {
            color: var(--secondary);
            font-size: 0.9rem;
        }
        
        .form-group {
            margin-bottom: 1.5rem;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 0.5rem;
            color: var(--secondary);
            font-weight: 500;
        }
        
        .form-input {
            width: 100%;
            padding: 0.75rem 1rem;
            border: 2px solid #334155;
            border-radius: 0.5rem;
            background: #1e293b;
            color: var(--light);
            font-size: 1rem;
            transition: all 0.3s ease;
        }
        
        .form-input:focus {
            border-color: var(--primary);
            outline: none;
            box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.2);
        }
        
        .btn {
            width: 100%;
            padding: 0.75rem;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 0.5rem;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .btn:hover {
            background: var(--primary-dark);
            transform: translateY(-1px);
        }
        
        .error-message {
            background: var(--danger);
            color: white;
            padding: 0.75rem;
            border-radius: 0.5rem;
            margin-top: 1rem;
            text-align: center;
            display: none;
        }
        
        .theme-toggle {
            position: absolute;
            top: 2rem;
            right: 2rem;
            background: none;
            border: none;
            color: var(--secondary);
            cursor: pointer;
            font-size: 1.5rem;
        }
    </style>
</head>
<body>
    <button class="theme-toggle" onclick="toggleTheme()">🌓</button>
    
    <div class="login-container">
        <div class="logo">
            <h1><i class="fas fa-shield-alt"></i> Turkmen VPN</h1>
            <p>Admin Paneline Hoş Geldiňiz</p>
        </div>
        
        <form id="loginForm">
            <div class="form-group">
                <label for="username"><i class="fas fa-user"></i> Ulanyjy ady:</label>
                <input type="text" id="username" class="form-input" placeholder="Username giriziň" required>
            </div>
            
            <div class="form-group">
                <label for="password"><i class="fas fa-lock"></i> Parol:</label>
                <input type="password" id="password" class="form-input" placeholder="Paroly giriziň" required>
            </div>
            
            <button type="submit" class="btn">
                <i class="fas fa-sign-in-alt"></i> Giriş
            </button>
            
            <div id="errorMessage" class="error-message">
                <i class="fas fa-exclamation-triangle"></i> Ýalňyş ulanyjy ady ýa-da parol!
            </div>
        </form>
    </div>

    <script>
        function toggleTheme() {
            document.body.classList.toggle('light-theme');
        }
        
        document.getElementById('loginForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            
            try {
                const response = await fetch('/api/auth/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username, password })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    localStorage.setItem('token', result.token);
                    window.location.href = '/panel.html';
                } else {
                    document.getElementById('errorMessage').style.display = 'block';
                    setTimeout(() => {
                        document.getElementById('errorMessage').style.display = 'none';
                    }, 3000);
                }
            } catch (error) {
                document.getElementById('errorMessage').textContent = 'Server ýalňyşy!';
                document.getElementById('errorMessage').style.display = 'block';
            }
        });
    </script>
</body>
</html>
EOF

    # Admin panel sahypasy
    cat > panel.html <<'EOF'
<!DOCTYPE html>
<html lang="tk">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Turkmen VPN - Admin Panel</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary: #6366f1;
            --primary-dark: #4338ca;
            --secondary: #64748b;
            --dark: #1e293b;
            --darker: #0f172a;
            --light: #f8fafc;
            --danger: #ef4444;
            --success: #10b981;
            --warning: #f59e0b;
            --sidebar-width: 250px;
        }
        
        .light-theme {
            --dark: #f8fafc;
            --darker: #e2e8f0;
            --light: #1e293b;
            --secondary: #475569;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', system-ui, sans-serif; 
            background: var(--darker);
            color: var(--light);
            display: flex;
            min-height: 100vh;
        }
        
        /* Sidebar */
        .sidebar {
            width: var(--sidebar-width);
            background: var(--dark);
            border-right: 1px solid #334155;
            padding: 1.5rem;
            position: fixed;
            height: 100vh;
            overflow-y: auto;
        }
        
        .logo {
            text-align: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid #334155;
        }
        
        .logo h1 {
            color: var(--primary);
            font-size: 1.3rem;
        }
        
        .nav-links {
            list-style: none;
        }
        
        .nav-links li {
            margin-bottom: 0.5rem;
        }
        
        .nav-links a {
            display: flex;
            align-items: center;
            padding: 0.75rem 1rem;
            color: var(--secondary);
            text-decoration: none;
            border-radius: 0.5rem;
            transition: all 0.3s ease;
        }
        
        .nav-links a:hover, .nav-links a.active {
            background: var(--primary);
            color: white;
        }
        
        .nav-links i {
            margin-right: 0.75rem;
            width: 20px;
            text-align: center;
        }
        
        /* Main Content */
        .main-content {
            flex: 1;
            margin-left: var(--sidebar-width);
            padding: 2rem;
        }
        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid #334155;
        }
        
        .user-menu {
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        
        .btn {
            padding: 0.5rem 1rem;
            border: none;
            border-radius: 0.5rem;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        
        .btn-primary { background: var(--primary); color: white; }
        .btn-danger { background: var(--danger); color: white; }
        .btn-success { background: var(--success); color: white; }
        .btn-warning { background: var(--warning); color: white; }
        
        .btn:hover { transform: translateY(-1px); }
        
        /* Cards */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .stat-card {
            background: var(--dark);
            padding: 1.5rem;
            border-radius: 1rem;
            border: 1px solid #334155;
            text-align: center;
        }
        
        .stat-number {
            font-size: 2rem;
            font-weight: bold;
            color: var(--primary);
            margin-bottom: 0.5rem;
        }
        
        .stat-label {
            color: var(--secondary);
            font-size: 0.9rem;
        }
        
        /* Tables */
        .table-container {
            background: var(--dark);
            border-radius: 1rem;
            border: 1px solid #334155;
            overflow: hidden;
        }
        
        .table-header {
            padding: 1.5rem;
            border-bottom: 1px solid #334155;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th, td {
            padding: 1rem;
            text-align: left;
            border-bottom: 1px solid #334155;
        }
        
        th {
            background: rgba(99, 102, 241, 0.1);
            color: var(--primary);
            font-weight: 600;
        }
        
        /* Forms */
        .form-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1.5rem;
        }
        
        .form-group {
            margin-bottom: 1rem;
        }
        
        .form-label {
            display: block;
            margin-bottom: 0.5rem;
            color: var(--secondary);
            font-weight: 500;
        }
        
        .form-input, .form-select {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #334155;
            border-radius: 0.5rem;
            background: var(--darker);
            color: var(--light);
        }
        
        .config-box {
            background: var(--darker);
            padding: 1rem;
            border-radius: 0.5rem;
            border: 1px solid #334155;
            font-family: 'Courier New', monospace;
            white-space: pre-wrap;
            word-break: break-all;
            margin: 1rem 0;
            font-size: 0.9rem;
        }
        
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        
        .theme-toggle {
            background: none;
            border: none;
            color: var(--secondary);
            cursor: pointer;
            font-size: 1.2rem;
        }
        
        .badge {
            padding: 0.25rem 0.5rem;
            border-radius: 0.25rem;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .badge-free { background: var(--secondary); color: white; }
        .badge-premium { background: var(--primary); color: white; }
        .badge-vip { background: var(--warning); color: white; }
        
        .status {
            padding: 0.25rem 0.5rem;
            border-radius: 0.25rem;
            font-size: 0.8rem;
        }
        
        .status.active { background: var(--success); color: white; }
        .status.inactive { background: var(--danger); color: white; }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="logo">
            <h1><i class="fas fa-shield-alt"></i> Turkmen VPN</h1>
        </div>
        
        <ul class="nav-links">
            <li><a href="#" class="active" onclick="showTab('dashboard')"><i class="fas fa-tachometer-alt"></i> Dashboard</a></li>
            <li><a href="#" onclick="showTab('users')"><i class="fas fa-users"></i> Ulanyjylar</a></li>
            <li><a href="#" onclick="showTab('create')"><i class="fas fa-plus-circle"></i> Täze Potpiska</a></li>
            <li><a href="#" onclick="showTab('configs')"><i class="fas fa-code"></i> Konfigurasiýa</a></li>
            <li><a href="#" onclick="showTab('settings')"><i class="fas fa-cog"></i> Sazlamalar</a></li>
        </ul>
    </div>

    <!-- Main Content -->
    <div class="main-content">
        <div class="header">
            <h2 id="pageTitle"><i class="fas fa-tachometer-alt"></i> Dashboard</h2>
            <div class="user-menu">
                <button class="theme-toggle" onclick="toggleTheme()"><i class="fas fa-moon"></i></button>
                <span id="currentUser">Admin</span>
                <button class="btn btn-danger" onclick="logout()"><i class="fas fa-sign-out-alt"></i> Çykyş</button>
            </div>
        </div>

        <!-- Dashboard Tab -->
        <div id="dashboard" class="tab-content active">
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-number" id="totalUsers">0</div>
                    <div class="stat-label"><i class="fas fa-users"></i> Jemi Ulanyjylar</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" id="activeUsers">0</div>
                    <div class="stat-label"><i class="fas fa-user-check"></i> Aktiw Ulanyjylar</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">3</div>
                    <div class="stat-label"><i class="fas fa-server"></i> Serverler</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" id="totalData">0 GB</div>
                    <div class="stat-label"><i class="fas fa-chart-bar"></i> Jemi Traffic</div>
                </div>
            </div>
        </div>

        <!-- Users Tab -->
        <div id="users" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3><i class="fas fa-users"></i> Ulanyjylaryň Sanawy</h3>
                    <button class="btn btn-primary" onclick="showTab('create')"><i class="fas fa-plus"></i> Täze Ulanyjy</button>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th><i class="fas fa-user"></i> Username</th>
                            <th><i class="fas fa-crown"></i> Potpiska</th>
                            <th><i class="fas fa-database"></i> Limit</th>
                            <th><i class="fas fa-calendar"></i> Möhleti</th>
                            <th><i class="fas fa-circle"></i> Status</th>
                            <th><i class="fas fa-cog"></i> Hereketler</th>
                        </tr>
                    </thead>
                    <tbody id="usersTable">
                        <!-- Dynamic content -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Create Subscription Tab -->
        <div id="create" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3><i class="fas fa-plus-circle"></i> Täze Potpiska Döret</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <form id="createSubscriptionForm">
                        <div class="form-grid">
                            <div class="form-group">
                                <label class="form-label"><i class="fas fa-user"></i> Ulanyjy ady:</label>
                                <input type="text" class="form-input" id="newUsername" placeholder="Ulanyjy adyny giriziň" required>
                            </div>
                            <div class="form-group">
                                <label class="form-label"><i class="fas fa-server"></i> Server görnüşi:</label>
                                <select class="form-select" id="serverType" required>
                                    <option value="shadowsocks">Shadowsocks</option>
                                    <option value="vless">VLESS</option>
                                    <option value="vmess">VMESS</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label class="form-label"><i class="fas fa-crown"></i> Potpiska görnüşi:</label>
                                <select class="form-select" id="subType" required>
                                    <option value="free">Mugt (1GB)</option>
                                    <option value="premium">Premium (10GB)</option>
                                    <option value="vip">VIP (Çäksiz)</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label class="form-label"><i class="fas fa-database"></i> Data limiti (GB):</label>
                                <input type="number" class="form-input" id="dataLimit" placeholder="Çäksiz üçin boş goýuň" min="0">
                            </div>
                            <div class="form-group">
                                <label class="form-label"><i class="fas fa-calendar"></i> Möhlet (gün):</label>
                                <input type="number" class="form-input" id="duration" value="30" min="1" placeholder="30">
                            </div>
                        </div>
                        <button type="submit" class="btn btn-success"><i class="fas fa-check"></i> Potpiska Döret</button>
                    </form>
                </div>
            </div>
        </div>

        <!-- Configs Tab -->
        <div id="configs" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3><i class="fas fa-code"></i> Konfigurasiýa Generator</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <div class="form-grid">
                        <div class="form-group">
                            <label class="form-label"><i class="fas fa-user"></i> Ulanyjy ady:</label>
                            <input type="text" class="form-input" id="configUsername" placeholder="Konfigurasiýa aljak ulanyjy">
                        </div>
                        <div class="form-group">
                            <label class="form-label"><i class="fas fa-server"></i> Server görnüşi:</label>
                            <select class="form-select" id="configServerType">
                                <option value="shadowsocks">Shadowsocks</option>
                                <option value="vless">VLESS</option>
                                <option value="vmess">VMESS</option>
                            </select>
                        </div>
                    </div>
                    <button class="btn btn-primary" onclick="generateConfig()"><i class="fas fa-download"></i> Konfigurasiýa Al</button>
                    
                    <div id="configOutput" style="margin-top: 20px;"></div>
                </div>
            </div>
        </div>

        <!-- Settings Tab -->
        <div id="settings" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3><i class="fas fa-cog"></i> Panel Sazlamalary</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <h4><i class="fas fa-user-cog"></i> Giriş Maglumatlary</h4>
                    <div class="form-grid" style="margin-bottom: 2rem;">
                        <div class="form-group">
                            <label class="form-label">Täze Username:</label>
                            <input type="text" class="form-input" id="resetUsername" placeholder="Täze username">
                        </div>
                        <div class="form-group">
                            <label class="form-label">Täze Parol:</label>
                            <input type="password" class="form-input" id="resetPassword" placeholder="Täze parol">
                        </div>
                    </div>
                    <button class="btn btn-warning" onclick="resetCredentials()"><i class="fas fa-sync"></i> Username/Parol Üýtget</button>
                    
                    <hr style="margin: 2rem 0; border-color: #334155;">
                    
                    <h4><i class="fas fa-network-wired"></i> Panel Porty</h4>
                    <div class="form-group">
                        <label class="form-label">Panel Porty:</label>
                        <input type="number" class="form-input" id="panelPort" value="7000" min="1000" max="65535">
                    </div>
                    <button class="btn btn-warning" onclick="changePanelPort()"><i class="fas fa-exchange-alt"></i> Port Üýtget</button>
                    
                    <hr style="margin: 2rem 0; border-color: #334155;">
                    
                    <h4><i class="fas fa-play-circle"></i> Panel Dolandyryşy</h4>
                    <div style="display: flex; gap: 1rem; margin-top: 1rem;">
                        <button class="btn btn-success" onclick="panelAction('start')"><i class="fas fa-play"></i> Panel Başlat</button>
                        <button class="btn btn-warning" onclick="panelAction('stop')"><i class="fas fa-stop"></i> Panel Duruz</button>
                        <button class="btn btn-primary" onclick="panelAction('restart')"><i class="fas fa-redo"></i> Panel Täzeden</button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Giriş barlag
        const token = localStorage.getItem('token');
        if (!token) {
            window.location.href = '/login.html';
        }

        // Tab görkezmek
        function showTab(tabName) {
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });
            document.querySelectorAll('.nav-links a').forEach(link => {
                link.classList.remove('active');
            });
            
            document.getElementById(tabName).classList.add('active');
            event.target.classList.add('active');
            
            // Page title üýtget
            const titles = {
                'dashboard': '<i class="fas fa-tachometer-alt"></i> Dashboard',
                'users': '<i class="fas fa-users"></i> Ulanyjylar',
                'create': '<i class="fas fa-plus-circle"></i> Täze Potpiska', 
                'configs': '<i class="fas fa-code"></i> Konfigurasiýa',
                'settings': '<i class="fas fa-cog"></i> Sazlamalar'
            };
            document.getElementById('pageTitle').innerHTML = titles[tabName];
            
            // Maglumatlary ýükle
            if (tabName === 'dashboard') loadStats();
            if (tabName === 'users') loadUsers();
        }

        // Tema üýtgetmek
        function toggleTheme() {
            document.body.classList.toggle('light-theme');
            const icon = document.querySelector('.theme-toggle i');
            if (document.body.classList.contains('light-theme')) {
                icon.className = 'fas fa-sun';
            } else {
                icon.className = 'fas fa-moon';
            }
        }

        // Çykyş
        function logout() {
            localStorage.removeItem('token');
            window.location.href = '/login.html';
        }

        // Statistikalar
        async function loadStats() {
            try {
                const response = await fetch('/api/admin/stats', {
                    headers: { 'Authorization': 'Bearer ' + token }
                });
                const data = await response.json();
                
                if (data.success) {
                    document.getElementById('totalUsers').textContent = data.totalUsers;
                    document.getElementById('activeUsers').textContent = data.activeUsers;
                    document.getElementById('totalData').textContent = data.totalData + ' GB';
                }
            } catch (error) {
                console.error('Stats ýüklenmedi:', error);
            }
        }

        // Ulanyjylar
        async function loadUsers() {
            try {
                const response = await fetch('/api/admin/users', {
                    headers: { 'Authorization': 'Bearer ' + token }
                });
                const users = await response.json();
                
                const tbody = document.getElementById('usersTable');
                if (users.success && users.data) {
                    tbody.innerHTML = users.data.map(user => `
                        <tr>
                            <td><i class="fas fa-user"></i> ${user.username}</td>
                            <td><span class="badge badge-${user.subscription_type}">${user.subscription_type}</span></td>
                            <td>${user.data_limit ? (user.data_limit / 1073741824).toFixed(1) + ' GB' : '<i class="fas fa-infinity"></i> Çäksiz'}</td>
                            <td>${user.expiration_date || '<i class="fas fa-infinity"></i> Çäksiz'}</td>
                            <td><span class="status ${user.is_active ? 'active' : 'inactive'}">${user.is_active ? 'Aktiw' : 'Passiw'}</span></td>
                            <td>
                                <button class="btn btn-primary" onclick="editUser('${user.username}')" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;"><i class="fas fa-edit"></i></button>
                                <button class="btn btn-danger" onclick="deleteUser('${user.username}')" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;"><i class="fas fa-trash"></i></button>
                            </td>
                        </tr>
                    `).join('');
                } else {
                    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">Ulanyjy ýok</td></tr>';
                }
            } catch (error) {
                console.error('Ulanyjylar ýüklenmedi:', error);
                document.getElementById('usersTable').innerHTML = '<tr><td colspan="6" style="text-align: center;">Ýüklenýär...</td></tr>';
            }
        }

        // Potpiska döret
        document.getElementById('createSubscriptionForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const formData = {
                username: document.getElementById('newUsername').value,
                server_type: document.getElementById('serverType').value,
                subscription_type: document.getElementById('subType').value,
                data_limit: document.getElementById('dataLimit').value || null,
                duration: document.getElementById('duration').value || 30
            };

            try {
                const response = await fetch('/api/admin/create-user', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ' + token
                    },
                    body: JSON.stringify(formData)
                });

                const result = await response.json();
                
                if (result.success) {
                    alert('✅ Potpiska üstünlikli döredildi!');
                    this.reset();
                    loadUsers();
                    loadStats();
                } else {
                    alert('❌ Ýalňyş: ' + result.message);
                }
            } catch (error) {
                alert('❌ Serwer ýalňyşy: ' + error);
            }
        });

        // Konfigurasiýa generator
        async function generateConfig() {
            const username = document.getElementById('configUsername').value;
            const serverType = document.getElementById('configServerType').value;
            
            if (!username) {
                alert('❌ Ulanyjy adyny giriziň!');
                return;
            }

            try {
                const response = await fetch(`/api/admin/generate-config?username=${username}&type=${serverType}`, {
                    headers: { 'Authorization': 'Bearer ' + token }
                });
                
                const result = await response.json();
                
                if (result.success) {
                    document.getElementById('configOutput').innerHTML = `
                        <h4><i class="fas fa-file-code"></i> ${serverType.toUpperCase()} Konfigurasiýasy:</h4>
                        <div class="config-box">${result.config}</div>
                        <button class="btn btn-success" onclick="downloadConfig('${username}', '${serverType}')"><i class="fas fa-download"></i> Konfigurasiýany Ýükle</button>
                    `;
                } else {
                    alert('❌ Ýalňyş: ' + result.message);
                }
            } catch (error) {
                alert('❌ Serwer ýalňyşy: ' + error);
            }
        }

        // Panel hereketleri
        async function panelAction(action) {
            try {
                const response = await fetch(`/api/admin/panel-${action}`, {
                    method: 'POST',
                    headers: { 'Authorization': 'Bearer ' + token }
                });
                
                const result = await response.json();
                alert(result.message);
            } catch (error) {
                alert('❌ Serwer ýalňyşy: ' + error);
            }
        }

        // Username/parol üýtgetmek
        async function resetCredentials() {
            const newUsername = document.getElementById('resetUsername').value;
            const newPassword = document.getElementById('resetPassword').value;
            
            if (!newUsername && !newPassword) {
                alert('❌ Username ýa-da parol giriziň!');
                return;
            }

            try {
                const response = await fetch('/api/admin/reset-credentials', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ' + token
                    },
                    body: JSON.stringify({
                        username: newUsername,
                        password: newPassword
                    })
                });
                
                const result = await response.json();
                alert(result.message);
            } catch (error) {
                alert('❌ Serwer ýalňyşy: ' + error);
            }
        }

        // Port üýtgetmek
        async function changePanelPort() {
            const newPort = document.getElementById('panelPort').value;
            
            if (!newPort || newPort < 1000 || newPort > 65535) {
                alert('❌ Dogry port giriziň (1000-65535)');
                return;
            }

            try {
                const response = await fetch('/api/admin/change-port', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ' + token
                    },
                    body: JSON.stringify({ port: newPort })
                });
                
                const result = await response.json();
                alert(result.message);
            } catch (error) {
                alert('❌ Serwer ýalňyşy: ' + error);
            }
        }

        // Sahypa ýükelenende
        document.addEventListener('DOMContentLoaded', function() {
            loadStats();
            loadUsers();
        });
    </script>
</body>
</html>
EOF
}

# API backend düzümleri
setup_backend() {
    print_status "API backend düzülýär..."
    
    cd /opt/turkmen-vpn-panel/api
    
    # Python requirements
    cat > requirements.txt <<'EOF'
Flask==2.3.3
pyjwt==2.8.0
cryptography==41.0.4
EOF

    # Esas API aplikasiýasy
    cat > app.py <<EOF
from flask import Flask, request, jsonify, send_file
import sqlite3
import jwt
import datetime
import json
import random
import string
import subprocess
import os
import hashlib
from functools import wraps

app = Flask(__name__)
app.config['SECRET_KEY'] = '${ADMIN_PASSWORD}'
app.config['DATABASE'] = '/opt/turkmen-vpn-panel/data/vpn_panel.db'

def get_db_connection():
    conn = sqlite3.connect(app.config['DATABASE'])
    conn.row_factory = sqlite3.Row
    return conn

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        
        if not token:
            return jsonify({'success': False, 'message': 'Token gerek!'}), 401
        
        try:
            token = token.split(' ')[1]
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
            request.current_user = data['username']
        except:
            return jsonify({'success': False, 'message': 'Ýaroqsyz token!'}), 401
        
        return f(*args, **kwargs)
    return decorated

# Giriş endpointi
@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    
    conn = get_db_connection()
    
    # Admin ulanyjyny barlag
    admin = conn.execute(
        'SELECT * FROM admin_users WHERE username = ? AND password = ?',
        (username, password)
    ).fetchone()
    
    if admin:
        token = jwt.encode({
            'username': username,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24)
        }, app.config['SECRET_KEY'])
        
        return jsonify({
            'success': True,
            'token': token,
            'message': 'Giriş üstünlikli!'
        })
    else:
        return jsonify({
            'success': False,
            'message': 'Ýalňyş ulanyjy ady ýa-da parol!'
        })

# Admin statistikalar
@app.route('/api/admin/stats')
@token_required
def get_stats():
    conn = get_db_connection()
    
    total_users = conn.execute('SELECT COUNT(*) FROM users').fetchone()[0]
    active_users = conn.execute('SELECT COUNT(*) FROM users WHERE is_active = 1').fetchone()[0]
    
    total_data_result = conn.execute('SELECT SUM(data_limit) FROM users WHERE data_limit IS NOT NULL').fetchone()[0]
    total_data = total_data_result or 0
    total_data_gb = total_data / 1073741824
    
    return jsonify({
        'success': True,
        'totalUsers': total_users,
        'activeUsers': active_users,
        'totalData': round(total_data_gb, 1)
    })

# Ulanyjylary getir
@app.route('/api/admin/users')
@token_required
def get_users():
    conn = get_db_connection()
    
    users = conn.execute('''
        SELECT username, subscription_type, data_limit, expiration_date, is_active 
        FROM users 
        ORDER BY created_at DESC
    ''').fetchall()
    
    users_list = []
    for user in users:
        users_list.append({
            'username': user['username'],
            'subscription_type': user['subscription_type'],
            'data_limit': user['data_limit'],
            'expiration_date': user['expiration_date'],
            'is_active': bool(user['is_active'])
        })
    
    return jsonify({
        'success': True,
        'data': users_list
    })

# Täze ulanyjy döret
@app.route('/api/admin/create-user', methods=['POST'])
@token_required
def create_user():
    data = request.json
    username = data.get('username')
    server_type = data.get('server_type')
    subscription_type = data.get('subscription_type')
    data_limit = data.get('data_limit')
    duration = data.get('duration', 30)
    
    # Data limit kesgitle
    if data_limit:
        data_limit_bytes = int(data_limit) * 1073741824
    elif subscription_type == 'free':
        data_limit_bytes = 1073741824  # 1GB
    elif subscription_type == 'premium':
        data_limit_bytes = 10737418240  # 10GB
    else:  # vip
        data_limit_bytes = None  # Çäksiz
    
    # Möhleti kesgitle
    expiration_date = None
    if duration and int(duration) > 0:
        expiration_date = (datetime.datetime.now() + datetime.timedelta(days=int(duration))).strftime('%Y-%m-%d')
    
    conn = get_db_connection()
    
    try:
        # Ulanyjyny döret
        password = ''.join(random.choices(string.ascii_letters + string.digits, k=12))
        
        conn.execute('''
            INSERT INTO users (username, password, subscription_type, data_limit, expiration_date)
            VALUES (?, ?, ?, ?, ?)
        ''', (username, password, subscription_type, data_limit_bytes, expiration_date))
        
        conn.commit()
        
        return jsonify({
            'success': True,
            'message': 'Ulanyjy üstünlikli döredildi!',
            'password': password
        })
        
    except sqlite3.IntegrityError:
        return jsonify({
            'success': False,
            'message': 'Bu ulanyjy ady eýýäm bar!'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Serrler: {str(e)}'
        })

# Konfigurasiýa generator
@app.route('/api/admin/generate-config')
@token_required
def generate_config():
    username = request.args.get('username')
    server_type = request.args.get('type', 'shadowsocks')
    
    conn = get_db_connection()
    
    # Server maglumatlaryny al
    server = conn.execute(
        'SELECT * FROM servers WHERE type = ? AND is_active = 1 LIMIT 1',
        (server_type,)
    ).fetchone()
    
    if not server:
        return jsonify({'success': False, 'message': 'Server tapylmady'})
    
    # Ulanyjyny barlag
    user = conn.execute(
        'SELECT * FROM users WHERE username = ?',
        (username,)
    ).fetchone()
    
    if not user:
        return jsonify({'success': False, 'message': 'Ulanyjy tapylmady'})
    
    # Konfigurasiýa döret
    if server_type == 'shadowsocks':
        config = generate_shadowsocks_config(server, user)
    elif server_type == 'vless':
        config = generate_vless_config(server, user)
    elif server_type == 'vmess':
        config = generate_vmess_config(server, user)
    else:
        return jsonify({'success': False, 'message': 'Nädogry server görnüşi'})
    
    return jsonify({
        'success': True,
        'config': config,
        'type': server_type
    })

def generate_shadowsocks_config(server, user):
    config_data = json.loads(server['config'])
    password = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
    
    config = f"""# Turkmen VPN - Shadowsocks
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}
# Limit: {f"{user['data_limit']/1073741824:.1f} GB" if user['data_limit'] else 'Çäksiz'}

ss://{config_data['method']}:{password}@{server['host']}:{server['port']}#TurkmenVPN-{user['username']}

# Android/Mobile üçin:
# 1. Shadowsocks programmasyny ýükle
# 2. Ýokardaky linki goýuň
# 3. Baglanyşygy işlet

# Windows üçin:
# 1. Shadowsocks Windows-dan ýükle
# 2. Konfigurasiýany giriziň:
#    Server: {server['host']}
#    Port: {server['port']}
#    Parol: {password}
#    Şifr: {config_data['method']}"""
    
    return config

def generate_vless_config(server, user):
    uuid = hashlib.md5(f"{user['username']}{app.config['SECRET_KEY']}".encode()).hexdigest()
    
    config = f"""# Turkmen VPN - VLESS
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}

vless://{uuid}@{server['host']}:{server['port']}?type=ws&security=none&path=%2Fvless#TurkmenVPN-{user['username']}

# NML programmalar üçin:
# 1. Konfigurasiýany import ediň
# 2. Baglanyşygy işlet

# QR Kod üçin ýokardaky linki ulanyp bilersiňiz"""
    
    return config

def generate_vmess_config(server, user):
    uuid = hashlib.md5(f"{user['username']}{app.config['SECRET_KEY']}".encode()).hexdigest()
    
    vmess_config = {
        "v": "2",
        "ps": f"TurkmenVPN-{user['username']}",
        "add": server['host'],
        "port": server['port'],
        "id": uuid,
        "aid": 0,
        "scy": "auto",
        "net": "ws",
        "type": "none",
        "host": "",
        "path": "/vmess",
        "tls": "none"
    }
    
    import base64
    config_json = json.dumps(vmess_config)
    config_base64 = base64.b64encode(config_json.encode()).decode()
    
    config = f"""# Turkmen VPN - VMESS
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}

vmess://{config_base64}

# NML programmalar üçin:
# 1. Konfigurasiýany import ediň
# 2. Baglanyşygy işlet

# Ýa-da ýokardaky vmess linkini goýuň"""
    
    return config

# Panel hereketleri
@app.route('/api/admin/panel-start', methods=['POST'])
@token_required
def panel_start():
    try:
        subprocess.run(['systemctl', 'start', 'vpn-api'], check=True)
        subprocess.run(['systemctl', 'start', 'nginx'], check=True)
        return jsonify({'success': True, 'message': 'Panel üstünlikli başlatyldy!'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Ýalňyş: {str(e)}'})

@app.route('/api/admin/panel-stop', methods=['POST'])
@token_required
def panel_stop():
    try:
        subprocess.run(['systemctl', 'stop', 'vpn-api'], check=True)
        return jsonify({'success': True, 'message': 'Panel üstünlikli duruzuldy!'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Ýalňyş: {str(e)}'})

@app.route('/api/admin/panel-restart', methods=['POST'])
@token_required
def panel_restart():
    try:
        subprocess.run(['systemctl', 'restart', 'vpn-api'], check=True)
        subprocess.run(['systemctl', 'restart', 'nginx'], check=True)
        return jsonify({'success': True, 'message': 'Panel üstünlikli täzeden başlatyldy!'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Ýalňyş: {str(e)}'})

# Username/parol üýtgetmek
@app.route('/api/admin/reset-credentials', methods=['POST'])
@token_required
def reset_credentials():
    data = request.json
    new_username = data.get('username')
    new_password = data.get('password')
    
    conn = get_db_connection()
    
    try:
        if new_username:
            conn.execute(
                'UPDATE admin_users SET username = ? WHERE username = ?',
                (new_username, request.current_user)
            )
        
        if new_password:
            conn.execute(
                'UPDATE admin_users SET password = ? WHERE username = ?',
                (new_password, request.current_user)
            )
        
        conn.commit()
        
        return jsonify({
            'success': True,
            'message': 'Giriş maglumatlary üstünlikli üýtgedildi!'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Ýalňyş: {str(e)}'
        })

# Port üýtgetmek
@app.route('/api/admin/change-port', methods=['POST'])
@token_required
def change_port():
    data = request.json
    new_port = data.get('port')
    
    try:
        # Nginx konfigurasiýasyny üýtget
        with open('/etc/nginx/sites-available/vpn-panel', 'r') as f:
            config = f.read()
        
        config = config.replace('listen ${PANEL_PORT};', f'listen {new_port};')
        
        with open('/etc/nginx/sites-available/vpn-panel', 'w') as f:
            f.write(config)
        
        # Nginx restart
        subprocess.run(['systemctl', 'restart', 'nginx'], check=True)
        
        return jsonify({
            'success': True,
            'message': f'Panel porty {new_port} üstünlikli üýtgedildi!'
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Ýalňyş: {str(e)}'
        })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

    # Python gereklerini ýükle
    pip3 install -r requirements.txt
}

# Nginx düzümleri
setup_nginx() {
    print_status "Nginx düzülýär..."
    
    cat > /etc/nginx/sites-available/vpn-panel <<EOF
server {
    listen ${PANEL_PORT};
    server_name _;
    
    root /opt/turkmen-vpn-panel/web;
    index index.html login.html;
    
    location / {
        try_files \$uri \$uri/ /login.html;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # Giriş barlag üçin
    location /panel.html {
        if (\$http_authorization = "") {
            return 302 /login.html;
        }
    }
}
EOF

    # Ubuntu/Debian
    if [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf /etc/nginx/sites-available/vpn-panel /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi
    
    # CentOS
    if [ -d "/etc/nginx/conf.d" ]; then
        cp /etc/nginx/sites-available/vpn-panel /etc/nginx/conf.d/vpn-panel.conf
    fi
    
    systemctl enable nginx
    systemctl restart nginx
}

# Systemd servisleri
setup_services() {
    print_status "Systemd servisleri düzülýär..."
    
    cat > /etc/systemd/system/vpn-api.service <<EOF
[Unit]
Description=Turkmen VPN API
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/turkmen-vpn-panel/api
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5
User=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vpn-api
    systemctl start vpn-api
}

# Shadowsocks düzümleri
setup_shadowsocks() {
    print_status "Shadowsocks düzülýär..."
    
    # Shadowsocks konfigurasiýasy
    mkdir -p /etc/shadowsocks
    cat > /etc/shadowsocks/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": 8388,
    "password": "turkmenvpn2024",
    "method": "aes-256-gcm",
    "timeout": 300,
    "fast_open": false
}
EOF

    # Systemd servisi
    cat > /etc/systemd/system/shadowsocks.service <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks/config.json
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks
    systemctl start shadowsocks
}

# Terminal panel skripti
setup_terminal_panel() {
    print_status "Terminal panel düzülýär..."
    
    cat > /usr/local/bin/panel <<EOF
#!/bin/bash

# Turkmen VPN Terminal Panel
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
CYAN='\\033[0;36m'
BLUE='\\033[0;34m'
PURPLE='\\033[0;35m'
NC='\\033[0m'

# Maglumatlar
ADMIN_USERNAME="${ADMIN_USERNAME}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
PANEL_PORT="${PANEL_PORT}"
SERVER_IP="${SERVER_IP}"

show_menu() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║           TURKMEN VPN TERMINAL PANEL         ║"
    echo "║                  🇹🇲                         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}1.${NC} Panel Başlat"
    echo -e "${YELLOW}2.${NC} Panel Duruz" 
    echo -e "${YELLOW}3.${NC} Panel Täzeden Başlat"
    echo -e "${YELLOW}4.${NC} Panel Statusy"
    echo -e "${YELLOW}5.${NC} Username/Parol Üýtget"
    echo -e "${YELLOW}6.${NC} Panel Port Üýtget"
    echo -e "${YELLOW}7.${NC} Loglary Görkez"
    echo -e "${YELLOW}8.${NC} Web Panel Aç"
    echo -e "${YELLOW}9.${NC} Giriş Maglumatlary"
    echo -e "${YELLOW}0.${NC} Çykyş"
    echo
    read -p "Saýlamagyňyzy giriziň: " choice
}

panel_start() {
    echo -e "${GREEN}Panel başlatylýar...${NC}"
    systemctl start vpn-api
    systemctl start nginx
    systemctl start shadowsocks
    echo -e "${GREEN}Panel üstünlikli başlatyldy!${NC}"
}

panel_stop() {
    echo -e "${YELLOW}Panel duruzulýar...${NC}"
    systemctl stop vpn-api
    echo -e "${GREEN}Panel duruzuldy!${NC}"
}

panel_restart() {
    echo -e "${YELLOW}Panel täzeden başlatylýar...${NC}"
    systemctl restart vpn-api
    systemctl restart nginx
    systemctl restart shadowsocks
    echo -e "${GREEN}Panel täzeden başlatyldy!${NC}"
}

panel_status() {
    echo -e "${CYAN}Panel Statusy:${NC}"
    echo "────────────────────────"
    systemctl is-active vpn-api && echo -e "API: ${GREEN}Aktiw${NC}" || echo -e "API: ${RED}Passiw${NC}"
    systemctl is-active nginx && echo -e "Nginx: ${GREEN}Aktiw${NC}" || echo -e "Nginx: ${RED}Passiw${NC}"
    systemctl is-active shadowsocks && echo -e "Shadowsocks: ${GREEN}Aktiw${NC}" || echo -e "Shadowsocks: ${RED}Passiw${NC}"
    echo "────────────────────────"
}

reset_credentials() {
    read -p "Täze username: " new_user
    read -s -p "Täze parol: " new_pass
    echo
    
    sqlite3 /opt/turkmen-vpn-panel/data/vpn_panel.db <<EOF
        UPDATE admin_users SET username='$new_user', password='$new_pass' 
        WHERE username='$ADMIN_USERNAME';
EOF
    
    echo -e "${GREEN}Username/parol üstünlikli üýtgedildi!${NC}"
    ADMIN_USERNAME="\$new_user"
    ADMIN_PASSWORD="\$new_pass"
}

change_port() {
    read -p "Täze panel porty: " new_port
    
    sed -i "s/listen ${PANEL_PORT};/listen ${new_port};/" /etc/nginx/sites-available/vpn-panel
    systemctl restart nginx
    
    echo -e "${GREEN}Panel porty üstünlikli üýtgedildi: ${new_port}${NC}"
    PANEL_PORT="\$new_port"
}

show_logs() {
    echo -e "${YELLOW}API loglary (Ctrl+C çykmak):${NC}"
    journalctl -u vpn-api -f
}

open_panel() {
    echo -e "${CYAN}Web panel açylýar...${NC}"
    echo -e "${GREEN}Panel URL: http://${SERVER_IP}:${PANEL_PORT}${NC}"
    echo -e "${YELLOW}Username: ${ADMIN_USERNAME}${NC}"
    echo -e "${YELLOW}Parol: ${ADMIN_PASSWORD}${NC}"
}

show_credentials() {
    echo -e "${CYAN}Giriş Maglumatlary:${NC}"
    echo "────────────────────────"
    echo -e "${YELLOW}Panel URL:${NC} http://${SERVER_IP}:${PANEL_PORT}"
    echo -e "${YELLOW}Username:${NC} ${ADMIN_USERNAME}"
    echo -e "${YELLOW}Parol:${NC} ${ADMIN_PASSWORD}"
    echo "────────────────────────"
}

# Esas loop
while true; do
    show_menu
    case \$choice in
        1) panel_start ;;
        2) panel_stop ;;
        3) panel_restart ;;
        4) panel_status ;;
        5) reset_credentials ;;
        6) change_port ;;
        7) show_logs ;;
        8) open_panel ;;
        9) show_credentials ;;
        0) echo -e "${CYAN}Hoşçakal!${NC}"; exit 0 ;;
        *) echo -e "${RED}Nädogry saýlama!${NC}" ;;
    esac
    echo
    read -p "Dowam etmek üçin ENTER basyň..."
done
EOF

    chmod +x /usr/local/bin/panel
}

# Firewall düzümleri
setup_firewall() {
    print_status "Firewall düzülýär..."
    
    # UFW işledýän bolsa
    if command -v ufw >/dev/null 2>&1; then
        ufw allow ${PANEL_PORT}/tcp
        ufw allow 8388/tcp
        ufw allow 443/tcp
        ufw allow 8443/tcp
        ufw --force enable
    fi
    
    # iptables
    iptables -I INPUT -p tcp --dport ${PANEL_PORT} -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 8388 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null || true
}

# Gurnama prosesi
main() {
    clear
    get_credentials
    
    print_status "Gurnama başlaýar..."
    
    system_setup
    install_dependencies
    setup_database
    setup_web_panel
    setup_backend
    setup_nginx
    setup_services
    setup_shadowsocks
    setup_terminal_panel
    setup_firewall
    
    # Gurnama tamamlandy
    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║           GURNALAMA TAMAMLANDY!             ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    echo -e "${CYAN}GIRIŞ MAGLUMATLARY:${NC}"
    echo -e "  ${YELLOW}Web Panel:${NC} http://${SERVER_IP}:${PANEL_PORT}"
    echo -e "  ${YELLOW}Username:${NC} ${ADMIN_USERNAME}"
    echo -e "  ${YELLOW}Parol:${NC} ${ADMIN_PASSWORD}"
    echo
    echo -e "${CYAN}TERMINAL PANEL:${NC}"
    echo -e "  ${YELLOW}panel${NC} - Terminal paneli işletmek üçin"
    echo
    echo -e "${CYAN}SERVER PORTLARY:${NC}"
    echo -e "  ${YELLOW}Shadowsocks:${NC} 8388"
    echo -e "  ${YELLOW}VLESS:${NC} 443" 
    echo -e "  ${YELLOW}VMESS:${NC} 8443"
    echo
    print_warning "Firewall-dan portlary açmagy ýadyňyzdan çykarmaň!"
    echo
    echo -e "${GREEN}Terminal paneli işletmek üçin: ${CYAN}panel${NC}"
    echo
    echo -e "${YELLOW}Web paneli açmak üçin:${NC}"
    echo -e "  http://${SERVER_IP}:${PANEL_PORT}"
}

# Scripti işlet
main "$@"
