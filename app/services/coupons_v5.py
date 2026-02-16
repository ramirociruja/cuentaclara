from dataclasses import dataclass
from datetime import date
from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.pdfgen import canvas

from reportlab.pdfbase import pdfmetrics


@dataclass
class CouponV5Data:
    company_name: str
    company_cuit: str | None

    customer_name: str
    customer_address: str | None
    customer_province: str | None

    collector_name: str | None
    description: str | None

    loan_id: int
    installment_number: int
    installments_count: int
    due_date: date
    installment_amount: float
    installment_balance: float

    total_paid: float
    remaining: float

    overdue_count: int
    overdue_amount: float
    is_overdue: bool
    days_overdue: int


def _money(v: float) -> str:
    n = int(round(v or 0))
    return f"$ {n:,}".replace(",", ".")


def _fit_text(c: canvas.Canvas, text: str, font: str, size: float, max_width: float) -> str:
    """Trunca con '…' para que no supere max_width."""
    if not text:
        return ""
    c.setFont(font, size)
    if c.stringWidth(text, font, size) <= max_width:
        return text

    ell = "…"
    lo, hi = 0, len(text)
    while lo < hi:
        mid = (lo + hi) // 2
        candidate = text[:mid].rstrip() + ell
        if c.stringWidth(candidate, font, size) <= max_width:
            lo = mid + 1
        else:
            hi = mid
    cut = max(0, lo - 1)
    return text[:cut].rstrip() + ell


