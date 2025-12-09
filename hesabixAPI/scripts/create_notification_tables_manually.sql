-- ایجاد دستی جداول سیستم نوتیفیکیشن
-- در صورت مشکل در migration، این اسکریپت را اجرا کنید

USE hesabix_db;

-- ================== notification_event_types ==================
CREATE TABLE IF NOT EXISTS `notification_event_types` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `code` VARCHAR(100) NOT NULL UNIQUE,
    `name` VARCHAR(200) NOT NULL,
    `description` TEXT,
    `category` VARCHAR(50),
    `available_variables` JSON,
    `default_sms_template` TEXT,
    `default_email_template` TEXT,
    `default_email_subject` VARCHAR(200),
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    `requires_approval` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `ix_event_types_code` (`code`),
    INDEX `ix_event_types_category` (`category`),
    INDEX `ix_event_types_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ================== business_notification_templates ==================
CREATE TABLE IF NOT EXISTS `business_notification_templates` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `business_id` INT NOT NULL,
    `code` VARCHAR(100) NOT NULL,
    `name` VARCHAR(200) NOT NULL,
    `description` TEXT,
    `event_type` VARCHAR(100) NOT NULL,
    `channel` ENUM('sms', 'email') NOT NULL,
    `recipient_type` ENUM('customer', 'supplier', 'employee') NOT NULL DEFAULT 'customer',
    `subject` VARCHAR(200),
    `body` TEXT NOT NULL,
    `available_variables` JSON,
    `status` ENUM('draft', 'pending_approval', 'approved', 'rejected', 'suspended') NOT NULL DEFAULT 'draft',
    `is_active` BOOLEAN NOT NULL DEFAULT FALSE,
    `approval_status` ENUM('pending', 'ai_approved', 'admin_approved', 'rejected') NOT NULL DEFAULT 'pending',
    `approved_by_ai` BOOLEAN NOT NULL DEFAULT FALSE,
    `approved_by_admin_id` INT,
    `ai_confidence_score` DECIMAL(5, 2),
    `ai_review_notes` TEXT,
    `admin_review_notes` TEXT,
    `approved_at` DATETIME,
    `rejected_at` DATETIME,
    `rejection_reason` TEXT,
    `daily_limit` INT NOT NULL DEFAULT 100,
    `is_automated` BOOLEAN NOT NULL DEFAULT FALSE,
    `created_by_user_id` INT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (`business_id`) REFERENCES `businesses`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`approved_by_admin_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
    UNIQUE KEY `uk_business_template_code` (`business_id`, `code`),
    INDEX `ix_business_templates_business` (`business_id`),
    INDEX `ix_business_templates_event_type` (`event_type`),
    INDEX `ix_business_templates_status` (`status`),
    INDEX `ix_business_templates_approval` (`approval_status`),
    INDEX `ix_business_templates_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ================== notification_moderation_queue ==================
CREATE TABLE IF NOT EXISTS `notification_moderation_queue` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `template_id` INT NOT NULL,
    `business_id` INT NOT NULL,
    `status` ENUM('pending', 'ai_reviewing', 'ai_reviewed', 'admin_reviewing', 'completed') NOT NULL DEFAULT 'pending',
    `ai_reviewed_at` DATETIME,
    `ai_decision` ENUM('approve', 'reject', 'review_required'),
    `ai_confidence` DECIMAL(5, 2),
    `ai_flags` JSON,
    `ai_suggestions` TEXT,
    `admin_reviewed_at` DATETIME,
    `reviewed_by_admin_id` INT,
    `admin_decision` ENUM('approve', 'reject'),
    `admin_notes` TEXT,
    `priority` INT NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `completed_at` DATETIME,
    FOREIGN KEY (`template_id`) REFERENCES `business_notification_templates`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`business_id`) REFERENCES `businesses`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`reviewed_by_admin_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
    INDEX `ix_moderation_queue_status` (`status`),
    INDEX `ix_moderation_queue_priority` (`priority`),
    INDEX `ix_moderation_queue_business` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ================== notification_send_logs ==================
CREATE TABLE IF NOT EXISTS `notification_send_logs` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `business_id` INT NOT NULL,
    `template_id` INT,
    `recipient_type` ENUM('person', 'user') NOT NULL,
    `recipient_id` INT NOT NULL,
    `recipient_identifier` VARCHAR(100),
    `channel` ENUM('sms', 'email') NOT NULL,
    `subject` VARCHAR(200),
    `body` TEXT NOT NULL,
    `context_data` JSON,
    `status` ENUM('pending', 'sent', 'failed', 'rejected') NOT NULL DEFAULT 'pending',
    `sent_at` DATETIME,
    `failed_at` DATETIME,
    `failure_reason` TEXT,
    `provider_name` VARCHAR(50),
    `provider_message_id` VARCHAR(200),
    `cost` DECIMAL(10, 2),
    `triggered_by_user_id` INT,
    `event_type` VARCHAR(100),
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`business_id`) REFERENCES `businesses`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`template_id`) REFERENCES `business_notification_templates`(`id`) ON DELETE SET NULL,
    INDEX `ix_send_logs_business_date` (`business_id`, `created_at`),
    INDEX `ix_send_logs_recipient` (`recipient_type`, `recipient_id`),
    INDEX `ix_send_logs_status` (`status`),
    INDEX `ix_send_logs_template` (`template_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ================== notification_daily_stats ==================
CREATE TABLE IF NOT EXISTS `notification_daily_stats` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `business_id` INT NOT NULL,
    `template_id` INT,
    `date` DATE NOT NULL,
    `channel` ENUM('sms', 'email') NOT NULL,
    `total_sent` INT NOT NULL DEFAULT 0,
    `total_failed` INT NOT NULL DEFAULT 0,
    `total_cost` DECIMAL(10, 2) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (`business_id`) REFERENCES `businesses`(`id`) ON DELETE CASCADE,
    FOREIGN KEY (`template_id`) REFERENCES `business_notification_templates`(`id`) ON DELETE SET NULL,
    UNIQUE KEY `uk_daily_stats` (`business_id`, `template_id`, `date`, `channel`),
    INDEX `ix_daily_stats_business_date` (`business_id`, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SELECT 'جداول با موفقیت ایجاد شدند!' as result;


