"""Quitar unicidad de cliente por DNI y telefono

Revision ID: 623f91524136
Revises: 7cd71e69d4bf
Create Date: 2025-10-27 23:15:49.547827

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '623f91524136'
down_revision: Union[str, None] = '7cd71e69d4bf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # 1) Dropear UNIQUEs viejos (los que incluyan company_id y alguna de dni/phone/email)
    drop_sql = """
    DO $$
    DECLARE
      r RECORD;
    BEGIN
      FOR r IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN LATERAL unnest(c.conkey) AS k(attnum) ON TRUE
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE n.nspname = 'public'
          AND t.relname = 'customers'
          AND c.contype = 'u'
        GROUP BY c.conname
        HAVING bool_or(a.attname = 'company_id')
           AND bool_or(a.attname IN ('dni','phone','email'))
      LOOP
        EXECUTE format('ALTER TABLE public.customers DROP CONSTRAINT %I', r.conname);
      END LOOP;
    END $$;
    """
    op.execute(drop_sql)

    # 2) Crear índices únicos por empleado
    op.create_index(
        'ux_customers_employee_dni',
        'customers',
        ['employee_id', 'dni'],
        unique=True
    )
    op.create_index(
        'ux_customers_employee_phone',
        'customers',
        ['employee_id', 'phone'],
        unique=True
    )
    op.create_index(
        'ux_customers_employee_email',
        'customers',
        ['employee_id', 'email'],
        unique=True
    )

def downgrade():
    # Revertir: eliminar los nuevos índices únicos por empleado
    op.drop_index('ux_customers_employee_email', table_name='customers')
    op.drop_index('ux_customers_employee_phone', table_name='customers')
    op.drop_index('ux_customers_employee_dni', table_name='customers')

    # Volver a unicidad por empresa
    op.create_index(
        'ux_customers_company_dni',
        'customers',
        ['company_id', 'dni'],
        unique=True
    )
    op.create_index(
        'ux_customers_company_phone',
        'customers',
        ['company_id', 'phone'],
        unique=True
    )
    op.create_index(
        'ux_customers_company_email',
        'customers',
        ['company_id', 'email'],
        unique=True
    )