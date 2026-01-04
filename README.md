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
- **RAM**: 2 GB
- **Disk Space**: 10 GB free space
- **Network**: Internet connection for installation and updates

**Recommended Requirements:**
- **CPU**: 4+ cores (for better performance)
- **RAM**: 4 GB or more
- **Disk Space**: 20 GB free space
- **Network**: Stable internet connection

**Production Requirements (High Load):**
- **CPU**: 8+ cores
- **RAM**: 8 GB or more
- **Disk Space**: 50 GB+ free space
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

**Note**: If you encounter HTTP/2 errors, the `--http1.1` flag forces curl to use HTTP/1.1 protocol.

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

To upgrade to the latest version:

```bash
cd /tmp && curl -sSL --http1.1 https://shell.hesabix.ir/deploy.sh | tr -d '\r' > installer.sh && chmod +x installer.sh && sudo bash installer.sh
```

The script is idempotent and safe to re-run. It will update the code and restart services.

**Note**: If you encounter HTTP/2 errors, the `--http1.1` flag forces curl to use HTTP/1.1 protocol.

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
