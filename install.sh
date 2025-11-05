#!/bin/bash

# Real Işleýän Turkmen VPN Panel
# Marzban stili - Tamamly sistem

# Renk kodlary
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
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
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}           TURKMEN VPN PANEL GURNALAMA${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
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
    
    read -p "Web panel porty (default: 3000): " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-3000}
}

# Sistem tälimleri
system_setup() {
    print_status "Sistem tälenir..."
    apt update && apt upgrade -y
}

# Gerekli programmalar
install_dependencies() {
    print_status "Programmalar ýüklenir..."
    apt install -y wget curl git python3 python3-pip nodejs npm nginx \
        mysql-server mysql-client openvpn shadowsocks-libev
}

# MySQL düzümleri
setup_mysql() {
    print_status "MySQL düzülýär..."
    
    systemctl start mysql
    systemctl enable mysql
    
    # MySQL güvenlik düzümleri
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ADMIN_PASSWORD}';"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "FLUSH PRIVILEGES;"
    
    # VPN database döret
    mysql -uroot -p${ADMIN_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS vpn_panel;"
    mysql -uroot -p${ADMIN_PASSWORD} -e "CREATE USER IF NOT EXISTS 'vpn_admin'@'localhost' IDENTIFIED BY '${ADMIN_PASSWORD}';"
    mysql -uroot -p${ADMIN_PASSWORD} -e "GRANT ALL PRIVILEGES ON vpn_panel.* TO 'vpn_admin'@'localhost';"
    mysql -uroot -p${ADMIN_PASSWORD} -e "FLUSH PRIVILEGES;"
    
    # Tablisalary döret
    mysql -uroot -p${ADMIN_PASSWORD} vpn_panel <<EOF
    CREATE TABLE IF NOT EXISTS admin_users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        email VARCHAR(100),
        subscription_type ENUM('free', 'premium', 'vip') DEFAULT 'free',
        data_limit BIGINT DEFAULT 1073741824,
        used_data BIGINT DEFAULT 0,
        expiration_date DATE,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS servers (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        type ENUM('shadowsocks', 'vless', 'vmess') NOT NULL,
        host VARCHAR(255) NOT NULL,
        port INT NOT NULL,
        config JSON,
        is_active BOOLEAN DEFAULT TRUE
    );
    
    INSERT IGNORE INTO admin_users (username, password) 
    VALUES ('${ADMIN_USERNAME}', SHA2('${ADMIN_PASSWORD}', 256));
    
    INSERT IGNORE INTO servers (name, type, host, port, config) VALUES
    ('Shadowsocks Server 1', 'shadowsocks', '0.0.0.0', 8388, '{"method": "aes-256-gcm", "password": "default123"}'),
    ('VLESS Server 1', 'vless', '0.0.0.0', 443, '{"flow": "", "encryption": "none"}'),
    ('VMESS Server 1', 'vmess', '0.0.0.0', 8443, '{"alterId": 0}');
EOF
}

# Web panel düzümleri
setup_web_panel() {
    print_status "Web panel düzülýär..."
    
    # Projekt papkasyny döret
    mkdir -p /opt/turkmen-vpn-panel/{web,api,configs}
    cd /opt/turkmen-vpn-panel
    
    # Frontend sahypalary
    cat > web/login.html <<'EOF'
<!DOCTYPE html>
<html lang="tk">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Turkmen VPN - Giriş</title>
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
            background: rgba(30, 41, 59, 0.9);
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
            <h1>🇹🇲 Turkmen VPN</h1>
            <p>Admin Paneline Hoş Geldiňiz</p>
        </div>
        
        <form id="loginForm">
            <div class="form-group">
                <label for="username">Ulanyjy ady:</label>
                <input type="text" id="username" class="form-input" required>
            </div>
            
            <div class="form-group">
                <label for="password">Parol:</label>
                <input type="password" id="password" class="form-input" required>
            </div>
            
            <button type="submit" class="btn">Giriş</button>
            
            <div id="errorMessage" class="error-message">
                Ýalňyş ulanyjy ady ýa-da parol!
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
        });
    </script>
