from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250927_000018_seed_currencies'
down_revision = 'f876bfa36805'
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insert_sql = sa.text(
		"""
		INSERT INTO currencies (name, title, symbol, code, created_at, updated_at)
		VALUES (:name, :title, :symbol, :code, NOW(), NOW())
		ON DUPLICATE KEY UPDATE
			title = VALUES(title),
			symbol = VALUES(symbol),
			updated_at = VALUES(updated_at)
		"""
	)

	currencies = [
		{"name": "Iranian Rial", "title": "ریال ایران", "symbol": "﷼", "code": "IRR"},
		{"name": "United States Dollar", "title": "US Dollar", "symbol": "$", "code": "USD"},
		{"name": "Euro", "title": "Euro", "symbol": "€", "code": "EUR"},
		{"name": "British Pound", "title": "Pound Sterling", "symbol": "£", "code": "GBP"},
		{"name": "Japanese Yen", "title": "Yen", "symbol": "¥", "code": "JPY"},
		{"name": "Chinese Yuan", "title": "Yuan", "symbol": "¥", "code": "CNY"},
		{"name": "Swiss Franc", "title": "Swiss Franc", "symbol": "CHF", "code": "CHF"},
		{"name": "Canadian Dollar", "title": "Canadian Dollar", "symbol": "$", "code": "CAD"},
		{"name": "Australian Dollar", "title": "Australian Dollar", "symbol": "$", "code": "AUD"},
		{"name": "New Zealand Dollar", "title": "New Zealand Dollar", "symbol": "$", "code": "NZD"},
		{"name": "Russian Ruble", "title": "Ruble", "symbol": "₽", "code": "RUB"},
		{"name": "Turkish Lira", "title": "Lira", "symbol": "₺", "code": "TRY"},
		{"name": "UAE Dirham", "title": "Dirham", "symbol": "د.إ", "code": "AED"},
		{"name": "Saudi Riyal", "title": "Riyal", "symbol": "﷼", "code": "SAR"},
		{"name": "Qatari Riyal", "title": "Qatari Riyal", "symbol": "﷼", "code": "QAR"},
		{"name": "Kuwaiti Dinar", "title": "Kuwaiti Dinar", "symbol": "د.ك", "code": "KWD"},
		{"name": "Omani Rial", "title": "Omani Rial", "symbol": "﷼", "code": "OMR"},
		{"name": "Bahraini Dinar", "title": "Bahraini Dinar", "symbol": ".د.ب", "code": "BHD"},
		{"name": "Iraqi Dinar", "title": "Iraqi Dinar", "symbol": "ع.د", "code": "IQD"},
		{"name": "Afghan Afghani", "title": "Afghani", "symbol": "؋", "code": "AFN"},
		{"name": "Pakistani Rupee", "title": "Rupee", "symbol": "₨", "code": "PKR"},
		{"name": "Indian Rupee", "title": "Rupee", "symbol": "₹", "code": "INR"},
		{"name": "Armenian Dram", "title": "Dram", "symbol": "֏", "code": "AMD"},
		{"name": "Azerbaijani Manat", "title": "Manat", "symbol": "₼", "code": "AZN"},
		{"name": "Georgian Lari", "title": "Lari", "symbol": "₾", "code": "GEL"},
		{"name": "Kazakhstani Tenge", "title": "Tenge", "symbol": "₸", "code": "KZT"},
		{"name": "Uzbekistani Som", "title": "Som", "symbol": "so'm", "code": "UZS"},
		{"name": "Tajikistani Somoni", "title": "Somoni", "symbol": "ЅМ", "code": "TJS"},
		{"name": "Turkmenistani Manat", "title": "Manat", "symbol": "m", "code": "TMT"},
		{"name": "Afgani Lek", "title": "Lek", "symbol": "L", "code": "ALL"},
		{"name": "Bulgarian Lev", "title": "Lev", "symbol": "лв", "code": "BGN"},
		{"name": "Romanian Leu", "title": "Leu", "symbol": "lei", "code": "RON"},
		{"name": "Polish Złoty", "title": "Zloty", "symbol": "zł", "code": "PLN"},
		{"name": "Czech Koruna", "title": "Koruna", "symbol": "Kč", "code": "CZK"},
		{"name": "Hungarian Forint", "title": "Forint", "symbol": "Ft", "code": "HUF"},
		{"name": "Danish Krone", "title": "Krone", "symbol": "kr", "code": "DKK"},
		{"name": "Norwegian Krone", "title": "Krone", "symbol": "kr", "code": "NOK"},
		{"name": "Swedish Krona", "title": "Krona", "symbol": "kr", "code": "SEK"},
		{"name": "Icelandic Króna", "title": "Krona", "symbol": "kr", "code": "ISK"},
		{"name": "Croatian Kuna", "title": "Kuna", "symbol": "kn", "code": "HRK"},
		{"name": "Serbian Dinar", "title": "Dinar", "symbol": "дин.", "code": "RSD"},
		{"name": "Bosnia and Herzegovina Mark", "title": "Mark", "symbol": "KM", "code": "BAM"},
		{"name": "Ukrainian Hryvnia", "title": "Hryvnia", "symbol": "₴", "code": "UAH"},
		{"name": "Belarusian Ruble", "title": "Ruble", "symbol": "Br", "code": "BYN"},
		{"name": "Egyptian Pound", "title": "Pound", "symbol": "£", "code": "EGP"},
		{"name": "South African Rand", "title": "Rand", "symbol": "R", "code": "ZAR"},
		{"name": "Nigerian Naira", "title": "Naira", "symbol": "₦", "code": "NGN"},
		{"name": "Kenyan Shilling", "title": "Shilling", "symbol": "Sh", "code": "KES"},
		{"name": "Ethiopian Birr", "title": "Birr", "symbol": "Br", "code": "ETB"},
		{"name": "Moroccan Dirham", "title": "Dirham", "symbol": "د.م.", "code": "MAD"},
		{"name": "Tunisian Dinar", "title": "Dinar", "symbol": "د.ت", "code": "TND"},
		{"name": "Algerian Dinar", "title": "Dinar", "symbol": "د.ج", "code": "DZD"},
		{"name": "Israeli New Shekel", "title": "Shekel", "symbol": "₪", "code": "ILS"},
		{"name": "Jordanian Dinar", "title": "Dinar", "symbol": "د.ا", "code": "JOD"},
		{"name": "Lebanese Pound", "title": "Pound", "symbol": "ل.ل", "code": "LBP"},
		{"name": "Syrian Pound", "title": "Pound", "symbol": "£", "code": "SYP"},
		{"name": "Azerbaijani Manat", "title": "Manat", "symbol": "₼", "code": "AZN"},
		{"name": "Singapore Dollar", "title": "Singapore Dollar", "symbol": "$", "code": "SGD"},
		{"name": "Hong Kong Dollar", "title": "Hong Kong Dollar", "symbol": "$", "code": "HKD"},
		{"name": "Thai Baht", "title": "Baht", "symbol": "฿", "code": "THB"},
		{"name": "Malaysian Ringgit", "title": "Ringgit", "symbol": "RM", "code": "MYR"},
		{"name": "Indonesian Rupiah", "title": "Rupiah", "symbol": "Rp", "code": "IDR"},
		{"name": "Philippine Peso", "title": "Peso", "symbol": "₱", "code": "PHP"},
		{"name": "Vietnamese Dong", "title": "Dong", "symbol": "₫", "code": "VND"},
		{"name": "South Korean Won", "title": "Won", "symbol": "₩", "code": "KRW"},
		{"name": "Taiwan New Dollar", "title": "New Dollar", "symbol": "$", "code": "TWD"},
		{"name": "Mexican Peso", "title": "Peso", "symbol": "$", "code": "MXN"},
		{"name": "Brazilian Real", "title": "Real", "symbol": "R$", "code": "BRL"},
		{"name": "Argentine Peso", "title": "Peso", "symbol": "$", "code": "ARS"},
		{"name": "Chilean Peso", "title": "Peso", "symbol": "$", "code": "CLP"},
		{"name": "Colombian Peso", "title": "Peso", "symbol": "$", "code": "COP"},
		{"name": "Peruvian Sol", "title": "Sol", "symbol": "S/.", "code": "PEN"},
		{"name": "Uruguayan Peso", "title": "Peso", "symbol": "$U", "code": "UYU"},
		{"name": "Paraguayan Guarani", "title": "Guarani", "symbol": "₲", "code": "PYG"},
		{"name": "Bolivian Boliviano", "title": "Boliviano", "symbol": "Bs.", "code": "BOB"},
		{"name": "Dominican Peso", "title": "Peso", "symbol": "RD$", "code": "DOP"},
		{"name": "Cuban Peso", "title": "Peso", "symbol": "$", "code": "CUP"},
		{"name": "Costa Rican Colon", "title": "Colon", "symbol": "₡", "code": "CRC"},
		{"name": "Guatemalan Quetzal", "title": "Quetzal", "symbol": "Q", "code": "GTQ"},
		{"name": "Honduran Lempira", "title": "Lempira", "symbol": "L", "code": "HNL"},
		{"name": "Nicaraguan Córdoba", "title": "Cordoba", "symbol": "C$", "code": "NIO"},
		{"name": "Panamanian Balboa", "title": "Balboa", "symbol": "B/.", "code": "PAB"},
		{"name": "Venezuelan Bolívar", "title": "Bolivar", "symbol": "Bs.", "code": "VES"},
	]

	for row in currencies:
		conn.execute(insert_sql, row)


def downgrade() -> None:
	conn = op.get_bind()
	codes = [
		'IRR','USD','EUR','GBP','JPY','CNY','CHF','CAD','AUD','NZD','RUB','TRY','AED','SAR','QAR','KWD','OMR','BHD','IQD','AFN','PKR','INR','AMD','AZN','GEL','KZT','UZS','TJS','TMT','ALL','BGN','RON','PLN','CZK','HUF','DKK','NOK','SEK','ISK','HRK','RSD','BAM','UAH','BYN','EGP','ZAR','NGN','KES','ETB','MAD','TND','DZD','ILS','JOD','LBP','SYP','SGD','HKD','THB','MYR','IDR','PHP','VND','KRW','TWD','MXN','BRL','ARS','CLP','COP','PEN','UYU','PYG','BOB','DOP','CUP','CRC','GTQ','HNL','NIO','PAB','VES'
	]
	delete_sql = sa.text("DELETE FROM currencies WHERE code IN :codes")
	conn.execute(delete_sql, {"codes": tuple(codes)})


