# Hesabix - Comprehensive Accounting System

Hesabix is a complete and modern accounting system designed for small and medium businesses. It includes a powerful API backend (FastAPI + PostgreSQL) and a beautiful web interface (Flutter Web).

## About Hesabix

Hesabix is an open-source accounting software that provides comprehensive financial management capabilities. The system is built with modern technologies to ensure high performance, scalability, and ease of use.

### Key Features

- **Complete Accounting System**: Manage all aspects of your business finances
- **Modern Architecture**: Built with FastAPI and PostgreSQL for high performance
- **Beautiful Web Interface**: Responsive Flutter Web application
- **Multi-user Support**: Support for multiple users and businesses
- **Real-time Updates**: Live data synchronization
- **Secure**: JWT authentication and encrypted data transmission
- **Persian Calendar Support**: Full support for Jalali (Persian) calendar
- **Multi-language**: Support for Persian and English languages

### Technology Stack

**Backend:**
- FastAPI - Modern, fast web framework
- PostgreSQL - Robust relational database
- SQLAlchemy - Powerful ORM
- Alembic - Database migration management
- Python 3.10+ (Python 3.12 on Ubuntu 24.04, Python 3.10/3.11 on Ubuntu 22.04)

**Frontend:**
- Flutter Web - Cross-platform web framework
- Material Design - Modern UI components
- Responsive Design - Works on all screen sizes

**Infrastructure:**
- Nginx - Reverse proxy and web server
- SSL/TLS - Secure connections with Let's Encrypt
- Systemd - Service management

## System Requirements

### Operating System

- **Ubuntu 22.04 LTS** or higher
- **Debian 12** or higher

The installation script automatically detects and verifies the operating system compatibility.

### Hardware Requirements

**Minimum Requirements:**
- **CPU**: 2 cores
- **RAM**: 8 GB
- **Disk Space**: 10 GB free space
- **Network**: Internet connection for installation and updates

**Recommended Requirements:**
- **CPU**: 4+ cores (for better performance)
- **RAM**: 12 GB or more
- **Disk Space**: 20 GB free space
- **Network**: Stable internet connection

**Production Requirements (High Load):**
- **CPU**: 8+ cores
- **RAM**: 64 GB or more
- **Disk Space**: 5000 GB+ free space
- **Network**: High-speed internet connection

### Software Requirements

The installation script automatically installs all required software:
- Git
- Python 3 (version depends on Ubuntu/Debian release - Python 3.10+ required)
- PostgreSQL
- Nginx
- Flutter SDK (for building frontend)
- Certbot (for SSL certificates)

## Installation

### Quick Installation

The easiest way to install Hesabix is using the automated installation script:

```bash
cd /tmp && curl -sSL --http1.1 https://shell.hesabix.ir/deploy.sh | tr -d '\r' > installer.sh && chmod +x installer.sh && sudo bash installer.sh
```

