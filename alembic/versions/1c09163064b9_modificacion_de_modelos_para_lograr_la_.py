"""Modificacion de modelos para lograr la unicidad de cliente

Revision ID: 1c09163064b9
Revises: 623f91524136
Create Date: 2025-11-19 22:38:19.837330

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1c09163064b9'
down_revision: Union[str, None] = '623f91524136'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # 1) Agregar columna employee_id en loans (nullable por ahora)
    op.add_column(
        "loans",
        sa.Column("employee_id", sa.Integer(), nullable=True)
    )

    # 2) Crear índice para mejorar filtros por cobrador
    op.create_index(
        "ix_loans_employee_id",
        "loans",
        ["employee_id"],
        unique=False,
    )

    # 3) Crear foreign key a employees.id
    op.create_foreign_key(
        "fk_loans_employee_id_employees",
        source_table="loans",
        referent_table="employees",
        local_cols=["employee_id"],
        remote_cols=["id"],
    )

    # 4) Migrar datos: copiar employee_id desde customers hacia loans
    bind = op.get_bind()
    metadata = sa.MetaData()

    loans = sa.Table(
        "loans",
        metadata,
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("customer_id", sa.Integer),
        sa.Column("employee_id", sa.Integer),
    )

    customers = sa.Table(
        "customers",
        metadata,
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("employee_id", sa.Integer),
    )

    # SELECT loan.id, customer.employee_id
    join_stmt = (
        sa.select(loans.c.id, customers.c.employee_id)
        .select_from(
            loans.join(customers, loans.c.customer_id == customers.c.id)
        )
    )

    results = list(bind.execute(join_stmt))

    # Actualizar cada loan con el employee_id correspondiente del customer
    for loan_id, employee_id in results:
        if employee_id is not None:
            update_stmt = (
                loans.update()
                .where(loans.c.id == loan_id)
                .values(employee_id=employee_id)
            )
            bind.execute(update_stmt)


def downgrade():
    # Revertir los cambios si hiciera falta
    op.drop_constraint(
        "fk_loans_employee_id_employees",
        "loans",
        type_="foreignkey",
    )
    op.drop_index("ix_loans_employee_id", table_name="loans")
    op.drop_column("loans", "employee_id")
