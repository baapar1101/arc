"""
اکشن پشتیبان‌گیری از داده‌های کسب‌وکار (فایل .hbx)
"""

from typing import Any, Dict

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution


class BusinessBackupAction(ActionHandler):
    """ایجاد فایل پشتیبان کامل tenant برای کسب‌وکار جاری ورک‌فلو"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "پشتیبان کسب‌وکار",
            "description": "ایجاد فایل پشتیبان (.hbx) و ذخیره در فایل‌سرور؛ خروجی شامل file_id است تا نود بعدی (مثلاً ارسال بله) همان فایل را بفرستد. در نود بله: send_file_attachment=true و attachment_file_id=$شناسه_این_نود.file_id",
            "icon": "backup",
            "config_schema": {
                "upload_to_ftp": {
                    "type": "boolean",
                    "description": "پس از ذخیره، ارسال کپی به سرور FTP (نیازمند تنظیمات FTP)",
                    "default": False,
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "NO_DB_OR_BUSINESS"}

        upload = bool(WorkflowEngine._resolve_value_static(config.get("upload_to_ftp"), context, node_results) or False)

        user_id = context.get("user_id")
        try:
            uid = int(user_id) if user_id is not None else None
        except (TypeError, ValueError):
            uid = None

        from adapters.api.v1.business_backups import run_workflow_business_backup

        result = run_workflow_business_backup(
            db,
            int(business_id),
            uid,
            upload_to_ftp=upload,
        )
        if isinstance(result, dict) and result.get("success"):
            fid = result.get("file_id")
            if fid:
                # هم‌نام با فیلد دانلود فایل‌سرور برای ارجاع در نود بعدی ($node_id.file_id)
                result["attachment_file_id"] = fid
                result["for_next_node"] = {
                    "file_id": str(fid),
                    "filename": result.get("filename"),
                }
        return result
