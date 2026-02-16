from sqlalchemy import Column, Index, Integer, String, Float, ForeignKey, DateTime, Boolean, text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database.db import Base
from datetime import datetime, timezone

from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime, timezone

from app.constants import InstallmentStatus, LoanStatus

class Customer(Base):
    __tablename__ = "customers"

    id = Column(Integer, primary_key=True, index=True)

    # 🔄 Nuevo esquema: sin "name"
    first_name = Column(String, nullable=False, index=True)
    last_name  = Column(String, nullable=False, index=True)

    email = Column(String, nullable=True, index=True)
    phone = Column(String, nullable=True, index=True)
    dni   = Column(String, nullable=True, index=True)

    address = Column(String, nullable=True)
    province = Column(String, nullable=True)

    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True, index=True)
    company_id  = Column(Integer, ForeignKey("companies.id"), nullable=False, index=True)

    employee = relationship("Employee", back_populates="customers", lazy="joined", foreign_keys=[employee_id])
    company  = relationship("Company", back_populates="customers", lazy="joined")

    loans     = relationship("Loan", back_populates="customer", lazy="selectin")
    purchases = relationship("Purchase", back_populates="customer", lazy="selectin")


    @property
    def full_name(self) -> str:
        # helper útil para mostrar en recibos u otras vistas
        return f"{self.first_name} {self.last_name}".strip()


    __table_args__ = (
        # Unicidad por empresa (en vez de unique=True global)
        Index('ux_customers_employee_dni', 'employee_id', 'dni', unique=True),
        Index('ux_customers_employee_phone', 'employee_id', 'phone', unique=True),
        Index('ux_customers_employee_email', 'employee_id', 'email', unique=True),
    )

   

class Employee(Base):
    __tablename__ = "employees"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    role = Column(String, nullable=False)
    phone = Column(String, unique=True, nullable=True)
    email = Column(String, unique=True, nullable=False, index=True)  # Campo para email
    password = Column(String, nullable=False)  # Campo para la contraseña cifrada
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    company_id = Column(Integer, ForeignKey('companies.id'))
    token_version = Column(Integer, nullable=False, default=0)

    company = relationship("Company", back_populates="employees")  # Relación bidireccional
    customers = relationship("Customer", back_populates="employee")  # Relación inversa
    loans = relationship("Loan", back_populates="employee")
    purchases = relationship("Purchase", back_populates="employee")



class Loan(Base):
    __tablename__ = "loans"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    company_id = Column(Integer, ForeignKey('companies.id'))
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True, index=True)

    amount = Column(Float, nullable=False)
    total_due = Column(Float, nullable=False)  # Amount + interest
    installments_count = Column(Integer, nullable=False)
    installment_amount = Column(Float, nullable=False)
    frequency = Column(String, nullable=True)  # "weekly" or "monthly"
    installment_interval_days = Column(Integer, nullable=True)  # nuevo: ej 1, 7, 15, 28
    start_date = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    status = Column(String, default=LoanStatus.ACTIVE.value)  # "active", "paid", "defaulted"

    status_changed_at = Column(DateTime(timezone=True), nullable=True)
    status_reason = Column(String, nullable=True)

    
    description = Column(String, nullable=True)
    collection_day = Column(Integer, nullable=True)  # 1..7 (ISO: lunes=1)
    
     # --- NUEVO: tracking refinanciación ---
    refinanced_from_loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True, index=True)
    refinanced_to_loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True, index=True)

    refinanced_from_loan = relationship(
        "Loan",
        foreign_keys=[refinanced_from_loan_id],
        remote_side=[id],
        uselist=False,
        post_update=True,
    )
    refinanced_to_loan = relationship(
        "Loan",
        foreign_keys=[refinanced_to_loan_id],
        uselist=False,
        post_update=True,
    )
    
    
    company = relationship("Company", back_populates="loans")  # Relación bidireccional
    customer = relationship("Customer", back_populates="loans")
    employee = relationship("Employee", back_populates="loans")
    
    payments = relationship("Payment", back_populates="loan")
    installments = relationship("Installment", back_populates="loan", cascade="all, delete-orphan")
    @property
    def employee_name(self):
        """Nombre del cobrador / empleado dueño del préstamo."""
        return self.employee.name if self.employee else None


