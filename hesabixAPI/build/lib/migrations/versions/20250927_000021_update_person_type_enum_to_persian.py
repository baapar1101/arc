from alembic import op

# revision identifiers, used by Alembic.
revision = '20250927_000021_update_person_type_enum_to_persian'
down_revision = 'd3e84892c1c2'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# 1) Allow both English and Persian, plus new 'سهامدار'
	op.execute(
		"""
		ALTER TABLE persons 
		MODIFY COLUMN person_type 
		ENUM('CUSTOMER','MARKETER','EMPLOYEE','SUPPLIER','PARTNER','SELLER',
		     'مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده','سهامدار') NOT NULL
		"""
	)

	# 2) Migrate existing data from English to Persian
	op.execute("UPDATE persons SET person_type = 'مشتری' WHERE person_type = 'CUSTOMER'")
	op.execute("UPDATE persons SET person_type = 'بازاریاب' WHERE person_type = 'MARKETER'")
	op.execute("UPDATE persons SET person_type = 'کارمند' WHERE person_type = 'EMPLOYEE'")
	op.execute("UPDATE persons SET person_type = 'تامین‌کننده' WHERE person_type = 'SUPPLIER'")
	op.execute("UPDATE persons SET person_type = 'همکار' WHERE person_type = 'PARTNER'")
	op.execute("UPDATE persons SET person_type = 'فروشنده' WHERE person_type = 'SELLER'")

	# 3) Restrict enum to Persian only (including 'سهامدار')
	op.execute(
		"""
		ALTER TABLE persons 
		MODIFY COLUMN person_type 
		ENUM('مشتری','بازاریاب','کارمند','تامین‌کننده','همکار','فروشنده','سهامدار') NOT NULL
		"""
	)


def downgrade() -> None:
	# Revert to English-only (without shareholder)
	op.execute(
		"""
		ALTER TABLE persons 
		MODIFY COLUMN person_type 
		ENUM('CUSTOMER','MARKETER','EMPLOYEE','SUPPLIER','PARTNER','SELLER') NOT NULL
		"""
	)

	# Convert data back from Persian to English
	reverse_mapping = {
		'مشتری': 'CUSTOMER',
		'بازاریاب': 'MARKETER',
		'کارمند': 'EMPLOYEE',
		'تامین‌کننده': 'SUPPLIER',
		'همکار': 'PARTNER',
		'فروشنده': 'SELLER',
	}
	for fa, en in reverse_mapping.items():
		op.execute(text("UPDATE persons SET person_type = :en WHERE person_type = :fa"), {"fa": fa, "en": en})
