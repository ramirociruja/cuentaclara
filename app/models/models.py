from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Boolean, text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database.db import Base
from datetime import datetime, timezone

class Customer(Base):
    __tablename__ = "customers"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    email = Column(String, unique=True, index=True, nullable=True)
    phone = Column(String, unique=True, nullable=True)
    dni = Column(String, unique=True, index=True, nullable=True)
    address = Column(String, nullable=True)
    province = Column(String, nullable=True)
    created_at = Column(
    DateTime(timezone=True),
    default=lambda: datetime.now(timezone.utc),
    nullable=False,
    index=True
)

    
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True)
    company_id = Column(Integer, ForeignKey('companies.id'))  # Aquí agregamos el `company_id`



    loans = relationship("Loan", back_populates="customer")
    purchases = relationship("Purchase", back_populates="customer")
    employee = relationship("Employee", back_populates="customers")  # Nueva relación
    company = relationship("Company", back_populates="customers")  # Relación bidireccional
   

class Employee(Base):
    __tablename__ = "employees"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    role = Column(String, nullable=False)
    phone = Column(String, unique=True, nullable=True)
    email = Column(String, unique=True, nullable=False, index=True)  # Campo para email
    password = Column(String, nullable=False)  # Campo para la contraseña cifrada
    created_at = Column(DateTime, default=datetime.utcnow)

    company_id = Column(Integer, ForeignKey('companies.id'))

    company = relationship("Company", back_populates="employees")  # Relación bidireccional
    customers = relationship("Customer", back_populates="employee")  # Relación inversa


class Loan(Base):
    __tablename__ = "loans"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    amount = Column(Float, nullable=False)
    total_due = Column(Float, nullable=False)  # Amount + interest
    installments_count = Column(Integer, nullable=False)
    installment_amount = Column(Float, nullable=False)
    frequency = Column(String, nullable=False)  # "weekly" or "monthly"
    start_date = Column(DateTime, default=datetime.utcnow)
    status = Column(String, default="active")  # "active", "paid", "defaulted"
    
    company_id = Column(Integer, ForeignKey('companies.id'))
    
    company = relationship("Company", back_populates="loans")  # Relación bidireccional
    customer = relationship("Customer", back_populates="loans")
    payments = relationship("Payment", back_populates="loan")
    installments = relationship("Installment", back_populates="loan", cascade="all, delete-orphan")


class Purchase(Base):
    __tablename__ = "purchases"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    product_name = Column(String, nullable=False)
    amount = Column(Float, nullable=False)
    total_due = Column(Float, nullable=False)
    installments_count = Column(Integer, nullable=False)
    installment_amount = Column(Float, nullable=False)
    frequency = Column(String, nullable=False)  # "weekly" or "monthly"
    start_date = Column(DateTime, default=datetime.utcnow)
    status = Column(String, default="active")  # "active", "paid", "defaulted"
    
    company_id = Column(Integer, ForeignKey('companies.id'))
    
    company = relationship("Company", back_populates="purchases")  # Relación bidireccional
    customer = relationship("Customer", back_populates="purchases")
    payments = relationship("Payment", back_populates="purchase")
    installments = relationship("Installment", back_populates="purchase", cascade="all, delete-orphan")


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True)
    purchase_id = Column(Integer, ForeignKey("purchases.id"), nullable=True)
    amount = Column(Float, nullable=False)
    payment_date = Column(DateTime, default=datetime.utcnow)
    
    loan = relationship("Loan", back_populates="payments")
    purchase = relationship("Purchase", back_populates="payments")


class Installment(Base):
    __tablename__ = "installments"

    id = Column(Integer, primary_key=True, index=True)
    loan_id = Column(Integer, ForeignKey("loans.id"), nullable=True)
    purchase_id = Column(Integer, ForeignKey("purchases.id"), nullable=True)

    number = Column(Integer, nullable=False)  # Cuota 1, 2, 3...
    due_date = Column(DateTime, nullable=False)
    amount = Column(Float, nullable=False)
    paid_amount = Column(Float, default=0)
    is_paid = Column(Boolean, default=False)
    status = Column(String, nullable=False)  # Campo para el estado de la cuota
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
            self.status = "Pagada"
            remaining_amount -= amount_needed
        else:
            # Pago parcial
            self.paid_amount += remaining_amount
            self.status = "Parcialmente pagada"
            remaining_amount = 0

        return remaining_amount

class Company(Base):
    __tablename__ = 'companies'

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    customers = relationship("Customer", back_populates="company")
    employees = relationship("Employee", back_populates="company")  # ✅
    loans = relationship("Loan", back_populates="company")
    purchases = relationship("Purchase", back_populates="company")
