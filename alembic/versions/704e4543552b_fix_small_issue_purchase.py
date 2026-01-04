"""Fix small issue purchase

Revision ID: 704e4543552b
Revises: 255260c5ffb2
Create Date: 2026-01-04 16:57:10.430994
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "704e4543552b"
down_revision: Union[str, None] = "255260c5ffb2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- columnas nuevas ---
    op.add_column(
        "purchases",
        sa.Column("employee_id", sa.Integer(), nullable=True),
    )
    op.add_column(
        "purchases",
        sa.Column("description", sa.String(), nullable=True),
    )
    op.add_column(
        "purchases",
        sa.Column("collection_day", sa.Integer(), nullable=True),
    )

    # --- foreign key ---
    op.create_foreign_key(
        "fk_purchases_employee_id_employees",
        "purchases",
        "employees",
        ["employee_id"],
        ["id"],
    )

    # --- índices ---
    op.create_index(
        "ix_purchases_employee_id",
        "purchases",
        ["employee_id"],
    )


def downgrade() -> None:
    # --- revertir índices ---
    op.drop_index("ix_purchases_employee_id", table_name="purchases")

    # --- revertir foreign key ---
    op.drop_constraint(
        "fk_purchases_employee_id_employees",
        "purchases",
        type_="foreignkey",
    )

    # --- revertir columnas ---
    op.drop_column("purchases", "collection_day")
    op.drop_column("purchases", "description")
    op.drop_column("purchases", "employee_id")