class Purchase(Base):
    __tablename__ = "purchases"

    id = Column(Integer, primary_key=True, index=True)

    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)
    company_id  = Column(Integer, ForeignKey("companies.id"), nullable=False, index=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True, index=True)

    # Monto base de la venta (equivalente a Loan.amount)
    amount = Column(Float, nullable=False)

    # Total a pagar (puede ser = amount si no hay recargo/financiación)
    total_due = Column(Float, nullable=False)

    installments_count  = Column(Integer, nullable=False)
    installment_amount  = Column(Float, nullable=False)
    frequency           = Column(String, nullable=True)  # "weekly" | "monthly"
    installment_interval_days = Column(Integer, nullable=True)  # nuevo

    start_date = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    status = Column(String, default=LoanStatus.ACTIVE.value)  # "active","paid","defaulted"

    status_changed_at = Column(DateTime(timezone=True), nullable=True)
    status_reason = Column(String, nullable=True)

    # Equivalentes a Loan
    description    = Column(String, nullable=True)
    collection_day = Column(Integer, nullable=True)  # 1..7 (ISO)

    # (Opcional) si querés conservarlo explícito
    product_name = Column(String, nullable=True)

    company  = relationship("Company", back_populates="purchases")
    customer = relationship("Customer", back_populates="purchases")
    employee = relationship("Employee", back_populates="purchases")

    payments      = relationship("Payment", back_populates="purchase")
    installments  = relationship("Installment", back_populates="purchase", cascade="all, delete-orphan")

    @property
    def employee_name(self):
        return self.employee.name if self.employee else None


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True)
    purchase_id = Column(Integer, ForeignKey("purchases.id"), nullable=True)
    amount = Column(Float, nullable=False)
    payment_date = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Anulación de pago
    is_voided = Column(Boolean, default=False)
    voided_at = Column(DateTime(timezone=True), nullable=True)
    void_reason = Column(String, nullable=True)
    voided_by_employee_id = Column(Integer, ForeignKey('employees.id'), nullable=True)

    # Tipo y descripción del pago
    payment_type = Column(String, nullable=True)   # 'cash' | 'transfer' | 'other'
    description  = Column(String, nullable=True)   # texto libre / detalle

    loan = relationship("Loan", back_populates="payments")
    purchase = relationship("Purchase", back_populates="payments")
    collector_id = Column(Integer, ForeignKey("employees.id"), nullable=False)
    collector = relationship("Employee", foreign_keys=[collector_id])



class Installment(Base):
    __tablename__ = "installments"

    id = Column(Integer, primary_key=True, index=True)
    loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True)
    purchase_id = Column(Integer, ForeignKey("purchases.id"), nullable=True)

    number = Column(Integer, nullable=False)  # Cuota 1, 2, 3...
    due_date = Column(DateTime(timezone=True), nullable=False)
    amount = Column(Float, nullable=False)
    paid_amount = Column(Float, default=0)
    is_paid = Column(Boolean, default=False)
    # campo status (agregá/ajustá el default)
    status = Column(String, nullable=False, default=InstallmentStatus.PENDING.value)
    # Campo para el estado de la cuota
    is_overdue = Column(Boolean, default=False)  # Campo para indicar si está vencida

    # Relaciones
    loan = relationship("Loan", back_populates="installments")
    purchase = relationship("Purchase", back_populates="installments")

    def register_payment(self, amount: float):
        """Método para registrar el pago y actualizar la cuota."""
        if amount <= 0:
            return 0

        remaining_amount = amount
        amount_needed = self.amount - self.paid_amount

        if remaining_amount >= amount_needed:
            # Pago completo
            self.paid_amount = self.amount
            self.is_paid = True
            self.status = InstallmentStatus.PAID.value
            remaining_amount -= amount_needed
        else:
            # Pago parcial
            self.paid_amount += remaining_amount
            self.status = InstallmentStatus.PARTIAL.value
            remaining_amount = 0

        return remaining_amount

class Company(Base):
    __tablename__ = 'companies'

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    service_status = Column(String, nullable=False, default="active", index=True)
    license_expires_at = Column(DateTime(timezone=True), nullable=True)
    suspended_at = Column(DateTime(timezone=True), nullable=True)
    suspension_reason = Column(String, nullable=True)
    customers = relationship("Customer", back_populates="company")
    employees = relationship("Employee", back_populates="company")  # ✅
    loans = relationship("Loan", back_populates="company")
    purchases = relationship("Purchase", back_populates="company")


class PaymentAllocation(Base):
    __tablename__ = "payment_allocations"

    id = Column(Integer, primary_key=True, index=True)

    # vínculo al pago y a la cuota
    payment_id = Column(
        Integer,
        ForeignKey("payments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    installment_id = Column(
        Integer,
        ForeignKey("installments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # monto de este pago aplicado a ESA cuota
    amount_applied = Column(Float, nullable=False)

    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )   

    # relaciones
    payment = relationship("Payment", backref="allocations")
    installment = relationship("Installment", backref="allocations")

    


# app/models/onboarding_import.py
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.database.db import Base
from datetime import datetime, timezone
import uuid

class OnboardingImportSession(Base):
    __tablename__ = "onboarding_import_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)

    original_filename = Column(String(255), nullable=True)
    status = Column(String(32), nullable=False, default="validated")

    payload_json = Column(JSONB, nullable=False)   # rows normalizados (customers/loans/payments)
    summary_json = Column(JSONB, nullable=False)
    errors_json = Column(JSONB, nullable=False)
    warnings_json = Column(JSONB, nullable=False)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
