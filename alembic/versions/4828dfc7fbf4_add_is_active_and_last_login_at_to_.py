"""add is_active and last_login_at to employees

Revision ID: 4828dfc7fbf4
Revises: 9641df439cf6
Create Date: 2026-02-16 16:59:28.521774

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '4828dfc7fbf4'
down_revision: Union[str, None] = '9641df439cf6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
    "employees",
    sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true"))
    )
    op.add_column("employees", sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("employees", sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True))

    op.create_index("ix_employees_is_active", "employees", ["is_active"], unique=False)
    op.create_index("ix_employees_last_login_at", "employees", ["last_login_at"], unique=False)



def downgrade() -> None:
    op.drop_index("ix_employees_last_login_at", table_name="employees")
    op.drop_index("ix_employees_is_active", table_name="employees")

    op.drop_column("employees", "last_login_at")
    op.drop_column("employees", "disabled_at")
    op.drop_column("employees", "is_active")
