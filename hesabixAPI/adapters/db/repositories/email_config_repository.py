from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.email_config import EmailConfig
from adapters.db.repositories.base_repo import BaseRepository


class EmailConfigRepository(BaseRepository[EmailConfig]):
    def __init__(self, db: Session):
        super().__init__(db, EmailConfig)

    def get_active_config(self) -> Optional[EmailConfig]:
        """Get the currently active email configuration"""
        return self.db.query(self.model_class).filter(self.model_class.is_active == True).first()
    
    def get_default_config(self) -> Optional[EmailConfig]:
        """Get the default email configuration"""
        return self.db.query(self.model_class).filter(self.model_class.is_default == True).first()
    
    def set_default_config(self, config_id: int) -> bool:
        """Set a configuration as default (removes default from others)"""
        try:
            # First check if the config exists
            config = self.get_by_id(config_id)
            if not config:
                return False
            
            # Remove default from all configs
            self.db.query(self.model_class).update({self.model_class.is_default: False})
            
            # Set the specified config as default
            config.is_default = True
            self.db.commit()
            return True
        except Exception as e:
            self.db.rollback()
            print(f"Error in set_default_config: {e}")  # Debug log
            return False

    def get_by_name(self, name: str) -> Optional[EmailConfig]:
        """Get email configuration by name"""
        return self.db.query(self.model_class).filter(self.model_class.name == name).first()

    def get_all_configs(self) -> List[EmailConfig]:
        """Get all email configurations"""
        return self.db.query(self.model_class).order_by(self.model_class.created_at.desc()).all()

    def set_active_config(self, config_id: int) -> bool:
        """Set a specific configuration as active and deactivate others"""
        try:
            # Deactivate all configs
            self.db.query(self.model_class).update({self.model_class.is_active: False})
            
            # Activate the specified config
            config = self.get_by_id(config_id)
            if config:
                config.is_active = True
                self.db.commit()
                return True
            return False
        except Exception:
            self.db.rollback()
            return False

    def test_connection(self, config: EmailConfig) -> dict:
        """Test SMTP connection for a configuration
        
        Returns:
            dict: {
                'connected': bool,
                'error_message': str | None,
                'error_details': dict | None
            }
        """
        import socket
        import traceback
        
        def safe_str(obj) -> str:
            """Safely convert object to string, handling encoding issues"""
            try:
                if obj is None:
                    return "None"
                if isinstance(obj, bytes):
                    return obj.decode('utf-8', errors='replace')
                elif isinstance(obj, str):
                    # Ensure the string can be encoded/decoded properly
                    try:
                        obj.encode('utf-8')
                        return obj
                    except UnicodeEncodeError:
                        # If encoding fails, replace problematic characters
                        return obj.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
                else:
                    # For other types, convert to string
                    result = str(obj)
                    # Ensure the result is valid UTF-8
                    try:
                        result.encode('utf-8')
                        return result
                    except UnicodeEncodeError:
                        return result.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
            except (UnicodeDecodeError, UnicodeEncodeError) as e:
                try:
                    return repr(obj)
                except Exception:
                    return f"Unable to convert to string (encoding error: {type(e).__name__})"
            except Exception as e:
                try:
                    return repr(obj)
                except Exception:
                    return f"Unable to convert to string ({type(e).__name__})"
        
        def safe_traceback() -> str:
            """Safely get traceback as string"""
            try:
                tb = traceback.format_exc()
                # Ensure it's properly encoded - handle both bytes and str
                if isinstance(tb, bytes):
                    return tb.decode('utf-8', errors='replace')
                elif isinstance(tb, str):
                    # If it's already a string, try to ensure it's valid UTF-8
                    try:
                        tb.encode('utf-8')
                        return tb
                    except UnicodeEncodeError:
                        # If encoding fails, replace problematic characters
                        return tb.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
                return str(tb)
            except (UnicodeDecodeError, UnicodeEncodeError) as e:
                return f"Unable to get traceback (encoding error: {safe_str(e)})"
            except Exception as e:
                return f"Unable to get traceback: {safe_str(e)}"
        
        def safe_error_message(template: str, **kwargs) -> str:
            """Safely format error message with UTF-8 encoding"""
            try:
                # Format the message
                formatted = template.format(**{k: safe_str(v) for k, v in kwargs.items()})
                # Ensure it can be encoded as UTF-8
                formatted.encode('utf-8')
                return formatted
            except (UnicodeEncodeError, UnicodeDecodeError) as e:
                # If encoding fails, try to replace problematic characters
                try:
                    if 'formatted' in locals():
                        return formatted.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
                    else:
                        # If formatting itself failed, try to format with safe_str
                        safe_kwargs = {k: safe_str(v) for k, v in kwargs.items()}
                        formatted = template.format(**safe_kwargs)
                        return formatted.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
                except Exception:
                    # Fallback: return a simple error message (using ASCII-safe characters)
                    try:
                        return "Error in connection test (encoding issue)"
                    except Exception:
                        return "Connection test error"
            except Exception as e:
                # For any other exception, try to return a safe message
                try:
                    return f"Error formatting message: {safe_str(e)}"
                except Exception:
                    return "Connection test error"
        
        error_details = {
            "error_type": None,
            "host": config.smtp_host,
            "port": config.smtp_port,
            "use_ssl": config.use_ssl,
            "use_tls": config.use_tls,
            "raw_error": None,
            "traceback": None
        }
        
        try:
            import smtplib
            from email.mime.text import MIMEText
            
            # First, try to resolve DNS and check if host is reachable
            try:
                socket.gethostbyname(config.smtp_host)
            except socket.gaierror as dns_error:
                error_details["error_type"] = "DNS_RESOLUTION_ERROR"
                error_details["raw_error"] = safe_str(dns_error)
                return {
                    "connected": False,
                    "error_message": safe_error_message("خطا در یافتن آدرس سرور: {host} یافت نشد. لطفاً آدرس میزبان را بررسی کنید.", host=config.smtp_host),
                    "error_details": error_details
                }
            
            # Try to connect to the port to check if it's open
            try:
                test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                test_socket.settimeout(5)
                result = test_socket.connect_ex((config.smtp_host, config.smtp_port))
                test_socket.close()
                
                if result != 0:
                    error_details["error_type"] = "PORT_NOT_ACCESSIBLE"
                    error_details["raw_error"] = f"Port connection test failed with code: {result}"
                    return {
                        "connected": False,
                        "error_message": safe_error_message("پورت {port} در {host} در دسترس نیست یا بسته است. (کد خطا: {code})", port=config.smtp_port, host=config.smtp_host, code=result),
                        "error_details": error_details
                    }
            except Exception as socket_error:
                error_details["error_type"] = "SOCKET_TEST_ERROR"
                error_details["raw_error"] = safe_str(socket_error)
            
            # Create SMTP connection
            if config.use_ssl:
                server = smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=10)
            else:
                server = smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=10)
                if config.use_tls:
                    server.starttls()
            
            # Login - ensure username and password are properly encoded
            # smtplib expects ASCII-compatible strings, so we need to handle encoding
            username = config.smtp_username
            password = config.smtp_password
            
            # If password contains non-ASCII characters, encode it properly
            # SMTP AUTH typically uses base64 encoding, but smtplib handles this internally
            # However, we need to ensure the string can be encoded to bytes
            try:
                # Try to encode to ensure it's valid
                password.encode('ascii')
            except UnicodeEncodeError:
                # If password contains non-ASCII, we need to handle it
                # SMTP AUTH uses base64, so non-ASCII should work, but smtplib may have issues
                # Let's try to use the password as-is, but ensure it's a proper string
                if isinstance(password, bytes):
                    password = password.decode('utf-8', errors='replace')
                # Ensure username is also properly encoded
                if isinstance(username, bytes):
                    username = username.decode('utf-8', errors='replace')
            
            server.login(username, password)
            server.quit()
            return {"connected": True, "error_message": None, "error_details": None}
            
        except smtplib.SMTPAuthenticationError as e:
            error_details["error_type"] = "SMTP_AUTHENTICATION_ERROR"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("خطای احراز هویت: نام کاربری یا رمز عبور اشتباه است.\n\nجزئیات: {details}", details=error_str),
                "error_details": error_details
            }
        except smtplib.SMTPConnectError as e:
            error_details["error_type"] = "SMTP_CONNECT_ERROR"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("خطا در اتصال به سرور SMTP: نمی‌توان به {host}:{port} متصل شد.\n\nجزئیات: {details}\n\nنکته: پورت {port} ممکن است اشتباه باشد. پورت‌های معمول SMTP: 25 (بدون رمزگذاری), 587 (TLS), 465 (SSL)", host=config.smtp_host, port=config.smtp_port, details=error_str),
                "error_details": error_details
            }
        except smtplib.SMTPException as e:
            error_details["error_type"] = "SMTP_EXCEPTION"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("خطای SMTP: {details}", details=error_str),
                "error_details": error_details
            }
        except TimeoutError as e:
            error_details["error_type"] = "TIMEOUT_ERROR"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("زمان اتصال به پایان رسید: سرور SMTP در {host}:{port} پاسخ نمی‌دهد.\n\nجزئیات: {details}", host=config.smtp_host, port=config.smtp_port, details=error_str),
                "error_details": error_details
            }
        except ConnectionRefusedError as e:
            error_details["error_type"] = "CONNECTION_REFUSED"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("اتصال رد شد: سرور SMTP در {host}:{port} در دسترس نیست.\n\nجزئیات: {details}\n\nعلل احتمالی:\n- سرور SMTP در حال اجرا نیست\n- پورت اشتباه است (پورت‌های معمول: 25, 587, 465)\n- فایروال یا شبکه اتصال را مسدود کرده است\n- آدرس میزبان اشتباه است", host=config.smtp_host, port=config.smtp_port, details=error_str),
                "error_details": error_details
            }
        except socket.timeout as e:
            error_details["error_type"] = "SOCKET_TIMEOUT"
            error_details["raw_error"] = safe_str(e)
            error_details["traceback"] = safe_traceback()
            error_str = safe_str(e)
            return {
                "connected": False,
                "error_message": safe_error_message("زمان اتصال به پایان رسید: سرور در {host}:{port} پاسخ نمی‌دهد.\n\nجزئیات: {details}", host=config.smtp_host, port=config.smtp_port, details=error_str),
                "error_details": error_details
            }
        except Exception as e:
            error_type = type(e).__name__
            error_msg = safe_str(e)
            error_details["error_type"] = error_type
            error_details["raw_error"] = error_msg
            error_details["traceback"] = safe_traceback()
            
            # ترجمه خطاهای رایج به فارسی
            error_msg_lower = error_msg.lower()
            if "certificate verify failed" in error_msg_lower or "ssl" in error_msg_lower:
                error_msg = safe_error_message("خطای تأیید گواهینامه SSL: گواهینامه سرور معتبر نیست.\n\nجزئیات: {details}", details=error_msg)
            elif "name resolution" in error_msg_lower or "getaddrinfo failed" in error_msg_lower:
                error_msg = safe_error_message("خطا در یافتن آدرس سرور: {host} یافت نشد.\n\nجزئیات: {details}", host=config.smtp_host, details=error_msg)
            elif "timed out" in error_msg_lower:
                error_msg = safe_error_message("زمان اتصال به پایان رسید: سرور پاسخ نمی‌دهد.\n\nجزئیات: {details}", details=error_msg)
            else:
                error_msg = safe_error_message("خطا در تست اتصال ({type}): {details}", type=error_type, details=error_msg)
            
            return {
                "connected": False,
                "error_message": safe_error_message(error_msg),
                "error_details": error_details
            }