> **HTTP/2 issue on some servers**: On some servers (e.g. older curl versions or specific network/firewall configuration), using HTTP/2 may cause errors. The command above uses the `--http1.1` flag to always use HTTP/1.1. If you get a curl error, see the [Troubleshooting HTTP/2](#troubleshooting-http2-when-downloading-install-script) section.

**Alternative method using wget** (if curl still fails):
```bash
cd /tmp && wget -qO- https://shell.hesabix.ir/deploy.sh | tr -d '\r' > installer.sh && chmod +x installer.sh && sudo bash installer.sh
```

This command will:
1. Download the installation script
2. Make it executable
3. Run the installation with root privileges

### Installation Process

The installation script will guide you through the following steps:

1. **License Agreement**: You must accept the GNU GPL v3.0 license
2. **System Check**: Verifies OS compatibility and disk space
3. **Configuration**: Prompts for:
   - API domain (e.g., `api.example.com`)
   - Frontend domain (e.g., `app.example.com`)
   - Git branch (default: `main`)
   - Database password (auto-generated if not provided)
   - Optional: pgAdmin4 installation
4. **Configuration Summary**: Shows all settings before installation
5. **Confirmation**: Final confirmation before starting installation
6. **Installation**: Automated installation of all components

### What Gets Installed

The installation script automatically:

- **Installs Prerequisites**: Git, Python, PostgreSQL, Nginx, and other required packages
- **Clones Repository**: Downloads the latest code from the repository
- **Sets Up Database**: Creates PostgreSQL database and user
- **Deploys Backend**: Sets up Python virtual environment and installs dependencies
- **Builds Frontend**: Compiles Flutter Web application
- **Configures Nginx**: Sets up reverse proxy for API and serves frontend
- **Configures SSL**: Optional Let's Encrypt SSL certificate setup
- **Creates Services**: Systemd services for API and workers
- **Optimizes Performance**: Auto-calculates optimal worker count and database pool settings

### Performance Optimization

The installation script automatically optimizes settings based on your server resources:

- **Worker Count**: Automatically calculated as `(2 × CPU cores) + 1`
- **Database Pool**: Optimized connection pool based on worker count
- **Persistent Connections**: Configured for reduced response time
- **Resource Limits**: Appropriate limits set for services

### Post-Installation

After successful installation, you will see:

- **Access URLs**: API and UI URLs
- **Service Management Commands**: How to manage services
- **Log File Location**: Where to find installation logs
- **Database Password Location**: Where the password is stored

### Service Management

```bash
# Check API status
systemctl status hesabix-api

# Restart API
systemctl restart hesabix-api

# View API logs
journalctl -u hesabix-api -f

# Check RQ Worker status
systemctl status hesabix-rq-worker

# Check Notification Moderation Worker
systemctl status hesabix-notification-moderation

# Check Nginx status
systemctl status nginx
```

### Upgrading

You can upgrade in either of the following ways.

#### Re-run the installer (full deploy script)

To upgrade by downloading and running the deployment script again:

```bash
cd /tmp && curl -sSL --http1.1 https://shell.hesabix.ir/deploy.sh | tr -d '\r' > installer.sh && chmod +x installer.sh && sudo bash installer.sh
```

The script is idempotent and safe to re-run. It will update the code and restart services.

> **HTTP/2 issue**: If you encounter an HTTP/2-related error, use the same command with the `--http1.1` flag or refer to the [Troubleshooting HTTP/2](#troubleshooting-http2-when-downloading-install-script) section.

#### Update on the server with `hesabix -update`

After a standard installation, a small CLI is available at `/usr/local/bin/hesabix`. For an in-place upgrade from the configured Git repository (without re-downloading the installer), run as **root**:

```bash
sudo hesabix -update
```

This runs `update.sh` in the deployed app directory. It typically: pulls the latest code from the saved remote and branch, applies database migrations, restarts Hesabix systemd units (API, RQ worker, notification moderation—and pgAdmin4 if installed), rebuilds the Flutter web frontend, and reloads Nginx. Progress and errors are also written to `/opt/hesabix/update.log`.

Optional overrides (useful for forks or testing a branch):

```bash
sudo hesabix -update -source https://source.hesabix.ir/hesabix/arc.git
sudo hesabix -update -branch main
sudo hesabix -update -source https://example.com/your/repo.git -branch develop
```

Other `hesabix` commands:

- `sudo hesabix -services {start|stop|restart|status}` — control Hesabix-related systemd units without updating code.
- `sudo hesabix -cli reload` — refresh `/usr/local/bin/hesabix` from the repo if the CLI script was updated.

`hesabix -update` requires a completed prior deploy (`/opt/hesabix/.deploy_env`, app clone under `/opt/hesabix/app`, and `/opt/hesabix/app/update.sh`). If those are missing, use the installer method above.

## Configuration

### Environment Variables

You can customize the installation by setting environment variables:

```bash
API_DOMAIN=api.example.com \
UI_DOMAIN=app.example.com \
BRANCH=main \
DB_PASSWORD=your_secure_password \
UVICORN_WORKERS=17 \
sudo -E bash installer.sh
```

### Database Password

The database password is automatically generated and stored in:
```
/opt/hesabix/.db_password
```

You can also provide your own password via the `DB_PASSWORD` environment variable.

### Log Files

Installation logs are saved to:
```
/opt/hesabix/deploy.log
```

Application logs are available via systemd journal:
```bash
journalctl -u hesabix-api -f
```

## Troubleshooting

### Troubleshooting HTTP/2 When Downloading Install Script

Some servers have issues with HTTP/2 due to curl version, network configuration, or firewall. In such cases, you may see errors like `curl: (92) HTTP/2 stream 1 was not closed cleanly` or `HTTP/2 framing layer problem` when downloading the install script.

**Solutions (in order of preference):**

1. **Use HTTP/1.1 with curl**  
   Always include the `--http1.1` flag in the command:
   ```bash
   curl -sSL --http1.1 -o installer.sh https://shell.hesabix.ir/deploy.sh
   ```
   Then run:
   ```bash
   cd /tmp && tr -d '\r' < installer.sh > installer_clean.sh && chmod +x installer_clean.sh && sudo bash installer_clean.sh
   ```

2. **Use wget instead of curl**  
   wget uses HTTP/1.1 by default:
   ```bash
   cd /tmp && wget -qO- https://shell.hesabix.ir/deploy.sh | tr -d '\r' > installer.sh && chmod +x installer.sh && sudo bash installer.sh
   ```
   If you get an SSL certificate error, you can add `--no-check-certificate` to the wget command (only in test environments or when you are sure it is safe).

3. **Update curl**  
   If your curl version is old, update it and try again with `--http1.1`:
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install --only-upgrade curl
   ```

4. **Manual download and upload to server**  
   If none of the above works, download the file on another system using a browser or curl, then transfer it to the server via SCP/SFTP and run:
   ```bash
   chmod +x installer.sh && sudo bash installer.sh
   ```

### Common Issues

1. **Installation Fails**
   - Check disk space (minimum 2GB required)
   - Verify internet connection
   - Check installation logs: `/opt/hesabix/deploy.log`

2. **Service Won't Start**
   - Check service status: `systemctl status hesabix-api`
   - View logs: `journalctl -u hesabix-api`
   - Verify database connection

3. **SSL Certificate Issues**
   - Ensure domain DNS is properly configured
   - Check firewall settings (ports 80 and 443)
   - Verify domain accessibility

4. **Database Connection Errors**
   - Check PostgreSQL service: `systemctl status postgresql`
   - Verify database credentials
   - Check connection from application logs

### Getting Help

- **Documentation**: Check the `/opt/hesabix/app/docs` directory
- **Logs**: Review installation and application logs
- **Support**: Visit https://hesabix.ir/support

## Security

### Best Practices

- **SSL/TLS**: Always enable SSL for production deployments
- **Firewall**: Configure firewall to restrict access
- **Updates**: Regularly update the system and application
- **Backups**: Set up regular database backups
- **Passwords**: Use strong, unique passwords

### File Permissions

The installation script automatically sets appropriate file permissions:
- `.env` file: `600` (read/write for owner only)
- Application files: Owned by `www-data` user
- Database password: Stored securely with restricted access

## License

This software is distributed under the **GNU General Public License v3.0 (GPL-3.0)**.

Full license text: http://www.gnu.org/licenses/gpl-3.0.txt

## Support

- **Website**: https://hesabix.ir
- **Support**: https://hesabix.ir/support
- **Repository**: https://source.hesabix.ir/hesabix/arc.git

## Development

For development setup and contribution guidelines, please refer to the development documentation in the repository.

---

**Hesabix** - Modern Accounting System for Your Business