def build_coupons_v5_pdf(
    items: list[CouponV5Data],
    tz: str | None = None,
) -> bytes:
    _ = tz

    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    W, H = A4

    # Ocupar total ancho: márgenes laterales a 0
    mx = 0
    my = 8 * mm
    gap_y = 4 * mm

    usable_h = H - 2 * my - 2 * gap_y
    slot_h = usable_h / 3
    slot_w = W  # Total ancho

    def draw_pair(x: float, y: float, w: float, h: float, d: CouponV5Data):
        mid = x + w / 2
        c.setDash(3, 3)
        c.setLineWidth(1)
        c.line(mid, y + 2 * mm, mid, y + h - 2 * mm)
        c.setDash()

        def half(x0: float, label: str):
            pad = 5 * mm
            w0 = w / 2
            top = y + h - pad
            cur = top

            header = d.company_name
            if d.company_cuit:
                header = f"{header} (CUIT {d.company_cuit})"

            c.setFont("Helvetica-Bold", 8.5)
            c.drawString(x0 + pad, cur - 6, header)

            # Rol a la derecha
            c.setFont("Helvetica", 8)
            c.setFillColor(colors.grey)
            c.drawRightString(x0 + w0 - pad, cur - 6, label)

            # ID préstamo (más discreto y sin “apretar” el bloque principal)
            c.setFont("Helvetica", 8)
            c.drawRightString(x0 + w0 - pad, cur - 18, f"ID préstamo: {d.loan_id}")
            c.setFillColor(colors.black)

            cur -= 25  # Espacio aumentado para balancear verticalmente
            c.setLineWidth(0.5)
            c.line(x0 + pad, cur, x0 + w0 - pad, cur)
            cur -= 20  # Espacio aumentado

            # Cliente
            c.setFont("Helvetica-Bold", 13.5)
            c.drawString(x0 + pad, cur, d.customer_name)
            cur -= 15  # Espacio aumentado

            # Dirección + provincia en 2 líneas
            addr = d.customer_address or "-"
            prov = d.customer_province or "-"
            c.setFont("Helvetica", 9.5)
            c.setFillColor(colors.grey)
            c.drawString(x0 + pad, cur, addr)
            cur -= 12  # Espacio ajustado
            c.drawString(x0 + pad, cur, prov)
            c.setFillColor(colors.black)
            cur -= 15  # Espacio aumentado

            # Cobrador
            cob = d.collector_name or "Sin asignar"
            c.setFont("Helvetica", 9.5)
            c.drawString(x0 + pad, cur, f"Cobrador: {cob}")
            cur -= 15  # Espacio aumentado

            # Descripción
            if d.description:
                c.setFont("Helvetica-Oblique", 8.8)
                c.setFillColor(colors.grey)
                c.drawString(x0 + pad, cur, d.description[:70])
                c.setFillColor(colors.black)
                cur -= 18  # Espacio aumentado
            else:
                cur -= 10  # Espacio mínimo si no hay descripción

            # Cuota + monto (sin solape)
            amount_gap = 8 * mm
            amount_reserved = 32 * mm
            left_max_x = x0 + w0 - pad - amount_reserved - amount_gap
            left_max_w = max(10, left_max_x - (x0 + pad))

            # Línea 1: cuota
            c.setFont("Helvetica-Bold", 11)
            c.drawString(
                x0 + pad,
                cur,
                f"Cuota {d.installment_number}/{d.installments_count}",
            )

            # Línea 2: vencimiento
            c.setFont("Helvetica", 9.5)
            c.setFillColor(colors.grey)
            c.drawString(
                x0 + pad,
                cur - 12,
                f"Vence: {d.due_date.strftime('%d/%m/%Y')}",
            )
            c.setFillColor(colors.black)

            cur -= 22  # ajustar cursor para que no se pise con el monto


            # ✅ Mostrar: "$90 de $150" (saldo en negrita, total en gris)
            saldo = _money(getattr(d, "installment_balance", 0) or 0)   # $90
            total = _money(getattr(d, "installment_amount", 0) or 0)    # $150
            suffix = f" de {total}"

            x_right = x0 + w0 - pad
            y_amt = cur + 1

            # Parte gris (derecha): " de $150"
            suffix_font = "Helvetica"
            suffix_size = 9
            c.setFont(suffix_font, suffix_size)
            c.setFillColor(colors.grey)
            c.drawRightString(x_right, y_amt, suffix)

            # Parte negra en negrita (izquierda de la gris): "$90"
            suffix_w = pdfmetrics.stringWidth(suffix, suffix_font, suffix_size)
            c.setFont("Helvetica-Bold", 17)
            c.setFillColor(colors.black)
            c.drawRightString(x_right - suffix_w, y_amt, saldo)

            # Label (lo dejo para no tocar layout)
            c.setFont("Helvetica", 8.8)
            c.setFillColor(colors.grey)
            c.drawRightString(x_right, cur - 10, "Saldo cuota")
            c.setFillColor(colors.black)

            cur -= 20



            if d.is_overdue:
                c.setFont("Helvetica-Bold", 10)
                c.setFillColor(colors.red)
                c.drawString(x0 + pad, cur, f"Vencida · {d.days_overdue} días")  # ✅ izquierda
                c.setFillColor(colors.black)
                cur -= 15


            # Pie del cupón: Monto pagado al final, con padding inferior
            # Agregar padding de 10mm desde el bottom
            # Pie del cupón: anclado al bottom con padding chico
            footer_pad = 4 * mm

            monto_title_y = y + footer_pad + 12 * mm
            monto_line_y  = y + footer_pad + 10 * mm

            line_gap = 4 * mm  # interlineado real

            status1_y = y + footer_pad + 6 * mm
            status2_y = status1_y - line_gap

            c.setFont("Helvetica-Bold", 11.5)
            c.drawString(x0 + pad, monto_title_y, "Monto pagado:")
            c.setLineWidth(0.9)
            c.line(x0 + pad, monto_line_y, x0 + w0 - pad, monto_line_y)

            c.setFont("Helvetica", 9)
            c.setFillColor(colors.grey)
            c.drawString(
                x0 + pad,
                status1_y,
                f"Pagado: {_money(d.total_paid)} | Saldo préstamo: {_money(d.remaining)}",
            )
            if d.overdue_count > 0:
                c.drawString(
                    x0 + pad,
                    status2_y,
                    f"Atraso: {d.overdue_count} cuotas ({_money(d.overdue_amount)})",
                )
            c.setFillColor(colors.black)

        half(x, "COBRADOR")
        half(mid, "CLIENTE")

    for i, item in enumerate(items):
        pos_in_page = i % 3
        if i > 0 and pos_in_page == 0:
            c.showPage()

        y0 = H - my - (pos_in_page + 1) * slot_h - pos_in_page * gap_y
        draw_pair(mx, y0, slot_w, slot_h, item)
        # Separadores horizontales entre cupones (una sola línea)
        c.setStrokeColor(colors.black)
        c.setLineWidth(0.9)

        # Línea superior de la página (opcional): yo NO la dibujaría.
        # Solo separadores ENTRE slots:
        if pos_in_page in (1, 2):
            y_sep = y0 + slot_h + gap_y / 2  # línea entre este slot y el anterior
            c.line(mx, y_sep, mx + slot_w, y_sep)


    c.save()
    return buf.getvalue()