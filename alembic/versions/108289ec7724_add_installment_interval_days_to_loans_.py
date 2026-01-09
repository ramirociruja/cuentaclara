"""add installment_interval_days to loans and purchases

Revision ID: 108289ec7724
Revises: 704e4543552b
Create Date: 2026-01-06 21:26:20.785565

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '108289ec7724'
down_revision: Union[str, None] = '704e4543552b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1) Agregar columnas (nullable para no romper)
    op.add_column("loans", sa.Column("installment_interval_days", sa.Integer(), nullable=True))
    op.add_column("purchases", sa.Column("installment_interval_days", sa.Integer(), nullable=True))

    # 2) Backfill desde frequency (legacy)
    # weekly -> 7, monthly -> 28
    op.execute(
        """
        UPDATE loans
        SET installment_interval_days = CASE
            WHEN frequency = 'weekly'  THEN 7
            WHEN frequency = 'monthly' THEN 28
            ELSE NULL
        END
        WHERE installment_interval_days IS NULL;
        """
    )

    op.execute(
        """
        UPDATE purchases
        SET installment_interval_days = CASE
            WHEN frequency = 'weekly'  THEN 7
            WHEN frequency = 'monthly' THEN 28
            ELSE NULL
        END
        WHERE installment_interval_days IS NULL;
        """
    )


def downgrade() -> None:
    op.drop_column("purchases", "installment_interval_days")
    op.drop_column("loans", "installment_interval_days")