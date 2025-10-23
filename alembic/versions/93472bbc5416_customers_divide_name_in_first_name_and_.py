"""customers: divide name in first name and last name

Revision ID: 93472bbc5416
Revises: ef68e87bc69a
Create Date: 2025-10-22 00:46:37.422397

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '93472bbc5416'
down_revision: Union[str, None] = 'ef68e87bc69a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # 1) agregar columnas nuevas (temporariamente NULL para poder backfillear)
    op.add_column("customers", sa.Column("first_name", sa.String(length=120), nullable=True))
    op.add_column("customers", sa.Column("last_name", sa.String(length=120), nullable=True))

    # 2) backfill rápido desde name
    conn = op.get_bind()
    # last_name = última palabra; first_name = resto (si solo 1 palabra, last_name = '')
    conn.execute(sa.text("""
        UPDATE customers
        SET
          first_name = CASE
              WHEN name IS NULL OR name = '' THEN ''
              WHEN split_part(name, ' ', 2) = '' THEN name
              ELSE regexp_replace(name, '\\s+[^\\s]+$', '')
          END,
          last_name = CASE
              WHEN name IS NULL OR name = '' THEN ''
              WHEN split_part(name, ' ', 2) = '' THEN ''
              ELSE regexp_replace(name, '^.*\\s', '')
          END
    """))

    # 3) forzar NOT NULL ya con datos
    op.alter_column("customers", "first_name", existing_type=sa.String(length=120), nullable=False)
    op.alter_column("customers", "last_name",  existing_type=sa.String(length=120), nullable=False)

    # 4) índices útiles
    op.create_index("ix_customers_first_name", "customers", ["first_name"])
    op.create_index("ix_customers_last_name",  "customers", ["last_name"])

    # 5) eliminar índice e columna antiguos
    # Borrar índice si existe (fue creado en initial: ix_customers_name)
    try:
        op.drop_index("ix_customers_name", table_name="customers")
    except Exception:
        pass

    op.drop_column("customers", "name")

def downgrade():
    # Restaurar name (nullable) y backfill inverso
    op.add_column("customers", sa.Column("name", sa.String(), nullable=True))
    conn = op.get_bind()
    conn.execute(sa.text("""
        UPDATE customers
        SET name = CONCAT(first_name, CASE WHEN last_name = '' THEN '' ELSE ' ' END, last_name)
    """))
    op.create_index("ix_customers_name", "customers", ["name"])

    op.drop_index("ix_customers_last_name", table_name="customers")
    op.drop_index("ix_customers_first_name", table_name="customers")

    op.drop_column("customers", "last_name")
    op.drop_column("customers", "first_name")