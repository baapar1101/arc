#!/usr/bin/env python3
"""
تابع کمکی برای ایجاد جدول PostgreSQL از روی ساختار MySQL
"""

from typing import Dict, List, Any
from sqlalchemy import text, inspect

def mysql_to_postgresql_type(mysql_type: str) -> str:
    """تبدیل نوع داده MySQL به PostgreSQL"""
    mysql_type_lower = mysql_type.lower()
    
    # boolean
    if mysql_type_lower.startswith('tinyint(1)'):
        return 'BOOLEAN'
    
    # integer types
    if mysql_type_lower.startswith('tinyint'):
        return 'SMALLINT'
    if mysql_type_lower.startswith('smallint'):
        return 'SMALLINT'
    if mysql_type_lower.startswith('mediumint'):
        return 'INTEGER'
    if mysql_type_lower.startswith('int') or mysql_type_lower.startswith('integer'):
        return 'INTEGER'
    if mysql_type_lower.startswith('bigint'):
        return 'BIGINT'
    
    # string types
    if mysql_type_lower.startswith('char'):
        # char(n) -> char(n)
        return mysql_type.upper()
    if mysql_type_lower.startswith('varchar'):
        # varchar(n) -> character varying(n)
        length = mysql_type.split('(')[1].split(')')[0] if '(' in mysql_type else ''
        return f'VARCHAR({length})' if length else 'VARCHAR'
    if mysql_type_lower.startswith('text'):
        if 'tiny' in mysql_type_lower:
            return 'TEXT'
        if 'medium' in mysql_type_lower:
            return 'TEXT'
        if 'long' in mysql_type_lower:
            return 'TEXT'
        return 'TEXT'
    
    # binary types
    if mysql_type_lower.startswith('blob'):
        return 'BYTEA'
    if mysql_type_lower.startswith('binary') or mysql_type_lower.startswith('varbinary'):
        return 'BYTEA'
    
    # numeric types
    if mysql_type_lower.startswith('decimal') or mysql_type_lower.startswith('numeric'):
        return mysql_type.upper()
    if mysql_type_lower.startswith('float'):
        return 'REAL'
    if mysql_type_lower.startswith('double'):
        return 'DOUBLE PRECISION'
    
    # date/time types
    if mysql_type_lower.startswith('date'):
        return 'DATE'
    if mysql_type_lower.startswith('time'):
        return 'TIME'
    if mysql_type_lower.startswith('datetime'):
        return 'TIMESTAMP'
    if mysql_type_lower.startswith('timestamp'):
        return 'TIMESTAMP'
    if mysql_type_lower.startswith('year'):
        return 'SMALLINT'
    
    # JSON
    if mysql_type_lower.startswith('json'):
        return 'JSONB'
    
    # enum (convert to VARCHAR)
    if mysql_type_lower.startswith('enum'):
        # Extract max length from enum values
        enum_values = mysql_type.split("'")[1::2]  # Extract values between quotes
        max_len = max(len(v) for v in enum_values) if enum_values else 255
        return f'VARCHAR({max_len})'
    
    # set (convert to TEXT)
    if mysql_type_lower.startswith('set'):
        return 'TEXT'
    
    # default
    return 'TEXT'

def get_table_structure_mysql(mysql_session, table_name: str, schema: str) -> List[Dict[str, Any]]:
    """دریافت ساختار جدول از MySQL"""
    query = text("""
        SELECT 
            column_name,
            data_type,
            column_type,
            is_nullable,
            column_default,
            extra,
            column_key,
            COALESCE(column_comment, '') as column_comment
        FROM information_schema.columns
        WHERE table_schema = :schema AND table_name = :table
        ORDER BY ordinal_position
    """)
    
    result = mysql_session.execute(query, {'schema': schema, 'table': table_name})
    columns = []
    for row in result:
        # SQLAlchemy returns Row objects - use index access which is most reliable
        columns.append({
            'name': row[0],
            'data_type': row[1],
            'column_type': row[2],
            'is_nullable': row[3] == 'YES',
            'default': row[4],
            'extra': row[5],
            'key': row[6],
            'comment': row[7] if len(row) > 7 else '',
        })
    
    return columns

def get_primary_key_mysql(mysql_session, table_name: str, schema: str) -> List[str]:
    """دریافت primary key از MySQL"""
    query = text("""
        SELECT column_name
        FROM information_schema.key_column_usage
        WHERE table_schema = :schema 
            AND table_name = :table 
            AND constraint_name = 'PRIMARY'
        ORDER BY ordinal_position
    """)
    
    result = mysql_session.execute(query, {'schema': schema, 'table': table_name})
    return [row[0] for row in result]  # Use index access

