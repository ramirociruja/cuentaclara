"""Add collector_id to payments

Revision ID: 175ff3c3090b
Revises: 1c09163064b9
Create Date: 2025-11-20 00:59:22.943130

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '175ff3c3090b'
down_revision: Union[str, None] = '1c09163064b9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # 1) Crear la columna como NULL por ahora
    op.add_column(
        "payments",
        sa.Column("collector_id", sa.Integer(), nullable=True)
    )

    # FK
    op.create_foreign_key(
        "fk_payments_collector",
        "payments",
        "employees",
        ["collector_id"],
        ["id"],
    )

    # 2) Actualizar pagos existentes:
    #    - Si tiene loan_id → usar loans.employee_id
    #    - Si tiene purchase_id → usar purchases.employee_id
    #    - Solo si collector_id sigue NULL
    op.execute("""
        UPDATE payments p
        SET collector_id = l.employee_id
        FROM loans l
        WHERE p.collector_id IS NULL
          AND p.loan_id = l.id
    """)

    # 3) Finalmente, exigir NOT NULL
    op.alter_column("payments", "collector_id", nullable=False)


def downgrade():
    op.drop_constraint("fk_payments_collector", "payments", type_="foreignkey")
    op.drop_column("payments", "collector_id")