</body>
</html>
EOF

    # Admin panel sahypasy
    cat > web/panel.html <<'EOF'
<!DOCTYPE html>
<html lang="tk">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Turkmen VPN - Admin Panel</title>
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
        }
        
        .btn-primary { background: var(--primary); color: white; }
        .btn-danger { background: var(--danger); color: white; }
        .btn-success { background: var(--success); color: white; }
        
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
            justify-content: between;
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
            font-family: monospace;
            white-space: pre-wrap;
            word-break: break-all;
            margin: 1rem 0;
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
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="logo">
            <h1>🇹🇲 Turkmen VPN</h1>
        </div>
        
        <ul class="nav-links">
            <li><a href="#" class="active" onclick="showTab('dashboard')"><i>📊</i> Dashboard</a></li>
            <li><a href="#" onclick="showTab('users')"><i>👥</i> Ulanyjylar</a></li>
            <li><a href="#" onclick="showTab('create')"><i>➕</i> Täze Potpiska</a></li>
            <li><a href="#" onclick="showTab('servers')"><i>🖥️</i> Serverler</a></li>
            <li><a href="#" onclick="showTab('configs')"><i>⚙️</i> Konfigurasiýa</a></li>
            <li><a href="#" onclick="showTab('settings')"><i>🔧</i> Sazlamalar</a></li>
        </ul>
    </div>

    <!-- Main Content -->
    <div class="main-content">
        <div class="header">
            <h2 id="pageTitle">Dashboard</h2>
            <div class="user-menu">
                <button class="theme-toggle" onclick="toggleTheme()">🌓</button>
                <span id="currentUser">Admin</span>
                <button class="btn btn-danger" onclick="logout()">Çykyş</button>
            </div>
        </div>

        <!-- Dashboard Tab -->
        <div id="dashboard" class="tab-content active">
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-number" id="totalUsers">0</div>
                    <div class="stat-label">Jemi Ulanyjylar</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" id="activeUsers">0</div>
                    <div class="stat-label">Aktiw Ulanyjylar</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">4</div>
                    <div class="stat-label">Serverler</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number" id="totalData">0 GB</div>
                    <div class="stat-label">Jemi Traffic</div>
                </div>
            </div>
        </div>

        <!-- Users Tab -->
        <div id="users" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3>Ulanyjylaryň Sanawy</h3>
                    <button class="btn btn-primary" onclick="showTab('create')">Täze Ulanyjy</button>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>Potpiska</th>
                            <th>Limit (GB)</th>
                            <th>Möhleti</th>
                            <th>Status</th>
                            <th>Hereketler</th>
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
                    <h3>Täze Potpiska Döret</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <form id="createSubscriptionForm">
                        <div class="form-grid">
                            <div class="form-group">
                                <label class="form-label">Ulanyjy ady:</label>
                                <input type="text" class="form-input" id="newUsername" required>
                            </div>
                            <div class="form-group">
                                <label class="form-label">Server görnüşi:</label>
                                <select class="form-select" id="serverType" required>
                                    <option value="shadowsocks">Shadowsocks</option>
                                    <option value="vless">VLESS</option>
                                    <option value="vmess">VMESS</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label class="form-label">Potpiska görnüşi:</label>
                                <select class="form-select" id="subType" required>
                                    <option value="free">Mugt (1GB)</option>
                                    <option value="premium">Premium (10GB)</option>
                                    <option value="vip">VIP (Çäksiz)</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label class="form-label">Data limiti (GB):</label>
                                <input type="number" class="form-input" id="dataLimit" placeholder="Çäksiz üçin boş goýuň">
                            </div>
                            <div class="form-group">
                                <label class="form-label">Möhlet (gün):</label>
                                <input type="number" class="form-input" id="duration" value="30" min="1">
                            </div>
                        </div>
                        <button type="submit" class="btn btn-success">Potpiska Döret</button>
                    </form>
                </div>
            </div>
        </div>

        <!-- Configs Tab -->
        <div id="configs" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3>Konfigurasiýa Generator</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <div class="form-grid">
                        <div class="form-group">
                            <label class="form-label">Ulanyjy ady:</label>
                            <input type="text" class="form-input" id="configUsername">
                        </div>
                        <div class="form-group">
                            <label class="form-label">Server görnüşi:</label>
                            <select class="form-select" id="configServerType">
                                <option value="shadowsocks">Shadowsocks</option>
                                <option value="vless">VLESS</option>
                                <option value="vmess">VMESS</option>
                            </select>
                        </div>
                    </div>
                    <button class="btn btn-primary" onclick="generateConfig()">Konfigurasiýa Al</button>
                    
                    <div id="configOutput"></div>
                </div>
            </div>
        </div>

        <!-- Settings Tab -->
        <div id="settings" class="tab-content">
            <div class="table-container">
                <div class="table-header">
                    <h3>Panel Sazlamalary</h3>
                </div>
                <div style="padding: 1.5rem;">
                    <div class="form-grid">
                        <div class="form-group">
                            <label class="form-label">Täze Username:</label>
                            <input type="text" class="form-input" id="resetUsername">
                        </div>
                        <div class="form-group">
                            <label class="form-label">Täze Parol:</label>
                            <input type="password" class="form-input" id="resetPassword">
                        </div>
                    </div>
                    <button class="btn btn-warning" onclick="resetCredentials()">Username/Parol Üýtget</button>
                    
                    <hr style="margin: 2rem 0; border-color: #334155;">
                    
                    <div class="form-group">
                        <label class="form-label">Panel Porty:</label>
                        <input type="number" class="form-input" id="panelPort" value="3000">
                    </div>
                    <button class="btn btn-warning" onclick="changePanelPort()">Port Üýtget</button>
                    
                    <hr style="margin: 2rem 0; border-color: #334155;">
                    
                    <div class="form-group">
                        <h4>Panel Dolandyryşy</h4>
                        <div style="display: flex; gap: 1rem; margin-top: 1rem;">
                            <button class="btn btn-success" onclick="panelAction('start')">Panel Başlat</button>
                            <button class="btn btn-warning" onclick="panelAction('stop')">Panel Duruz</button>
                            <button class="btn btn-primary" onclick="panelAction('restart')">Panel Täzeden</button>
                        </div>
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
                'dashboard': 'Dashboard',
                'users': 'Ulanyjylar',
                'create': 'Täze Potpiska', 
                'servers': 'Serverler',
                'configs': 'Konfigurasiýa',
                'settings': 'Sazlamalar'
            };
            document.getElementById('pageTitle').textContent = titles[tabName];
            
            // Maglumatlary ýükle
            if (tabName === 'dashboard') loadStats();
            if (tabName === 'users') loadUsers();
        }

        // Tema üýtgetmek
        function toggleTheme() {
            document.body.classList.toggle('light-theme');
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
                
                document.getElementById('totalUsers').textContent = data.totalUsers;
                document.getElementById('activeUsers').textContent = data.activeUsers;
                document.getElementById('totalData').textContent = data.totalData + ' GB';
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
                tbody.innerHTML = users.map(user => `
                    <tr>
                        <td>${user.username}</td>
                        <td><span class="badge">${user.subscription_type}</span></td>
                        <td>${user.data_limit ? (user.data_limit / 1073741824).toFixed(1) + ' GB' : 'Çäksiz'}</td>
                        <td>${user.expiration_date || 'Çäksiz'}</td>
                        <td><span class="status ${user.is_active ? 'active' : 'inactive'}">${user.is_active ? 'Aktiw' : 'Passiw'}</span></td>
                        <td>
                            <button class="btn btn-primary btn-sm" onclick="editUser('${user.username}')">Üýtget</button>
                            <button class="btn btn-danger btn-sm" onclick="deleteUser('${user.username}')">Poz</button>
                        </td>
                    </tr>
                `).join('');
            } catch (error) {
                console.error('Ulanyjylar ýüklenmedi:', error);
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
                    alert('Potpiska üstünlikli döredildi!');
                    this.reset();
                } else {
                    alert('Ýalňyş: ' + result.message);
                }
            } catch (error) {
                alert('Serrler ýüze çykdy: ' + error);
            }
        });

        // Konfigurasiýa generator
        async function generateConfig() {
            const username = document.getElementById('configUsername').value;
            const serverType = document.getElementById('configServerType').value;
            
            if (!username) {
                alert('Ulanyjy adyny giriziň!');
                return;
            }

            try {
                const response = await fetch(`/api/admin/generate-config?username=${username}&type=${serverType}`, {
                    headers: { 'Authorization': 'Bearer ' + token }
                });
                
                const result = await response.json();
                
                if (result.success) {
                    document.getElementById('configOutput').innerHTML = `
                        <div class="config-box">${result.config}</div>
                        <button class="btn btn-success" onclick="downloadConfig('${username}', '${serverType}')">Konfigurasiýany Ýükle</button>
                    `;
                } else {
                    alert('Ýalňyş: ' + result.message);
                }
            } catch (error) {
                alert('Serrler ýüze çykdy: ' + error);
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
                alert('Serrler ýüze çykdy: ' + error);
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
mysql-connector-python==8.1.0
PyJWT==2.8.0
cryptography==41.0.4
python-dotenv==1.0.0
EOF

    # Esas API aplikasiýasy
    cat > app.py <<EOF
from flask import Flask, request, jsonify, send_file
import mysql.connector
import hashlib
import jwt
import datetime
import json
import random
import string
import subprocess
import os
from functools import wraps

app = Flask(__name__)
app.config['SECRET_KEY'] = '${ADMIN_PASSWORD}'

def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="vpn_admin",
        password="${ADMIN_PASSWORD}",
        database="vpn_panel"
    )

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
    cursor = conn.cursor()
    
    hashed_password = hashlib.sha256(password.encode()).hexdigest()
    
    cursor.execute("SELECT * FROM admin_users WHERE username = %s AND password = %s", 
                   (username, hashed_password))
    user = cursor.fetchone()
    
    if user:
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
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM users")
    total_users = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM users WHERE is_active = TRUE")
    active_users = cursor.fetchone()[0]
    
    cursor.execute("SELECT SUM(data_limit) FROM users WHERE data_limit IS NOT NULL")
    total_data = cursor.fetchone()[0] or 0
    total_data_gb = total_data / 1073741824
    
    return jsonify({
        'totalUsers': total_users,
        'activeUsers': active_users,
        'totalData': round(total_data_gb, 1)
    })

# Ulanyjylary getir
@app.route('/api/admin/users')
@token_required
def get_users():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT username, subscription_type, data_limit, expiration_date, is_active 
        FROM users 
        ORDER BY created_at DESC
    """)
    users = cursor.fetchall()
    
    return jsonify(users)

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
    cursor = conn.cursor()
    
    try:
        # Ulanyjyny döret
        password = ''.join(random.choices(string.ascii_letters + string.digits, k=12))
        hashed_password = hashlib.sha256(password.encode()).hexdigest()
        
        cursor.execute("""
            INSERT INTO users (username, password, subscription_type, data_limit, expiration_date)
            VALUES (%s, %s, %s, %s, %s)
        """, (username, hashed_password, subscription_type, data_limit_bytes, expiration_date))
        
        conn.commit()
        
        return jsonify({
            'success': True,
            'message': 'Ulanyjy üstünlikli döredildi!',
            'password': password
        })
        
    except mysql.connector.IntegrityError:
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
    cursor = conn.cursor(dictionary=True)
    
    # Server maglumatlaryny al
    cursor.execute("SELECT * FROM servers WHERE type = %s AND is_active = TRUE LIMIT 1", (server_type,))
    server = cursor.fetchone()
    
    if not server:
        return jsonify({'success': False, 'message': 'Server tapylmady'})
    
    # Ulanyjyny barlag
    cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
    user = cursor.fetchone()
    
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
    config_json = server['config']
    if isinstance(config_json, str):
        config_data = json.loads(config_json)
    else:
        config_data = config_json
    
    password = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
    
    config = f"""ss://{config_data['method']}:{password}@{server['host']}:{server['port']}
# Turkmen VPN - Shadowsocks
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}
# Limit: {f"{user['data_limit']/1073741824:.1f} GB" if user['data_limit'] else 'Çäksiz'}

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
    uuid = str(jwt.encode({'user': user['username']}, app.config['SECRET_KEY'], algorithm='HS256'))[:36]
    
    config = f"""vless://{uuid}@{server['host']}:{server['port']}?type=ws&security=none&path=%2Fvless#TurkmenVPN-{user['username']}

# Turkmen VPN - VLESS
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}

# NML programmalar üçin:
# 1. Konfigurasiýany import ediň
# 2. Baglanyşygy işlet

# QR Kod üçin ýokardaky linki ulanyp bilersiňiz"""
    
    return config