def get_indexes_mysql(mysql_session, table_name: str, schema: str) -> List[Dict[str, Any]]:
    """دریافت indexes از MySQL"""
    query = text("""
        SELECT 
            index_name,
            column_name,
            non_unique,
            seq_in_index
        FROM information_schema.statistics
        WHERE table_schema = :schema 
            AND table_name = :table
            AND index_name != 'PRIMARY'
        ORDER BY index_name, seq_in_index
    """)
    
    result = mysql_session.execute(query, {'schema': schema, 'table': table_name})
    indexes = {}
    for row in result:
        index_name = row[0]  # index_name
        column_name = row[1]  # column_name
        non_unique = row[2]  # non_unique
        # seq_in_index = row[3]  # not used
        
        if index_name not in indexes:
            indexes[index_name] = {
                'name': index_name,
                'unique': non_unique == 0,
                'columns': []
            }
        indexes[index_name]['columns'].append(column_name)
    
    return list(indexes.values())

def create_table_postgresql(postgres_session, table_name: str, columns: List[Dict[str, Any]], 
                           primary_key: List[str], indexes: List[Dict[str, Any]]):
    """ایجاد جدول در PostgreSQL"""
    
    # ساخت CREATE TABLE statement
    column_defs = []
    
    for col in columns:
        col_def = f'"{col["name"]}" {mysql_to_postgresql_type(col["column_type"])}'
        
        # NOT NULL
        if not col['is_nullable']:
            col_def += ' NOT NULL'
        
        # DEFAULT
        if col['default']:
            default = col['default']
            # Handle special defaults
            if default == 'CURRENT_TIMESTAMP':
                col_def += ' DEFAULT CURRENT_TIMESTAMP'
            elif default == 'CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP':
                col_def += ' DEFAULT CURRENT_TIMESTAMP'
            elif default.startswith("'") and default.endswith("'"):
                col_def += f" DEFAULT {default}"
            elif default.upper() in ('NULL', 'TRUE', 'FALSE'):
                col_def += f' DEFAULT {default.upper()}'
            else:
                # Check if this is a boolean column with numeric default
                pg_type = mysql_to_postgresql_type(col['column_type']).upper()
                if pg_type == 'BOOLEAN' or 'BOOLEAN' in pg_type:
                    # Convert numeric defaults to boolean
                    if default in ('0', '1'):
                        col_def += f" DEFAULT {'FALSE' if default == '0' else 'TRUE'}"
                    else:
                        col_def += f' DEFAULT {default.upper()}' if default.upper() in ('TRUE', 'FALSE') else f" DEFAULT '{default}'"
                else:
                    try:
                        float(default)  # Check if numeric
                        col_def += f' DEFAULT {default}'
                    except:
                        col_def += f" DEFAULT '{default}'"
        
        # AUTO_INCREMENT -> SERIAL یا sequence
        if 'auto_increment' in col['extra'].lower():
            # PostgreSQL doesn't have auto_increment, we'll use SERIAL or let sequence handle it
            if col_def.startswith(f'"{col["name"]}" INTEGER'):
                col_def = col_def.replace('INTEGER', 'SERIAL')
            elif col_def.startswith(f'"{col["name"]}" BIGINT'):
                col_def = col_def.replace('BIGINT', 'BIGSERIAL')
        
        column_defs.append(col_def)
    
    # PRIMARY KEY
    create_sql = f'CREATE TABLE IF NOT EXISTS "{table_name}" (\n    '
    create_sql += ',\n    '.join(column_defs)
    
    if primary_key:
        pk_cols = ', '.join(f'"{col}"' for col in primary_key)
        create_sql += f',\n    PRIMARY KEY ({pk_cols})'
    
    create_sql += '\n);'
    
    # اجرای CREATE TABLE
    try:
        postgres_session.execute(text(create_sql))
        postgres_session.commit()
        print(f"  ✅ جدول {table_name} ایجاد شد")
        
        # ایجاد indexes (skip primary key index)
        for idx in indexes:
            if idx['columns']:
                idx_cols = ', '.join(f'"{col}"' for col in idx['columns'])
                unique = 'UNIQUE' if idx['unique'] else ''
                idx_name = idx['name'] if len(idx['name']) <= 63 else idx['name'][:63]  # PostgreSQL limit
                idx_sql = f'CREATE {unique} INDEX IF NOT EXISTS "{idx_name}" ON "{table_name}" ({idx_cols});'
                try:
                    postgres_session.execute(text(idx_sql))
                    postgres_session.commit()
                except Exception as e:
                    print(f"  ⚠️ خطا در ایجاد index {idx_name}: {e}")
        
        return True
    except Exception as e:
        postgres_session.rollback()
        print(f"  ❌ خطا در ایجاد جدول {table_name}: {e}")
        return False

