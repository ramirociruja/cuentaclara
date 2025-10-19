# app/constants.py
from enum import Enum

# ==============================
# Installments (cuotas)
# ==============================
class InstallmentStatus(str, Enum):
    PENDING    = "pending"      # Pendiente
    PARTIAL    = "partial"      # Parcialmente pagada
    PAID       = "paid"         # Pagada
    OVERDUE    = "overdue"      # Vencida
    CANCELED   = "canceled"     # Cancelada
    REFINANCED = "refinanced"   # Refinanciada

# ==============================
# Loans / Purchases (préstamos / ventas)
# ==============================
class LoanStatus(str, Enum):
    ACTIVE     = "active"       # Activo
    PAID       = "paid"         # Pagado
    DEFAULTED  = "defaulted"    # Incumplido / en mora
    CANCELED   = "canceled"     # Cancelado
    REFINANCED = "refinanced"   # Refinanciado

# ==============================
# Normalización de entradas “legacy”
# (ES y variantes → EN canónico)
# ==============================
NORMALIZE_INSTALLMENT_STATUS = {
    # Pendiente
    "pendiente": InstallmentStatus.PENDING,
    "pending":   InstallmentStatus.PENDING,

    # Parcialmente pagada
    "parcialmente pagada": InstallmentStatus.PARTIAL,
    "parcial":             InstallmentStatus.PARTIAL,
    "partial":             InstallmentStatus.PARTIAL,
    "partially paid":      InstallmentStatus.PARTIAL,

    # Pagada
    "pagada":   InstallmentStatus.PAID,
    "pagado":   InstallmentStatus.PAID,  # por si vino con género distinto
    "paid":     InstallmentStatus.PAID,

    # Vencida
    "vencida":  InstallmentStatus.OVERDUE,
    "vencido":  InstallmentStatus.OVERDUE,
    "overdue":  InstallmentStatus.OVERDUE,

    # Cancelada
    "cancelada": InstallmentStatus.CANCELED,
    "cancelado": InstallmentStatus.CANCELED,
    "canceled":  InstallmentStatus.CANCELED,
    "cancelled": InstallmentStatus.CANCELED,  # variante en inglés británico

    # Refinanciada
    "refinanciada": InstallmentStatus.REFINANCED,
    "refinanciado": InstallmentStatus.REFINANCED,
    "refinanced":   InstallmentStatus.REFINANCED,
}

NORMALIZE_LOAN_STATUS = {
    # EN canónico
    "active":     LoanStatus.ACTIVE,
    "paid":       LoanStatus.PAID,
    "defaulted":  LoanStatus.DEFAULTED,
    "canceled":   LoanStatus.CANCELED,
    "cancelled":  LoanStatus.CANCELED,  # variante
    "refinanced": LoanStatus.REFINANCED,

    # ES legacy
    "activo":        LoanStatus.ACTIVE,
    "pagado":        LoanStatus.PAID,
    "pagada":        LoanStatus.PAID,
    "incumplido":    LoanStatus.DEFAULTED,
    "en mora":       LoanStatus.DEFAULTED,
    "cancelado":     LoanStatus.CANCELED,
    "cancelada":     LoanStatus.CANCELED,
    "refinanciado":  LoanStatus.REFINANCED,
    "refinanciada":  LoanStatus.REFINANCED,
}

# Tipos de pago válidos (por si validás)
PAYMENT_TYPES = {"cash", "transfer", "other"}
