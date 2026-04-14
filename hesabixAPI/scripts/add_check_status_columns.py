from __future__ import annotations

from sqlalchemy import inspect, text
from adapters.db.session import engine


def main() -> None:
	with engine.connect() as conn:
		insp = inspect(conn)
		cols = {c['name'] for c in insp.get_columns('checks')}

		# Add status columns if missing
		ddl_statements: list[str] = []

		if 'status' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `status` ENUM('RECEIVED_ON_HAND','TRANSFERRED_ISSUED','DEPOSITED','CLEARED','ENDORSED','RETURNED','BOUNCED','CANCELLED') NULL AFTER `currency_id`"
			)
		if 'status_at' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `status_at` DATETIME NULL AFTER `status`"
			)
		if 'current_holder_type' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `current_holder_type` ENUM('BUSINESS','BANK','PERSON') NULL AFTER `status_at`"
			)
		if 'current_holder_id' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `current_holder_id` INT NULL AFTER `current_holder_type`"
			)
		if 'last_action_document_id' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `last_action_document_id` INT NULL AFTER `current_holder_id`"
			)
		if 'developer_data' not in cols:
			ddl_statements.append(
				"ALTER TABLE `checks` ADD COLUMN `developer_data` JSON NULL AFTER `last_action_document_id`"
			)

		for stmt in ddl_statements:
			conn.execute(text(stmt))

		# Create indexes if missing
		existing_indexes = {idx['name'] for idx in insp.get_indexes('checks')}
		if 'ix_checks_business_status' not in existing_indexes and 'status' in {c['name'] for c in insp.get_columns('checks')}:
			conn.execute(text("CREATE INDEX `ix_checks_business_status` ON `checks` (`business_id`, `status`)"))
		if 'ix_checks_business_holder_type' not in existing_indexes and 'current_holder_type' in {c['name'] for c in insp.get_columns('checks')}:
			conn.execute(text("CREATE INDEX `ix_checks_business_holder_type` ON `checks` (`business_id`, `current_holder_type`)"))
		if 'ix_checks_business_holder_id' not in existing_indexes and 'current_holder_id' in {c['name'] for c in insp.get_columns('checks')}:
			conn.execute(text("CREATE INDEX `ix_checks_business_holder_id` ON `checks` (`business_id`, `current_holder_id`)"))

		# Add FK if missing
		fks = insp.get_foreign_keys('checks')
		fk_names = {fk.get('name') for fk in fks if fk.get('name')}
		if 'fk_checks_last_action_document' not in fk_names and 'last_action_document_id' in {c['name'] for c in insp.get_columns('checks')}:
			conn.execute(text(
				"ALTER TABLE `checks` ADD CONSTRAINT `fk_checks_last_action_document` FOREIGN KEY (`last_action_document_id`) REFERENCES `documents`(`id`) ON DELETE SET NULL"
			))

		conn.commit()


if __name__ == '__main__':
	main()
