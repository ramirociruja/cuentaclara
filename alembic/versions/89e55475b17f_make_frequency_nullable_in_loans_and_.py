"""make frequency nullable in loans and purchases

Revision ID: 89e55475b17f
Revises: 108289ec7724
Create Date: 2026-01-06 22:17:56.888244

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '89e55475b17f'
down_revision: Union[str, None] = '108289ec7724'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # loans.frequency -> nullable
    op.alter_column(
        "loans",
        "frequency",
        existing_type=sa.String(),
        nullable=True,
    )

    # purchases.frequency -> nullable
    op.alter_column(
        "purchases",
        "frequency",
        existing_type=sa.String(),
        nullable=True,
    )


def downgrade():
    # ⚠️ OJO:
    # si existen NULLs, este downgrade fallará.
    # Solo para rollback controlado en dev.
    op.alter_column(
        "purchases",
        "frequency",
        existing_type=sa.String(),
        nullable=False,
    )

    op.alter_column(
        "loans",
        "frequency",
        existing_type=sa.String(),
        nullable=False,
    )