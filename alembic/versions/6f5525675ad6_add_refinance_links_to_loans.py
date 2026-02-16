"""add refinance links to loans

Revision ID: 6f5525675ad6
Revises: 8fbf76635f01
Create Date: 2026-01-23 10:41:04.496004

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6f5525675ad6'
down_revision: Union[str, None] = '8fbf76635f01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("loans", sa.Column("refinanced_from_loan_id", sa.Integer(), nullable=True))
    op.add_column("loans", sa.Column("refinanced_to_loan_id", sa.Integer(), nullable=True))

    op.create_index("ix_loans_refinanced_from_loan_id", "loans", ["refinanced_from_loan_id"])
    op.create_index("ix_loans_refinanced_to_loan_id", "loans", ["refinanced_to_loan_id"])

    op.create_foreign_key(
        "fk_loans_refinanced_from_loan_id_loans",
        "loans",
        "loans",
        ["refinanced_from_loan_id"],
        ["id"],
        ondelete="SET NULL",
    )

    op.create_foreign_key(
        "fk_loans_refinanced_to_loan_id_loans",
        "loans",
        "loans",
        ["refinanced_to_loan_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_loans_refinanced_to_loan_id_loans", "loans", type_="foreignkey")
    op.drop_constraint("fk_loans_refinanced_from_loan_id_loans", "loans", type_="foreignkey")

    op.drop_index("ix_loans_refinanced_to_loan_id", table_name="loans")
    op.drop_index("ix_loans_refinanced_from_loan_id", table_name="loans")

    op.drop_column("loans", "refinanced_to_loan_id")
    op.drop_column("loans", "refinanced_from_loan_id")
