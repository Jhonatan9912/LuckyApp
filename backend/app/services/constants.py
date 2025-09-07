# app/services/constants.py

# Estados activos de payout_requests (bloquean comisiones)
ACTIVE_PAYOUT_REQUEST_STATUSES = ["requested", "approved", "pending"]


# Si en tu sistema solo usas 'pending' para “retenida”, puedes simplificar a ('pending',)
HELD_COMMISSION_STATUSES = ["pending", "grace", "hold", "approved", "accrued"]
