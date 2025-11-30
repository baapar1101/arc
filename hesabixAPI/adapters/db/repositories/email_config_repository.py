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
                'error_message': str | None
            }
        """
        try:
            import smtplib
            from email.mime.text import MIMEText
            
            # Create SMTP connection
            if config.use_ssl:
                server = smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=10)
            else:
                server = smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=10)
                if config.use_tls:
                    server.starttls()
            
            # Login
            server.login(config.smtp_username, config.smtp_password)
            server.quit()
            return {"connected": True, "error_message": None}
        except smtplib.SMTPAuthenticationError as e:
            return {
                "connected": False,
                "error_message": f"خطای احراز هویت: نام کاربری یا رمز عبور اشتباه است. ({str(e)})"
            }
        except smtplib.SMTPConnectError as e:
            return {
                "connected": False,
                "error_message": f"خطا در اتصال به سرور SMTP: نمی‌توان به {config.smtp_host}:{config.smtp_port} متصل شد. ({str(e)})"
            }
        except smtplib.SMTPException as e:
            return {
                "connected": False,
                "error_message": f"خطای SMTP: {str(e)}"
            }
        except TimeoutError as e:
            return {
                "connected": False,
                "error_message": f"زمان اتصال به پایان رسید: سرور SMTP پاسخ نمی‌دهد. ({str(e)})"
            }
        except ConnectionRefusedError as e:
            return {
                "connected": False,
                "error_message": f"اتصال رد شد: سرور SMTP در {config.smtp_host}:{config.smtp_port} در دسترس نیست. ({str(e)})"
            }
        except Exception as e:
            error_msg = str(e)
            # ترجمه خطاهای رایج به فارسی
            if "certificate verify failed" in error_msg.lower():
                error_msg = "خطای تأیید گواهینامه SSL: گواهینامه سرور معتبر نیست."
            elif "name resolution" in error_msg.lower() or "getaddrinfo failed" in error_msg.lower():
                error_msg = f"خطا در یافتن آدرس سرور: {config.smtp_host} یافت نشد."
            elif "timed out" in error_msg.lower():
                error_msg = "زمان اتصال به پایان رسید: سرور پاسخ نمی‌دهد."
            
            return {
                "connected": False,
                "error_message": f"خطا در تست اتصال: {error_msg}"
            }
