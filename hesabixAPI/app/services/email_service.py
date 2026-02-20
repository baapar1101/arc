import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from typing import Optional, List
from sqlalchemy.orm import Session

from adapters.db.models.email_config import EmailConfig
from adapters.db.repositories.email_config_repository import EmailConfigRepository


class EmailService:
    def __init__(self, db: Session):
        self.db = db
        self.email_repo = EmailConfigRepository(db)

    def send_email(
        self, 
        to: str, 
        subject: str, 
        body: str, 
        html_body: Optional[str] = None,
        config_id: Optional[int] = None
    ) -> bool:
        """
        Send email using SMTP configuration
        
        Args:
            to: Recipient email address
            subject: Email subject
            body: Plain text body
            html_body: HTML body (optional)
            config_id: Specific config ID to use (optional)
        
        Returns:
            bool: True if email sent successfully, False otherwise
        """
        try:
            # Get email configuration - prioritize default config
            if config_id:
                config = self.email_repo.get_by_id(config_id)
            else:
                # First try to get default config
                config = self.email_repo.get_default_config()
                if not config:
                    # Fallback to active config
                    config = self.email_repo.get_active_config()
            
            if not config:
                return False
            
            # Create message
            msg = MIMEMultipart('alternative')
            msg['From'] = f"{config.from_name} <{config.from_email}>"
            msg['To'] = to
            msg['Subject'] = subject
            
            # Add plain text part
            text_part = MIMEText(body, 'plain', 'utf-8')
            msg.attach(text_part)
            
            # Add HTML part if provided
            if html_body:
                html_part = MIMEText(html_body, 'html', 'utf-8')
                msg.attach(html_part)
            
            # Send email
            return self._send_smtp_email(config, msg)
            
        except Exception as e:
            print(f"Error sending email: {e}")
            return False

    def send_template_email(
        self, 
        template_name: str, 
        to: str, 
        context: dict,
        config_id: Optional[int] = None
    ) -> bool:
        """
        Send email using a template (placeholder for future template system)
        
        Args:
            template_name: Name of the template
            to: Recipient email address
            context: Template context variables
            config_id: Specific config ID to use (optional)
        
        Returns:
            bool: True if email sent successfully, False otherwise
        """
        # For now, just use basic template substitution
        # This can be extended with a proper template engine later
        subject = context.get('subject', 'Email from Hesabix')
        body = context.get('body', '')
        html_body = context.get('html_body')
        
        return self.send_email(to, subject, body, html_body, config_id)

    def send_email_with_attachment(
        self,
        to: str,
        subject: str,
        body: str,
        attachment_filename: str,
        attachment_content: bytes,
        config_id: Optional[int] = None,
    ) -> bool:
        """
        ارسال ایمیل با فایل پیوست.
        برای فایل‌های بکاپ و گزارش‌ها استفاده می‌شود.
        """
        try:
            if config_id:
                config = self.email_repo.get_by_id(config_id)
            else:
                config = self.email_repo.get_default_config()
                if not config:
                    config = self.email_repo.get_active_config()
            if not config:
                return False

            msg = MIMEMultipart("mixed")
            msg["From"] = f"{config.from_name} <{config.from_email}>"
            msg["To"] = to
            msg["Subject"] = subject

            text_part = MIMEText(body, "plain", "utf-8")
            msg.attach(text_part)

            attachment_part = MIMEBase("application", "octet-stream")
            attachment_part.set_payload(attachment_content)
            encoders.encode_base64(attachment_part)
            attachment_part.add_header(
                "Content-Disposition",
                "attachment",
                filename=("utf-8", "", attachment_filename),
            )
            msg.attach(attachment_part)

            return self._send_smtp_email(config, msg)
        except Exception as e:
            print(f"Error sending email with attachment: {e}")
            return False

    def test_connection(self, config_id: int) -> bool:
        """
        Test SMTP connection for a specific configuration
        
        Args:
            config_id: Configuration ID to test
        
        Returns:
            bool: True if connection successful, False otherwise
        """
        config = self.email_repo.get_by_id(config_id)
        if not config:
            return False
        
        return self.email_repo.test_connection(config)

    def get_active_config(self) -> Optional[EmailConfig]:
        """Get the currently active email configuration"""
        return self.email_repo.get_active_config()

    def get_all_configs(self) -> List[EmailConfig]:
        """Get all email configurations"""
        return self.email_repo.get_all_configs()

    def _send_smtp_email(self, config: EmailConfig, msg: MIMEMultipart) -> bool:
        """Internal method to send email via SMTP"""
        try:
            # Create SMTP connection with timeout
            if config.use_ssl:
                server = smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=10)
            else:
                server = smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=10)
                if config.use_tls:
                    server.starttls()
            
            # Login and send - ensure username and password are properly encoded
            username = config.smtp_username
            password = config.smtp_password
            
            # Handle encoding issues with password
            if isinstance(password, bytes):
                password = password.decode('utf-8', errors='replace')
            if isinstance(username, bytes):
                username = username.decode('utf-8', errors='replace')
            
            # Try to encode to ensure compatibility
            try:
                password.encode('ascii')
            except UnicodeEncodeError:
                # Password contains non-ASCII characters
                # smtplib should handle this with base64 encoding, but let's ensure it's a proper string
                pass
            
            server.login(username, password)
            server.send_message(msg)
            server.quit()
            
            return True
        except smtplib.SMTPAuthenticationError as e:
            print(f"SMTP Authentication error: {e}")
            return False
        except smtplib.SMTPConnectError as e:
            print(f"SMTP Connection error: Cannot connect to {config.smtp_host}:{config.smtp_port} - {e}")
            return False
        except smtplib.SMTPException as e:
            print(f"SMTP error: {e}")
            return False
        except ConnectionRefusedError as e:
            print(f"Connection refused: SMTP server at {config.smtp_host}:{config.smtp_port} is not available - {e}")
            return False
        except TimeoutError as e:
            print(f"Timeout error: SMTP server at {config.smtp_host}:{config.smtp_port} did not respond - {e}")
            return False
        except Exception as e:
            error_type = type(e).__name__
            print(f"SMTP error ({error_type}): {e}")
            return False