def generate_vmess_config(server, user):
    uuid = str(jwt.encode({'user': user['username']}, app.config['SECRET_KEY'], algorithm='HS256'))[:36]
    
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
    
    config = f"""vmess://{config_base64}

# Turkmen VPN - VMESS
# Ulanyjy: {user['username']}
# Möhlet: {user['expiration_date'] or 'Çäksiz'}

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
    
    location /panel.html {
        # Giriş barlag
        auth_request /api/auth/verify;
        error_page 401 = /login.html;
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
After=network.target mysql.service

[Service]
Type=simple
WorkingDirectory=/opt/turkmen-vpn-panel/api
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vpn-api
    systemctl start vpn-api
}

# Shadowsoks düzümleri
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
    
    cat > /usr/local/bin/panel <<'EOF'
#!/bin/bash

# Turkmen VPN Terminal Panel
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${CYAN}"
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
    
    mysql -uroot -p${ADMIN_PASSWORD} vpn_panel -e "
        UPDATE admin_users SET username='$new_user', password=SHA2('$new_pass', 256) 
        WHERE username='$ADMIN_USERNAME'"
    
    echo -e "${GREEN}Username/parol üstünlikli üýtgedildi!${NC}"
}

change_port() {
    read -p "Täze panel porty: " new_port
    
    sed -i "s/listen ${PANEL_PORT};/listen ${new_port};/" /etc/nginx/sites-available/vpn-panel
    systemctl restart nginx
    
    echo -e "${GREEN}Panel porty üstünlikli üýtgedildi: ${new_port}${NC}"
}

show_logs() {
    journalctl -u vpn-api -f
}

open_panel() {
    echo -e "${CYAN}Web panel açylýar...${NC}"
    echo -e "${GREEN}Panel URL: http://$(curl -s ifconfig.me):${PANEL_PORT}${NC}"
}

# Esas loop
while true; do
    show_menu
    case $choice in
        1) panel_start ;;
        2) panel_stop ;;
        3) panel_restart ;;
        4) panel_status ;;
        5) reset_credentials ;;
        6) change_port ;;
        7) show_logs ;;
        8) open_panel ;;
        0) echo -e "${CYAN}Hoşçakal!${NC}"; exit 0 ;;
        *) echo -e "${RED}Nädogry saýlama!${NC}" ;;
    esac
    echo
    read -p "Dowam etmek üçin ENTER basyň..."
done
EOF

    chmod +x /usr/local/bin/panel
}

# Gurnama prosesi
main() {
    clear
    get_credentials
    
    print_status "Gurnama başlaýar..."
    
    system_setup
    install_dependencies
    setup_mysql
    setup_web_panel
    setup_backend
    setup_nginx
    setup_services
    setup_shadowsocks
    setup_terminal_panel
    
    # Gurnama tamamlandy
    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║           GURNALAMA TAMAMLANDY!             ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    echo -e "${CYAN}GIRIŞ MAGLUMATLARY:${NC}"
    echo -e "  ${YELLOW}Web Panel:${NC} http://$(curl -s ifconfig.me):${PANEL_PORT}"
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
}

# Scripti işlet
main "$@"
