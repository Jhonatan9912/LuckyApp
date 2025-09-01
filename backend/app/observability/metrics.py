from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

SUBS_SYNC_OK = Counter("subs_sync_ok_total", "Sync OK de suscripciones")
SUBS_SYNC_ERR = Counter("subs_sync_err_total", "Sync con error de suscripciones")
RTDN_RCVD     = Counter("rtdn_received_total", "RTDN recibidas")
RTDN_ERR      = Counter("rtdn_error_total", "Errores procesando RTDN")
RECONCILE_UPD = Counter("reconcile_updated_total", "Suscripciones actualizadas por reconcile")
RECONCILE_ERR = Counter("reconcile_errors_total", "Errores en reconcile")

def metrics_http_response():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}